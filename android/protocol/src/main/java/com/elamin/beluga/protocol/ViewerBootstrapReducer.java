package com.elamin.beluga.protocol;

import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Arrays;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Phase;
import com.elamin.beluga.protocol.PairingPayloadDecoder.CommitPayload;
import com.elamin.beluga.protocol.PairingPayloadDecoder.ConfirmationPayload;
import com.elamin.beluga.protocol.PairingPayloadDecoder.HelloPayload;
import com.elamin.beluga.protocol.PairingPayloadDecoder.Payload;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.Agreement;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.AuthFailure;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.PreparedViewer;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.RecordPhase;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.RecordTransition;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.VerifiedHostConfirmation;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.ViewerIdentity;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.ViewerPairRecord;

/**
 * PRIVATE bootstrap-only reducer and trusted fake-port composition model.
 * Package visibility is not an in-process security boundary. Ports are injected authority,
 * not implemented storage/transport; their receipts prove no Android or disk durability.
 * No thread, executor, I/O, availability, reconnect, media or identity enrollment is created.
 */
final class ViewerBootstrapReducer {
    enum Kind { HELLO, WRITE_PENDING, CONFIRMATION, WRITE_ACCEPTED, ADMISSION, ACK,
        WRITE_ACTIVE, ACTIVATION, CLEANUP, CLOSE }
    enum End { NONE, COMPLETE, CANCELLED, PROTOCOL, ADAPTER, EXHAUSTED, FAILURE }
    enum CloseReason { CANCELLED, TIMEOUT, TARGET_CHANGED }
    enum Sent { COMPLETED }
    enum Cleaned { EXACT_CODE_AND_MARKER_REMOVED, RETAINED }
    enum Closed { FINISHED }

    static final class Owner {
        private final UUID operationID;
        private final long generation;
        private final AtomicBoolean retired = new AtomicBoolean();
        private final AtomicBoolean bound = new AtomicBoolean();
        Owner(UUID operationID, long generation) {
            require(nonzero(operationID) && generation > 0);
            this.operationID = operationID; this.generation = generation;
        }
        boolean isRetired() { return retired.get(); }
        /** Immediate cancellation fence; never performs reducer callbacks, disk or native IO. */
        void retire() { synchronized (this) { retired.set(true); } }
        @Override public String toString() { return "<redacted bootstrap owner>"; }
    }
    static final class Transport {
        private final Owner owner;
        private final Object exactInstance;
        Transport(Owner owner, Object exactInstance) {
            require(owner != null && exactInstance != null);
            this.owner = owner; this.exactInstance = exactInstance;
        }
        /** Read-only exact owner relationship; grants no binding or mutable authority. */
        boolean ownedBy(Owner exactOwner) { return owner == exactOwner; }
        @Override public String toString() { return "<redacted exact bootstrap transport>"; }
    }
    /** Trusted parsed-invitation association only; this slice does not implement its parser. */
    static final class Invitation {
        private final byte[] digest;
        Invitation(byte[] admittedCanonicalFingerprint) { digest = exact(admittedCanonicalFingerprint, 32); }
        @Override public String toString() { return "<redacted bootstrap invitation association>"; }
    }
    /** Immutable selected slot/new-record CAS stamp supplied by the trusted catalog adapter. */
    static final class StoreStamp {
        final UUID target, localID, pairID;
        final long catalogRevision, selectionRevision;
        final RecordPhase phase;
        private final byte[] recordDigest, invitationDigest;
        StoreStamp(UUID target, UUID localID, long catalogRevision, long selectionRevision,
                UUID pairID, RecordPhase phase, byte[] recordDigest, byte[] invitationDigest) {
            require(nonzero(target) && nonzero(localID) && catalogRevision >= 0 && selectionRevision >= 0);
            require((pairID == null && phase == null && recordDigest == null && invitationDigest == null)
                    || (nonzero(pairID) && phase != null && recordDigest != null && invitationDigest != null));
            this.target = target; this.localID = localID; this.catalogRevision = catalogRevision;
            this.selectionRevision = selectionRevision; this.pairID = pairID; this.phase = phase;
            this.recordDigest = recordDigest == null ? null : exact(recordDigest, 32);
            this.invitationDigest = invitationDigest == null ? null : exact(invitationDigest, 32);
        }
        byte[] recordDigest() { return copy(recordDigest); }
        byte[] invitationDigest() { return copy(invitationDigest); }
        boolean same(StoreStamp other) {
            return other != null && target.equals(other.target) && localID.equals(other.localID)
                    && catalogRevision == other.catalogRevision && selectionRevision == other.selectionRevision
                    && java.util.Objects.equals(pairID, other.pairID) && phase == other.phase
                    && Arrays.equals(recordDigest, other.recordDigest) && Arrays.equals(invitationDigest, other.invitationDigest);
        }
        @Override public String toString() { return "<redacted bootstrap store stamp>"; }
    }
    static final class PairedMac {
        final UUID pairID, hostID;
        final String displayName;
        private PairedMac(ViewerPairRecord record) {
            pairID = record.pairID(); hostID = record.hostDeviceID(); displayName = record.hostDisplayName();
        }
        @Override public String toString() { return "<redacted acknowledged paired Mac metadata>"; }
    }
    static final class Snapshot {
        final End end;
        final RecordPhase acknowledgedPhase;
        final PairedMac pairedMac;
        final boolean invitationAdmitted, transportCloseSubmitted, transportCloseAcknowledged;
        final long revision;
        private Snapshot(ViewerBootstrapReducer reducer) {
            end = reducer.end; revision = reducer.revision;
            acknowledgedPhase = reducer.durable == null ? null : reducer.durable.phase();
            pairedMac = acknowledgedPhase == RecordPhase.ACTIVE ? new PairedMac(reducer.durable) : null;
            invitationAdmitted = reducer.admitted;
            transportCloseSubmitted = reducer.closeEffect != null && reducer.closeEffect.dispatched;
            transportCloseAcknowledged = reducer.closeAcknowledged;
        }
        @Override public String toString() { return "<redacted bootstrap snapshot; paired is not connected>"; }
    }
    static final class Step {
        final Snapshot snapshot;
        final Effect critical, cleanup, close;
        private Step(ViewerBootstrapReducer reducer) {
            snapshot = new Snapshot(reducer); critical = reducer.current;
            cleanup = reducer.cleanupEffect; close = reducer.closeEffect;
        }
        @Override public String toString() { return "<redacted bootstrap effect plan>"; }
    }
    /** Closed exact-operation ticket; object equality, never logical IDs alone, grants admission. */
    private static final class Ticket {
        final Owner owner;
        final UUID operationID, target, pairID, commitID;
        final long generation, ordinal, revision;
        final Kind purpose;
        final StoreStamp predecessor;
        private Ticket(ViewerBootstrapReducer reducer, Kind purpose, ViewerPairRecord candidate) {
            owner = reducer.owner; operationID = owner.operationID; generation = owner.generation;
            target = reducer.stamp.target; pairID = candidate == null ? null : candidate.pairID();
            commitID = candidate == null ? null : candidate.commitID(); ordinal = reducer.ordinal;
            revision = reducer.revision; this.purpose = purpose; predecessor = reducer.stamp;
        }
    }
    static final class Effect {
        final Kind kind;
        private final Ticket ticket;
        private final Transport transport;
        private final ViewerPairRecord candidate;
        private final byte[] bytes, digest, invitationDigest;
        private final long priorAdmissionRevision;
        private boolean dispatched;
        private Effect(ViewerBootstrapReducer reducer, Kind kind, ViewerPairRecord candidate, byte[] bytes) {
            this.kind = kind; ticket = new Ticket(reducer, kind, candidate); transport = reducer.transport;
            this.candidate = candidate; this.bytes = copy(bytes); digest = bytes == null ? null : sha256(bytes);
            invitationDigest = reducer.invitation.digest.clone();
            priorAdmissionRevision = reducer.admissionRevision;
        }
        byte[] exactBytesForTrustedPort() { return copy(bytes); }
        byte[] exactDigestForTrustedPort() { return copy(digest); }
        byte[] invitationForTrustedPort() { return invitationDigest.clone(); }
        StoreStamp expectedStoreForTrustedPort() { return ticket.predecessor; }
        ViewerPairRecord candidateForTrustedPort() { return candidate; }
        Transport exactTransportForTrustedPort() { return transport; }
        boolean ownerRetiredForTrustedPort() { return ticket.owner.isRetired(); }
        long expectedAdmissionRevisionForTrustedPort() { return priorAdmissionRevision; }
        @Override public String toString() { return "<redacted exact bootstrap effect>"; }
    }
    interface WriteCallback { void committed(WriteObservation observation); void failed(); }
    interface AdmissionCallback { void committed(AdmissionObservation observation); void failed(); }
    interface SendCallback { void completed(SendObservation observation); void failed(); }
    interface CleanupCallback { void completed(CleanupObservation observation); void failed(); }
    interface CloseCallback { void completed(CloseObservation observation); }
    interface StorePort { void persist(Effect exactWrite, WriteCallback callback); }
    interface AdmissionPort { void persist(Effect exactAdmission, AdmissionCallback callback); }
    interface SendPort { void send(Effect exactSend, SendCallback callback); }
    interface CleanupPort { void clean(Effect exactCleanup, CleanupCallback callback); }
    interface ClosePort { void close(Effect exactClose, CloseCallback callback); }
    static final class Ports {
        final StorePort store;
        final AdmissionPort admission;
        final SendPort send;
        final CleanupPort cleanup;
        final ClosePort close;
        Ports(StorePort store, AdmissionPort admission, SendPort send, CleanupPort cleanup, ClosePort close) {
            require(store != null && admission != null && send != null && cleanup != null && close != null);
            this.store = store; this.admission = admission; this.send = send; this.cleanup = cleanup; this.close = close;
        }
    }
    /** Observations are untrusted until the exact injected issuer/callback/ticket/readback checks. */
    static final class WriteObservation {
        final Effect effect;
        final Object issuer;
        final StoreStamp before, after;
        private final byte[] readback;
        WriteObservation(Effect effect, Object issuer, StoreStamp before, StoreStamp after, byte[] readback) {
            this.effect = effect; this.issuer = issuer; this.before = before; this.after = after;
            this.readback = bounded(readback, ViewerPairRecord.MAXIMUM_PRIVATE_RECORD_BYTES);
        }
    }
    static final class AdmissionObservation {
        final Effect effect;
        final Object issuer;
        final StoreStamp recordStamp;
        final long priorRevision, resultingRevision;
        private final byte[] invitationDigest;
        AdmissionObservation(Effect effect, Object issuer, StoreStamp recordStamp, long priorRevision,
                long resultingRevision, byte[] invitationDigest) {
            this.effect = effect; this.issuer = issuer; this.recordStamp = recordStamp;
            this.priorRevision = priorRevision; this.resultingRevision = resultingRevision;
            this.invitationDigest = bounded(invitationDigest, 32);
        }
    }
    static final class SendObservation {
        final Effect effect;
        final Object issuer;
        final Transport transport;
        final Sent result;
        SendObservation(Effect effect, Object issuer, Transport transport, Sent result) {
            this.effect = effect; this.issuer = issuer; this.transport = transport; this.result = result;
        }
    }
    static final class CleanupObservation {
        final Effect effect;
        final Object issuer;
        final StoreStamp recordStamp;
        private final byte[] invitationDigest;
        final Cleaned result;
        CleanupObservation(Effect effect, Object issuer, StoreStamp recordStamp, byte[] invitationDigest, Cleaned result) {
            this.effect = effect; this.issuer = issuer; this.recordStamp = recordStamp;
            this.invitationDigest = bounded(invitationDigest, 32); this.result = result;
        }
    }
    static final class CloseObservation {
        final Effect effect;
        final Object issuer;
        final Transport transport;
        final Closed result;
        CloseObservation(Effect effect, Object issuer, Transport transport, Closed result) {
            this.effect = effect; this.issuer = issuer; this.transport = transport; this.result = result;
        }
    }
    private static final class Receipt {
        final Effect effect;
        final Object issuer;
        final StoreStamp resultingStamp;
        private Receipt(Effect effect, Object issuer, StoreStamp resultingStamp) {
            this.effect = effect; this.issuer = issuer; this.resultingStamp = resultingStamp;
        }
    }
    private static final class Deferred {
        final Owner owner;
        final Transport transport;
        final Payload payload;
        private Deferred(Owner owner, Transport transport, Payload payload) {
            this.owner = owner; this.transport = transport; this.payload = payload;
        }
    }

    private final Owner owner;
    private final Transport transport;
    private final ViewerIdentity identity;
    private final Invitation invitation;
    private final Ports ports;
    private final UUID expectedHostID;
    private final byte[] expectedHostKey;
    private final double createdAt;
    private final long maximumRevision, maximumOrdinal;
    private PreparedViewer prepared;
    private Agreement agreement;
    private ViewerPairRecord durable;
    private StoreStamp stamp;
    private byte[] unsentConfirmation;
    private Deferred deferred;
    private Effect current, cleanupEffect, closeEffect;
    private long revision, ordinal, admissionRevision;
    private boolean helloStarted, admitted, closeAcknowledged;
    private End end = End.NONE;

    private ViewerBootstrapReducer(Owner owner, Transport transport, PreparedViewer prepared, ViewerIdentity identity,
            Invitation invitation, StoreStamp initial, UUID expectedHostID, byte[] expectedHostKey, double createdAt,
            Ports ports, long maximumRevision, long maximumOrdinal) {
        require(owner != null && !owner.isRetired() && transport != null && transport.owner == owner
                && prepared != null && identity != null && invitation != null && initial != null && ports != null);
        require(initial.pairID == null && initial.localID.equals(identity.deviceID())
                && prepared.deviceID().equals(identity.deviceID())
                && Arrays.equals(prepared.signingPublicKey(), identity.signingPublicKey()));
        require((expectedHostID == null && expectedHostKey == null)
                || (nonzero(expectedHostID) && expectedHostKey != null && expectedHostKey.length == 32));
        require(!Double.isNaN(createdAt) && !Double.isInfinite(createdAt) && maximumRevision > 0 && maximumOrdinal > 0);
        require(owner.bound.compareAndSet(false, true));
        this.owner = owner; this.transport = transport; this.prepared = prepared; this.identity = identity;
        this.invitation = invitation; stamp = initial; this.expectedHostID = expectedHostID;
        this.expectedHostKey = expectedHostKey == null ? null : exact(expectedHostKey, 32); this.createdAt = createdAt;
        this.ports = ports; this.maximumRevision = maximumRevision; this.maximumOrdinal = maximumOrdinal;
    }
    static ViewerBootstrapReducer bootstrap(Owner owner, Transport transport, PreparedViewer prepared,
            ViewerIdentity identity, Invitation invitation, StoreStamp initial, UUID expectedHostID,
            byte[] expectedHostKey, double createdAt, Ports ports) {
        return new ViewerBootstrapReducer(owner, transport, prepared, identity, invitation, initial,
                expectedHostID, expectedHostKey, createdAt, ports, Long.MAX_VALUE, Long.MAX_VALUE);
    }
    /** PRIVATE fixture limit, no environment knob or production runtime admission shortcut. */
    static ViewerBootstrapReducer fixtureWithLimits(Owner owner, Transport transport, PreparedViewer prepared,
            ViewerIdentity identity, Invitation invitation, StoreStamp initial, Ports ports, long maxRevision, long maxOrdinal) {
        return new ViewerBootstrapReducer(owner, transport, prepared, identity, invitation, initial,
                null, null, 1700000000.25, ports, maxRevision, maxOrdinal);
    }
    synchronized Step currentStep() { return new Step(this); }
    synchronized Step onReady(Transport source) {
        if (!live(source) || helloStarted) return new Step(this);
        helloStarted = true; emit(Kind.HELLO, null, prepared.helloPayload()); return new Step(this);
    }
    synchronized Step onPayload(Transport source, Payload payload) {
        if (!live(source)) return new Step(this);
        if (payload == null || encoded(payload).length > PairingPayloadDecoder.MAXIMUM_PLAINTEXT_BYTES) {
            retire(End.PROTOCOL); return new Step(this);
        }
        if (current != null) {
            if (!current.dispatched || deferred != null) retire(End.PROTOCOL);
            else deferred = new Deferred(owner, source, payload);
        } else process(payload);
        return new Step(this);
    }
    /** Retires the owner before taking the reducer monitor; a final acknowledgement commit uses this same short owner fence. */
    Step close(CloseReason reason) {
        owner.retire();
        synchronized (this) { retire(reason == CloseReason.TIMEOUT ? End.FAILURE : End.CANCELLED); return new Step(this); }
    }
    synchronized Step onPeerLeft(Transport source) {
        if (live(source)) retire(End.FAILURE); return new Step(this);
    }
    private boolean live(Transport source) {
        return end == End.NONE && !owner.isRetired() && source == transport && source.owner == owner;
    }
    private boolean current(Effect effect) {
        return effect != null && current == effect && live(effect.transport) && effect.ticket.owner == owner
                && effect.ticket.operationID.equals(owner.operationID) && effect.ticket.generation == owner.generation
                && effect.ticket.ordinal > 0 && effect.ticket.ordinal <= ordinal
                && effect.ticket.revision > 0 && effect.ticket.revision <= revision
                && effect.ticket.purpose == effect.kind && effect.ticket.target.equals(stamp.target)
                && effect.ticket.predecessor.same(stamp);
    }
    private void process(Payload payload) {
        try {
            if (payload instanceof HelloPayload) {
                if (!helloStarted || agreement != null || durable != null) { retire(End.PROTOCOL); return; }
                Agreement accepted = ViewerPairingAuthenticator.acceptHost(prepared, (HelloPayload) payload);
                if (expectedHostID != null && (!expectedHostID.equals(accepted.hostDeviceID())
                        || !Arrays.equals(expectedHostKey, accepted.hostSigningPublicKey()))) { retire(End.PROTOCOL); return; }
                agreement = accepted; prepared = null;
            } else if (payload instanceof ConfirmationPayload) {
                if (agreement == null || durable != null) { retire(End.PROTOCOL); return; }
                VerifiedHostConfirmation proof = agreement.authenticateHostConfirmation((ConfirmationPayload) payload);
                ViewerPairRecord candidate = agreement.makePendingRecord(proof, createdAt);
                unsentConfirmation = PairingCanonicalCodec.confirmationPayload(agreement.constructUnsentViewerConfirmation(proof));
                write(Kind.WRITE_PENDING, candidate);
            } else if (payload instanceof CommitPayload) {
                CommitPayload commit = (CommitPayload) payload;
                if (durable == null) { retire(End.PROTOCOL); return; }
                if (commit.phase() == Phase.PROPOSAL && (durable.phase() == RecordPhase.PENDING
                        || durable.phase() == RecordPhase.ACCEPTED_ISSUED)) {
                    write(Kind.WRITE_ACCEPTED, durable.prepareAcknowledgement(commit, identity).record());
                } else if (commit.phase() == Phase.COMPLETION && durable.phase() == RecordPhase.ACCEPTED_ISSUED && admitted) {
                    RecordTransition transition = durable.acceptCompletion(commit, identity);
                    write(Kind.WRITE_ACTIVE, transition.record());
                } else retire(End.PROTOCOL);
            } else retire(End.PROTOCOL);
        } catch (AuthFailure | IllegalArgumentException refused) { retire(End.PROTOCOL); }
    }
    private void write(Kind purpose, ViewerPairRecord candidate) throws AuthFailure {
        if (stamp.catalogRevision == Long.MAX_VALUE) { retire(End.EXHAUSTED); return; }
        // This exact signed encoding is frozen ONCE, never re-encoded to admit a callback.
        byte[] encoding = candidate.encodeForPrivateStorage(identity).copyForPrivateStorage();
        emit(purpose, candidate, encoding); Arrays.fill(encoding, (byte) 0);
    }
    private Effect effect(Kind kind, ViewerPairRecord candidate, byte[] bytes) {
        if (revision == maximumRevision || ordinal == maximumOrdinal) { retire(End.EXHAUSTED); return null; }
        revision++; ordinal++; return new Effect(this, kind, candidate, bytes);
    }
    private void emit(Kind kind, ViewerPairRecord candidate, byte[] bytes) { current = effect(kind, candidate, bytes); }
    private void drain() {
        if (current == null && deferred != null && end == End.NONE && !owner.isRetired()) {
            Deferred next = deferred; deferred = null;
            if (next.owner != owner || next.transport != transport) retire(End.PROTOCOL); else process(next.payload);
        }
    }
    private void retire(End reason) {
        owner.retire();
        if (end != End.NONE) return;
        end = reason; current = null; cleanupEffect = null; deferred = null; prepared = null; agreement = null;
        if (unsentConfirmation != null) Arrays.fill(unsentConfirmation, (byte) 0);
        unsentConfirmation = null;
        // Terminal cleanup owns its old transport. It grants no runtime authority and needs no counter increment.
        closeEffect = new Effect(this, Kind.CLOSE, durable, null);
    }

    /** One-shot dispatch, with outstanding state established BEFORE an inline trusted-port callback. */
    void dispatch(Effect effect) {
        synchronized (this) {
            boolean terminalClose = effect != null && effect == closeEffect && effect.kind == Kind.CLOSE;
            boolean cleanup = effect != null && effect == cleanupEffect && effect.kind == Kind.CLEANUP && live(effect.transport);
            if (!(terminalClose || cleanup || current(effect)) || effect.dispatched) return;
            effect.dispatched = true;
        }
        AtomicBoolean consumed = new AtomicBoolean();
        // Close-only cleanup may run after retirement. Authorizing ports must ALSO recheck this
        // captured latch immediately before their eventual side effect; already-begun work cannot be recalled.
        if (effect.kind != Kind.CLOSE && owner.isRetired()) return;
        try {
            switch (effect.kind) {
                case WRITE_PENDING: case WRITE_ACCEPTED: case WRITE_ACTIVE:
                    ports.store.persist(effect, new WriteCallback() {
                        @Override public void committed(WriteObservation observation) {
                            if (consumed.compareAndSet(false, true)) acceptWrite(effect, ports.store, observation);
                        }
                        @Override public void failed() { if (consumed.compareAndSet(false, true)) fail(effect); }
                    }); break;
                case ADMISSION:
                    ports.admission.persist(effect, new AdmissionCallback() {
                        @Override public void committed(AdmissionObservation observation) {
                            if (consumed.compareAndSet(false, true)) acceptAdmission(effect, ports.admission, observation);
                        }
                        @Override public void failed() { if (consumed.compareAndSet(false, true)) fail(effect); }
                    }); break;
                case HELLO: case CONFIRMATION: case ACK: case ACTIVATION:
                    ports.send.send(effect, new SendCallback() {
                        @Override public void completed(SendObservation observation) {
                            if (consumed.compareAndSet(false, true)) acceptSend(effect, ports.send, observation);
                        }
                        @Override public void failed() { if (consumed.compareAndSet(false, true)) fail(effect); }
                    }); break;
                case CLEANUP:
                    ports.cleanup.clean(effect, new CleanupCallback() {
                        @Override public void completed(CleanupObservation observation) {
                            if (consumed.compareAndSet(false, true)) acceptCleanup(effect, ports.cleanup, observation);
                        }
                        @Override public void failed() { if (consumed.compareAndSet(false, true)) retainCleanup(effect); }
                    }); break;
                case CLOSE:
                    ports.close.close(effect, new CloseCallback() {
                        @Override public void completed(CloseObservation observation) {
                            if (consumed.compareAndSet(false, true)) acceptClose(effect, ports.close, observation);
                        }
                    }); break;
                default: throw new IllegalStateException("Invalid private bootstrap effect");
            }
        } catch (RuntimeException adapterFailure) {
            if (consumed.compareAndSet(false, true)) {
                if (effect.kind == Kind.CLEANUP) retainCleanup(effect);
                else if (effect.kind != Kind.CLOSE) fail(effect);
            }
        }
    }
    private synchronized void fail(Effect effect) {
        synchronized (owner) { if (current(effect)) retire(End.FAILURE); }
    }
    private synchronized void acceptWrite(Effect effect, StorePort issuer, WriteObservation observation) {
        if (!current(effect)) return;
        StoreStamp after = observation == null ? null : observation.after;
        boolean matches = observation != null && observation.effect == effect && observation.issuer == issuer
                && observation.before != null && observation.before.same(effect.ticket.predecessor)
                && after != null && after.catalogRevision == stamp.catalogRevision + 1
                && after.selectionRevision == stamp.selectionRevision && after.target.equals(stamp.target)
                && after.localID.equals(identity.deviceID()) && effect.candidate.pairID().equals(after.pairID)
                && after.phase == effect.candidate.phase() && Arrays.equals(after.recordDigest, effect.digest)
                && Arrays.equals(after.invitationDigest, effect.invitationDigest)
                && Arrays.equals(observation.readback, effect.bytes) && Arrays.equals(sha256(observation.readback), effect.digest);
        if (!matches) { rejectObservation(effect); return; }
        synchronized (owner) {
            // Close can retire the latch while the caller holds the reducer monitor. Recheck at
            // the acknowledgement linearization point, not just before readback validation.
            if (!current(effect)) return;
            Receipt receipt = new Receipt(effect, issuer, after);
            if (receipt.effect != current || receipt.issuer != ports.store) { retire(End.ADAPTER); return; }
            durable = effect.candidate; stamp = receipt.resultingStamp; current = null;
            switch (effect.kind) {
                case WRITE_PENDING:
                    emit(Kind.CONFIRMATION, durable, unsentConfirmation); unsentConfirmation = null; agreement = null; break;
                case WRITE_ACCEPTED:
                    // The exact immutable attempt/pair/invitation association was already admitted.
                    // Replays still persist retained ACK state, but do not re-admit the one-time code.
                    if (admitted) emit(Kind.ACK, durable, durable.recoveryAction().unsentRetainedPayload());
                    else if (admissionRevision == Long.MAX_VALUE) retire(End.EXHAUSTED);
                    else emit(Kind.ADMISSION, durable, null); break;
                case WRITE_ACTIVE:
                    // Paired metadata now derives ONLY from the acknowledged exact active record.
                    emit(Kind.ACTIVATION, durable, durable.recoveryAction().unsentRetainedPayload());
                    if (end == End.NONE) cleanupEffect = effect(Kind.CLEANUP, durable, null);
                    break;
                default: retire(End.ADAPTER);
            }
        }
        drain();
    }
    private synchronized void acceptAdmission(Effect effect, AdmissionPort issuer, AdmissionObservation observation) {
        if (!current(effect)) return;
        if (observation == null || observation.effect != effect || observation.issuer != issuer
                || !stamp.same(observation.recordStamp) || effect.priorAdmissionRevision != admissionRevision
                || observation.priorRevision != effect.priorAdmissionRevision
                || observation.resultingRevision != effect.priorAdmissionRevision + 1
                || !Arrays.equals(observation.invitationDigest, effect.invitationDigest)) { rejectObservation(effect); return; }
        synchronized (owner) {
            if (!current(effect)) return;
            Receipt receipt = new Receipt(effect, issuer, stamp);
            if (receipt.issuer != ports.admission) { retire(End.ADAPTER); return; }
            admissionRevision = observation.resultingRevision; admitted = true; current = null;
            emit(Kind.ACK, durable, durable.recoveryAction().unsentRetainedPayload());
        }
        drain();
    }
    private synchronized void acceptSend(Effect effect, SendPort issuer, SendObservation observation) {
        if (!current(effect)) return;
        if (observation == null || observation.effect != effect || observation.issuer != issuer
                || observation.transport != transport || observation.result != Sent.COMPLETED) { rejectObservation(effect); return; }
        synchronized (owner) {
            if (!current(effect)) return;
            current = null;
            if (effect.kind == Kind.ACTIVATION) retire(End.COMPLETE);
        }
        drain();
    }
    private synchronized void acceptCleanup(Effect effect, CleanupPort issuer, CleanupObservation observation) {
        synchronized (owner) {
            if (end != End.NONE || owner.isRetired() || cleanupEffect != effect) return;
            cleanupEffect = null;
            if (observation != null && observation.effect == effect && observation.issuer == issuer
                    && stamp.same(observation.recordStamp) && Arrays.equals(effect.invitationDigest, observation.invitationDigest)
                    && observation.result == Cleaned.EXACT_CODE_AND_MARKER_REMOVED) admitted = false;
        }
    }
    private synchronized void retainCleanup(Effect effect) { if (cleanupEffect == effect) cleanupEffect = null; }
    private void rejectObservation(Effect effect) {
        synchronized (owner) { if (current(effect)) retire(End.ADAPTER); }
    }
    private synchronized void acceptClose(Effect effect, ClosePort issuer, CloseObservation observation) {
        if (closeEffect == effect && observation != null && observation.effect == effect && observation.issuer == issuer
                && observation.transport == transport && observation.result == Closed.FINISHED) closeAcknowledged = true;
    }
    private static byte[] encoded(Payload payload) {
        if (payload instanceof HelloPayload) return PairingCanonicalCodec.helloPayload(((HelloPayload) payload).canonicalMessage());
        if (payload instanceof ConfirmationPayload) return PairingCanonicalCodec.confirmationPayload(((ConfirmationPayload) payload).canonicalMessage());
        if (payload instanceof CommitPayload) return PairingCanonicalCodec.commitPayload(((CommitPayload) payload).canonicalMessage());
        return new byte[PairingPayloadDecoder.MAXIMUM_PLAINTEXT_BYTES + 1];
    }
    private static byte[] sha256(byte[] bytes) {
        if (bytes == null) return null;
        try { return MessageDigest.getInstance("SHA-256").digest(bytes); }
        catch (NoSuchAlgorithmException unavailable) { throw new IllegalStateException("Required private SHA-256 unavailable"); }
    }
    private static boolean nonzero(UUID id) { return id != null && (id.getMostSignificantBits() != 0 || id.getLeastSignificantBits() != 0); }
    private static byte[] copy(byte[] bytes) { return bytes == null ? null : bytes.clone(); }
    private static byte[] bounded(byte[] bytes, int maximum) { return bytes == null || bytes.length > maximum ? null : bytes.clone(); }
    private static byte[] exact(byte[] bytes, int count) { require(bytes != null && bytes.length == count); return bytes.clone(); }
    private static void require(boolean condition) { if (!condition) throw new IllegalArgumentException("Invalid private bootstrap composition"); }
}
