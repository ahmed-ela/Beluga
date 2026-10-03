package com.elamin.beluga.protocol;

import java.math.BigInteger;
import java.util.Arrays;
import java.util.concurrent.CompletionStage;
import java.util.function.BooleanSupplier;
import com.elamin.beluga.protocol.ViewerScreenControlCodec.Acknowledgement;
import com.elamin.beluga.protocol.ViewerScreenControlCodec.Command;
import com.elamin.beluga.protocol.ViewerScreenControlCodec.Message;
import com.elamin.beluga.protocol.ViewerScreenControlCodec.ScreenState;

/**
 * Exact ordered-control lifetime, with at most one unresolved write and one required Hide.
 * The trusted adapter calls poll and owns native queue/drain bounds. Failure only revokes this
 * gate and signals the parent; neither an ACK nor close proves rendered pixels or native drain.
 */
final class ViewerScreenSession {
    static final long ACKNOWLEDGEMENT_NANOS = 15_000_000_000L;
    private static final BigInteger LIMIT = new BigInteger("18446744073709551615");
    enum Scene { ACTIVE, INACTIVE, BACKGROUND }
    enum State { INACTIVE, SHOW_PENDING, ACTIVE, HIDE_PENDING, CLOSED }
    enum Failure { HEALTH, SEND, ACKNOWLEDGEMENT, PROTOCOL, TIMEOUT, CLOCK, ID_EXHAUSTED }
    interface Clock { long nanoTime(); }
    interface Transport {
        /**
         * Copy at admission, serialize actual writes, and check authorized immediately before
         * DataChannel.send. Success means that exact native write accepted the complete bytes.
         * The returned stage does not prove a host acknowledgement or native drainage.
         */
        CompletionStage<Void> send(byte[] bytes, BooleanSupplier authorized);
    }
    interface FailureListener { void failed(Failure reason); }
    static final class Snapshot {
        final State state; final Scene scene; final boolean presentationAllowed;
        final String currentRequestID;
        private Snapshot(State state, Scene scene, boolean presentationAllowed, String id) {
            this.state = state; this.scene = scene; this.presentationAllowed = presentationAllowed; currentRequestID = id;
        }
        @Override public String toString() { return "<Beluga screen-control state; not pixels or input authority>"; }
    }
    static final class PresentationLease {
        private final ViewerScreenSession issuer;
        private final Object operation, generation;
        private PresentationLease(ViewerScreenSession issuer, Object operation, Object generation) {
            this.issuer = issuer; this.operation = operation; this.generation = generation;
        }
        @Override public String toString() { return "<Beluga screen presentation lease; not rendered-pixel proof>"; }
    }
    private static final class Request {
        final String id; final Command command; final Object operation = new Object(); final long began;
        boolean dispatched, attachmentReturned, observed, sendFailed, sent, complete;
        ScreenState acknowledgement;
        Request(String id, Command command, long began) { this.id = id; this.command = command; this.began = began; }
    }
    private final Object lock = new Object(), peer, control, track;
    private final Transport transport;
    private final Clock clock;
    private final FailureListener failureListener;
    private BigInteger nextID;
    private Scene scene = Scene.INACTIVE;
    private boolean healthy, closed, hideRequired, failurePublished;
    private Failure failure;
    private long lastNow;
    private Object presentationGeneration = new Object();
    private Request visibility, latest, activeShow, inFlight, queuedHide;

    ViewerScreenSession(Object peer, Object control, Object track, Transport transport, Clock clock, FailureListener listener) {
        this(peer, control, track, transport, clock, listener, "1");
    }
    // Boundary fixture seam only; ordinary lifetimes start at request 1 and cannot restore IDs.
    ViewerScreenSession(Object peer, Object control, Object track, Transport transport, Clock clock,
            FailureListener listener, String initialID) {
        if (peer == null || control == null || track == null || transport == null || clock == null || listener == null
                || initialID == null || initialID.length() == 0 || initialID.length() > 20 || initialID.charAt(0) == '0')
            throw new IllegalArgumentException("Invalid Beluga screen-control lifetime");
        for (int i = 0; i < initialID.length(); i++) if (initialID.charAt(i) < '0' || initialID.charAt(i) > '9')
            throw new IllegalArgumentException("Invalid Beluga screen-control lifetime");
        nextID = new BigInteger(initialID);
        if (nextID.signum() <= 0 || nextID.compareTo(LIMIT) > 0) throw new IllegalArgumentException("Invalid Beluga screen-control lifetime");
        this.peer = peer; this.control = control; this.track = track;
        this.transport = transport; this.clock = clock; failureListener = listener; lastNow = clock.nanoTime();
    }
    boolean admitHealthy(Object exactPeer, Object exactControl) {
        synchronized (lock) {
            if (closed || !exact(exactPeer, exactControl)) return false;
            healthy = true; return true;
        }
    }
    void loseHealth(Object exactPeer, Object exactControl) {
        synchronized (lock) { if (!closed && exact(exactPeer, exactControl)) failLocked(Failure.HEALTH); }
        publishFailure();
    }
    void scene(Scene next) {
        if (next == null) throw new IllegalArgumentException("Invalid Beluga scene");
        synchronized (lock) {
            if (closed || !observeNowLocked() || scene == next) { /* No automatic Show. */ }
            else {
                scene = next; rotatePresentationLocked();
                if (next == Scene.BACKGROUND && hideRequired) hideLocked(lastNow);
            }
        }
        publishFailure(); pump();
    }
    String show() {
        String id = null;
        synchronized (lock) {
            if (!closed && observeNowLocked() && healthy && scene == Scene.ACTIVE
                    && !hideRequired && inFlight == null && queuedHide == null) {
                Request request = requestLocked(Command.SHOW_SCREEN, lastNow);
                if (request != null) {
                    rotatePresentationLocked(); visibility = latest = request; activeShow = null; hideRequired = true; id = request.id;
                }
            }
        }
        publishFailure(); pump(); return id;
    }
    String hide() {
        String id = null;
        synchronized (lock) {
            if (!closed && observeNowLocked()) {
                rotatePresentationLocked(); activeShow = null;
                if (hideRequired) { Request request = hideLocked(lastNow); if (request != null) id = request.id; }
            }
        }
        publishFailure(); pump(); return id;
    }
    String requestKeyFrame() {
        String id = null;
        synchronized (lock) {
            if (!closed && observeNowLocked() && canPresentLocked() && inFlight == null && queuedHide == null
                    && (latest == null || latest.complete)) {
                Request request = requestLocked(Command.REQUEST_KEY_FRAME, lastNow);
                if (request != null) { latest = request; id = request.id; }
            }
        }
        publishFailure(); pump(); return id;
    }
    private Request hideLocked(long now) {
        if (visibility != null && visibility.command == Command.HIDE_SCREEN && !visibility.complete) return visibility;
        rotatePresentationLocked(); activeShow = null;
        if (!healthy) { failLocked(Failure.HEALTH); return null; }
        Request request = requestLocked(Command.HIDE_SCREEN, now);
        if (request != null) { visibility = latest = request; queuedHide = request; }
        return request;
    }
    private Request requestLocked(Command command, long now) {
        if (nextID.compareTo(LIMIT) >= 0) { failLocked(Failure.ID_EXHAUSTED); return null; }
        Request request = new Request(nextID.toString(), command, now); nextID = nextID.add(BigInteger.ONE); return request;
    }
    void receive(Object exactPeer, Object exactControl, byte[] bytes) {
        synchronized (lock) { if (closed || !exact(exactPeer, exactControl)) return; }
        final Message message;
        try { message = ViewerScreenControlCodec.decodeHostMessage(bytes); }
        catch (ViewerScreenControlCodec.CodecFailure malformed) { fail(Failure.PROTOCOL); return; }
        synchronized (lock) {
            if (!closed && exact(exactPeer, exactControl) && observeNowLocked()) {
                switch (message.kind()) {
                    case NON_SCREEN: break;
                    case UNSUPPORTED_SCREEN_EVENT: failLocked(Failure.PROTOCOL); break;
                    case ACK:
                        Acknowledgement ack = message.acknowledgement();
                        if (latest == null || !latest.dispatched || !latest.id.equals(ack.requestID())) break;
                        if (latest.acknowledgement != null && latest.acknowledgement != ack.state()) failLocked(Failure.ACKNOWLEDGEMENT);
                        else {
                            latest.acknowledgement = ack.state();
                            if (latest.command != Command.SHOW_SCREEN && ack.state() != expected(latest)) failLocked(Failure.ACKNOWLEDGEMENT);
                            else finishRequestLocked(latest);
                        }
                        break;
                    default: failLocked(Failure.PROTOCOL);
                }
            }
        }
        publishFailure(); pump();
    }
    void poll() {
        synchronized (lock) {
            if (!closed) observeNowLocked();
        }
        publishFailure(); pump();
    }
    Snapshot snapshot() {
        Snapshot result;
        synchronized (lock) {
            if (!closed) observeNowLocked();
            State state = closed ? State.CLOSED : visibility == null ? State.INACTIVE
                    : visibility.command == Command.HIDE_SCREEN ? visibility.complete ? State.INACTIVE : State.HIDE_PENDING
                    : activeShow != null ? State.ACTIVE : visibility.complete ? State.INACTIVE : State.SHOW_PENDING;
            result = new Snapshot(state, scene, canPresentLocked(), latest == null ? null : latest.id);
        }
        publishFailure(); return result;
    }
    PresentationLease presentationLease() {
        PresentationLease result;
        synchronized (lock) {
            if (!closed) observeNowLocked();
            result = canPresentLocked() ? new PresentationLease(this, activeShow.operation, presentationGeneration) : null;
        }
        publishFailure(); return result;
    }
    /**
     * Permission to rebind the native owner's already-presented same-Show buffer after transient
     * inactivity. The caller must hold its own exact post-swap receipt; this method proves no draw
     * or buffer origin. Only scene generation may differ. It never restores or changes a Show.
     */
    PresentationLease rebindRetainedPresentation(PresentationLease previousLease, Object exactPeer,
            Object exactControl, Object exactTrack) {
        PresentationLease result;
        synchronized (lock) {
            if (!closed) observeNowLocked();
            result = previousLease != null && previousLease.issuer == this && exact(exactPeer, exactControl)
                    && track == exactTrack && canPresentLocked() && previousLease.operation == activeShow.operation
                    ? new PresentationLease(this, activeShow.operation, presentationGeneration) : null;
        }
        publishFailure(); return result;
    }
    boolean permits(PresentationLease lease, Object exactPeer, Object exactControl, Object exactTrack) {
        boolean result;
        synchronized (lock) {
            if (!closed) observeNowLocked();
            result = lease != null && lease.issuer == this && exact(exactPeer, exactControl) && track == exactTrack
                    && canPresentLocked() && lease.operation == activeShow.operation && lease.generation == presentationGeneration;
        }
        publishFailure(); return result;
    }
    void close() {
        synchronized (lock) { closed = true; healthy = false; rotatePresentationLocked(); activeShow = null; queuedHide = null; }
    }
    private boolean exact(Object exactPeer, Object exactControl) { return peer == exactPeer && control == exactControl; }
    private boolean canPresentLocked() { return !closed && healthy && scene == Scene.ACTIVE && activeShow != null; }
    private void rotatePresentationLocked() { presentationGeneration = new Object(); }
    // Clock is trusted, bounded and sampled under the same lock as observation. A concurrent
    // caller cannot turn an earlier pre-lock sample into a false rollback. Poll is only a
    // wakeup mechanism: no late ACK, write or lease check can extend an unfinished request.
    private boolean observeNowLocked() {
        long now = clock.nanoTime();
        if (now - lastNow < 0) { failLocked(Failure.CLOCK); return false; }
        lastNow = now;
        if ((latest != null && !latest.complete && now - latest.began >= ACKNOWLEDGEMENT_NANOS)
                || (inFlight != null && now - inFlight.began >= ACKNOWLEDGEMENT_NANOS)) {
            failLocked(Failure.TIMEOUT); return false;
        }
        return true;
    }
    private static ScreenState expected(Request request) { return request.command == Command.HIDE_SCREEN ? ScreenState.INACTIVE : ScreenState.ACTIVE; }
    private void finishRequestLocked(Request request) {
        if (closed || request != latest || !request.sent || request.acknowledgement == null || request.complete) return;
        request.complete = true;
        switch (request.command) {
            case SHOW_SCREEN:
                if (request == visibility && request.acknowledgement == ScreenState.ACTIVE) activeShow = request;
                else { activeShow = null; hideRequired = false; }
                break;
            case HIDE_SCREEN: activeShow = null; hideRequired = false; break;
            case REQUEST_KEY_FRAME: break; // Never changes Show ownership or scene generation.
            default: failLocked(Failure.PROTOCOL);
        }
    }
    private void pump() {
        final Request request;
        synchronized (lock) {
            if (closed || inFlight != null) return;
            if (!observeNowLocked()) { request = null; }
            else {
                request = queuedHide != null ? queuedHide : latest != null && !latest.dispatched ? latest : null;
                if (request == null) return;
                if (queuedHide == request) queuedHide = null;
                request.dispatched = true; inFlight = request;
            }
        }
        if (request == null) { publishFailure(); return; }
        byte[] bytes = null;
        try {
            bytes = ViewerScreenControlCodec.encodeCommand(request.id, request.command);
            if (bytes.length == 0 || bytes.length > 4_096) { fail(Failure.PROTOCOL); return; }
            CompletionStage<Void> result = transport.send(bytes, () -> sendAuthorized(request));
            if (result == null) { fail(Failure.SEND); return; }
            try {
                result.whenComplete((ignored, error) -> observedSend(request, error != null));
                synchronized (lock) { request.attachmentReturned = true; }
                settleSend(request);
            } catch (RuntimeException attachmentUnproved) { fail(Failure.SEND); }
        } catch (ViewerScreenControlCodec.CodecFailure invalid) { fail(Failure.PROTOCOL); }
        catch (RuntimeException refusal) { fail(Failure.SEND); }
        finally { if (bytes != null) Arrays.fill(bytes, (byte) 0); }
    }
    private boolean sendAuthorized(Request request) {
        boolean result;
        synchronized (lock) {
            result = !closed && observeNowLocked() && healthy && request == latest && request == inFlight
                    && (request.command != Command.SHOW_SCREEN || scene == Scene.ACTIVE);
        }
        publishFailure(); return result;
    }
    private void observedSend(Request request, boolean unsuccessful) {
        synchronized (lock) {
            if (closed) return;
            if (!observeNowLocked()) { /* Terminal deadline or rollback. */ }
            else if (request.observed) failLocked(Failure.PROTOCOL);
            else { request.observed = true; request.sendFailed = unsuccessful; }
        }
        publishFailure(); settleSend(request);
    }
    private void settleSend(Request request) {
        synchronized (lock) {
            if (!closed && observeNowLocked() && inFlight == request && request.attachmentReturned && request.observed) {
                inFlight = null;
                if (request == latest) {
                    if (request.sendFailed) failLocked(Failure.SEND);
                    else { request.sent = true; finishRequestLocked(request); }
                }
                // A superseded Show write may have been refused by its revoked guard. Hide is
                // still required: retiring local Show state must never erase that queued work.
            }
        }
        publishFailure(); pump();
    }
    private void fail(Failure reason) { synchronized (lock) { failLocked(reason); } publishFailure(); }
    private void failLocked(Failure reason) {
        if (closed) return;
        closed = true; healthy = false; failure = reason; activeShow = null; queuedHide = null; rotatePresentationLocked();
    }
    private void publishFailure() {
        Failure reason;
        synchronized (lock) {
            if (failure == null || failurePublished) return;
            failurePublished = true; reason = failure;
        }
        failureListener.failed(reason);
    }
    @Override public String toString() { return "<Beluga screen-control lifetime; no input authority>"; }
}
