package com.elamin.beluga.protocol;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import java.util.function.BooleanSupplier;
import org.junit.Before;
import org.junit.Test;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Role;
import com.elamin.beluga.protocol.PairingPayloadDecoder.HelloPayload;
import com.elamin.beluga.protocol.PairingPayloadDecoder.ConfirmationPayload;
import com.elamin.beluga.protocol.PairingPayloadDecoder.CommitPayload;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.*;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.RecordPhase;
import com.elamin.beluga.protocol.ViewerStorageCatalog.Failure;

/** Actual session/codec/parser/reducer/catalog; trusted IN-MEMORY ports, not Android or sockets. */
public final class ViewerPairingSessionTest {
    private static final String ENGINE_SHA = "7d8a58cd34400271d0c68ac1e263450c4ad4978337ae1bb87246362a6d0ec06a";
    private static final String ENVELOPE_SHA = "28690a8285418f4cc6373233302a63e5a3217c063d32032d73dd1bb2ff6f550f";
    private static final long EPOCH = 1_700_000_000_250L;
    private static final UUID SLOT = UUID.fromString("33333333-2222-1111-4444-555555555555");
    private static final String READY = "{\"type\":\"ready\",\"role\":\"viewer\",\"invitationExpiresAt\":\"2023-11-14T22:18:20.250Z\",\"iceServers\":[]}";
    private Map<String, byte[]> engine, envelopes;
    private PairingInvitation invitation;

    @Before public void loadExactIndependentPublicSwiftCaptures() throws Exception {
        engine = load("/public-swift-engine-v1.tsv", ENGINE_SHA, 45, 64 * 1024);
        envelopes = load("/public-swift-bootstrap-envelopes-v1.tsv", ENVELOPE_SHA, 29, 128 * 1024);
        assertArrayEquals(engine.get("input.invitation-secret"), envelopes.get("input.invitation-secret"));
        String[] host = {"hello.host.payload", "confirmation.host.payload", "commit.proposal.payload", "commit.completion.payload"};
        for (int index = 0; index < host.length; index++)
            assertArrayEquals(engine.get(host[index]), envelopes.get("capture.host." + index + ".payload"));
        invitation = invitation(data("input.invitation-secret"));
        byte[] secret = invitation.copySecretForPairing();
        assertEquals(20, secret.length); assertArrayEquals(data("input.invitation-secret"), secret);
        secret[0] ^= 1;
        assertArrayEquals(data("input.invitation-secret"), invitation.copySecretForPairing());
        Arrays.fill(secret, (byte) 0);
        byte[] domain = ascii("AudioStreamer.WorldwideInvitation.Admitted.v1\0");
        MessageDigest digest = MessageDigest.getInstance("SHA-256"); digest.update(domain);
        byte[] canonical = ascii(invitation.exportedCode());
        byte[] expected = digest.digest(canonical);
        byte[] fingerprint = invitation.admissionFingerprint(); assertArrayEquals(expected, fingerprint);
        fingerprint[0] ^= 1; assertArrayEquals(expected, invitation.admissionFingerprint());
        digest.reset(); digest.update(domain);
        assertFalse(Arrays.equals(expected, digest.digest(data("input.invitation-secret"))));
        digest.reset(); digest.update(domain);
        assertFalse(Arrays.equals(expected, digest.digest(ascii(invitation.exportedCode().replace("-", "")))));
        Arrays.fill(canonical, (byte) 0);
    }

    @Test public void fourHostStepsRequireExactTransactionsActivationAndCloseBeforePaired() throws Exception {
        try (Fixture f = fixture()) {
            f.start(); f.ready(); f.completeHostHandshake();
            ViewerPairingSession.Result result = f.result();
            assertEquals(ViewerPairingSession.Status.PAIRED, result.status);
            assertEquals(ViewerPairingSession.Failure.NONE, result.failure);
            assertEquals(id("derived.pair-id-text"), result.pairID);
            assertEquals(id("input.host-device-id"), result.hostID);
            assertEquals(text(data("input.host-display-name")), result.displayName);
            assertEquals(RecordPhase.ACTIVE, f.storage.phase());
            assertEquals(1, f.storage.releases.get()); assertFalse(f.storage.isActive());
            assertEquals(Arrays.asList("activate", "send0", "WRITE_PENDING", "send1", "WRITE_ACCEPTED",
                    "admit", "send2", "WRITE_ACTIVE", "cleanup", "send3", "close", "receipt", "release"), f.trace());
            assertEquals(1, f.connects.get()); assertEquals(4, f.socket.sentCount());
            assertTrue(result.toString().contains("redacted"));
        }
    }

    @Test public void http101AloneNeverStartsHelloOrClaimsPairing() throws Exception {
        try (Fixture f = fixture()) {
            f.start(); await(f.connected);
            assertEquals(0, f.socket.sentCount()); assertEquals(null, f.storage.phase());
            assertFalse(f.session.completion().toCompletableFuture().isDone());
            f.session.cancel(); assertEquals(ViewerPairingSession.Status.CANCELLED, f.result().status);
            assertEquals(1, f.storage.releases.get());
        }
    }

    @Test public void heldActivationSendCompletionCannotReportPairedOrCloseEarly() throws Exception {
        try (Fixture f = fixture()) {
            f.socket.holdSend = 3;
            f.start(); f.ready(); f.completeHostHandshake();
            assertEquals(RecordPhase.ACTIVE, f.storage.phase());
            assertFalse(f.session.completion().toCompletableFuture().isDone());
            assertEquals(0, f.socket.closeCalls.get()); assertEquals(0, f.storage.releases.get());
            f.socket.sent(3).completion.complete(null);
            assertEquals(ViewerPairingSession.Status.PAIRED, f.result().status);
        }
    }

    @Test public void heldNativeCloseAndTerminalNotificationGrantNoReleaseReceipt() throws Exception {
        try (Fixture f = fixture()) {
            f.socket.holdClose = true;
            f.start(); f.ready(); f.completeHostHandshake(); await(f.socket.closeEntered);
            f.listener.onTerminal(NettyPairingWssTransport.FailureCode.CLOSED);
            assertTrue(f.storage.isActive()); assertEquals(0, f.storage.releases.get());
            assertFalse(f.session.completion().toCompletableFuture().isDone());
            f.socket.closed.complete(null);
            assertEquals(ViewerPairingSession.Status.PAIRED, f.result().status);
            assertEquals(1, f.storage.releases.get());
        }
    }

    @Test public void failedNativeCloseRetainsOwnerAndNeverBecomesPaired() throws Exception {
        try (Fixture f = fixture()) {
            f.socket.failClose = true;
            f.start(); f.ready(); f.completeHostHandshake();
            ViewerPairingSession.Result result = f.result();
            assertEquals(ViewerPairingSession.Status.CLEANUP_UNPROVEN, result.status);
            assertEquals(ViewerPairingSession.Failure.DRAIN, result.failure);
            assertEquals(0, f.storage.releases.get()); assertTrue(f.storage.isActive());
            assertEquals(null, result.hostID);
        }
    }

    @Test public void cancelDuringPurePreparationNeverActivatesOrAllocates() throws Exception {
        try (Fixture f = fixture()) {
            f.prepareGate = new Gate(); f.start(); await(f.prepareGate.entered);
            f.session.cancel(); f.prepareGate.release.countDown();
            assertEquals(ViewerPairingSession.Status.CANCELLED, f.result().status);
            assertEquals(0, f.storage.activations.get()); assertEquals(0, f.connects.get());
            assertEquals(0, f.storage.releases.get()); assertFalse(f.storage.isActive());
        }
    }

    @Test public void cancelDuringAtomicActivationRefusesBeforeOwnerPublication() throws Exception {
        try (Fixture f = fixture()) {
            f.storage.activationGate = new Gate(); f.start(); await(f.storage.activationGate.entered);
            f.session.cancel(); f.storage.activationGate.release.countDown();
            assertEquals(ViewerPairingSession.Status.CANCELLED, f.result().status);
            assertEquals(0, f.storage.activations.get()); assertEquals(0, f.connects.get());
            assertEquals(0, f.storage.releases.get()); assertFalse(f.storage.isActive());
        }
    }

    @Test public void cancelWithHeldHelloSendDrainsExactCloseAndRejectsLateInputs() throws Exception {
        try (Fixture f = fixture()) {
            f.socket.holdSend = 0; f.start(); f.ready(); f.socket.sent(0);
            f.session.cancel();
            assertEquals(ViewerPairingSession.Status.CANCELLED, f.result().status);
            assertEquals(1, f.socket.closeCalls.get()); assertEquals(1, f.storage.releases.get());
            byte[] late = envelopes.get("capture.host.0.inbound").clone(); f.listener.onText(late);
            assertArrayEquals(new byte[late.length], late);
            assertEquals(1, f.socket.sentCount()); assertEquals(null, f.storage.phase());
        }
    }

    @Test public void boundedFloodDuringHeldStorageRetiresBeforeAnotherDurableWrite() throws Exception {
        try (Fixture f = fixture()) {
            f.storage.writeGate = new Gate(); f.start(); f.ready(); f.socket.sent(0);
            f.host(0); f.host(1); await(f.storage.writeGate.entered);
            for (int index = 0; index <= ViewerPairingSession.MAXIMUM_QUEUED_FRAMES; index++) f.host(2);
            f.storage.writeGate.release.countDown();
            ViewerPairingSession.Result result = f.result();
            assertEquals(ViewerPairingSession.Status.FAILED, result.status);
            assertEquals(ViewerPairingSession.Failure.OVERFLOW, result.failure);
            assertEquals(1, f.socket.sentCount()); assertEquals(null, f.storage.phase());
            assertEquals(1, f.storage.releases.get());
        }
    }

    @Test public void heldPendingWriteReturningAfterExpiryNeverSendsConfirmation() throws Exception {
        try (Fixture f = fixture()) {
            f.storage.writeGate = new Gate(); f.start(); f.ready(); f.socket.sent(0);
            f.host(0); f.host(1); await(f.storage.writeGate.entered);
            f.clock.advanceSeconds(301); f.storage.writeGate.release.countDown();
            ViewerPairingSession.Result result = f.result();
            assertEquals(ViewerPairingSession.Status.FAILED, result.status);
            assertEquals(ViewerPairingSession.Failure.TIMEOUT, result.failure);
            assertEquals(1, f.socket.sentCount()); assertEquals(1, f.storage.releases.get());
            // Already-entered atomic storage may commit; that is not authority for post-deadline send.
            assertTrue(f.storage.phase() == null || f.storage.phase() == RecordPhase.PENDING);
        }
    }

    @Test public void earlyFactoryReadyIsFencedUntilExactSocketPublication() throws Exception {
        try (Fixture f = fixture()) {
            f.earlyReady = true; f.start(); await(f.connected); f.completeHostHandshake();
            assertEquals(ViewerPairingSession.Status.PAIRED, f.result().status);
            assertEquals(1, f.connects.get());
        }
    }

    @Test public void earlyFactoryCallbacksThenUncertainThrowCannotForgeCloseReceipt() throws Exception {
        try (Fixture f = fixture()) {
            f.earlyReady = true; f.uncertainFactoryThrow = true; f.start();
            ViewerPairingSession.Result result = f.result();
            assertEquals(ViewerPairingSession.Status.CLEANUP_UNPROVEN, result.status);
            assertEquals(ViewerPairingSession.Failure.NETWORK, result.failure);
            assertEquals(0, f.storage.releases.get()); assertTrue(f.storage.isActive());
            assertEquals(0, f.socket.sentCount()); assertEquals(0, f.socket.closeCalls.get());
        }
    }

    @Test public void peerLeftIsTerminalAndNeverStartsReplacementOrReconnect() throws Exception {
        try (Fixture f = fixture()) {
            f.start(); f.ready(); f.socket.sent(0);
            f.listener.onText(ascii("{\"type\":\"peer-left\",\"role\":\"host\"}"));
            assertEquals(ViewerPairingSession.Status.FAILED, f.result().status);
            assertEquals(1, f.storage.releases.get()); assertEquals(1, f.connects.get());
            f.listener.onText(ascii(READY)); assertEquals(1, f.socket.sentCount());
        }
    }

    @Test public void alreadyExpiredBrokerReadyNeverSendsHello() throws Exception {
        try (Fixture f = fixture()) {
            f.start(); await(f.connected);
            f.listener.onText(ascii(READY.replace("22:18:20.250", "22:13:20.000")));
            ViewerPairingSession.Result result = f.result();
            assertEquals(ViewerPairingSession.Status.FAILED, result.status);
            assertEquals(ViewerPairingSession.Failure.TIMEOUT, result.failure);
            assertEquals(0, f.socket.sentCount()); assertEquals(1, f.storage.releases.get());
        }
    }

    @Test public void closeDeadlineNeverReleasesHeldTransportOrReportsPaired() throws Exception {
        try (Fixture f = fixture()) {
            f.socket.holdClose = true; f.start(); f.ready(); f.completeHostHandshake(); await(f.socket.closeEntered);
            f.clock.advanceSeconds(46);
            ViewerPairingSession.Result result = f.result();
            assertEquals(ViewerPairingSession.Status.CLEANUP_UNPROVEN, result.status);
            assertEquals(ViewerPairingSession.Failure.DRAIN, result.failure);
            assertEquals(0, f.storage.releases.get()); assertTrue(f.storage.isActive());
        }
    }

    private Fixture fixture() throws Exception { return new Fixture(); }

    private final class Fixture implements AutoCloseable {
        final List<String> events = Collections.synchronizedList(new ArrayList<>());
        final TestClock clock = new TestClock();
        final AtomicInteger connects = new AtomicInteger();
        final CountDownLatch connected = new CountDownLatch(1);
        final MemoryStorage storage = new MemoryStorage(this);
        final TestSocket socket = new TestSocket(this);
        final ViewerPairingSession session;
        volatile NettyPairingWssTransport.Listener listener;
        volatile Gate prepareGate;
        boolean earlyReady, uncertainFactoryThrow;
        boolean started;
        Fixture() throws Exception {
            session = new ViewerPairingSession((join, received) -> {
                assertEquals("viewer", join.role());
                assertEquals(text(envelopes.get("derived.channel")), join.channelID());
                assertEquals(text(envelopes.get("derived.admission")), join.admissionProofForUpgradeHeader());
                connects.incrementAndGet(); listener = received;
                received.onOpen(); if (earlyReady) received.onText(ascii(READY));
                connected.countDown();
                if (uncertainFactoryThrow) throw new IllegalStateException("Public fixture uncertain allocation");
                return socket;
            }, clock);
        }
        void start() {
            started = true;
            session.start(invitation, (owner, transport, nativeClose) -> {
                storage.prepare(owner, transport, nativeClose);
                Gate gate = prepareGate; if (gate != null) gate.hold();
                return new ViewerPairingSession.Prepared(prepared(),
                        ViewerPairingAuthenticator.viewerIdentity(id("input.viewer-device-id"), data("input.viewer-signing-seed")),
                        storage.stamp(), storage);
            });
        }
        void ready() throws Exception { await(connected); listener.onText(ascii(READY)); }
        void host(int index) { listener.onText(envelopes.get("capture.host." + index + ".inbound").clone()); }
        void completeHostHandshake() throws Exception {
            socket.sent(0); host(0); host(1); socket.sent(1); host(2); socket.sent(2); host(3); socket.sent(3);
        }
        ViewerPairingSession.Result result() throws Exception { return session.completion().toCompletableFuture().get(5, TimeUnit.SECONDS); }
        List<String> trace() { synchronized (events) { return new ArrayList<>(events); } }
        @Override public void close() {
            release(prepareGate); release(storage.activationGate); release(storage.writeGate);
            if (started) {
                session.cancel(); socket.closed.complete(null); socket.failHeldSends();
                try { session.completion().toCompletableFuture().get(5, TimeUnit.SECONDS); }
                catch (InterruptedException error) { Thread.currentThread().interrupt(); throw new AssertionError("Owned session cleanup interrupted", error); }
                catch (Exception error) { throw new AssertionError("Owned session completion must be bounded", error); }
            }
            socket.hostCodec.close(); storage.catalog.close();
        }
    }

    private static final class TestClock implements ViewerPairingSession.Clock {
        final AtomicLong nanos = new AtomicLong(1);
        @Override public long nanoTime() { return nanos.get(); }
        @Override public long epochMillis() { return EPOCH + TimeUnit.NANOSECONDS.toMillis(nanos.get() - 1); }
        void advanceSeconds(long seconds) { nanos.addAndGet(TimeUnit.SECONDS.toNanos(seconds)); }
    }
    private static final class Gate {
        final CountDownLatch entered = new CountDownLatch(1), release = new CountDownLatch(1);
        void hold() throws InterruptedException { entered.countDown(); await(release); }
    }
    private static final class SentFrame {
        final CompletableFuture<Void> completion = new CompletableFuture<>();
    }
    private final class TestSocket implements ViewerPairingSession.Socket {
        final Fixture fixture;
        final PairingBootstrapEnvelopeCodec hostCodec;
        final List<SentFrame> sends = new ArrayList<>();
        final AtomicInteger closeCalls = new AtomicInteger();
        final CountDownLatch closeEntered = new CountDownLatch(1);
        final CompletableFuture<Void> closed = new CompletableFuture<>();
        int holdSend = -1;
        boolean holdClose, failClose;
        private AssertionError assertion;
        TestSocket(Fixture fixture) throws Exception {
            this.fixture = fixture; hostCodec = PairingBootstrapEnvelopeCodec.create(invitation, Role.HOST);
        }
        @Override public CompletionStage<Void> send(byte[] wire, BooleanSupplier authorized) {
            if (!authorized.getAsBoolean()) return failed("Public fixture revoked write");
            try {
                // Decode the actual session's freshly sealed ciphertext, not an echoed send ticket.
                byte[] owned = wire.clone();
                PairingPayloadDecoder.Payload payload;
                try { payload = hostCodec.open(forward(owned)).structurallyAdmittedPayload(); }
                finally { Arrays.fill(owned, (byte) 0); }
                SentFrame frame = new SentFrame(); int index;
                synchronized (this) {
                    index = sends.size(); assertTrue(index < 4);
                    assertAuthenticViewerMessage(index, payload);
                    fixture.events.add("send" + index); sends.add(frame); notifyAll();
                }
                if (index != holdSend) frame.completion.complete(null);
                return frame.completion.thenApply(ignored -> null);
            } catch (AssertionError error) {
                // Surface fixture failures on the test thread, never kill the session worker
                // before its actual close path can run.
                synchronized (this) { assertion = error; notifyAll(); }
                return failed("Public fixture assertion failed");
            } catch (Exception error) { return failed("Public fixture send failed"); }
        }
        @Override public CompletionStage<Void> close() {
            closeCalls.incrementAndGet(); fixture.events.add("close");
            failHeldSends(); closeEntered.countDown();
            if (failClose) closed.completeExceptionally(new IllegalStateException("Public fixture close failed"));
            else if (!holdClose) closed.complete(null);
            return closed.thenApply(ignored -> null);
        }
        synchronized SentFrame sent(int index) throws InterruptedException {
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5);
            while (sends.size() <= index) {
                if (assertion != null) throw assertion;
                long remaining = deadline - System.nanoTime();
                assertTrue("Exact captured send must arrive within bound", remaining > 0);
                TimeUnit.NANOSECONDS.timedWait(this, remaining);
            }
            return sends.get(index);
        }
        synchronized int sentCount() { return sends.size(); }
        void failHeldSends() {
            List<SentFrame> snapshot;
            synchronized (this) { snapshot = new ArrayList<>(sends); }
            for (SentFrame send : snapshot) send.completion.completeExceptionally(new IllegalStateException("Public fixture send closed"));
        }
    }

    private final class MemoryStorage implements ViewerPairingSession.Storage {
        final Fixture fixture;
        final AtomicInteger activations = new AtomicInteger(), releases = new AtomicInteger();
        ViewerStorageCatalog catalog;
        Owner owner; Transport transport;
        ViewerStorageCloseDrain drain;
        ViewerStorageCloseDrain.Receipt receipt;
        volatile Gate activationGate, writeGate;
        private boolean active;
        MemoryStorage(Fixture fixture) throws Exception {
            this.fixture = fixture;
            catalog = ViewerStorageCatalog.firstEnrollment(id("input.viewer-device-id"), data("input.viewer-signing-seed"));
            ViewerStorageCatalog next = catalog.begin(SLOT, invitation.admissionFingerprint(), 0, 0);
            catalog.close(); catalog = next;
        }
        void prepare(Owner exactOwner, Transport exactTransport, ClosePort nativeClose) throws Failure {
            owner = exactOwner; transport = exactTransport;
            drain = new ViewerStorageCloseDrain(owner, transport, nativeClose, observed -> {
                synchronized (this) {
                    ViewerStorageCatalog.demand(active && owner.isRetired() && receipt == null
                            && observed.belongsTo(drain, owner, transport));
                    receipt = observed; fixture.events.add("receipt");
                }
            });
        }
        synchronized StoreStamp stamp() throws Failure { return catalog.stamp(SLOT); }
        @Override public void activate() throws Exception {
            Gate gate = activationGate; if (gate != null) gate.hold();
            synchronized (this) {
                synchronized (owner) {
                    ViewerStorageCatalog.demand(!active && !owner.isRetired() && drain != null);
                    active = true; activations.incrementAndGet(); fixture.events.add("activate");
                }
            }
        }
        @Override public void persist(Effect effect, WriteCallback callback) {
            WriteObservation observed;
            byte[] bytes = effect.exactBytesForTrustedPort();
            try {
                Gate gate = writeGate;
                if (gate != null && effect.kind == Kind.WRITE_PENDING) gate.hold();
                synchronized (this) {
                    requireLive(effect); StoreStamp before = catalog.stamp(SLOT);
                    assertTrue(before.same(effect.expectedStoreForTrustedPort()));
                    ViewerStorageCatalog next = catalog.write(before, bytes);
                    catalog.close(); catalog = next;
                    byte[] readback = catalog.entry(SLOT).bytes();
                    assertArrayEquals(bytes, readback);
                    fixture.events.add(effect.kind.name());
                    observed = new WriteObservation(effect, this, before, catalog.stamp(SLOT), readback);
                    Arrays.fill(readback, (byte) 0);
                }
            } catch (Exception refused) { callback.failed(); return; }
            finally { if (bytes != null) Arrays.fill(bytes, (byte) 0); }
            callback.committed(observed);
        }
        @Override public void persist(Effect effect, AdmissionCallback callback) {
            AdmissionObservation observed;
            try {
                synchronized (this) {
                    requireLive(effect); StoreStamp before = catalog.stamp(SLOT);
                    long previous = catalog.admissionRevision(SLOT);
                    ViewerStorageCatalog next = catalog.admit(before, effect.expectedAdmissionRevisionForTrustedPort(), effect.invitationForTrustedPort());
                    catalog.close(); catalog = next; fixture.events.add("admit");
                    observed = new AdmissionObservation(effect, this, catalog.stamp(SLOT), previous,
                            catalog.admissionRevision(SLOT), catalog.entry(SLOT).invitation());
                }
            } catch (Failure refused) { callback.failed(); return; }
            callback.committed(observed);
        }
        @Override public void clean(Effect effect, CleanupCallback callback) {
            synchronized (this) { fixture.events.add("cleanup"); }
            // No scanner-owned raw code is held here; never claim that the UI erased it.
            callback.completed(new CleanupObservation(effect, this, effect.expectedStoreForTrustedPort(),
                    effect.invitationForTrustedPort(), Cleaned.RETAINED));
        }
        @Override public void close(Effect effect, CloseCallback callback) {
            drain.close(effect, observed -> callback.completed(new CloseObservation(effect, this, transport, Closed.FINISHED)));
        }
        @Override public synchronized void release() throws Failure {
            ViewerStorageCatalog.demand(active && owner.isRetired() && receipt != null
                    && receipt.belongsTo(drain, owner, transport));
            active = false; releases.incrementAndGet(); fixture.events.add("release");
        }
        private void requireLive(Effect effect) throws Failure {
            ViewerStorageCatalog.demand(active && !owner.isRetired() && !effect.ownerRetiredForTrustedPort()
                    && effect.exactTransportForTrustedPort() == transport && effect.expectedStoreForTrustedPort().target.equals(SLOT));
        }
        synchronized boolean isActive() { return active; }
        synchronized RecordPhase phase() throws Failure {
            return catalog.entry(SLOT).record == null ? null : catalog.entry(SLOT).record.phase();
        }
    }

    private ViewerPairingAuthenticator.PreparedViewer prepared() throws Exception {
        return ViewerPairingAuthenticator.authenticateRetainedLocalHello(id("input.viewer-device-id"),
                text(data("input.viewer-display-name")), data("input.viewer-signing-seed"), data("input.invitation-secret"),
                data("input.viewer-ephemeral-private"), data("input.viewer-nonce"),
                (HelloPayload) PairingPayloadDecoder.decode(data("hello.viewer.payload")));
    }
    private void assertAuthenticViewerMessage(int index, PairingPayloadDecoder.Payload payload) throws Exception {
        byte[] reference = envelopes.get("capture.viewer." + index + ".payload");
        if (index == 0) {
            // Retained full Hello is transcript input; its exact bytes are intentionally fixed.
            assertArrayEquals(reference, PairingBootstrapEnvelopeCodec.canonicalPayload(payload)); return;
        }
        byte[] input, expected, signature;
        PairingPayloadDecoder.Payload decoded = PairingPayloadDecoder.decode(reference);
        if (index == 1) {
            assertTrue(payload instanceof ConfirmationPayload && decoded instanceof ConfirmationPayload);
            ConfirmationPayload actual = (ConfirmationPayload) payload;
            input = PairingCanonicalCodec.confirmationSignatureInput(actual.canonicalMessage());
            expected = PairingCanonicalCodec.confirmationSignatureInput(((ConfirmationPayload) decoded).canonicalMessage());
            signature = actual.signature();
        } else {
            assertTrue(payload instanceof CommitPayload && decoded instanceof CommitPayload);
            CommitPayload actual = (CommitPayload) payload;
            input = PairingCanonicalCodec.commitSignatureInput(actual.canonicalMessage());
            expected = PairingCanonicalCodec.commitSignatureInput(((CommitPayload) decoded).canonicalMessage());
            signature = actual.signature();
        }
        // Full domain-separated fields INCLUDING exact MAC/tag must match the independent
        // Swift capture. Swift/BC may produce distinct valid Ed25519 signatures: authenticate
        // the newly emitted signature rather than incorrectly demanding byte equality.
        assertArrayEquals(expected, input);
        assertTrue(BouncyCastlePairingCrypto.ed25519Verify(data("derived.viewer-signing-public-key"), input, signature));
    }
    private byte[] data(String key) { byte[] value = engine.get(key); assertNotNull("Exact public fixture row required", value); return value.clone(); }
    private UUID id(String key) { return UUID.fromString(text(data(key))); }
    private static void release(Gate gate) { if (gate != null) gate.release.countDown(); }
    private static void await(CountDownLatch signal) throws InterruptedException {
        assertTrue("Bounded exact fixture callback required", signal.await(5, TimeUnit.SECONDS));
    }
    private static CompletionStage<Void> failed(String publicDiagnostic) {
        CompletableFuture<Void> result = new CompletableFuture<>();
        result.completeExceptionally(new IllegalStateException(publicDiagnostic)); return result;
    }
    private static byte[] forward(byte[] outbound) {
        String wire = new String(outbound, StandardCharsets.US_ASCII);
        assertTrue(wire.startsWith("{"));
        return ascii("{\"from\":\"viewer\"," + wire.substring(1));
    }
    private static PairingInvitation invitation(byte[] secret) throws Exception {
        assertEquals(20, secret.length);
        byte[] body = new byte[21]; body[0] = 1; System.arraycopy(secret, 0, body, 1, 20);
        MessageDigest hash = MessageDigest.getInstance("SHA-256"); hash.update(ascii("AudioStreamer.RemoteInvitation.Checksum.v1\0"));
        byte[] packet = Arrays.copyOf(body, 25); System.arraycopy(hash.digest(body), 0, packet, 21, 4);
        String alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"; StringBuilder code = new StringBuilder(); int buffer = 0, bits = 0;
        for (byte b : packet) { buffer = (buffer << 8) | (b & 255); bits += 8; while (bits >= 5) { bits -= 5; code.append(alphabet.charAt((buffer >>> bits) & 31)); } }
        return PairingInvitation.parseManual(code.toString());
    }
    private static Map<String, byte[]> load(String resource, String expectedSHA, int inventory, int maximum) throws Exception {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        try (InputStream input = ViewerPairingSessionTest.class.getResourceAsStream(resource)) {
            assertNotNull("Exact public Swift resource required", input);
            byte[] chunk = new byte[4096]; int count;
            while ((count = input.read(chunk)) != -1) {
                assertTrue("Public fixture bounded before append", output.size() + count <= maximum);
                output.write(chunk, 0, count);
            }
        }
        byte[] file = output.toByteArray(); assertTrue(file.length > 0);
        assertArrayEquals(hex(expectedSHA), MessageDigest.getInstance("SHA-256").digest(file));
        Map<String, byte[]> rows = new TreeMap<>(); String previous = "";
        for (String line : new String(file, StandardCharsets.UTF_8).split("\n")) {
            if (line.startsWith("#")) continue;
            String[] fields = line.split("\t", -1); assertEquals(2, fields.length);
            assertTrue(previous.compareTo(fields[0]) < 0);
            byte[] value = Base64.getDecoder().decode(fields[1]);
            assertEquals(fields[1], Base64.getEncoder().encodeToString(value));
            assertEquals(null, rows.put(fields[0], value)); previous = fields[0];
        }
        assertEquals(inventory, rows.size()); return rows;
    }
    private static byte[] hex(String value) {
        byte[] bytes = new byte[value.length() / 2];
        for (int index = 0; index < bytes.length; index++) bytes[index] = (byte) Integer.parseInt(value.substring(index * 2, index * 2 + 2), 16);
        return bytes;
    }
    private static String text(byte[] bytes) { return new String(bytes, StandardCharsets.UTF_8); }
    private static byte[] ascii(String value) { return value.getBytes(StandardCharsets.US_ASCII); }
}
