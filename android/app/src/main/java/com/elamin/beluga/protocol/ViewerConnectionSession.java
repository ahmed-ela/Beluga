package com.elamin.beluga.protocol;

import java.util.ArrayDeque;
import java.util.Arrays;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.BooleanSupplier;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Owner;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.StoreStamp;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Transport;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.SessionCredential;
import com.elamin.beluga.protocol.ViewerReconnectStorageLifecycle.NativeClose;
import com.elamin.beluga.protocol.ViewerReconnectStorageLifecycle.Reserved;

/**
 * One selected-ACTIVE connection, not a disposable health check. A parent cancellation fence
 * survives retirement of the availability child. Its exact store binding is retained through
 * media teardown. Readiness is NOT evidence of decoded audio/video. No UI, retry or enrollment.
 * Blocking trusted storage/native factory calls cannot be forcibly cancelled by this worker.
 */
final class ViewerConnectionSession {
    static final long STARTUP_NANOS = 30_000_000_000L, DRAIN_NANOS = 10_000_000_000L;
    private static final int MAXIMUM_FRAMES = 4;
    enum State { PREPARING, AVAILABILITY, STARTING_MEDIA, ACTIVE, CLOSING, TERMINAL }
    enum Status { ENDED, CANCELLED, FAILED, CLEANUP_UNPROVEN }
    enum Failure { NONE, CANCELLED, PREPARATION, PROTOCOL, NETWORK, OVERFLOW, TIMEOUT, MEDIA, DRAIN, RELEASE }
    static final class Result {
        final Status status; final Failure failure;
        private Result(Status status, Failure failure) { this.status = status; this.failure = failure; }
        @Override public String toString() { return "<Beluga connection terminal; not decoded-media evidence>"; }
    }
    interface Clock { long nanoTime(); }
    interface Socket {
        CompletionStage<Void> send(byte[] wire, BooleanSupplier authorized);
        /** Actual exact socket, callback and event-loop drainage. */
        CompletionStage<Void> close();
    }
    interface AvailabilityConnector {
        Socket connect(ViewerAvailabilityEnvelopeCodec.JoinHeaders join, NettyPairingWssTransport.Listener listener)
                throws PreallocationRefusal;
    }
    static final class PreallocationRefusal extends Exception {
        private static final long serialVersionUID = 1L;
        PreallocationRefusal() { super("Beluga connection refused before allocation"); }
    }
    /** May read existing storage, but may not enroll, publish a binding or allocate native work. */
    interface Preparation { Storage prepare() throws Exception; }
    interface Storage {
        /** Atomic publication: refusal must leave no binding and allocate no native transport. */
        void activate(Owner child, Transport exact, NativeClose trustedClose) throws Exception;
        ViewerAvailabilityLocator locator() throws Exception;
        /** Exact selected ACTIVE record's retained activation payload; no regeneration. */
        byte[] retainedActivation() throws Exception;
        Reserved reserve() throws Exception;
        CompletionStage<Void> close() throws Exception;
        void verifyClosed(StoreStamp exactCommitted) throws Exception;
        /** Only after exact child close and all parent-owned native media drainage. */
        void release() throws Exception;
    }
    interface MediaListener {
        /** Operational native readiness only, not a PCM or video-frame observation. */
        void active();
        /** Native startup/session failure; no raw exception, SDP, route or credential is exposed. */
        void failed();
        void ended();
    }
    interface Media {
        /** Idempotent short synchronous delivery/command gate. No IO or callback into this session. */
        void revoke();
        /** Joins exact receiver, signaling, callback and pending native-allocation teardown. */
        CompletionStage<Void> close();
    }
    interface MediaFactory {
        /**
         * Transfers credential ownership to exactly one codec/native session, never a copy or
         * another peer. This parent retains an idempotent cleanup reference and may close it
         * immediately at revocation. Native teardown still must drain before storage release.
         * Must consult authorized at actual allocation/publication and queued native work.
         * A checked refusal proves no allocation; any unchecked/null outcome is uncertain.
         */
        Media start(SessionCredential credential, BooleanSupplier authorized, MediaListener listener)
                throws PreallocationRefusal;
    }
    private enum Allocation { NOT_STARTED, STARTING, OWNED, REFUSED, UNKNOWN }
    private final AvailabilityConnector connector;
    private final MediaFactory mediaFactory;
    private final Clock clock;
    private final Object mailbox = new Object(), parentFence = new Object();
    private final Owner child = new Owner(UUID.randomUUID(), 1);
    private final Transport availabilityTransport = new Transport(child, this);
    private final ArrayDeque<byte[]> frames = new ArrayDeque<>();
    private final AtomicReference<Failure> failure = new AtomicReference<>(Failure.NONE);
    private final AtomicBoolean started = new AtomicBoolean();
    private final CompletableFuture<Result> terminal = new CompletableFuture<>();
    private volatile boolean parentRetired, finished, intentionalAvailabilityClose, startupComplete;
    private volatile SessionCredential credential;
    private volatile Media media;
    private volatile Socket socket;
    private volatile Allocation availabilityAllocation = Allocation.NOT_STARTED;
    private Allocation mediaAllocation = Allocation.NOT_STARTED;
    private volatile State state = State.PREPARING;
    private long startupDeadline;
    // Mailbox scalars; no callback executes crypto, store IO, or reducer/native work.
    private boolean opened, mediaReady, mediaEnded;
    // Worker-only ownership.
    private Storage storage;
    private ViewerAvailabilityLocator locator;
    private ViewerAvailabilityEnvelopeCodec codec;
    private Reserved reserved;
    private ReconnectMessages.Response response;
    private String exchange;
    private boolean activated, availabilityClosed, released, interrupted;

    ViewerConnectionSession(AvailabilityConnector connector, MediaFactory mediaFactory, Clock clock) {
        if (connector == null || mediaFactory == null || clock == null) throw new IllegalArgumentException();
        this.connector = connector; this.mediaFactory = mediaFactory; this.clock = clock;
    }
    static ViewerConnectionSession production(MediaFactory mediaFactory) {
        return new ViewerConnectionSession((join, listener) -> {
            final NettyPairingWssTransport nativeSocket;
            try { nativeSocket = NettyPairingWssTransport.connectAvailability(NettyPairingWssTransport.PRODUCTION_ORIGIN, join, listener); }
            catch (NettyPairingWssTransport.TransportFailure refused) { throw new PreallocationRefusal(); }
            return new Socket() {
                @Override public CompletionStage<Void> send(byte[] wire, BooleanSupplier guard) { return nativeSocket.sendGuarded(wire, guard); }
                @Override public CompletionStage<Void> close() { return nativeSocket.closeAsync(); }
            };
        }, mediaFactory, System::nanoTime);
    }
    CompletionStage<Result> start(Preparation preparation) {
        if (preparation == null || !started.compareAndSet(false, true)) throw new IllegalStateException();
        startupDeadline = clock.nanoTime() + STARTUP_NANOS;
        Thread worker = new Thread(() -> run(preparation), "Beluga-connection-session"); worker.setDaemon(true);
        try { worker.start(); }
        catch (RuntimeException refused) { fail(Failure.PREPARATION); clearLocal(); complete(true); }
        return completion();
    }
    CompletionStage<Result> completion() { return terminal.thenApply(value -> value); }
    State state() { return state; }
    void cancel() { fail(Failure.CANCELLED); }
    private boolean authorized() { return !parentRetired && (startupComplete || clock.nanoTime() - startupDeadline < 0); }
    private void demandLive() throws Refused {
        if (!authorized()) { if (!parentRetired) fail(Failure.TIMEOUT); throw new Refused(); }
    }
    private static final class Refused extends Exception { private static final long serialVersionUID = 1L; }

    private void run(Preparation preparation) {
        try {
            demandLive(); storage = preparation.prepare(); if (storage == null) throw new Refused(); demandLive();
            storage.activate(child, availabilityTransport, this::closeAvailabilityNative); activated = true; demandLive();
            locator = storage.locator(); demandLive(); codec = locator.createCodec();
            state = State.AVAILABILITY; availabilityAllocation = Allocation.STARTING;
            try { socket = connector.connect(locator.copyJoinHeaders(), availabilityListener()); }
            catch (PreallocationRefusal refused) { availabilityAllocation = Allocation.REFUSED; fail(Failure.NETWORK); throw new Refused(); }
            catch (RuntimeException uncertain) { availabilityAllocation = Allocation.UNKNOWN; fail(Failure.NETWORK); throw new Refused(); }
            if (socket == null) { availabilityAllocation = Allocation.UNKNOWN; fail(Failure.NETWORK); throw new Refused(); }
            availabilityAllocation = Allocation.OWNED; demandLive();
            while (!isOpened() || exchange == null) { processFrames(false); demandLive(); waitMailbox(startupDeadline); }
            byte[] activation = storage.retainedActivation();
            try { demandLive(); send(codec.sealActivation(activation).copyWireBytes(), false); }
            finally { if (activation != null) Arrays.fill(activation, (byte) 0); }
            demandLive(); reserved = storage.reserve(); demandLive();
            byte[] request = reserved.requestPayloadForTrustedSender();
            try { send(codec.sealRequest(request).copyWireBytes(), true); }
            finally { Arrays.fill(request, (byte) 0); }
            while (response == null) { processFrames(true); demandLive(); waitMailbox(startupDeadline); }
            SessionCredential derived = reserved.completeResponse(response); response = null;
            synchronized (parentFence) {
                if (parentRetired) { derived.close(); throw new Refused(); }
                credential = derived;
            }
            demandLive(); intentionalAvailabilityClose = true;
            if (!closeAvailability()) throw new Refused();
            demandLive(); storage.verifyClosed(reserved.afterStamp()); demandLive();
            codec.close(); codec = null; locator.close(); locator = null;
            state = State.STARTING_MEDIA; mediaAllocation = Allocation.STARTING;
            Media created;
            try { created = mediaFactory.start(credential, this::authorized, mediaListener()); }
            catch (PreallocationRefusal refused) { mediaAllocation = Allocation.REFUSED; fail(Failure.MEDIA); throw new Refused(); }
            catch (RuntimeException uncertain) { mediaAllocation = Allocation.UNKNOWN; fail(Failure.MEDIA); throw new Refused(); }
            if (created == null) { mediaAllocation = Allocation.UNKNOWN; fail(Failure.MEDIA); throw new Refused(); }
            synchronized (parentFence) { media = created; mediaAllocation = Allocation.OWNED; }
            if (parentRetired) revokeMedia(created);
            while (!isMediaEnded()) {
                demandLive();
                if (isMediaReady()) {
                    synchronized (parentFence) {
                        if (parentRetired) throw new Refused();
                        startupComplete = true; state = State.ACTIVE;
                    }
                }
                waitMailbox(startupComplete ? clock.nanoTime() + STARTUP_NANOS : startupDeadline);
            }
        } catch (Exception | Error refused) {
            if (failure.get() == Failure.NONE) fail(activated ? Failure.PROTOCOL : Failure.PREPARATION);
        } finally {
            retireParent(); state = State.CLOSING;
            boolean clean = drainAndRelease(); clearLocal(); complete(clean);
            if (interrupted) Thread.currentThread().interrupt();
        }
    }
    private void send(byte[] wire, boolean request) throws Exception {
        try {
            demandLive();
            BooleanSupplier guard = () -> authorized() && !child.isRetired() && (!request || (reserved != null && reserved.canSend()));
            if (!awaitStage(socket.send(wire, guard), startupDeadline, true, request)) { fail(Failure.NETWORK); throw new Refused(); }
            demandLive();
        } finally { Arrays.fill(wire, (byte) 0); }
    }
    private void processFrames(boolean allowResponse) throws Exception {
        byte[] wire;
        while ((wire = takeFrame()) != null) {
            try {
                demandLive(); ViewerAvailabilityEnvelopeCodec.Event event = codec.receive(wire);
                switch (event.kind()) {
                    case READY:
                        if (exchange == null) exchange = event.exchangeID();
                        else if (!exchange.equals(event.exchangeID())) throw new Refused();
                        break;
                    case WAITING: if (exchange != null) throw new Refused(); break;
                    case SIGNAL_RESPONSE:
                        if (!allowResponse || response != null || reserved == null) throw new Refused();
                        response = event.response(); break;
                    case PEER_LEFT: case SERVER_ERROR: fail(Failure.NETWORK); throw new Refused();
                    default: throw new Refused();
                }
            } finally { Arrays.fill(wire, (byte) 0); }
        }
    }
    private NettyPairingWssTransport.Listener availabilityListener() {
        return new NettyPairingWssTransport.Listener() {
            @Override public void onOpen() { synchronized (mailbox) { if (!finished) { opened = true; mailbox.notifyAll(); } } }
            @Override public void onText(byte[] utf8) {
                if (utf8 == null || utf8.length == 0 || utf8.length > ViewerAvailabilityEnvelopeCodec.MAXIMUM_WIRE_BYTES) {
                    if (utf8 != null) Arrays.fill(utf8, (byte) 0); fail(Failure.OVERFLOW); return;
                }
                boolean overflow = false;
                synchronized (mailbox) {
                    if (finished || parentRetired || intentionalAvailabilityClose) { Arrays.fill(utf8, (byte) 0); return; }
                    if (frames.size() >= MAXIMUM_FRAMES) overflow = true;
                    else { frames.addLast(utf8); mailbox.notifyAll(); }
                }
                if (overflow) { Arrays.fill(utf8, (byte) 0); fail(Failure.OVERFLOW); }
            }
            @Override public void onTerminal(NettyPairingWssTransport.FailureCode reason) {
                if (!intentionalAvailabilityClose && !finished) fail(Failure.NETWORK);
            }
        };
    }
    private MediaListener mediaListener() {
        return new MediaListener() {
            @Override public void active() { synchronized (mailbox) { if (!finished && !mediaEnded && !parentRetired) { mediaReady = true; mailbox.notifyAll(); } } }
            @Override public void failed() { fail(Failure.MEDIA); }
            @Override public void ended() {
                synchronized (mailbox) {
                    if (finished) return;
                    // Stamp the first reason before publishing end: otherwise the worker could
                    // finish a clean teardown between this callback and a later fail() call.
                    if (!mediaReady) failure.compareAndSet(Failure.NONE, Failure.MEDIA);
                    mediaEnded = true; mailbox.notifyAll();
                }
                // A premature normal-end callback is not successful session readiness. The
                // first failure wins, so an already-accepted cancellation remains cancellation.
                retireParent();
            }
        };
    }
    private CompletionStage<Void> closeAvailabilityNative(Transport exact) {
        if (exact != availabilityTransport || !child.isRetired()) return failedStage();
        if (availabilityAllocation == Allocation.NOT_STARTED || availabilityAllocation == Allocation.REFUSED)
            return CompletableFuture.completedFuture(null);
        if (availabilityAllocation != Allocation.OWNED || socket == null) return failedStage();
        return socket.close();
    }
    private static CompletionStage<Void> failedStage() {
        CompletableFuture<Void> refusal = new CompletableFuture<>(); refusal.completeExceptionally(new Refused()); return refusal;
    }
    private boolean closeAvailability() {
        if (availabilityClosed) return true;
        intentionalAvailabilityClose = true; child.retire();
        try { availabilityClosed = awaitStage(storage.close(), clock.nanoTime() + DRAIN_NANOS, false, false); }
        catch (Exception refused) { availabilityClosed = false; }
        if (!availabilityClosed) fail(Failure.DRAIN);
        return availabilityClosed;
    }
    private boolean drainAndRelease() {
        boolean clean = !activated || closeAvailability();
        Media exact = media;
        if (mediaAllocation == Allocation.STARTING || mediaAllocation == Allocation.UNKNOWN) clean = false;
        else if (mediaAllocation == Allocation.OWNED) {
            try { clean = awaitStage(exact.close(), clock.nanoTime() + DRAIN_NANOS, false, false) && clean; }
            catch (Exception refused) { clean = false; }
        }
        if (!clean) { fail(Failure.DRAIN); return false; }
        if (activated) {
            try { storage.release(); released = true; }
            catch (Exception refused) { fail(Failure.RELEASE); return false; }
        }
        return true;
    }
    private static final class StageWait { boolean observed, attached, failed; }
    private boolean awaitStage(CompletionStage<Void> stage, long deadline, boolean parseFrames, boolean allowResponse) throws Exception {
        if (stage == null) return false;
        StageWait wait = new StageWait();
        try {
            stage.whenComplete((ignored, error) -> {
                synchronized (mailbox) {
                    if (!wait.observed) { wait.observed = true; wait.failed = error != null; mailbox.notifyAll(); }
                }
            });
            synchronized (mailbox) { wait.attached = true; }
        } catch (RuntimeException refused) { synchronized (mailbox) { wait.attached = true; wait.failed = true; wait.observed = true; } }
        while (true) {
            if (parseFrames) { processFrames(allowResponse); demandLive(); }
            synchronized (mailbox) { if (wait.attached && wait.observed) return !wait.failed; }
            if (clock.nanoTime() - deadline >= 0) return false;
            waitMailbox(deadline);
        }
    }
    private void waitMailbox(long deadline) {
        long remaining = deadline - clock.nanoTime(); if (remaining <= 0) return;
        synchronized (mailbox) {
            try { mailbox.wait(Math.max(1, Math.min(50, remaining / 1_000_000L))); }
            catch (InterruptedException stopped) { interrupted = true; }
        }
        if (interrupted && !parentRetired) fail(Failure.CANCELLED);
    }
    private byte[] takeFrame() { synchronized (mailbox) { return frames.pollFirst(); } }
    private boolean isOpened() { synchronized (mailbox) { return opened; } }
    private boolean isMediaReady() { synchronized (mailbox) { return mediaReady; } }
    private boolean isMediaEnded() { synchronized (mailbox) { return mediaEnded; } }
    private void fail(Failure reason) {
        if (finished) return;
        failure.compareAndSet(Failure.NONE, reason); retireParent();
        synchronized (mailbox) { while (!frames.isEmpty()) Arrays.fill(frames.removeFirst(), (byte) 0); mailbox.notifyAll(); }
    }
    private void retireParent() {
        SessionCredential key; Media exact;
        synchronized (parentFence) { parentRetired = true; state = State.CLOSING; key = credential; exact = media; }
        child.retire(); if (key != null) key.close(); if (exact != null) revokeMedia(exact);
    }
    private void revokeMedia(Media exact) { try { exact.revoke(); } catch (RuntimeException refused) { failure.compareAndSet(Failure.NONE, Failure.DRAIN); } }
    private void clearLocal() {
        if (credential != null) credential.close(); if (codec != null) codec.close(); if (locator != null) locator.close();
        credential = null; codec = null; locator = null; socket = null; media = null; storage = null; reserved = null; response = null;
        synchronized (mailbox) { while (!frames.isEmpty()) Arrays.fill(frames.removeFirst(), (byte) 0); }
    }
    private void complete(boolean clean) {
        Failure reason = failure.get(); Status status = !clean ? Status.CLEANUP_UNPROVEN
                : reason == Failure.CANCELLED ? Status.CANCELLED : reason == Failure.NONE ? Status.ENDED : Status.FAILED;
        if (!clean && reason == Failure.NONE) reason = Failure.DRAIN;
        if (activated && !released && clean) throw new IllegalStateException("Unreleased Beluga binding");
        finished = true; state = State.TERMINAL; terminal.complete(new Result(status, reason));
    }
}
