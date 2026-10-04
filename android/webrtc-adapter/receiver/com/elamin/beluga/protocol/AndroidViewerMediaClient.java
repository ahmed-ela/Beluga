package com.elamin.beluga.protocol;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import java.util.Arrays;
import java.util.Objects;
import java.util.concurrent.CompletionStage;
import java.util.function.BooleanSupplier;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.SessionCredential;

/** Main-thread app composition. Acknowledged capture is not decoded or presented pixel proof. */
public final class AndroidViewerMediaClient implements AutoCloseable {
    public enum Scene { ACTIVE, INACTIVE, BACKGROUND }
    public enum ScreenStatus { UNAVAILABLE, HIDDEN, SHOW_PENDING, ACKNOWLEDGED, HIDE_PENDING, CLOSED }
    public interface ScreenListener { void onScreenState(ScreenState state); }
    public static final class ScreenState {
        public final ScreenStatus status;
        public final Scene scene;
        public final boolean canShow, canHide, presentationAllowed;
        public final String requestID;
        public final long viewGeneration;
        private ScreenState(ScreenStatus status, Scene scene, boolean canShow, boolean canHide,
                boolean presentationAllowed, String requestID, long viewGeneration) {
            this.status = status; this.scene = scene; this.canShow = canShow; this.canHide = canHide;
            this.presentationAllowed = presentationAllowed; this.requestID = requestID;
            this.viewGeneration = viewGeneration;
        }
        @Override public String toString() { return "<Beluga screen state; not pixel proof>"; }
    }

    /** Pure identity fence shared by worker callbacks and main-thread presentation. */
    static final class Ownership<T> {
        static final class Token<T> {
            private T receiver;
            private boolean attached, active, retired, settled, clean;
        }
        private Token<T> current;
        private boolean closed, accepting;
        synchronized void accepting(boolean value) { accepting = value; }
        synchronized Token<T> reserve() {
            if (closed || !accepting || (current != null && !(current.settled && current.clean))) return null;
            current = new Token<>(); return current;
        }
        synchronized boolean attach(Token<T> token, T receiver) {
            Objects.requireNonNull(receiver);
            if (token == null || token != current || token.attached || token.settled)
                throw new IllegalStateException("Beluga media owner mismatch");
            token.attached = true; token.receiver = receiver;
            return live(token);
        }
        synchronized boolean active(Token<T> token) {
            if (!live(token)) return false;
            token.active = true; return true;
        }
        synchronized T retire(Token<T> token) {
            if (token == null || token != current) return null;
            token.retired = true; return token.receiver;
        }
        synchronized void complete(Token<T> token, boolean clean) {
            if (token == null || token != current || token.settled) return;
            token.retired = true; token.settled = true; token.clean = clean;
        }
        synchronized Token<T> close() {
            closed = true;
            if (current != null) current.retired = true;
            return current;
        }
        synchronized Token<T> current() { return current; }
        synchronized boolean live(Token<T> token) {
            return !closed && token != null && token == current && !token.retired && !token.settled;
        }
        synchronized T ready(Token<T> token) { return live(token) && token.active ? token.receiver : null; }
        synchronized T attached(Token<T> token) { return token != null && token == current ? token.receiver : null; }
        synchronized boolean released(Token<T> token) { return token != null && token == current && token.settled && token.clean; }
    }

    private static final int STARTUP_OBSERVATIONS = 310, COMMAND_OBSERVATIONS = 160;
    private static final long OBSERVATION_MILLIS = 100;
    private final Context uiContext;
    private final Handler main;
    private final ViewerLibraryController library;
    private final Ownership<WebRtcViewerReceiver> ownership = new Ownership<>();
    private Scene scene = Scene.INACTIVE;
    private ScreenState state = new ScreenState(ScreenStatus.UNAVAILABLE, scene, false, false, false, null, 0);
    private ScreenListener observer;
    private Ownership.Token<WebRtcViewerReceiver> viewOwner, observingOwner;
    private WebRtcVideoSurface surface;
    private long viewGeneration;
    private int observationsLeft;
    private boolean closed, surfaceAttempted;
    private final Runnable observation = this::observe;

    public static AndroidViewerMediaClient create(Context uiContext) {
        requireMain(); return new AndroidViewerMediaClient(Objects.requireNonNull(uiContext));
    }
    private AndroidViewerMediaClient(Context uiContext) {
        this.uiContext = uiContext;
        main = new Handler(Looper.getMainLooper());
        library = ViewerLibraryController.create(uiContext, this::startReceiver);
    }
    public ViewerLibraryController library() { requireMain(); return library; }
    public ScreenState screen() { requireMain(); return state; }
    /** Mount this exact View once, retaining it through Hide and transient inactivity. */
    public View view() { requireMain(); return surface; }
    public void observeScreen(ScreenListener observer) {
        requireMain(); this.observer = observer;
        if (observer != null) observer.onScreenState(state);
    }
    public void setSceneActive(boolean active) { setScene(active ? Scene.ACTIVE : Scene.INACTIVE); }
    public void setScene(Scene next) {
        requireMain(); Objects.requireNonNull(next);
        if (closed) return;
        scene = next; ownership.accepting(next == Scene.ACTIVE);
        if (surface != null) surface.scene(nativeScene(next));
        Ownership.Token<WebRtcViewerReceiver> token = ownership.current();
        if (next == Scene.BACKGROUND) stopObservation();
        reconcile(token);
        if (next != Scene.BACKGROUND) beginObservation(token, COMMAND_OBSERVATIONS);
    }
    public String show() {
        requireMain();
        Ownership.Token<WebRtcViewerReceiver> token = ownership.current();
        reconcile(token);
        if (!state.canShow || surface == null || ownership.ready(token) == null) return null;
        String request = surface.show();
        reconcile(token); beginObservation(token, COMMAND_OBSERVATIONS); return request;
    }
    public String hide() {
        requireMain();
        Ownership.Token<WebRtcViewerReceiver> token = ownership.current();
        reconcile(token);
        if (!state.canHide || surface == null || ownership.ready(token) == null) return null;
        String request = surface.hide();
        reconcile(token); beginObservation(token, COMMAND_OBSERVATIONS); return request;
    }
    @Override public void close() {
        requireMain(); if (closed) return;
        closed = true; scene = Scene.BACKGROUND; stopObservation();
        Ownership.Token<WebRtcViewerReceiver> token = ownership.close();
        WebRtcViewerReceiver receiver = ownership.attached(token);
        if (surface != null) surface.scene(ViewerScreenSession.Scene.BACKGROUND);
        if (receiver != null) receiver.revoke();
        library.close();
        // The receiver still owns its mounted surface until the exact native drainage receipt.
        publish(new ScreenState(ScreenStatus.CLOSED, scene, false, false, false, null, viewGeneration));
        observer = null;
    }

    private ViewerConnectionSession.Media startReceiver(Context application, AndroidViewerSecureStore.ReconnectPeer peer,
            SessionCredential credential, BooleanSupplier authorized, ViewerConnectionSession.MediaListener listener)
            throws ViewerConnectionSession.PreallocationRefusal {
        Ownership.Token<WebRtcViewerReceiver> token = ownership.reserve();
        if (token == null) throw new ViewerConnectionSession.PreallocationRefusal();
        Runnable changed = () -> postChange(token);
        byte[] viewerKey = null, hostKey = null;
        final WebRtcViewerReceiver receiver;
        try {
            viewerKey = peer.copyViewerPublicKey(); hostKey = peer.copyHostPublicKey();
            receiver = WebRtcViewerReceiver.start(application, credential, peer.viewerID, viewerKey, peer.hostID, hostKey,
                    authorized, new ViewerConnectionSession.MediaListener() {
                        @Override public void active() {
                            if (ownership.active(token)) { listener.active(); changed.run(); }
                        }
                        @Override public void failed() { ownership.retire(token); listener.failed(); changed.run(); }
                        @Override public void ended() { ownership.retire(token); listener.ended(); changed.run(); }
                    });
        } catch (ViewerConnectionSession.PreallocationRefusal refused) {
            ownership.complete(token, true); changed.run(); throw refused;
        } catch (RuntimeException | Error uncertain) {
            ownership.complete(token, false); changed.run(); throw uncertain;
        } finally {
            if (viewerKey != null) Arrays.fill(viewerKey, (byte) 0);
            if (hostKey != null) Arrays.fill(hostKey, (byte) 0);
        }
        if (!ownership.attach(token, receiver)) receiver.revoke();
        receiver.completion().whenComplete((ignored, failure) -> {
            ownership.complete(token, failure == null); changed.run();
        });
        changed.run();
        return new ViewerConnectionSession.Media() {
            @Override public void revoke() {
                receiver.revoke(); ownership.retire(token); changed.run();
            }
            @Override public CompletionStage<Void> close() { revoke(); return receiver.close(); }
        };
    }
    private void postChange(Ownership.Token<WebRtcViewerReceiver> token) {
        if (main.post(() -> {
            if (ownership.current() != token) return;
            reconcile(token); beginObservation(token, STARTUP_OBSERVATIONS);
        })) return;
        WebRtcViewerReceiver exact = ownership.retire(token);
        if (exact != null) exact.revoke();
    }

    private void reconcile(Ownership.Token<WebRtcViewerReceiver> token) {
        requireMain(); if (ownership.current() != token) return;
        // Refresh reads the actual parent state; the media active callback alone never sets it.
        if (!closed && scene != Scene.BACKGROUND) library.refreshConnectionStatus();
        if (ownership.current() != token) return;
        if (viewOwner != token || ownership.released(token)) {
            if (surface != null) { surface = null; viewGeneration++; }
            viewOwner = token; surfaceAttempted = false;
        }
        WebRtcViewerReceiver receiver = ownership.ready(token);
        if (!closed && scene != Scene.BACKGROUND && receiver != null && !surfaceAttempted) {
            surfaceAttempted = true;
            WebRtcVideoSurface created = receiver.createVideoSurface(uiContext);
            if (created != null && ownership.ready(token) == receiver) {
                surface = created; viewGeneration++; surface.scene(nativeScene(scene));
            }
        }
        ViewerScreenSession model = receiver == null ? null : receiver.screenControlModel();
        ViewerScreenSession.Snapshot snapshot = model == null ? null : model.snapshot();
        // snapshot() can synchronously report protocol failure and retire this exact owner.
        if (ownership.current() != token) return;
        if (receiver != null && ownership.ready(token) != receiver) snapshot = null;
        if (closed || (token != null && !ownership.live(token))) {
            publish(new ScreenState(ScreenStatus.CLOSED, scene, false, false, false, null, viewGeneration)); return;
        }
        if (surface == null || snapshot == null) {
            publish(new ScreenState(ScreenStatus.UNAVAILABLE, scene, false, false, false, null, viewGeneration)); return;
        }
        ScreenStatus status;
        switch (snapshot.state) {
            case INACTIVE: status = ScreenStatus.HIDDEN; break;
            case SHOW_PENDING: status = ScreenStatus.SHOW_PENDING; break;
            case ACTIVE: status = ScreenStatus.ACKNOWLEDGED; break;
            case HIDE_PENDING: status = ScreenStatus.HIDE_PENDING; break;
            case CLOSED: default: status = ScreenStatus.CLOSED;
        }
        publish(new ScreenState(status, scene, scene == Scene.ACTIVE && status == ScreenStatus.HIDDEN,
                status == ScreenStatus.SHOW_PENDING || status == ScreenStatus.ACKNOWLEDGED,
                snapshot.presentationAllowed, snapshot.currentRequestID, viewGeneration));
    }
    private void beginObservation(Ownership.Token<WebRtcViewerReceiver> token, int limit) {
        if (closed || scene == Scene.BACKGROUND || !ownership.live(token)) { stopObservation(); return; }
        main.removeCallbacks(observation);
        observingOwner = token; observationsLeft = limit;
        main.postDelayed(observation, OBSERVATION_MILLIS);
    }
    private void observe() {
        Ownership.Token<WebRtcViewerReceiver> token = observingOwner;
        if (closed || scene == Scene.BACKGROUND || !ownership.live(token)) { stopObservation(); return; }
        reconcile(token);
        boolean waiting = library.state().connectionStatus == ViewerLibraryController.ConnectionStatus.CONNECTING
                || state.status == ScreenStatus.SHOW_PENDING || state.status == ScreenStatus.HIDE_PENDING;
        if (--observationsLeft > 0 && waiting && ownership.live(token)) main.postDelayed(observation, OBSERVATION_MILLIS);
        else stopObservation();
    }
    private void stopObservation() {
        main.removeCallbacks(observation); observingOwner = null; observationsLeft = 0;
    }
    private void publish(ScreenState next) {
        ScreenState previous = state; state = next;
        if (observer != null && (previous.status != next.status || previous.scene != next.scene
                || previous.canShow != next.canShow || previous.canHide != next.canHide
                || previous.presentationAllowed != next.presentationAllowed || previous.viewGeneration != next.viewGeneration
                || !Objects.equals(previous.requestID, next.requestID))) observer.onScreenState(next);
    }
    private static ViewerScreenSession.Scene nativeScene(Scene scene) { return ViewerScreenSession.Scene.valueOf(scene.name()); }
    private static void requireMain() {
        if (Looper.myLooper() != Looper.getMainLooper()) throw new IllegalStateException("Beluga media UI requires the main thread");
    }
}
