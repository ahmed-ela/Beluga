package com.elamin.beluga.protocol;

import java.util.ArrayDeque;
import java.util.Arrays;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.BooleanSupplier;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Role;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.*;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.PreparedViewer;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.ViewerIdentity;

/**
 * One foreground NEW-slot bootstrap, not reconnect or media. One worker performs crypto and
 * durable effects; Netty callbacks only hand off bounded input/completions. No automatic retry.
 * Package ports are trusted composition, not protection against code in the same process.
 */
final class ViewerPairingSession {
    static final int MAXIMUM_QUEUED_FRAMES = 4;
    private static final long BOOTSTRAP_NANOS = TimeUnit.SECONDS.toNanos(300);
    private static final long DRAIN_NANOS = TimeUnit.SECONDS.toNanos(45);

    enum Status { PAIRED, CANCELLED, FAILED, CLEANUP_UNPROVEN }
    enum Failure { NONE, CANCELLED, PREPARATION, PROTOCOL, NETWORK, OVERFLOW, TIMEOUT, DRAIN, RELEASE }
    static final class Result {
        final Status status;
        final Failure failure;
        final UUID pairID, hostID;
        final String displayName;
        Result(Status status, Failure failure, PairedMac mac) {
            this.status = status; this.failure = failure;
            pairID = mac == null ? null : mac.pairID;
            hostID = mac == null ? null : mac.hostID;
            displayName = mac == null ? null : mac.displayName;
        }
        @Override public String toString() { return "<redacted Beluga pairing result; not media connectivity>"; }
    }
    interface Clock { long nanoTime(); long epochMillis(); }
    interface Socket {
        /** Must take a private copy before returning. Success is actual local frame completion. */
        CompletionStage<Void> send(byte[] wire, BooleanSupplier authorized);
        /** Success requires the exact owned socket and callback/loop drain, not close requested. */
        CompletionStage<Void> close();
    }
    interface Connector {
        Socket connect(PairingBootstrapEnvelopeCodec.JoinHeaders join,
                NettyPairingWssTransport.Listener listener) throws PreallocationRefusal;
    }
    static final class PreallocationRefusal extends Exception {
        private static final long serialVersionUID = 1L;
        PreallocationRefusal() { super("Pairing transport refused before allocation"); }
    }
    interface Storage extends StorePort, AdmissionPort, CleanupPort, ClosePort {
        // Durable write/admission/cleanup ports execute synchronously on this session worker.
        // Only native send/close completions cross the bounded asynchronous mailbox.
        /** Atomic: refusal publishes nothing; success publishes the complete exact close path. */
        void activate() throws Exception;
        /** Requires exact native-close receipt and retired owner; never receipt-free release. */
        void release() throws Exception;
    }
    interface Preparation {
        /** May reserve a NEW empty slot, but must return pure, unactivated storage ports. */
        Prepared prepare(Owner owner, Transport transport, ClosePort nativeClose) throws Exception;
    }
    static final class Prepared {
        final PreparedViewer viewer;
        final ViewerIdentity identity;
        final StoreStamp initial;
        final Storage storage;
        Prepared(PreparedViewer viewer, ViewerIdentity identity, StoreStamp initial, Storage storage) {
            if (viewer == null || identity == null || initial == null || storage == null) throw new IllegalArgumentException();
            this.viewer = viewer; this.identity = identity; this.initial = initial; this.storage = storage;
        }
    }

    private enum Allocation { NOT_STARTED, STARTING, OWNED, REFUSED, UNKNOWN }
    private static final class StartInput {
        PairingInvitation invitation;
        Preparation preparation;
        StartInput(PairingInvitation invitation, Preparation preparation) {
            this.invitation = invitation; this.preparation = preparation;
        }
    }
    private final Object mailbox = new Object();
    private final ArrayDeque<byte[]> frames = new ArrayDeque<>();
    private final Owner owner = new Owner(UUID.randomUUID(), 1);
    private final Transport transport = new Transport(owner, this);
    private final Connector connector;
    private final Clock clock;
    private final CompletableFuture<Result> result = new CompletableFuture<>();
    private final AtomicBoolean started = new AtomicBoolean();
    private final NativeSend sender = new NativeSend();
    private final NativeClose closer = new NativeClose();
    // Only mailbox state below is accessed by native callbacks. No reducer/storage monitor.
    private Runnable sendCompletion, closeCompletion;
    private Failure failure = Failure.NONE;
    private boolean finished;
    // Worker-confined state, including native-factory publication.
    private PairingBootstrapEnvelopeCodec codec;
    private ViewerBootstrapReducer reducer;
    private Storage storage;
    private Socket socket;
    private Allocation allocation = Allocation.NOT_STARTED;
    private boolean activated, drainFailed;
    // Native queued-send admission reads the same tightening monotonic deadline.
    private volatile long deadline;
    private long drainDeadline;
    private Effect sentCritical, sentCleanup, sentClose;

    ViewerPairingSession(Connector connector, Clock clock) {
        if (connector == null || clock == null) throw new IllegalArgumentException();
        this.connector = connector; this.clock = clock;
    }
    static ViewerPairingSession production() {
        return new ViewerPairingSession((join, listener) -> {
            final NettyPairingWssTransport nativeSocket;
            try { nativeSocket = NettyPairingWssTransport.connect(NettyPairingWssTransport.PRODUCTION_ORIGIN, join, listener); }
            catch (NettyPairingWssTransport.TransportFailure refused) { throw new PreallocationRefusal(); }
            return new Socket() {
                @Override public CompletionStage<Void> send(byte[] wire, BooleanSupplier authorized) {
                    return nativeSocket.sendGuarded(wire, authorized);
                }
                @Override public CompletionStage<Void> close() { return nativeSocket.closeAsync(); }
            };
        }, new Clock() {
            @Override public long nanoTime() { return System.nanoTime(); }
            @Override public long epochMillis() { return System.currentTimeMillis(); }
        });
    }
    CompletionStage<Result> start(PairingInvitation invitation, Preparation preparation) {
        if (invitation == null || preparation == null || !started.compareAndSet(false, true)) throw new IllegalStateException();
        deadline = clock.nanoTime() + BOOTSTRAP_NANOS;
        StartInput input = new StartInput(invitation, preparation);
        Thread worker = new Thread(() -> run(input), "Beluga-pairing-session");
        worker.setDaemon(true);
        try { worker.start(); }
        catch (RuntimeException refused) {
            input.invitation = null; input.preparation = null;
            fail(Failure.PREPARATION); finish(Status.FAILED, null);
        }
        return result.thenApply(value -> value);
    }
    /** Revokes authorizing effects immediately, even while worker storage IO is in progress. */
    void cancel() { fail(Failure.CANCELLED); }
    CompletionStage<Result> completion() { return result.thenApply(value -> value); }
    @Override public String toString() { return "<redacted one-use Beluga pairing session>"; }

    private void run(StartInput inputOwner) {
        PairingInvitation invitation = inputOwner.invitation;
        Preparation preparation = inputOwner.preparation;
        inputOwner.invitation = null; inputOwner.preparation = null;
        try {
            if (owner.isRetired()) { finish(Status.CANCELLED, null); return; }
            codec = PairingBootstrapEnvelopeCodec.create(invitation, Role.VIEWER);
            Prepared input = preparation.prepare(owner, transport, closer);
            // Assembly/reducer validation cannot publish the store owner or allocate a socket.
            reducer = ViewerBootstrapReducer.bootstrap(owner, transport, input.viewer, input.identity,
                    new Invitation(invitation.admissionFingerprint()), input.initial, null, null,
                    clock.epochMillis() / 1000.0,
                    new Ports(input.storage, input.storage, sender, input.storage, input.storage));
            storage = input.storage;
            input = null;
            checkDeadline();
            if (!owner.isRetired()) { storage.activate(); activated = true; }
            if (!activated) {
                finish(currentFailure() == Failure.CANCELLED ? Status.CANCELLED : Status.FAILED, null); return;
            }
            // Drop UI invitation/preparation references before entering the long-lived loop.
            invitation = null; preparation = null;
            checkDeadline();
            if (!owner.isRetired()) {
                allocation = Allocation.STARTING;
                try {
                    socket = connector.connect(codec.copyJoinHeaders(), listener);
                    if (socket == null) throw new IllegalStateException();
                    allocation = Allocation.OWNED;
                } catch (PreallocationRefusal refused) { allocation = Allocation.REFUSED; fail(Failure.NETWORK); }
                catch (RuntimeException uncertain) { allocation = Allocation.UNKNOWN; fail(Failure.NETWORK); }
            }
            loop();
        } catch (Exception refused) {
            fail(Failure.PREPARATION);
            if (activated && reducer != null) {
                try { loop(); }
                catch (RuntimeException unrecovered) { finish(Status.CLEANUP_UNPROVEN, null); }
            } else finish(currentFailure() == Failure.CANCELLED ? Status.CANCELLED : Status.FAILED, null);
        } finally {
            releaseLocalReferences();
        }
    }

    private void loop() {
        while (true) {
            Snapshot snapshot = reducer.currentStep().snapshot;
            if (snapshot.end == End.NONE && clock.nanoTime() - deadline >= 0) fail(Failure.TIMEOUT);
            if (owner.isRetired() && snapshot.end == End.NONE)
                reducer.close(currentFailure() == Failure.CANCELLED ? CloseReason.CANCELLED : CloseReason.TIMEOUT);
            pump();
            snapshot = reducer.currentStep().snapshot;
            if (snapshot.end != End.NONE) {
                if (drainDeadline == 0) drainDeadline = clock.nanoTime() + DRAIN_NANOS;
                if (snapshot.transportCloseAcknowledged) {
                    try { storage.release(); }
                    catch (Exception refused) { fail(Failure.RELEASE); finish(Status.CLEANUP_UNPROVEN, null); return; }
                    if (snapshot.end == End.COMPLETE && currentFailure() == Failure.NONE) finish(Status.PAIRED, snapshot.pairedMac);
                    else if (snapshot.end == End.CANCELLED && currentFailure() == Failure.CANCELLED) finish(Status.CANCELLED, null);
                    else { fail(Failure.PROTOCOL); finish(Status.FAILED, null); }
                    return;
                }
                if (drainFailed || clock.nanoTime() - drainDeadline >= 0) {
                    fail(Failure.DRAIN); finish(Status.CLEANUP_UNPROVEN, null); return;
                }
            }
            Runnable completion = null; byte[] wire = null;
            synchronized (mailbox) {
                if (closeCompletion != null) { completion = closeCompletion; closeCompletion = null; }
                else if (sendCompletion != null) { completion = sendCompletion; sendCompletion = null; }
                else if (!owner.isRetired() && !frames.isEmpty()) wire = frames.removeFirst();
                else {
                    long remaining = (snapshot.end == End.NONE ? deadline : drainDeadline) - clock.nanoTime();
                    // A fixed small upper bound also rechecks a clock adjustment in deterministic tests.
                    try { mailbox.wait(Math.max(1, Math.min(1000, TimeUnit.NANOSECONDS.toMillis(remaining)))); }
                    catch (InterruptedException interrupted) { fail(Failure.CANCELLED); }
                }
            }
            if (completion != null) completion.run();
            if (wire != null) {
                try { accept(wire); }
                catch (Exception refused) { fail(Failure.PROTOCOL); }
                finally { Arrays.fill(wire, (byte) 0); }
            }
        }
    }
    /** Inline durable callbacks advance on this stack, never through recursive pump calls. */
    private void pump() {
        while (true) {
            if (reducer.currentStep().snapshot.end == End.NONE) checkDeadline();
            if (owner.isRetired() && reducer.currentStep().snapshot.end == End.NONE)
                reducer.close(currentFailure() == Failure.CANCELLED ? CloseReason.CANCELLED : CloseReason.TIMEOUT);
            Step step = reducer.currentStep();
            Effect next = null;
            if (step.close != null && step.close != sentClose) {
                next = step.close; sentClose = next;
                // Start the bound before invoking native close (which can complete inline).
                if (drainDeadline == 0) drainDeadline = clock.nanoTime() + DRAIN_NANOS;
            }
            else if (step.cleanup != null && step.cleanup != sentCleanup) { next = step.cleanup; sentCleanup = next; }
            else if (step.critical != null && step.critical != sentCritical) { next = step.critical; sentCritical = next; }
            if (next == null) return;
            reducer.dispatch(next);
        }
    }
    private void accept(byte[] wire) throws Exception {
        if (owner.isRetired()) return;
        PairingBootstrapBrokerEventParser.Event event = PairingBootstrapBrokerEventParser.parse(wire, Role.VIEWER);
        switch (event.kind()) {
            case WAITING:
                tightenDeadline(((PairingBootstrapBrokerEventParser.Waiting) event).claimedInvitationExpiresAtEpochMillis()); break;
            case READY:
                tightenDeadline(((PairingBootstrapBrokerEventParser.Ready) event).claimedInvitationExpiresAtEpochMillis());
                if (!owner.isRetired()) reducer.onReady(transport); break;
            case SIGNAL_WIRE:
                reducer.onPayload(transport, codec.open(wire).structurallyAdmittedPayload()); break;
            case PEER_LEFT: reducer.onPeerLeft(transport); break;
            case SERVER_ERROR: fail(Failure.PROTOCOL); break;
            default: throw new IllegalStateException();
        }
    }
    private void tightenDeadline(long claimedEpochMillis) {
        long remainingMillis = claimedEpochMillis - clock.epochMillis();
        if (remainingMillis <= 0) { fail(Failure.TIMEOUT); return; }
        long bound = clock.nanoTime() + TimeUnit.MILLISECONDS.toNanos(Math.min(300_000, remainingMillis));
        if (bound - deadline < 0) deadline = bound;
    }
    private void checkDeadline() {
        if (clock.nanoTime() - deadline >= 0) fail(Failure.TIMEOUT);
    }
    private final NettyPairingWssTransport.Listener listener = new NettyPairingWssTransport.Listener() {
        @Override public void onOpen() { /* HTTP101 is not broker READY or host authentication. */ }
        @Override public void onText(byte[] utf8) {
            if (utf8 == null) { fail(Failure.PROTOCOL); return; }
            synchronized (mailbox) {
                if (finished || owner.isRetired()) { Arrays.fill(utf8, (byte) 0); return; }
                if (utf8.length == 0 || utf8.length > PairingBootstrapBrokerEventParser.MAXIMUM_WIRE_BYTES
                        || frames.size() == MAXIMUM_QUEUED_FRAMES) {
                    Arrays.fill(utf8, (byte) 0); fail(Failure.OVERFLOW); return;
                }
                // Netty hands us an owned copy; no second unbounded executor queue.
                frames.addLast(utf8); mailbox.notifyAll();
            }
        }
        @Override public void onTerminal(NettyPairingWssTransport.FailureCode reason) {
            if (!owner.isRetired()) fail(Failure.NETWORK);
            // Terminal observation alone is NOT the close receipt. Await closeAsync separately.
        }
    };

    private final class NativeSend implements SendPort {
        @Override public void send(Effect effect, SendCallback callback) {
            checkDeadline();
            if (owner.isRetired() || effect.exactTransportForTrustedPort() != transport || allocation != Allocation.OWNED) {
                callback.failed(); return;
            }
            byte[] plain = effect.exactBytesForTrustedPort(), wire = null;
            AtomicBoolean once = new AtomicBoolean();
            try {
                wire = codec.seal(plain).copyWireBytes();
                checkDeadline();
                if (owner.isRetired()) { callback.failed(); return; }
                Owner capturedOwner = owner;
                socket.send(wire, () -> !capturedOwner.isRetired() && clock.nanoTime() - deadline < 0).whenComplete((ignored, error) -> {
                    if (!once.compareAndSet(false, true)) return;
                    postCompletion(false, () -> {
                        if (error != null) callback.failed();
                        else callback.completed(new SendObservation(effect, this, transport, Sent.COMPLETED));
                    });
                });
            } catch (Exception refused) { if (once.compareAndSet(false, true)) callback.failed(); }
            finally { if (plain != null) Arrays.fill(plain, (byte) 0); if (wire != null) Arrays.fill(wire, (byte) 0); }
        }
    }
    private final class NativeClose implements ClosePort {
        @Override public void close(Effect effect, CloseCallback callback) {
            if (!owner.isRetired() || effect.exactTransportForTrustedPort() != transport) { drainFailed = true; return; }
            if (allocation == Allocation.NOT_STARTED || allocation == Allocation.REFUSED) {
                callback.completed(new CloseObservation(effect, this, transport, Closed.FINISHED)); return;
            }
            if (allocation != Allocation.OWNED) { drainFailed = true; return; }
            AtomicBoolean once = new AtomicBoolean();
            try {
                socket.close().whenComplete((ignored, error) -> {
                    if (!once.compareAndSet(false, true)) return;
                    postCompletion(true, () -> {
                        if (error != null) drainFailed = true;
                        else callback.completed(new CloseObservation(effect, this, transport, Closed.FINISHED));
                    });
                });
            } catch (RuntimeException uncertain) { drainFailed = true; }
        }
    }
    private void postCompletion(boolean close, Runnable callback) {
        synchronized (mailbox) {
            if (finished) return;
            if (close ? closeCompletion != null : sendCompletion != null) { fail(Failure.OVERFLOW); return; }
            if (close) closeCompletion = callback; else sendCompletion = callback;
            mailbox.notifyAll();
        }
    }
    private Failure currentFailure() { synchronized (mailbox) { return failure; } }
    private void fail(Failure reason) {
        synchronized (mailbox) {
            if (finished) return;
            if (failure == Failure.NONE) failure = reason;
            owner.retire();
            while (!frames.isEmpty()) Arrays.fill(frames.removeFirst(), (byte) 0);
            mailbox.notifyAll();
        }
    }
    private void finish(Status status, PairedMac mac) {
        Result terminal;
        synchronized (mailbox) {
            if (finished) return;
            finished = true; owner.retire();
            while (!frames.isEmpty()) Arrays.fill(frames.removeFirst(), (byte) 0);
            sendCompletion = null; closeCompletion = null;
            terminal = new Result(status, failure, mac);
        }
        // Finish local secret/reference cleanup before exposing terminal admission to a successor.
        // This is not a promise of JVM heap zeroization or forced cancellation of blocked IO.
        releaseLocalReferences();
        result.complete(terminal);
    }
    private void releaseLocalReferences() {
        if (codec != null) codec.close();
        codec = null; socket = null; reducer = null; storage = null;
    }
}
