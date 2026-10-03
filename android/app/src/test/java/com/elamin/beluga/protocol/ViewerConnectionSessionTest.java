package com.elamin.beluga.protocol;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.TreeMap;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import java.util.function.BooleanSupplier;
import org.junit.Test;
import com.elamin.beluga.protocol.PairingPayloadDecoder.CommitPayload;
import com.elamin.beluga.protocol.PairingPayloadDecoder.ConfirmationPayload;
import com.elamin.beluga.protocol.PairingPayloadDecoder.HelloPayload;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Owner;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.StoreStamp;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Transport;
import com.elamin.beluga.protocol.ViewerConnectionSession.Failure;
import com.elamin.beluga.protocol.ViewerConnectionSession.Result;
import com.elamin.beluga.protocol.ViewerConnectionSession.Status;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.AuthFailure;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.SessionCredential;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.ViewerIdentity;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.ViewerPairRecord;
import com.elamin.beluga.protocol.ViewerReconnectStorageLifecycle.CloseReceipt;
import com.elamin.beluga.protocol.ViewerReconnectStorageLifecycle.Reserved;

/** Real retained-fixture authentication/storage lifecycle; fake native ports are NOT device/media proof. */
public final class ViewerConnectionSessionTest {
    private static final UUID VIEWER = UUID.fromString("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE");
    private static final UUID SLOT = UUID.fromString("12345678-1234-5678-ABCD-123456789ABC");

    @Test public void activationPrecedesPublicationAndRequestAndMediaRetainsTheRetiredChildBinding() throws Exception {
        try (Fixture f = new Fixture()) {
            f.socket.holdActivation = true; f.start(); assertTrue(f.socket.activationEntered.await(3, TimeUnit.SECONDS));
            assertEquals(0, f.storage.reservations); assertEquals(0, f.factory.calls); assertEquals("1", f.storage.counter());
            f.socket.listener.onText(f.readyWire(f.exchange)); // same READY must not resend/re-reserve/reset
            f.socket.activation.complete(null); f.awaitActive();
            assertEquals(Arrays.asList("activation", "reserve", "request", "availability-close", "verify", "media-start"), f.order);
            assertEquals(1, f.storage.reservations); assertEquals(2, f.socket.sends);
            assertTrue(f.storage.child.isRetired()); assertTrue(f.factory.guard.getAsBoolean());
            assertEquals(0, f.storage.releases); assertFalse(f.session.completion().toCompletableFuture().isDone());
            assertEquals(f.text(f.reconnect("reconnect.first.credential.channel")), f.factory.owned.channelID());
            f.factory.listener.ended(); Result result = f.result();
            assertEquals(Status.ENDED, result.status); assertEquals(Failure.NONE, result.failure);
            assertTrue(AndroidViewerConnection.permitsProcessRelease(result));
            assertEquals(1, f.storage.releases); assertEquals(1, f.factory.media.closes); assertEquals("2", f.storage.counter());
            assertFalse(f.factory.guard.getAsBoolean()); assertClosed(f.factory.owned);
        }
    }

    @Test public void cancellationWhileActivationWriteIsHeldCannotReserveOrSendRequest() throws Exception {
        try (Fixture f = new Fixture()) {
            f.socket.holdActivation = true; f.start(); assertTrue(f.socket.activationEntered.await(3, TimeUnit.SECONDS));
            f.session.cancel(); Result result = f.result();
            assertEquals(Status.CANCELLED, result.status); assertEquals(Failure.CANCELLED, result.failure);
            assertTrue(AndroidViewerConnection.permitsProcessRelease(result));
            assertFalse(f.socket.lastGuard.getAsBoolean()); assertEquals(1, f.socket.sends);
            assertEquals(0, f.storage.reservations); assertEquals(0, f.factory.calls); assertEquals("1", f.storage.counter());
            assertEquals(1, f.storage.releases);
            f.socket.activation.complete(null); assertEquals(0, f.factory.calls);
        }
    }

    @Test public void replacementReadyAbortsWithoutReusingThePersistedRequestOrCipher() throws Exception {
        try (Fixture f = new Fixture()) {
            f.socket.holdActivation = true; f.start(); assertTrue(f.socket.activationEntered.await(3, TimeUnit.SECONDS));
            f.socket.listener.onText(f.readyWire(Base64.getUrlEncoder().withoutPadding().encodeToString(repeat(0x33, 16))));
            Result result = f.result();
            assertEquals(Status.FAILED, result.status); assertEquals(Failure.PROTOCOL, result.failure);
            assertTrue(AndroidViewerConnection.permitsProcessRelease(result));
            assertEquals(0, f.storage.reservations); assertEquals(1, f.socket.sends); assertEquals(0, f.factory.calls);
            assertEquals("1", f.storage.counter()); assertEquals(1, f.storage.releases);
        }
    }

    @Test public void responseBeforeWriteCompletionIsBoundedAndCannotStartMediaEarly() throws Exception {
        try (Fixture f = new Fixture()) {
            f.socket.holdRequest = true; f.start(); assertTrue(f.socket.requestEntered.await(3, TimeUnit.SECONDS));
            assertEquals(1, f.storage.reservations); assertEquals("2", f.storage.counter());
            assertEquals(0, f.factory.calls); assertEquals(0, f.storage.verifications);
            f.socket.request.complete(null); f.awaitActive();
            assertEquals(1, f.factory.calls); f.factory.listener.ended(); assertEquals(Status.ENDED, f.result().status);
        }
    }

    @Test public void cancellationDuringHeldAvailabilityCloseCannotAllocateMediaOrReleaseEarly() throws Exception {
        try (Fixture f = new Fixture()) {
            f.socket.holdClose = true; f.start(); assertTrue(f.socket.closeEntered.await(3, TimeUnit.SECONDS));
            assertTrue(f.storage.child.isRetired()); assertEquals(0, f.factory.calls);
            f.session.cancel(); assertFalse(f.session.completion().toCompletableFuture().isDone());
            assertEquals(0, f.storage.releases); f.socket.closed.complete(null);
            assertEquals(Status.CANCELLED, f.result().status); assertEquals(0, f.factory.calls);
            assertEquals("2", f.storage.counter()); assertEquals(1, f.storage.releases);
        }
    }

    @Test public void cancellationDuringFreshClosedStoreReadbackCannotExposeCredentialToMedia() throws Exception {
        try (Fixture f = new Fixture()) {
            f.storage.holdVerify = true; f.start(); assertTrue(f.storage.verifyEntered.await(3, TimeUnit.SECONDS));
            f.session.cancel(); assertEquals(0, f.factory.calls); assertEquals(0, f.storage.releases);
            f.storage.verifyRelease.countDown(); assertEquals(Status.CANCELLED, f.result().status);
            assertEquals(0, f.factory.calls); assertEquals("2", f.storage.counter()); assertEquals(1, f.storage.releases);
        }
    }

    @Test public void cancellationDuringNativeFactoryPublicationRevokesAndJoinsTheExactReturnedReceiver() throws Exception {
        try (Fixture f = new Fixture()) {
            f.factory.holdStart = true; f.factory.media.holdClose = true;
            f.start(); assertTrue(f.factory.started.await(3, TimeUnit.SECONDS));
            assertTrue(f.factory.guard.getAsBoolean()); f.session.cancel(); assertFalse(f.factory.guard.getAsBoolean());
            assertClosed(f.factory.owned); assertEquals(0, f.storage.releases);
            f.factory.startRelease.countDown(); assertTrue(f.factory.media.closeEntered.await(3, TimeUnit.SECONDS));
            assertTrue(f.factory.media.revoked); assertFalse(f.session.completion().toCompletableFuture().isDone());
            assertEquals(0, f.storage.releases); f.factory.media.closed.complete(null);
            assertEquals(Status.CANCELLED, f.result().status); assertEquals(1, f.storage.releases);
        }
    }

    @Test public void activeCancelImmediatelyRevokesSecretsAndKeepsAdmissionUntilMediaClose() throws Exception {
        try (Fixture f = new Fixture()) {
            f.factory.media.holdClose = true; f.start(); f.awaitActive(); f.session.cancel();
            assertTrue(f.factory.media.revoked); assertClosed(f.factory.owned); assertFalse(f.factory.guard.getAsBoolean());
            assertTrue(f.factory.media.closeEntered.await(3, TimeUnit.SECONDS)); assertEquals(0, f.storage.releases);
            f.factory.media.closed.complete(null); assertEquals(Status.CANCELLED, f.result().status);
            assertEquals(1, f.storage.releases); assertEquals("2", f.storage.counter());
        }
    }

    @Test public void nativeFailureBeforeAndAfterReadinessIsFailedMediaAndStillJoinsTeardown() throws Exception {
        for (boolean beforeReady : new boolean[] {true, false}) {
            try (Fixture f = new Fixture()) {
                f.factory.failBeforeReady = beforeReady; f.factory.media.holdClose = true; f.start();
                if (!beforeReady) { f.awaitActive(); f.factory.listener.failed(); }
                assertTrue(f.factory.media.closeEntered.await(3, TimeUnit.SECONDS));
                assertTrue(f.factory.media.revoked); assertClosed(f.factory.owned);
                assertFalse(f.factory.guard.getAsBoolean()); assertEquals(0, f.storage.releases);
                assertFalse(f.session.completion().toCompletableFuture().isDone());
                f.factory.media.closed.complete(null); Result result = f.result();
                assertEquals(Status.FAILED, result.status); assertEquals(Failure.MEDIA, result.failure);
                assertTrue(AndroidViewerConnection.permitsProcessRelease(result));
                assertEquals(1, f.factory.media.closes); assertEquals(1, f.storage.releases); assertEquals("2", f.storage.counter());
            }
        }
    }

    @Test public void endBeforeReadinessFailsMediaUnlessCancellationAlreadyWon() throws Exception {
        for (boolean cancelFirst : new boolean[] {false, true}) {
            try (Fixture f = new Fixture()) {
                f.factory.endBeforeReady = true; f.factory.holdStart = cancelFirst; f.factory.media.holdClose = true;
                f.start(); assertTrue(f.factory.started.await(3, TimeUnit.SECONDS));
                if (cancelFirst) { f.session.cancel(); f.factory.startRelease.countDown(); }
                assertTrue(f.factory.media.closeEntered.await(3, TimeUnit.SECONDS));
                assertEquals(0, f.storage.releases); assertTrue(f.factory.media.revoked); assertClosed(f.factory.owned);
                f.factory.media.closed.complete(null); Result result = f.result();
                assertEquals(cancelFirst ? Status.CANCELLED : Status.FAILED, result.status);
                assertEquals(cancelFirst ? Failure.CANCELLED : Failure.MEDIA, result.failure);
                assertTrue(AndroidViewerConnection.permitsProcessRelease(result));
                assertEquals(1, f.factory.media.closes); assertEquals(1, f.storage.releases); assertEquals("2", f.storage.counter());
                f.factory.listener.active(); assertEquals(ViewerConnectionSession.State.TERMINAL, f.session.state());
            }
        }
    }

    @Test public void failedCloseOrUncertainNativeAllocationCannotReleaseBinding() throws Exception {
        for (int mode = 0; mode < 3; mode++) {
            try (Fixture f = new Fixture()) {
                if (mode == 0) f.socket.failClose = true;
                if (mode == 1) f.factory.throwUnknown = true;
                if (mode == 2) f.factory.media.failClose = true;
                f.start(); if (mode == 2) { f.awaitActive(); f.factory.listener.ended(); }
                Result result = f.result(); assertEquals(Status.CLEANUP_UNPROVEN, result.status);
                assertFalse(AndroidViewerConnection.permitsProcessRelease(result));
                assertEquals(0, f.storage.releases); assertEquals("2", f.storage.counter());
                if (f.factory.owned != null) assertClosed(f.factory.owned);
            }
        }
    }

    @Test public void mediaDrainDeadlineRetainsBindingAndLateCompletionCannotReleaseIt() throws Exception {
        try (Fixture f = new Fixture()) {
            f.factory.media.holdClose = true; f.start(); f.awaitActive(); f.session.cancel();
            assertTrue(f.factory.media.closeEntered.await(3, TimeUnit.SECONDS));
            f.clock.set(ViewerConnectionSession.DRAIN_NANOS + 1);
            Result result = f.result(); assertEquals(Status.CLEANUP_UNPROVEN, result.status);
            assertFalse(AndroidViewerConnection.permitsProcessRelease(result)); assertEquals(0, f.storage.releases);
            f.factory.media.closed.complete(null); assertEquals(0, f.storage.releases); assertClosed(f.factory.owned);
        }
    }

    @Test public void startupTimeoutAndCallbackOverflowRevokeWithoutInventingMediaReadiness() throws Exception {
        for (boolean overflow : new boolean[] {false, true}) {
            try (Fixture f = new Fixture()) {
                f.socket.holdActivation = !overflow; f.overflowDuringConnect = overflow; f.start();
                if (!overflow) {
                    assertTrue(f.socket.activationEntered.await(3, TimeUnit.SECONDS));
                    f.clock.set(ViewerConnectionSession.STARTUP_NANOS + 1);
                }
                Result result = f.result(); assertEquals(Status.FAILED, result.status);
                assertEquals(overflow ? Failure.OVERFLOW : Failure.TIMEOUT, result.failure);
                assertEquals(0, f.factory.calls); assertEquals(0, f.storage.reservations);
                assertEquals("1", f.storage.counter()); assertEquals(1, f.storage.releases);
            }
        }
    }

    private static final class Fixture implements AutoCloseable {
        final Map<String, byte[]> pairing = fixture("public-swift-engine-v1.tsv", "7d8a58cd34400271d0c68ac1e263450c4ad4978337ae1bb87246362a6d0ec06a", 45);
        final Map<String, byte[]> reconnect = fixture("public-swift-saved-pair-reconnect-v1.tsv", "3c8ef42139c81e4cff10fcc1957aa0460a7548792ce7e952498966eff51c629e", 98);
        final Map<String, byte[]> capture = fixture("public-swift-availability-v1.tsv", "c204b3e755aacdc8e4563f448547e0e85d17ce5b081e103b53b54f26e530ed20", 20);
        final List<String> order = java.util.Collections.synchronizedList(new ArrayList<>());
        final AtomicLong clock = new AtomicLong();
        final FakeStorage storage = new FakeStorage(this);
        final FakeSocket socket = new FakeSocket(this);
        final FakeFactory factory = new FakeFactory(this);
        final ViewerConnectionSession session;
        final String exchange = text(value(capture, "exchange.wire"));
        boolean overflowDuringConnect;
        Fixture() throws Exception {
            session = new ViewerConnectionSession((join, listener) -> {
                assertEquals(text(value(capture, "derived.channel")), join.channelID());
                assertEquals(text(value(capture, "derived.viewer-admission")), join.admissionProofForUpgradeHeader());
                socket.listener = listener; listener.onOpen(); listener.onText(readyWire(exchange));
                if (overflowDuringConnect) for (int i = 0; i < 4; i++) listener.onText(ascii("{\"type\":\"availability-waiting\"}"));
                return socket;
            }, factory, clock::get);
        }
        void start() { session.start(() -> storage); }
        Result result() throws Exception { return session.completion().toCompletableFuture().get(3, TimeUnit.SECONDS); }
        void awaitActive() throws Exception {
            assertTrue(factory.started.await(3, TimeUnit.SECONDS));
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(3);
            while (session.state() != ViewerConnectionSession.State.ACTIVE && System.nanoTime() - deadline < 0) Thread.yield();
            assertEquals(ViewerConnectionSession.State.ACTIVE, session.state());
        }
        byte[] pairing(String key) { return value(pairing, key); }
        byte[] reconnect(String key) { return value(reconnect, key); }
        String text(byte[] bytes) { return ViewerConnectionSessionTest.text(bytes); }
        byte[] readyWire(String id) { return ascii("{\"exchangeID\":\"" + id + "\",\"role\":\"viewer\",\"type\":\"availability-ready\"}"); }
        @Override public void close() throws Exception {
            session.cancel(); socket.activation.complete(null); socket.request.complete(null); socket.closed.complete(null);
            storage.verifyRelease.countDown(); factory.startRelease.countDown(); factory.media.closed.complete(null);
            if (!session.completion().toCompletableFuture().isDone()) result();
            storage.catalog.close(); if (storage.durable != null) Arrays.fill(storage.durable, (byte) 0);
        }
    }
    private static final class FakeStorage implements ViewerConnectionSession.Storage {
        final Fixture f; final ViewerStorageCatalog catalog;
        ViewerReconnectStorageLifecycle lifecycle; Owner child; Transport transport;
        CloseReceipt receipt; byte[] durable; int reservations, verifications, releases;
        boolean holdVerify; final CountDownLatch verifyEntered = new CountDownLatch(1), verifyRelease = new CountDownLatch(1);
        CompletionStage<Void> closed;
        FakeStorage(Fixture f) throws Exception { this.f = f; catalog = activeCatalog(f); durable = catalog.encode(); }
        @Override public void activate(Owner child, Transport exact, ViewerReconnectStorageLifecycle.NativeClose closer) throws Exception {
            lifecycle = new ViewerReconnectStorageLifecycle(child, exact, catalog.stamp(SLOT), closer);
            this.child = child; transport = exact;
        }
        @Override public ViewerAvailabilityLocator locator() throws Exception { return catalog.entry(SLOT).record.availabilityLocator(); }
        @Override public byte[] retainedActivation() { return f.pairing("commit.activationAcknowledgement.payload"); }
        @Override public Reserved reserve() throws Exception {
            reservations++; f.order.add("reserve");
            ViewerPairingAuthenticator.ReconnectPreparation preparation = catalog.entry(SLOT).record.authenticateRetainedReconnect(
                    ViewerPairingAuthenticator.viewerIdentity(VIEWER, f.pairing("input.viewer-signing-seed")),
                    f.reconnect("reconnect.first.input.viewer-ephemeral-private"), f.reconnect("reconnect.first.input.viewer-nonce"),
                    ReconnectMessages.decodeRequest(f.reconnect("reconnect.first.request.full")));
            return lifecycle.reserve(catalog, preparation, new ViewerReconnectStorageLifecycle.Publication() {
                @Override public void publish(ViewerStorageCatalog next) throws ViewerStorageCatalog.Failure { durable = next.encode(); }
                @Override public byte[] readbackCatalog() { return durable.clone(); }
            });
        }
        @Override public CompletionStage<Void> close() {
            if (closed == null) closed = lifecycle.retireAndClose().thenApply(actual -> { receipt = actual; return null; });
            return closed.thenApply(value -> value);
        }
        @Override public void verifyClosed(StoreStamp exact) throws Exception {
            verifications++; verifyEntered.countDown();
            if (holdVerify) assertTrue(verifyRelease.await(3, TimeUnit.SECONDS));
            assertTrue(child.isRetired()); assertNotNull(receipt); assertTrue(receipt.belongsTo(lifecycle));
            try (ViewerStorageCatalog readback = ViewerStorageCatalog.decode(durable)) { assertTrue(exact.same(readback.stamp(SLOT))); }
            f.order.add("verify");
        }
        @Override public void release() {
            assertTrue(child.isRetired()); assertNotNull(receipt); assertTrue(receipt.belongsTo(lifecycle));
            assertTrue(f.factory.media.closes == 1 || f.factory.calls == 0); releases++;
        }
        String counter() throws Exception { try (ViewerStorageCatalog current = ViewerStorageCatalog.decode(durable)) { return current.entry(SLOT).record.nextOutboundReconnectSequence(); } }
    }
    private static final class FakeSocket implements ViewerConnectionSession.Socket {
        final Fixture f; NettyPairingWssTransport.Listener listener;
        final CompletableFuture<Void> activation = new CompletableFuture<>(), request = new CompletableFuture<>(), closed = new CompletableFuture<>();
        final CountDownLatch activationEntered = new CountDownLatch(1), requestEntered = new CountDownLatch(1), closeEntered = new CountDownLatch(1);
        boolean holdActivation, holdRequest, holdClose, failClose; int sends; BooleanSupplier lastGuard;
        FakeSocket(Fixture f) { this.f = f; }
        @Override public CompletionStage<Void> send(byte[] wire, BooleanSupplier guard) {
            byte[] owned = wire.clone(); lastGuard = guard;
            try {
                assertTrue(guard.getAsBoolean());
                Map<String, Object> outer = PairingBootstrapEnvelopeCodec.parseAvailabilityWire(owned, 90_000);
                byte[] innerBytes = Base64.getUrlDecoder().decode((String) outer.get("envelope"));
                Map<String, Object> inner = PairingBootstrapEnvelopeCodec.parseAvailabilityWire(innerBytes, 65_536);
                long sequence = ((Long) outer.get("seq")).longValue();
                byte[] aad = ReconnectMessages.domain("AudioStreamer.Availability.Envelope.AAD.v1", new byte[] {1},
                        value(f.capture, "derived.channel"), value(f.capture, "exchange.raw"), new byte[] {2}, ByteBuffer.allocate(8).putLong(sequence).array());
                byte[] payload = BouncyCastlePairingCrypto.openCombined(value(f.capture, "derived.viewer-key"),
                        Base64.getDecoder().decode((String) inner.get("ciphertext")), aad);
                sends++;
                if (sends == 1) {
                    assertEquals(0, sequence); assertArrayEquals(value(f.capture, "capture.activation.payload"), payload);
                    f.order.add("activation"); activationEntered.countDown();
                    return holdActivation ? activation : CompletableFuture.completedFuture(null);
                }
                assertEquals(2, sends); assertEquals(1, sequence); assertEquals(1, f.storage.reservations);
                assertArrayEquals(value(f.capture, "capture.request.payload"), payload); f.order.add("request");
                listener.onText(value(f.capture, "capture.response.inbound")); requestEntered.countDown();
                return holdRequest ? request : CompletableFuture.completedFuture(null);
            } catch (Exception refused) { CompletableFuture<Void> failed = new CompletableFuture<>(); failed.completeExceptionally(refused); return failed; }
            finally { Arrays.fill(owned, (byte) 0); }
        }
        @Override public CompletionStage<Void> close() {
            f.order.add("availability-close"); closeEntered.countDown(); listener.onTerminal(NettyPairingWssTransport.FailureCode.CLOSED);
            if (failClose) closed.completeExceptionally(new IllegalStateException("Fixed synthetic native-close failure"));
            else if (!holdClose) closed.complete(null);
            return closed;
        }
    }
    private static final class FakeFactory implements ViewerConnectionSession.MediaFactory {
        final Fixture f; final FakeMedia media = new FakeMedia();
        final CountDownLatch started = new CountDownLatch(1), startRelease = new CountDownLatch(1);
        volatile SessionCredential owned; volatile BooleanSupplier guard; volatile ViewerConnectionSession.MediaListener listener;
        boolean holdStart, throwUnknown, failBeforeReady, endBeforeReady; int calls;
        FakeFactory(Fixture f) { this.f = f; }
        @Override public ViewerConnectionSession.Media start(SessionCredential credential, BooleanSupplier guard,
                ViewerConnectionSession.MediaListener listener) {
            calls++; owned = credential; this.guard = guard; this.listener = listener;
            assertTrue(guard.getAsBoolean()); assertTrue(f.storage.child.isRetired()); assertEquals(1, f.storage.verifications);
            assertEquals(0, f.storage.releases); f.order.add("media-start"); started.countDown();
            if (throwUnknown) throw new IllegalStateException("Fixed synthetic uncertain allocation");
            if (holdStart) {
                try { assertTrue(startRelease.await(3, TimeUnit.SECONDS)); }
                catch (InterruptedException refused) { Thread.currentThread().interrupt(); throw new IllegalStateException("Fixed fixture interrupted"); }
            }
            if (failBeforeReady) listener.failed();
            else if (endBeforeReady) listener.ended();
            else listener.active();
            return media;
        }
    }
    private static final class FakeMedia implements ViewerConnectionSession.Media {
        final CompletableFuture<Void> closed = new CompletableFuture<>(); final CountDownLatch closeEntered = new CountDownLatch(1);
        volatile boolean revoked; boolean holdClose, failClose; int closes;
        @Override public void revoke() { revoked = true; }
        @Override public CompletionStage<Void> close() {
            closes++; closeEntered.countDown();
            if (failClose) closed.completeExceptionally(new IllegalStateException("Fixed synthetic media-close failure"));
            else if (!holdClose) closed.complete(null);
            return closed;
        }
    }
    private static void assertClosed(SessionCredential credential) throws Exception {
        try { credential.channelID(); fail("Retired credential remained usable"); }
        catch (AuthFailure expected) { assertEquals(ViewerPairingAuthenticator.FailureCode.INVALID_RECONNECT, expected.code()); }
    }
    private static ViewerStorageCatalog activeCatalog(Fixture f) throws Exception {
        ViewerIdentity identity = ViewerPairingAuthenticator.viewerIdentity(VIEWER, f.pairing("input.viewer-signing-seed"));
        ViewerPairingAuthenticator.PreparedViewer prepared = ViewerPairingAuthenticator.authenticateRetainedLocalHello(VIEWER, "Test iPhone",
                f.pairing("input.viewer-signing-seed"), f.pairing("input.invitation-secret"), f.pairing("input.viewer-ephemeral-private"), f.pairing("input.viewer-nonce"),
                (HelloPayload) PairingPayloadDecoder.decode(f.pairing("hello.viewer.payload")));
        ViewerPairingAuthenticator.Agreement agreement = ViewerPairingAuthenticator.acceptHost(prepared,
                (HelloPayload) PairingPayloadDecoder.decode(f.pairing("hello.host.payload")));
        ViewerPairRecord pending = agreement.makePendingRecord(agreement.authenticateHostConfirmation(
                (ConfirmationPayload) PairingPayloadDecoder.decode(f.pairing("confirmation.host.payload"))), 1700000000.25);
        ViewerPairRecord accepted = pending.prepareAcknowledgement((CommitPayload) PairingPayloadDecoder.decode(f.pairing("commit.proposal.payload")), identity).record();
        ViewerPairRecord active = accepted.acceptCompletion((CommitPayload) PairingPayloadDecoder.decode(f.pairing("commit.completion.payload")), identity).record();
        ViewerStorageCatalog[] chain = new ViewerStorageCatalog[6];
        try {
            chain[0] = ViewerStorageCatalog.firstEnrollment(VIEWER, f.pairing("input.viewer-signing-seed"));
            chain[1] = chain[0].begin(SLOT, repeat(0x33, 32), 0, 0);
            chain[2] = chain[1].write(chain[1].stamp(SLOT), pending.encodeForPrivateStorage(identity).copyForPrivateStorage());
            chain[3] = chain[2].write(chain[2].stamp(SLOT), accepted.encodeForPrivateStorage(identity).copyForPrivateStorage());
            chain[4] = chain[3].admit(chain[3].stamp(SLOT), 0, repeat(0x33, 32));
            chain[5] = chain[4].write(chain[4].stamp(SLOT), active.encodeForPrivateStorage(identity).copyForPrivateStorage()); return chain[5];
        } finally { for (int i = 0; i < 5; i++) if (chain[i] != null) chain[i].close(); }
    }
    private static Map<String, byte[]> fixture(String name, String sha, int count) throws Exception {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        try (InputStream input = ViewerConnectionSessionTest.class.getResourceAsStream("/" + name)) {
            assertNotNull("Exact public fixture resource required", input); byte[] chunk = new byte[4096]; int n;
            while ((n = input.read(chunk)) != -1) { assertTrue(output.size() + n <= 131072); output.write(chunk, 0, n); }
        }
        byte[] bytes = output.toByteArray(); StringBuilder digest = new StringBuilder();
        for (byte b : MessageDigest.getInstance("SHA-256").digest(bytes)) digest.append(String.format(Locale.ROOT, "%02x", b & 255));
        assertEquals(sha, digest.toString()); Map<String, byte[]> rows = new TreeMap<>(); String previous = "";
        for (String line : text(bytes).split("\n")) {
            if (line.startsWith("#")) continue;
            String[] fields = line.split("\t", -1); assertEquals(2, fields.length); assertTrue(previous.compareTo(fields[0]) < 0);
            byte[] value = Base64.getDecoder().decode(fields[1]); assertEquals(fields[1], Base64.getEncoder().encodeToString(value));
            assertNull(rows.put(fields[0], value)); previous = fields[0];
        }
        assertEquals(count, rows.size()); return rows;
    }
    private static byte[] value(Map<String, byte[]> rows, String name) { byte[] value = rows.get(name); assertNotNull("Public fixture row required", value); return value.clone(); }
    private static byte[] repeat(int value, int count) { byte[] bytes = new byte[count]; Arrays.fill(bytes, (byte) value); return bytes; }
    private static String text(byte[] bytes) { return new String(bytes, StandardCharsets.US_ASCII); }
    private static byte[] ascii(String text) { return text.getBytes(StandardCharsets.US_ASCII); }
}
