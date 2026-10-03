package com.elamin.beluga.protocol;

import java.io.InputStream;
import java.lang.reflect.Constructor;
import java.lang.reflect.Modifier;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.UUID;
import com.elamin.beluga.protocol.PairingPayloadDecoder.HelloPayload;
import com.elamin.beluga.protocol.PairingPayloadDecoder.Payload;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.AdmissionCallback;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.AdmissionObservation;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.CleanupCallback;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.CleanupObservation;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.CloseCallback;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.CloseObservation;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.CloseReason;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Effect;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.End;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Kind;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Owner;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.SendCallback;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.SendObservation;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Step;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.StoreStamp;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Transport;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.WriteCallback;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.WriteObservation;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.PreparedViewer;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.RecordPhase;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.ViewerIdentity;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.ViewerPairRecord;

/** Controlled in-memory fake observations ONLY; no real store/network/durability authority. */
public final class ViewerBootstrapReducerTest {
    private static final String FIXTURE_SHA = "7d8a58cd34400271d0c68ac1e263450c4ad4978337ae1bb87246362a6d0ec06a";
    private static final UUID SLOT = UUID.fromString("33333333-2222-1111-4444-555555555555");
    private static final UUID OPERATION = UUID.fromString("66666666-2222-1111-4444-555555555555");
    private static final UUID OTHER = UUID.fromString("99999999-2222-1111-4444-555555555555");
    private static Map<String, byte[]> fixtures;
    private static int assertions;
    private ViewerBootstrapReducerTest() { }
    public static void main(String[] arguments) throws Exception {
        check(arguments.length == 1, "explicit hash-checked public fixture path required");
        fixtures = load(Path.of(arguments[0]));
        testOrderedSuccessAndAdmission();
        testOneSlotImmediateRepliesAndOverflow();
        testWrongOwnersTransportsAndSelectedHost();
        testWrongWriteReadbackAndStamp();
        testWrongAdmissionAndSendObservation();
        testOneShotAndStaleCompletions();
        testRetirementAndFailureAtEveryCriticalCut();
        testStrictBootstrapProtocolOrdering();
        testAcceptedProposalReplayRetainsExactAck();
        testCleanupCannotEraseReplacementAndDoesNotAuthorizeActivation();
        testBoundedCountersAndNewRecordOnlyAdmission();
        testInlineCallbacksAndDefensiveRedaction();
        System.out.println("Private viewer bootstrap fake-adapter assertions: " + assertions
                + "; PASS (ordering model only; no Android, store or transport durability proof)");
    }
    private static void testOrderedSuccessAndAdmission() throws Exception {
        Fixture f = at(Kind.WRITE_PENDING);
        check(f.reducer.currentStep().snapshot.acknowledgedPhase == null, "unsaved pending not acknowledged");
        Effect pending = critical(f, Kind.WRITE_PENDING);
        byte[] frozen = pending.exactBytesForTrustedPort();
        f.reducer.dispatch(pending);
        check(f.ports.events.equals(Arrays.asList(Kind.HELLO, Kind.WRITE_PENDING)), "pending write before confirmation");
        check(!f.reducer.currentStep().snapshot.invitationAdmitted, "ready/hello/write start never consume invitation");
        f.ports.writeSuccess();
        check(f.reducer.currentStep().snapshot.acknowledgedPhase == RecordPhase.PENDING, "exact pending readback acknowledgement");
        equal(frozen, f.ports.write.exactBytesForTrustedPort(), "same frozen encoding after callback");
        noPair(f, "pending still not paired");
        sendSuccess(f, Kind.CONFIRMATION);
        f.reducer.onPayload(f.transport, payload("commit.proposal.payload"));
        f.reducer.dispatch(critical(f, Kind.WRITE_ACCEPTED));
        check(!f.reducer.currentStep().snapshot.invitationAdmitted, "ACK candidate not admission");
        f.ports.writeSuccess();
        check(f.reducer.currentStep().snapshot.acknowledgedPhase == RecordPhase.ACCEPTED_ISSUED, "recoverable ACK acknowledged before admission");
        f.reducer.dispatch(critical(f, Kind.ADMISSION));
        check(f.ports.events.get(f.ports.events.size() - 1) == Kind.ADMISSION, "admission before ACK send");
        f.ports.admissionSuccess();
        check(f.reducer.currentStep().snapshot.invitationAdmitted, "only exact admission observation advances marker");
        Effect ack = critical(f, Kind.ACK);
        equal(ack.candidateForTrustedPort().recoveryAction().unsentRetainedPayload(), ack.exactBytesForTrustedPort(), "ACK exact persisted retained bytes");
        sendSuccess(f, Kind.ACK);
        f.reducer.onPayload(f.transport, payload("commit.completion.payload"));
        f.reducer.dispatch(critical(f, Kind.WRITE_ACTIVE));
        noPair(f, "active candidate not acknowledged");
        f.ports.writeSuccess();
        Step active = f.reducer.currentStep();
        check(active.snapshot.pairedMac != null && active.snapshot.pairedMac.hostID.equals(id("input.host-device-id")), "paired metadata only exact active readback");
        check(active.snapshot.acknowledgedPhase == RecordPhase.ACTIVE && active.cleanup.kind == Kind.CLEANUP, "cleanup follows active persistence");
        equal(active.critical.candidateForTrustedPort().recoveryAction().unsentRetainedPayload(), active.critical.exactBytesForTrustedPort(), "activation exact retained persisted bytes");
        f.reducer.dispatch(active.cleanup); f.ports.cleanupFailure();
        check(f.reducer.currentStep().snapshot.invitationAdmitted, "cleanup failure retains marker");
        sendSuccess(f, Kind.ACTIVATION);
        check(f.reducer.currentStep().snapshot.end == End.COMPLETE && f.owner.isRetired(), "activation completion retires bootstrap");
        check(f.reducer.currentStep().snapshot.pairedMac != null, "durable paired remains; connected not represented");
        dispatchClose(f);
        check(f.reducer.currentStep().snapshot.transportCloseSubmitted && !f.reducer.currentStep().snapshot.transportCloseAcknowledged, "close submission distinct from completion");
        f.ports.closeSuccess();
        check(f.reducer.currentStep().snapshot.transportCloseAcknowledged, "exact old transport fake completion observed");
        check(f.ports.events.equals(Arrays.asList(Kind.HELLO, Kind.WRITE_PENDING, Kind.CONFIRMATION,
                Kind.WRITE_ACCEPTED, Kind.ADMISSION, Kind.ACK, Kind.WRITE_ACTIVE, Kind.CLEANUP, Kind.ACTIVATION, Kind.CLOSE)), "complete strict ordering trace");
    }
    private static void testOneSlotImmediateRepliesAndOverflow() throws Exception {
        Fixture f = at(Kind.HELLO);
        f.reducer.dispatch(critical(f, Kind.HELLO));
        f.reducer.onPayload(f.transport, payload("hello.host.payload"));
        check(f.reducer.currentStep().critical.kind == Kind.HELLO, "host reply before send callback is bounded deferred");
        f.ports.sendSuccess();
        check(f.reducer.currentStep().critical == null, "deferred hello authenticated after send callback");
        f.reducer.onPayload(f.transport, payload("confirmation.host.payload"));
        writeSuccess(f, Kind.WRITE_PENDING);
        f.reducer.dispatch(critical(f, Kind.CONFIRMATION));
        f.reducer.onPayload(f.transport, payload("commit.proposal.payload"));
        f.ports.sendSuccess();
        check(critical(f, Kind.WRITE_ACCEPTED) != null, "immediate proposal revalidated after confirmation callback");
        writeSuccess(f, Kind.WRITE_ACCEPTED); admissionSuccess(f);
        f.reducer.dispatch(critical(f, Kind.ACK));
        f.reducer.onPayload(f.transport, payload("commit.completion.payload"));
        f.ports.sendSuccess();
        writeSuccess(f, Kind.WRITE_ACTIVE);
        check(f.reducer.currentStep().snapshot.pairedMac != null, "immediate completion takes exact active write boundary");
        Fixture overflow = at(Kind.HELLO);
        overflow.reducer.dispatch(critical(overflow, Kind.HELLO));
        overflow.reducer.onPayload(overflow.transport, payload("hello.host.payload"));
        overflow.reducer.onPayload(overflow.transport, payload("hello.host.payload"));
        check(overflow.reducer.currentStep().snapshot.end == End.PROTOCOL, "second queued payload closes not unbounded queue");
        overflow.ports.sendSuccess(); noPair(overflow, "overflow late send completion inert");
        Fixture undispatched = at(Kind.HELLO);
        undispatched.reducer.onPayload(undispatched.transport, payload("hello.host.payload"));
        check(undispatched.reducer.currentStep().snapshot.end == End.PROTOCOL, "no reply authority before send dispatch");
        Fixture premature = at(Kind.WRITE_PENDING);
        premature.reducer.dispatch(critical(premature, Kind.WRITE_PENDING));
        premature.reducer.onPayload(premature.transport, payload("commit.completion.payload"));
        premature.ports.writeSuccess(); sendSuccess(premature, Kind.CONFIRMATION);
        check(premature.reducer.currentStep().snapshot.end == End.PROTOCOL, "deferred message revalidates phase not preauthorized");
        check(premature.reducer.currentStep().snapshot.acknowledgedPhase == RecordPhase.PENDING, "invalid deferred completion preserves committed pending");
    }
    private static void testWrongOwnersTransportsAndSelectedHost() throws Exception {
        Fixture f = at(Kind.HELLO), sameLogical = at(Kind.HELLO);
        f.reducer.onReady(sameLogical.transport);
        f.reducer.onPayload(sameLogical.transport, payload("hello.host.payload"));
        check(f.reducer.currentStep().snapshot.end == End.NONE, "same IDs not owner/transport authority");
        f.reducer.dispatch(sameLogical.reducer.currentStep().critical);
        check(f.ports.events.isEmpty(), "effect from distinct reducer cannot dispatch");
        Transport replacement = new Transport(f.owner, new Object());
        f.reducer.onReady(replacement); f.reducer.onPayload(replacement, payload("hello.host.payload"));
        check(f.ports.events.isEmpty(), "replacement transport cannot inject");
        sendSuccess(f, Kind.HELLO); f.reducer.onPayload(f.transport, payload("hello.host.payload"));
        check(f.reducer.currentStep().snapshot.end == End.NONE, "wrong source did not consume valid event slot");
        Fixture wrongHost = fixture(null, OTHER, data("derived.host-signing-public-key"), Long.MAX_VALUE, Long.MAX_VALUE);
        wrongHost.reducer.onReady(wrongHost.transport); sendSuccess(wrongHost, Kind.HELLO);
        wrongHost.reducer.onPayload(wrongHost.transport, payload("hello.host.payload"));
        check(wrongHost.reducer.currentStep().snapshot.end == End.PROTOCOL, "selected host identity exact");
        Fixture wrongKey = fixture(null, id("input.host-device-id"), data("derived.viewer-signing-public-key"), Long.MAX_VALUE, Long.MAX_VALUE);
        wrongKey.reducer.onReady(wrongKey.transport); sendSuccess(wrongKey, Kind.HELLO);
        wrongKey.reducer.onPayload(wrongKey.transport, payload("hello.host.payload"));
        check(wrongKey.reducer.currentStep().snapshot.end == End.PROTOCOL, "selected host key exact");
    }
    private static void testWrongWriteReadbackAndStamp() throws Exception {
        for (int mutation = 0; mutation < 13; mutation++) {
            Fixture f = at(Kind.WRITE_PENDING);
            Effect write = critical(f, Kind.WRITE_PENDING); f.reducer.dispatch(write);
            StoreStamp before = write.expectedStoreForTrustedPort(), after = next(write);
            Object issuer = f.ports; Effect observedEffect = write; byte[] readback = write.exactBytesForTrustedPort();
            switch (mutation) {
                case 0: issuer = new Object(); break;
                case 1: observedEffect = at(Kind.WRITE_PENDING).reducer.currentStep().critical; break;
                case 2: before = empty(before.catalogRevision + 1, before.selectionRevision); break;
                case 3: after = stamp(write, after.catalogRevision + 1, after.selectionRevision, SLOT, RecordPhase.PENDING, write.exactDigestForTrustedPort(), write.invitationForTrustedPort()); break;
                case 4: after = stamp(write, after.catalogRevision, after.selectionRevision + 1, SLOT, RecordPhase.PENDING, write.exactDigestForTrustedPort(), write.invitationForTrustedPort()); break;
                case 5: after = stamp(write, after.catalogRevision, after.selectionRevision, OTHER, RecordPhase.PENDING, write.exactDigestForTrustedPort(), write.invitationForTrustedPort()); break;
                case 6: after = stamp(write, after.catalogRevision, after.selectionRevision, SLOT, RecordPhase.ACTIVE, write.exactDigestForTrustedPort(), write.invitationForTrustedPort()); break;
                case 7: after = stamp(write, after.catalogRevision, after.selectionRevision, SLOT, RecordPhase.PENDING, flip(write.exactDigestForTrustedPort()), write.invitationForTrustedPort()); break;
                case 8: after = stamp(write, after.catalogRevision, after.selectionRevision, SLOT, RecordPhase.PENDING, write.exactDigestForTrustedPort(), flip(write.invitationForTrustedPort())); break;
                case 9: readback = flip(readback); break;
                case 10: after = empty(before.catalogRevision + 1, before.selectionRevision); break;
                case 11: readback = new byte[16385]; break;
                case 12: readback = pendingVariantEncoding(); break;
                default: throw new AssertionError();
            }
            f.ports.writeCallback.committed(new WriteObservation(observedEffect, issuer, before, after, readback));
            check(f.reducer.currentStep().snapshot.end == End.ADAPTER, "wrong write observation refuses " + mutation);
            noPair(f, "wrong observation cannot publish candidate");
            check(f.reducer.currentStep().snapshot.acknowledgedPhase == null, "wrong write cannot authorize confirmation");
        }
    }
    private static void testWrongAdmissionAndSendObservation() throws Exception {
        for (int mutation = 0; mutation < 6; mutation++) {
            Fixture f = at(Kind.ADMISSION); Effect admission = critical(f, Kind.ADMISSION); f.reducer.dispatch(admission);
            StoreStamp stamp = admission.expectedStoreForTrustedPort(); Object issuer = f.ports;
            long prior = 0, result = 1; byte[] digest = admission.invitationForTrustedPort(); Effect observed = admission;
            if (mutation == 0) issuer = new Object();
            if (mutation == 1) observed = at(Kind.ADMISSION).reducer.currentStep().critical;
            if (mutation == 2) stamp = empty(stamp.catalogRevision, stamp.selectionRevision);
            if (mutation == 3) prior = 1;
            if (mutation == 4) result = 2;
            if (mutation == 5) digest = flip(digest);
            f.ports.admissionCallback.committed(new AdmissionObservation(observed, issuer, stamp, prior, result, digest));
            check(f.reducer.currentStep().snapshot.end == End.ADAPTER && !f.reducer.currentStep().snapshot.invitationAdmitted, "wrong admission cannot send ACK " + mutation);
            check(f.reducer.currentStep().snapshot.acknowledgedPhase == RecordPhase.ACCEPTED_ISSUED, "admission refusal preserves recoverable ACK");
        }
        for (int mutation = 0; mutation < 4; mutation++) {
            Fixture f = at(Kind.HELLO); Effect hello = critical(f, Kind.HELLO); f.reducer.dispatch(hello);
            f.ports.sendCallback.completed(new SendObservation(mutation == 0 ? at(Kind.HELLO).reducer.currentStep().critical : hello,
                    mutation == 1 ? new Object() : f.ports, mutation == 2 ? new Transport(f.owner, new Object()) : f.transport,
                    mutation == 3 ? null : ViewerBootstrapReducer.Sent.COMPLETED));
            check(f.reducer.currentStep().snapshot.end == End.ADAPTER, "wrong send observation refuses " + mutation);
        }
    }
    private static void testOneShotAndStaleCompletions() throws Exception {
        Fixture f = at(Kind.WRITE_PENDING); Effect write = critical(f, Kind.WRITE_PENDING);
        f.reducer.dispatch(write); f.reducer.dispatch(write);
        check(f.ports.events.size() == 2, "one-shot write dispatch");
        WriteCallback callback = f.ports.writeCallback; WriteObservation observation = f.ports.correctWrite();
        callback.committed(observation); Effect confirmation = critical(f, Kind.CONFIRMATION);
        callback.failed(); callback.committed(observation);
        check(f.reducer.currentStep().critical == confirmation && f.reducer.currentStep().snapshot.end == End.NONE, "success/failure share one callback consumption fence");
        f.reducer.onReady(f.transport); check(f.reducer.currentStep().critical == confirmation, "duplicate ready emits no Hello");
        f.reducer.close(CloseReason.CANCELLED); callback.committed(observation); f.reducer.dispatch(confirmation);
        check(f.ports.events.size() == 2, "retired old effect dispatch inert");
        Fixture successor = at(Kind.HELLO);
        callback.committed(observation); successor.reducer.dispatch(confirmation);
        check(successor.ports.events.isEmpty(), "old callbacks/effects cannot mutate successor with identical IDs");
        Fixture failed = at(Kind.WRITE_PENDING); failed.reducer.dispatch(critical(failed, Kind.WRITE_PENDING));
        WriteCallback failedCallback = failed.ports.writeCallback; WriteObservation failedObservation = failed.ports.correctWrite();
        failedCallback.failed(); failedCallback.committed(failedObservation);
        check(failed.reducer.currentStep().snapshot.end == End.FAILURE && failed.reducer.currentStep().snapshot.acknowledgedPhase == null, "failure first blocks late success authority");
    }
    private static void testRetirementAndFailureAtEveryCriticalCut() throws Exception {
        Kind[] cuts = { Kind.HELLO, Kind.WRITE_PENDING, Kind.CONFIRMATION, Kind.WRITE_ACCEPTED,
                Kind.ADMISSION, Kind.ACK, Kind.WRITE_ACTIVE, Kind.ACTIVATION };
        for (Kind cut : cuts) {
            Fixture f = at(cut); Effect effect = critical(f, cut); RecordPhase before = f.reducer.currentStep().snapshot.acknowledgedPhase;
            f.reducer.dispatch(effect); int submitted = f.ports.events.size();
            Step retired = f.reducer.close(CloseReason.CANCELLED);
            check(f.owner.isRetired() && retired.critical == null && retired.close != null, "synchronous authority retirement " + cut);
            f.ports.complete(cut); f.reducer.dispatch(effect);
            check(f.ports.events.size() == submitted && f.reducer.currentStep().snapshot.acknowledgedPhase == before, "late callback no promotion/send " + cut);
            f.reducer.close(CloseReason.TIMEOUT); dispatchClose(f); dispatchClose(f);
            check(f.ports.close.exactTransportForTrustedPort() == f.transport && f.ports.events.size() == submitted + 1, "exact old transport closes once after retirement " + cut);
            f.ports.closeSuccess(); check(f.reducer.currentStep().snapshot.end == End.CANCELLED, "repeated close preserves first terminal " + cut);
            Fixture failing = at(cut); failing.reducer.dispatch(critical(failing, cut)); RecordPhase previous = failing.reducer.currentStep().snapshot.acknowledgedPhase;
            failing.ports.fail(cut);
            check(failing.reducer.currentStep().snapshot.end == End.FAILURE && failing.reducer.currentStep().snapshot.acknowledgedPhase == previous, "failed/ambiguous operation preserves acknowledged predecessor " + cut);
        }
    }
    private static void testStrictBootstrapProtocolOrdering() throws Exception {
        String[] incoming = { "confirmation.host.payload", "commit.proposal.payload", "commit.completion.payload", "commit.acknowledgement.payload", "commit.activationAcknowledgement.payload" };
        for (String input : incoming) {
            Fixture f = at(Kind.HELLO); sendSuccess(f, Kind.HELLO); f.reducer.onPayload(f.transport, payload(input));
            check(f.reducer.currentStep().snapshot.end == End.PROTOCOL, "without agreement/record refuses " + input);
        }
        Fixture duplicateHello = at(Kind.WRITE_PENDING);
        duplicateHello.reducer.onPayload(duplicateHello.transport, payload("hello.host.payload"));
        check(duplicateHello.reducer.currentStep().snapshot.end == End.PROTOCOL, "duplicate hello before write dispatch refuses");
        Fixture duplicateConfirmation = at(Kind.CONFIRMATION); sendSuccess(duplicateConfirmation, Kind.CONFIRMATION);
        duplicateConfirmation.reducer.onPayload(duplicateConfirmation.transport, payload("confirmation.host.payload"));
        check(duplicateConfirmation.reducer.currentStep().snapshot.end == End.PROTOCOL, "duplicate confirmation after pending refuses");
        Fixture wrongRole = at(Kind.ACK); sendSuccess(wrongRole, Kind.ACK);
        wrongRole.reducer.onPayload(wrongRole.transport, payload("commit.acknowledgement.payload"));
        check(wrongRole.reducer.currentStep().snapshot.end == End.PROTOCOL, "viewer commit not host authority");
        Fixture nullPayload = at(Kind.HELLO); nullPayload.reducer.onPayload(nullPayload.transport, null);
        check(nullPayload.reducer.currentStep().snapshot.end == End.PROTOCOL, "null typed payload refuses");
        Fixture ended = at(Kind.WRITE_PENDING); ended.reducer.onPeerLeft(ended.transport);
        check(ended.reducer.currentStep().snapshot.end == End.FAILURE && ended.owner.isRetired(), "peer left retires before persistence");
    }
    private static void testAcceptedProposalReplayRetainsExactAck() throws Exception {
        Fixture f = at(Kind.ACK); byte[] first = critical(f, Kind.ACK).exactBytesForTrustedPort(); sendSuccess(f, Kind.ACK);
        f.reducer.onPayload(f.transport, payload("commit.proposal.payload")); writeSuccess(f, Kind.WRITE_ACCEPTED);
        check(f.reducer.currentStep().snapshot.acknowledgedPhase == RecordPhase.ACCEPTED_ISSUED, "replay remains accepted not active");
        equal(first, critical(f, Kind.ACK).exactBytesForTrustedPort(), "reauthenticated proposal reuses byte-exact persisted ACK");
        check(f.ports.admissionRevision == 1 && java.util.Collections.frequency(f.ports.events, Kind.ADMISSION) == 1,
                "same generation does not re-admit the one-time invitation; every ACK still follows exact record write");
    }
    private static void testCleanupCannotEraseReplacementAndDoesNotAuthorizeActivation() throws Exception {
        for (int mutation = 0; mutation < 4; mutation++) {
            Fixture f = at(Kind.ACTIVATION); Effect cleanup = f.reducer.currentStep().cleanup; f.reducer.dispatch(cleanup);
            StoreStamp stamp = cleanup.expectedStoreForTrustedPort();
            f.ports.cleanupCallback.completed(new CleanupObservation(cleanup, mutation == 0 ? new Object() : f.ports,
                    mutation == 1 ? empty(stamp.catalogRevision, stamp.selectionRevision + 1) : stamp,
                    mutation == 2 ? flip(cleanup.invitationForTrustedPort()) : cleanup.invitationForTrustedPort(),
                    mutation == 3 ? ViewerBootstrapReducer.Cleaned.RETAINED : ViewerBootstrapReducer.Cleaned.EXACT_CODE_AND_MARKER_REMOVED));
            check(f.reducer.currentStep().snapshot.invitationAdmitted, "wrong cleanup association retains marker " + mutation);
            check(critical(f, Kind.ACTIVATION) != null, "cleanup observation does not create activation authority");
        }
        Fixture success = at(Kind.ACTIVATION); success.reducer.dispatch(success.reducer.currentStep().cleanup); success.ports.cleanupSuccess();
        check(!success.reducer.currentStep().snapshot.invitationAdmitted && success.reducer.currentStep().snapshot.pairedMac != null, "exact cleanup can remove marker only after acknowledged active");
        Fixture retired = at(Kind.ACTIVATION); retired.reducer.dispatch(retired.reducer.currentStep().cleanup); retired.reducer.close(CloseReason.CANCELLED); retired.ports.cleanupSuccess();
        check(retired.reducer.currentStep().snapshot.invitationAdmitted, "late cleanup observation cannot update retired model");
    }
    private static void testBoundedCountersAndNewRecordOnlyAdmission() throws Exception {
        Fixture revision = fixture(null, null, null, 1, Long.MAX_VALUE);
        revision.reducer.onReady(revision.transport); sendSuccess(revision, Kind.HELLO);
        revision.reducer.onPayload(revision.transport, payload("hello.host.payload")); revision.reducer.onPayload(revision.transport, payload("confirmation.host.payload"));
        check(revision.reducer.currentStep().snapshot.end == End.EXHAUSTED && revision.reducer.currentStep().snapshot.acknowledgedPhase == null, "revision exhaustion closes without write/send");
        Fixture ordinal = fixture(null, null, null, Long.MAX_VALUE, 2);
        ordinal.reducer.onReady(ordinal.transport); sendSuccess(ordinal, Kind.HELLO);
        ordinal.reducer.onPayload(ordinal.transport, payload("hello.host.payload")); ordinal.reducer.onPayload(ordinal.transport, payload("confirmation.host.payload")); writeSuccess(ordinal, Kind.WRITE_PENDING);
        check(ordinal.reducer.currentStep().snapshot.end == End.EXHAUSTED && ordinal.reducer.currentStep().snapshot.acknowledgedPhase == RecordPhase.PENDING, "ordinal exhaustion preserves committed pending and never wraps");
        Fixture catalog = fixture(empty(Long.MAX_VALUE, 1), null, null, Long.MAX_VALUE, Long.MAX_VALUE);
        catalog.reducer.onReady(catalog.transport); sendSuccess(catalog, Kind.HELLO);
        catalog.reducer.onPayload(catalog.transport, payload("hello.host.payload")); catalog.reducer.onPayload(catalog.transport, payload("confirmation.host.payload"));
        check(catalog.reducer.currentStep().snapshot.end == End.EXHAUSTED, "catalog revision exhaustion refuses mutation");
        Fixture f = at(Kind.WRITE_PENDING); Effect pending = critical(f, Kind.WRITE_PENDING);
        illegal(() -> fixture(next(pending), null, null, Long.MAX_VALUE, Long.MAX_VALUE));
        illegal(() -> fixture(new StoreStamp(SLOT, OTHER, 0, 0, null, null, null, null), null, null, Long.MAX_VALUE, Long.MAX_VALUE));
        illegal(() -> ViewerBootstrapReducer.bootstrap(f.owner, f.transport, prepared(), identity(),
                new ViewerBootstrapReducer.Invitation(sha(new byte[] { 1 })), empty(0, 3), null, null, 1700000000.25,
                new ViewerBootstrapReducer.Ports(f.ports, f.ports, f.ports, f.ports, f.ports)));
        check(true, "occupied/wrong-local initial catalog never implicitly evicted or repaired");
    }
    private static void testInlineCallbacksAndDefensiveRedaction() throws Exception {
        Fixture f = at(Kind.WRITE_PENDING); Effect write = critical(f, Kind.WRITE_PENDING);
        byte[] bytes = write.exactBytesForTrustedPort(), digest = write.exactDigestForTrustedPort(), invitation = write.invitationForTrustedPort();
        bytes[0] ^= 1; digest[0] ^= 1; invitation[0] ^= 1;
        equal(sha(write.exactBytesForTrustedPort()), write.exactDigestForTrustedPort(), "effect defensive bytes/digest remain exact");
        f.ports.inlineWrite = true; f.reducer.dispatch(write);
        check(critical(f, Kind.CONFIRMATION) != null && f.reducer.currentStep().snapshot.acknowledgedPhase == RecordPhase.PENDING, "inline store callback sees installed outstanding ticket");
        f.ports.inlineSend = true; f.reducer.dispatch(critical(f, Kind.CONFIRMATION));
        check(f.reducer.currentStep().critical == null, "inline send completion accepted once");
        Fixture retiredAtPort = at(Kind.WRITE_PENDING);
        retiredAtPort.ports.beforeWrite = () -> retiredAtPort.reducer.close(CloseReason.CANCELLED);
        retiredAtPort.reducer.dispatch(critical(retiredAtPort, Kind.WRITE_PENDING));
        check(retiredAtPort.ports.events.equals(Arrays.asList(Kind.HELLO))
                && retiredAtPort.reducer.currentStep().snapshot.end == End.CANCELLED,
                "fake trusted port refuses write retired between dispatch admission and eventual side effect");
        for (Object value : new Object[] { write, f.owner, f.transport, f.reducer.currentStep(), f.reducer.currentStep().snapshot,
                write.expectedStoreForTrustedPort(), new ViewerBootstrapReducer.Invitation(sha(new byte[] { 1 })) }) {
            String text = value.toString(); check(text.startsWith("<redacted") && !text.contains("Test Mac") && !text.contains("AAA"), "fixed diagnostic redaction");
        }
        Class<?> receipt = Class.forName("com.elamin.beluga.protocol.ViewerBootstrapReducer$Receipt");
        for (Constructor<?> constructor : receipt.getDeclaredConstructors()) check(Modifier.isPrivate(constructor.getModifiers()), "receipt constructor private; no public persisted=true factory");
    }

    private static final class Fixture {
        final ViewerBootstrapReducer reducer;
        final Owner owner;
        final Transport transport;
        final FakePorts ports;
        Fixture(ViewerBootstrapReducer reducer, Owner owner, Transport transport, FakePorts ports) {
            this.reducer = reducer; this.owner = owner; this.transport = transport; this.ports = ports;
        }
    }
    private static final class FakePorts implements ViewerBootstrapReducer.StorePort, ViewerBootstrapReducer.AdmissionPort,
            ViewerBootstrapReducer.SendPort, ViewerBootstrapReducer.CleanupPort, ViewerBootstrapReducer.ClosePort {
        final List<Kind> events = new ArrayList<>();
        Effect write, admission, send, cleanup, close;
        WriteCallback writeCallback;
        AdmissionCallback admissionCallback;
        SendCallback sendCallback;
        CleanupCallback cleanupCallback;
        CloseCallback closeCallback;
        long admissionRevision;
        boolean inlineWrite, inlineSend;
        Runnable beforeWrite;
        @Override public void persist(Effect effect, WriteCallback callback) {
            if (beforeWrite != null) beforeWrite.run();
            if (effect.ownerRetiredForTrustedPort()) return;
            check(!effect.ownerRetiredForTrustedPort(), "fake store rechecks captured retirement before side effect");
            write = effect; writeCallback = callback; events.add(effect.kind); if (inlineWrite) writeSuccess();
        }
        @Override public void persist(Effect effect, AdmissionCallback callback) {
            check(!effect.ownerRetiredForTrustedPort(), "fake admission rechecks owner");
            admission = effect; admissionCallback = callback; events.add(effect.kind);
        }
        @Override public void send(Effect effect, SendCallback callback) {
            check(!effect.ownerRetiredForTrustedPort(), "fake send rechecks owner");
            send = effect; sendCallback = callback; events.add(effect.kind); if (inlineSend) sendSuccess();
        }
        @Override public void clean(Effect effect, CleanupCallback callback) {
            check(!effect.ownerRetiredForTrustedPort(), "fake cleanup rechecks owner");
            cleanup = effect; cleanupCallback = callback; events.add(effect.kind);
        }
        @Override public void close(Effect effect, CloseCallback callback) {
            check(effect.ownerRetiredForTrustedPort(), "exact old close still runs after retirement");
            close = effect; closeCallback = callback; events.add(effect.kind);
        }
        WriteObservation correctWrite() { return new WriteObservation(write, this, write.expectedStoreForTrustedPort(), next(write), write.exactBytesForTrustedPort()); }
        void writeSuccess() { writeCallback.committed(correctWrite()); }
        void admissionSuccess() {
            AdmissionObservation observation = new AdmissionObservation(admission, this, admission.expectedStoreForTrustedPort(),
                    admissionRevision, admissionRevision + 1, admission.invitationForTrustedPort());
            admissionRevision++; admissionCallback.committed(observation);
        }
        void sendSuccess() { sendCallback.completed(new SendObservation(send, this, send.exactTransportForTrustedPort(), ViewerBootstrapReducer.Sent.COMPLETED)); }
        void cleanupSuccess() { cleanupCallback.completed(new CleanupObservation(cleanup, this, cleanup.expectedStoreForTrustedPort(), cleanup.invitationForTrustedPort(), ViewerBootstrapReducer.Cleaned.EXACT_CODE_AND_MARKER_REMOVED)); }
        void cleanupFailure() { cleanupCallback.failed(); }
        void closeSuccess() { closeCallback.completed(new CloseObservation(close, this, close.exactTransportForTrustedPort(), ViewerBootstrapReducer.Closed.FINISHED)); }
        void complete(Kind kind) {
            switch (kind) {
                case WRITE_PENDING: case WRITE_ACCEPTED: case WRITE_ACTIVE: writeSuccess(); break;
                case ADMISSION: admissionSuccess(); break;
                default: sendSuccess();
            }
        }
        void fail(Kind kind) {
            switch (kind) {
                case WRITE_PENDING: case WRITE_ACCEPTED: case WRITE_ACTIVE: writeCallback.failed(); break;
                case ADMISSION: admissionCallback.failed(); break;
                default: sendCallback.failed();
            }
        }
    }
    private static Fixture fixture(StoreStamp initial, UUID expectedHostID, byte[] expectedHostKey, long maxRevision, long maxOrdinal) throws Exception {
        Owner owner = new Owner(OPERATION, 7); Transport transport = new Transport(owner, new Object()); FakePorts ports = new FakePorts();
        PreparedViewer prepared = prepared(); ViewerIdentity identity = identity();
        ViewerBootstrapReducer.Invitation invitation = new ViewerBootstrapReducer.Invitation(sha("PUBLIC fake canonical invitation association".getBytes(StandardCharsets.UTF_8)));
        ViewerBootstrapReducer.Ports bound = new ViewerBootstrapReducer.Ports(ports, ports, ports, ports, ports);
        StoreStamp stamp = initial == null ? empty(0, 3) : initial;
        ViewerBootstrapReducer reducer = maxRevision == Long.MAX_VALUE && maxOrdinal == Long.MAX_VALUE
                ? ViewerBootstrapReducer.bootstrap(owner, transport, prepared, identity, invitation, stamp, expectedHostID, expectedHostKey, 1700000000.25, bound)
                : ViewerBootstrapReducer.fixtureWithLimits(owner, transport, prepared, identity, invitation, stamp, bound, maxRevision, maxOrdinal);
        return new Fixture(reducer, owner, transport, ports);
    }
    private static Fixture at(Kind desired) throws Exception {
        Fixture f = fixture(null, null, null, Long.MAX_VALUE, Long.MAX_VALUE); f.reducer.onReady(f.transport);
        if (desired == Kind.HELLO) return f; sendSuccess(f, Kind.HELLO);
        f.reducer.onPayload(f.transport, payload("hello.host.payload")); f.reducer.onPayload(f.transport, payload("confirmation.host.payload"));
        if (desired == Kind.WRITE_PENDING) return f; writeSuccess(f, Kind.WRITE_PENDING);
        if (desired == Kind.CONFIRMATION) return f; sendSuccess(f, Kind.CONFIRMATION);
        f.reducer.onPayload(f.transport, payload("commit.proposal.payload"));
        if (desired == Kind.WRITE_ACCEPTED) return f; writeSuccess(f, Kind.WRITE_ACCEPTED);
        if (desired == Kind.ADMISSION) return f; admissionSuccess(f);
        if (desired == Kind.ACK) return f; sendSuccess(f, Kind.ACK);
        f.reducer.onPayload(f.transport, payload("commit.completion.payload"));
        if (desired == Kind.WRITE_ACTIVE) return f; writeSuccess(f, Kind.WRITE_ACTIVE);
        check(desired == Kind.ACTIVATION, "known fixture cut"); return f;
    }
    private static Effect critical(Fixture f, Kind kind) { Effect effect = f.reducer.currentStep().critical; check(effect != null && effect.kind == kind, "expected exact critical " + kind); return effect; }
    private static void sendSuccess(Fixture f, Kind kind) { f.reducer.dispatch(critical(f, kind)); f.ports.sendSuccess(); }
    private static void writeSuccess(Fixture f, Kind kind) { f.reducer.dispatch(critical(f, kind)); f.ports.writeSuccess(); }
    private static void admissionSuccess(Fixture f) { f.reducer.dispatch(critical(f, Kind.ADMISSION)); f.ports.admissionSuccess(); }
    private static void dispatchClose(Fixture f) { Effect effect = f.reducer.currentStep().close; check(effect != null && effect.kind == Kind.CLOSE, "terminal exact close effect"); f.reducer.dispatch(effect); }
    private static void noPair(Fixture f, String label) { check(f.reducer.currentStep().snapshot.pairedMac == null, label); }
    private static StoreStamp empty(long catalog, long selection) { return new StoreStamp(SLOT, id("input.viewer-device-id"), catalog, selection, null, null, null, null); }
    private static StoreStamp next(Effect effect) {
        StoreStamp before = effect.expectedStoreForTrustedPort();
        return stamp(effect, before.catalogRevision + 1, before.selectionRevision, before.target,
                effect.candidateForTrustedPort().phase(), effect.exactDigestForTrustedPort(), effect.invitationForTrustedPort());
    }
    private static StoreStamp stamp(Effect effect, long catalog, long selection, UUID target, RecordPhase phase, byte[] digest, byte[] invitation) {
        ViewerPairRecord candidate = effect.candidateForTrustedPort();
        return new StoreStamp(target, candidate.viewerDeviceID(), catalog, selection, candidate.pairID(), phase, digest, invitation);
    }
    private static Payload payload(String key) throws Exception { return PairingPayloadDecoder.decode(data(key)); }
    private static PreparedViewer prepared() throws Exception {
        return ViewerPairingAuthenticator.authenticateRetainedLocalHello(id("input.viewer-device-id"),
                new String(data("input.viewer-display-name"), StandardCharsets.UTF_8), data("input.viewer-signing-seed"),
                data("input.invitation-secret"), data("input.viewer-ephemeral-private"), data("input.viewer-nonce"), (HelloPayload) payload("hello.viewer.payload"));
    }
    private static ViewerIdentity identity() throws Exception { return ViewerPairingAuthenticator.viewerIdentity(id("input.viewer-device-id"), data("input.viewer-signing-seed")); }
    private static byte[] pendingVariantEncoding() throws Exception {
        ViewerPairingAuthenticator.Agreement agreement = ViewerPairingAuthenticator.acceptHost(prepared(), (HelloPayload) payload("hello.host.payload"));
        ViewerPairRecord otherValidRecord = agreement.makePendingRecord(agreement.authenticateHostConfirmation(
                (PairingPayloadDecoder.ConfirmationPayload) payload("confirmation.host.payload")), 1700000001.25);
        return otherValidRecord.encodeForPrivateStorage(identity()).copyForPrivateStorage();
    }
    private static UUID id(String key) { return UUID.fromString(new String(data(key), StandardCharsets.UTF_8)); }
    private static byte[] data(String key) { byte[] bytes = fixtures.get(key); check(bytes != null, "known public fixture key"); return bytes.clone(); }
    private static byte[] flip(byte[] bytes) { byte[] copy = bytes.clone(); copy[0] ^= 1; return copy; }
    private static byte[] sha(byte[] bytes) {
        try { return MessageDigest.getInstance("SHA-256").digest(bytes); }
        catch (java.security.NoSuchAlgorithmException unavailable) { throw new AssertionError(unavailable); }
    }
    private static Map<String, byte[]> load(Path path) throws Exception {
        byte[] bytes;
        try (InputStream stream = Files.newInputStream(path)) { bytes = stream.readNBytes(65537); }
        check(bytes.length > 0 && bytes.length <= 65536 && hex(sha(bytes)).equals(FIXTURE_SHA), "hash-pinned bounded real Swift public fixture");
        Map<String, byte[]> parsed = new TreeMap<>();
        for (String line : new String(bytes, StandardCharsets.UTF_8).split("\n")) {
            if (line.startsWith("#")) continue; String[] fields = line.split("\t", -1);
            check(fields.length == 2 && parsed.put(fields[0], Base64.getDecoder().decode(fields[1])) == null, "unique fixture row");
        }
        check(parsed.size() == 45, "complete actual45 inventory"); return parsed;
    }
    private static String hex(byte[] bytes) { StringBuilder result = new StringBuilder(); for (byte value : bytes) result.append(String.format(java.util.Locale.ROOT, "%02x", value & 255)); return result.toString(); }
    private interface Throwing { void run() throws Exception; }
    private static void illegal(Throwing operation) throws Exception { try { operation.run(); throw new AssertionError("Expected composition refusal"); } catch (IllegalArgumentException expected) { assertions++; } }
    private static void equal(byte[] expected, byte[] actual, String label) { check(Arrays.equals(expected, actual), label); }
    private static void check(boolean condition, String label) { assertions++; if (!condition) throw new AssertionError(label); }
}
