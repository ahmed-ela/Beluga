package com.elamin.beluga.protocol;

import android.content.Context;
import android.graphics.Color;
import android.graphics.SurfaceTexture;
import android.opengl.EGL14;
import android.opengl.EGLConfig;
import android.opengl.EGLContext;
import android.opengl.EGLDisplay;
import android.opengl.EGLSurface;
import android.opengl.GLES20;
import android.os.Handler;
import android.os.Looper;
import android.view.TextureView;
import android.view.View;
import android.widget.FrameLayout;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.atomic.AtomicBoolean;
import org.webrtc.GlRectDrawer;
import org.webrtc.VideoFrame;
import org.webrtc.VideoFrameDrawer;
import org.webrtc.VideoSink;
import com.elamin.beluga.protocol.ViewerScreenSession.PresentationLease;
import com.elamin.beluga.protocol.ViewerScreenSession.Scene;

/**
 * Receive-only M150 renderer source, not yet in the app dependency graph. A checked swap receipt is GPU
 * submission, NOT physical compositor/pixel proof. No screenshot, input or local capture path.
 * One mounted surface lifetime only; replacement fails closed. There is no shared decoder EGL
 * contract, so the single rendering frame is converted with public toI420(). Its cost is unmeasured.
 */
final class WebRtcVideoSurface extends FrameLayout implements VideoSink {
    private static final int MAXIMUM_DIMENSION = 8192;
    private static final long MAXIMUM_PIXELS = 33_554_432L;
    private static final long CLOSE_NANOS = 10_000_000_000L;
    private final Object lock = new Object(), peer, control, track;
    private final ViewerScreenSession model;
    private final Runnable failure;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final TextureView texture;
    private final View cover;
    private final AtomicBoolean revoked = new AtomicBoolean(), failed = new AtomicBoolean();
    private final AtomicBoolean cleanupUnproved = new AtomicBoolean();
    private final AtomicBoolean failurePublished = new AtomicBoolean();
    private final CompletableFuture<Void> drained = new CompletableFuture<>();
    private final List<VideoFrame> quarantinedFrames = new ArrayList<>();
    private Scene scene = Scene.INACTIVE;
    private SurfaceTexture ownedTexture;
    private Object surfaceToken;
    private int width, height;
    private long geometry, showGeneration, sceneGeneration, swapSequence, surfaceContentGeneration, closeBeganNanos;
    private int intakeCount;
    private boolean everMounted, textureDestroyed, textureReleased, closing, nativeFinished;
    private boolean receiptPosted, closePosted, swapInProgress;
    private Thread worker;
    private FrameJob pending;
    private Receipt retainedSwap, pendingReceipt;
    // Only the one GL worker touches these native owners. Raw EGL Booleans/errors are checked:
    // the retained SDK EglBase14 wrappers discard several swap/destroy results.
    private EGLDisplay display = EGL14.EGL_NO_DISPLAY;
    private EGLContext context = EGL14.EGL_NO_CONTEXT;
    private EGLSurface surface = EGL14.EGL_NO_SURFACE;
    private boolean initialized;
    private VideoFrameDrawer frameDrawer;
    private GlRectDrawer rectDrawer;

    private static final class Refused extends RuntimeException {
        private static final long serialVersionUID = 1L;
        Refused() { super("Beluga video surface refused"); }
    }
    private static final class CleanupUnproved extends IllegalStateException {
        private static final long serialVersionUID = 1L;
        CleanupUnproved() { super("Beluga video surface cleanup unproved"); }
    }
    private static final class FrameJob {
        final VideoFrame frame;
        final PresentationLease lease;
        final SurfaceTexture texture;
        final Object surfaceToken;
        final long geometry, showGeneration, sceneGeneration;
        final int width, height;
        FrameJob(VideoFrame frame, PresentationLease lease, WebRtcVideoSurface owner) {
            this.frame = frame; this.lease = lease; texture = owner.ownedTexture;
            surfaceToken = owner.surfaceToken; geometry = owner.geometry;
            showGeneration = owner.showGeneration; sceneGeneration = owner.sceneGeneration;
            width = owner.width; height = owner.height;
        }
    }
    private static final class Receipt {
        final PresentationLease lease;
        final SurfaceTexture texture;
        final Object surfaceToken;
        final long geometry, showGeneration, sceneGeneration, swapSequence, surfaceContentGeneration;
        Receipt(FrameJob job, long sequence, long surfaceContentGeneration) {
            lease = job.lease; texture = job.texture; surfaceToken = job.surfaceToken;
            geometry = job.geometry; showGeneration = job.showGeneration;
            sceneGeneration = job.sceneGeneration; swapSequence = sequence;
            this.surfaceContentGeneration = surfaceContentGeneration;
        }
        Receipt(Receipt before, PresentationLease rebound, long sceneGeneration) {
            lease = rebound; texture = before.texture; surfaceToken = before.surfaceToken;
            geometry = before.geometry; showGeneration = before.showGeneration;
            this.sceneGeneration = sceneGeneration; swapSequence = before.swapSequence;
            surfaceContentGeneration = before.surfaceContentGeneration;
        }
    }

    /** Main-only, lazy: no thread, native EGL allocation or automatic Show before actual mount. */
    WebRtcVideoSurface(Context context, ViewerScreenSession model, Object peer, Object control,
            Object track, Runnable failure) {
        super(context);
        requireMain();
        if (model == null || peer == null || control == null || track == null || failure == null)
            throw new IllegalArgumentException("Invalid Beluga video surface");
        this.model = model; this.peer = peer; this.control = control; this.track = track; this.failure = failure;
        texture = new TextureView(context); texture.setOpaque(true);
        cover = new View(context); cover.setBackgroundColor(Color.BLACK);
        cover.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        addView(texture, new LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT));
        addView(cover, new LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT));
        texture.setSurfaceTextureListener(new TextureView.SurfaceTextureListener() {
            @Override public void onSurfaceTextureAvailable(SurfaceTexture value, int w, int h) { mounted(value, w, h); }
            @Override public void onSurfaceTextureSizeChanged(SurfaceTexture value, int w, int h) { resized(value, w, h); }
            @Override public boolean onSurfaceTextureDestroyed(SurfaceTexture value) { return destroyed(value); }
            @Override public void onSurfaceTextureUpdated(SurfaceTexture value) { /* Not presentation authority. */ }
        });
        model.scene(Scene.INACTIVE);
    }

    void scene(Scene next) {
        requireMain();
        if (next == null) throw new IllegalArgumentException("Invalid Beluga scene");
        synchronized (lock) { if (closing || scene == next) return; }
        cover.setVisibility(View.VISIBLE);
        model.scene(next);
        Receipt before;
        synchronized (lock) {
            if (closing) return;
            if (scene == next) return;
            scene = next; sceneGeneration++; pendingReceipt = null;
            if (next == Scene.BACKGROUND) { showGeneration++; retainedSwap = null; }
            before = next == Scene.ACTIVE ? retainedSwap : null;
        }
        // Only an actual accepted POST-SWAP receipt may rebind after transient inactivity.
        // A pending/pre-draw frame can never mint this receipt or restore presentation.
        if (before != null) {
            PresentationLease rebound = model.rebindRetainedPresentation(before.lease, peer, control, track);
            if (rebound != null) {
                Receipt restored;
                synchronized (lock) {
                    restored = receiptSurfaceCurrent(before) && retainedSwap == before && scene == Scene.ACTIVE
                            ? new Receipt(before, rebound, sceneGeneration) : null;
                    if (restored != null) retainedSwap = restored;
                }
                if (restored != null) uncover(restored);
            }
        }
    }

    String show() {
        requireMain(); concealNewShow(); return revoked.get() ? null : model.show();
    }
    String hide() {
        requireMain(); concealNewShow(); return revoked.get() ? null : model.hide();
    }
    CompletionStage<Void> unmount() {
        requireMain(); hide(); return closeAsync();
    }
    private void concealNewShow() {
        cover.setVisibility(View.VISIBLE);
        synchronized (lock) { showGeneration++; retainedSwap = null; pendingReceipt = null; }
    }

    @Override public void onFrame(VideoFrame frame) {
        if (frame == null) return;
        synchronized (lock) {
            // Native callback serialization is not a resource-bound assumption: admit one
            // borrowed intake at a time, before any external frame/model work or retention.
            if (closing || revoked.get() || intakeCount != 0) return;
            intakeCount++;
        }
        boolean retained = false;
        boolean retainAttempted = false, retainReturned = false;
        FrameJob replaced = null;
        try {
            if (!validFrame(frame)) { fail(); return; }
            PresentationLease lease = model.presentationLease();
            if (lease == null || !model.permits(lease, peer, control, track) || revoked.get()) return;
            retainAttempted = true; frame.retain(); retainReturned = true; retained = true;
            synchronized (lock) {
                if (!closing && scene == Scene.ACTIVE && ownedTexture != null && !textureDestroyed) {
                    replaced = pending; pending = new FrameJob(frame, lease, this); retained = false;
                    lock.notifyAll();
                }
            }
        } catch (Throwable refusal) {
            if (retainAttempted && !retainReturned) cleanupUnproved.set(true);
            fail();
        }
        finally {
            if (replaced != null) releaseFrame(replaced.frame);
            if (retained) releaseFrame(frame);
            synchronized (lock) { intakeCount--; lock.notifyAll(); }
        }
    }

    /** Short, nonthrowing cancellation: no GL, frame release, native wait or external callback under lock. */
    void revoke() {
        revoked.set(true);
        synchronized (lock) {
            if (!closing) closeBeganNanos = System.nanoTime();
            closing = true; showGeneration++; retainedSwap = null; pendingReceipt = null;
            if (worker == null) nativeFinished = true;
            lock.notifyAll();
        }
        postClose();
    }
    CompletionStage<Void> closeAsync() { revoke(); return drained.thenApply(ignored -> null); }

    private void mounted(SurfaceTexture value, int w, int h) {
        requireMain();
        boolean reject;
        synchronized (lock) {
            reject = closing || everMounted || value == null || !validSize(w, h);
            if (!reject) {
                everMounted = true; ownedTexture = value; surfaceToken = new Object(); width = w; height = h;
                worker = new Thread(this::runGL, "Beluga video surface GL");
            }
        }
        if (reject) { if (!revoked.get()) fail(); return; }
        try { worker.start(); }
        catch (Throwable unknownStart) {
            cleanupUnproved.set(true); fail();
            drained.completeExceptionally(new CleanupUnproved());
        }
    }
    private void resized(SurfaceTexture value, int w, int h) {
        requireMain(); cover.setVisibility(View.VISIBLE);
        boolean reject;
        synchronized (lock) {
            reject = value != ownedTexture || textureDestroyed || !validSize(w, h);
            if (!reject) { width = w; height = h; geometry++; retainedSwap = null; pendingReceipt = null; }
        }
        if (reject && !revoked.get()) fail();
    }
    private boolean destroyed(SurfaceTexture value) {
        requireMain();
        boolean owned;
        synchronized (lock) { owned = value == ownedTexture; if (owned) { textureDestroyed = true; lock.notifyAll(); } }
        if (!owned) return true; // Never accepted: framework still owns this rejected surface.
        if (!revoked.get()) fail(); else postClose();
        return false; // Exact accepted texture is released only after checked GL drainage.
    }

    private void runGL() {
        try {
            SurfaceTexture accepted;
            synchronized (lock) { accepted = ownedTexture; }
            if (!revoked.get()) initialize(accepted);
            while (!revoked.get()) {
                FrameJob job;
                synchronized (lock) {
                    while (!closing && pending == null) lock.wait();
                    if (closing) break;
                    job = pending; pending = null;
                }
                try { if (authorized(job)) draw(job); }
                finally { releaseFrame(job.frame); }
            }
        } catch (Throwable refusal) { fail(); }
        finally {
            FrameJob abandoned;
            synchronized (lock) { abandoned = pending; pending = null; }
            if (abandoned != null) releaseFrame(abandoned.frame);
            boolean clean = releaseGL();
            if (!clean) { cleanupUnproved.set(true); fail(); }
            if (clean) {
                try {
                    SurfaceTexture accepted;
                    synchronized (lock) {
                        while (ownedTexture != null && !textureDestroyed) lock.wait();
                        accepted = ownedTexture;
                    }
                    if (accepted != null) {
                        accepted.release();
                        if (!accepted.isReleased()) throw new Refused();
                    }
                    synchronized (lock) { textureReleased = true; }
                } catch (Throwable unknownTextureRelease) { cleanupUnproved.set(true); fail(); }
            }
            synchronized (lock) { nativeFinished = true; lock.notifyAll(); }
            postClose();
        }
    }

    private void initialize(SurfaceTexture accepted) {
        if (accepted == null || revoked.get()) return;
        display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY);
        require(display != null && !display.equals(EGL14.EGL_NO_DISPLAY)); eglError();
        int[] versions = new int[2];
        require(EGL14.eglInitialize(display, versions, 0, versions, 1)); initialized = true; eglError();
        int[] attributes = {EGL14.EGL_RED_SIZE, 8, EGL14.EGL_GREEN_SIZE, 8, EGL14.EGL_BLUE_SIZE, 8,
                EGL14.EGL_ALPHA_SIZE, 8, EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                EGL14.EGL_SURFACE_TYPE, EGL14.EGL_WINDOW_BIT, EGL14.EGL_NONE};
        EGLConfig[] configs = new EGLConfig[1]; int[] count = new int[1];
        require(EGL14.eglChooseConfig(display, attributes, 0, configs, 0, 1, count, 0)); eglError();
        require(count[0] == 1 && configs[0] != null);
        context = EGL14.eglCreateContext(display, configs[0], EGL14.EGL_NO_CONTEXT,
                new int[] {EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE}, 0);
        require(context != null && !context.equals(EGL14.EGL_NO_CONTEXT)); eglError();
        surface = EGL14.eglCreateWindowSurface(display, configs[0], accepted, new int[] {EGL14.EGL_NONE}, 0);
        require(surface != null && !surface.equals(EGL14.EGL_NO_SURFACE)); eglError();
        require(EGL14.eglMakeCurrent(display, surface, surface, context)); eglError(); current();
        frameDrawer = new VideoFrameDrawer(); rectDrawer = new GlRectDrawer(); glError();
    }

    private void draw(FrameJob job) {
        if (!authorized(job)) return;
        VideoFrame.I420Buffer planarBuffer = null; VideoFrame planar = null;
        try {
            planarBuffer = job.frame.getBuffer().toI420(); require(planarBuffer != null);
            require(validSize(planarBuffer.getWidth(), planarBuffer.getHeight()));
            planar = new VideoFrame(planarBuffer, job.frame.getRotation(), job.frame.getTimestampNs()); planarBuffer = null;
            if (!authorized(job)) return;
            current();
            int[] dimension = new int[1];
            require(EGL14.eglQuerySurface(display, surface, EGL14.EGL_WIDTH, dimension, 0)); eglError(); require(dimension[0] == job.width);
            require(EGL14.eglQuerySurface(display, surface, EGL14.EGL_HEIGHT, dimension, 0)); eglError(); require(dimension[0] == job.height);
            int fw = planar.getRotatedWidth(), fh = planar.getRotatedHeight(); require(validSize(fw, fh));
            double scale = Math.min((double) job.width / fw, (double) job.height / fh);
            int dw = Math.max(1, Math.min(job.width, (int) Math.round(fw * scale)));
            int dh = Math.max(1, Math.min(job.height, (int) Math.round(fh * scale)));
            if (!authorized(job)) return; current(); glError();
            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0);
            GLES20.glViewport(0, 0, job.width, job.height);
            GLES20.glClearColor(0, 0, 0, 1); GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT); glError();
            frameDrawer.drawFrame(planar, rectDrawer, null, (job.width - dw) / 2, (job.height - dh) / 2, dw, dh);
            glError();
            if (!authorized(job)) return; current();
            final long content;
            synchronized (lock) {
                if (!jobCurrent(job)) return;
                if (surfaceContentGeneration == Long.MAX_VALUE || swapInProgress) throw new Refused();
                content = ++surfaceContentGeneration;
                retainedSwap = null; pendingReceipt = null; swapInProgress = true;
            }
            try {
                if (!authorized(job)) return;
                require(EGL14.eglSwapBuffers(display, surface)); eglError(); glError(); current();
                if (!authorized(job)) return;
                synchronized (lock) {
                    if (!jobCurrent(job) || content != surfaceContentGeneration) return;
                    if (swapSequence == Long.MAX_VALUE) throw new Refused();
                    Receipt receipt = new Receipt(job, ++swapSequence, content);
                    retainedSwap = receipt; pendingReceipt = receipt;
                }
            } finally {
                synchronized (lock) { swapInProgress = false; }
            }
            postReceipt();
        } finally {
            if (planar != null) releaseFrame(planar);
            if (planarBuffer != null) {
                try { planarBuffer.release(); }
                catch (Throwable unknownBufferRelease) { cleanupUnproved.set(true); fail(); }
            }
        }
    }

    private boolean authorized(FrameJob job) {
        if (revoked.get()) return false;
        synchronized (lock) { if (!jobCurrent(job)) return false; }
        if (!model.permits(job.lease, peer, control, track)) return false;
        synchronized (lock) { return jobCurrent(job); }
    }
    private boolean jobCurrent(FrameJob job) {
        return !closing && scene == Scene.ACTIVE && !textureDestroyed && job.texture == ownedTexture
                && job.surfaceToken == surfaceToken && job.geometry == geometry && job.showGeneration == showGeneration
                && job.sceneGeneration == sceneGeneration && job.width == width && job.height == height;
    }
    private boolean receiptSurfaceCurrent(Receipt receipt) {
        return !closing && !swapInProgress && !textureDestroyed && receipt.texture == ownedTexture && receipt.surfaceToken == surfaceToken
                && receipt.geometry == geometry && receipt.showGeneration == showGeneration && receipt.swapSequence == swapSequence
                && receipt.surfaceContentGeneration == surfaceContentGeneration;
    }
    private void postReceipt() {
        boolean post;
        synchronized (lock) { post = !closing && !receiptPosted; if (post) receiptPosted = true; }
        if (post && !main.post(() -> {
            Receipt receipt;
            synchronized (lock) { receipt = pendingReceipt; pendingReceipt = null; receiptPosted = false; }
            if (receipt != null) uncover(receipt);
        })) fail();
    }
    private void uncover(Receipt receipt) {
        requireMain();
        synchronized (lock) {
            if (!receiptSurfaceCurrent(receipt) || scene != Scene.ACTIVE || receipt.sceneGeneration != sceneGeneration) return;
        }
        if (!model.permits(receipt.lease, peer, control, track) || revoked.get()) return;
        synchronized (lock) {
            if (!receiptSurfaceCurrent(receipt) || scene != Scene.ACTIVE || receipt.sceneGeneration != sceneGeneration) return;
        }
        cover.setVisibility(View.GONE);
    }

    private boolean releaseGL() {
        boolean clean = true;
        if (initialized && context != null && !context.equals(EGL14.EGL_NO_CONTEXT)) {
            try {
                current(); if (frameDrawer != null) frameDrawer.release(); if (rectDrawer != null) rectDrawer.release();
                GLES20.glFinish(); glError();
            } catch (Throwable unknownDrawerRelease) { clean = false; }
            try { require(EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)); eglError(); }
            catch (Throwable unknownDetach) { clean = false; }
        }
        if (surface != null && !surface.equals(EGL14.EGL_NO_SURFACE)) {
            try { require(EGL14.eglDestroySurface(display, surface)); eglError(); surface = EGL14.EGL_NO_SURFACE; }
            catch (Throwable unknownSurfaceRelease) { clean = false; }
        }
        if (context != null && !context.equals(EGL14.EGL_NO_CONTEXT)) {
            try { require(EGL14.eglDestroyContext(display, context)); eglError(); context = EGL14.EGL_NO_CONTEXT; }
            catch (Throwable unknownContextRelease) { clean = false; }
        }
        if (initialized) {
            try { require(EGL14.eglTerminate(display)); eglError(); initialized = false; display = EGL14.EGL_NO_DISPLAY; }
            catch (Throwable unknownDisplayRelease) { clean = false; }
        }
        try { require(EGL14.eglReleaseThread()); eglError(); }
        catch (Throwable unknownThreadRelease) { clean = false; }
        return clean;
    }
    private void current() {
        require(initialized && context.equals(EGL14.eglGetCurrentContext())
                && display.equals(EGL14.eglGetCurrentDisplay()) && surface.equals(EGL14.eglGetCurrentSurface(EGL14.EGL_DRAW))
                && !surface.equals(EGL14.EGL_NO_SURFACE)); eglError();
    }
    private static void eglError() { require(EGL14.eglGetError() == EGL14.EGL_SUCCESS); }
    private static void glError() { require(GLES20.glGetError() == GLES20.GL_NO_ERROR); }
    private static void require(boolean accepted) { if (!accepted) throw new Refused(); }

    private void releaseFrame(VideoFrame value) {
        try { value.release(); }
        catch (Throwable unknownRelease) {
            cleanupUnproved.set(true);
            synchronized (lock) { if (quarantinedFrames.size() < 4) quarantinedFrames.add(value); }
            fail();
        }
    }
    private void fail() {
        failed.set(true); revoke();
        if (failurePublished.compareAndSet(false, true)) {
            try { failure.run(); } catch (Throwable refusedCallback) { failed.set(true); }
        }
    }
    private void postClose() {
        boolean post;
        synchronized (lock) { post = !closePosted && !drained.isDone(); if (post) closePosted = true; }
        if (post && !main.post(this::finishCloseOnMain)) {
            cleanupUnproved.set(true); drained.completeExceptionally(new CleanupUnproved()); fail();
        }
    }
    private void finishCloseOnMain() {
        requireMain(); cover.setVisibility(View.VISIBLE);
        if (texture.getParent() == this) removeView(texture);
        boolean wait, clean, terminal, timedOut;
        synchronized (lock) {
            terminal = drained.isDone();
            long elapsed = System.nanoTime() - closeBeganNanos;
            timedOut = closing && (elapsed < 0 || elapsed >= CLOSE_NANOS);
            wait = !nativeFinished || worker != null && worker.isAlive() || intakeCount != 0;
            clean = !cleanupUnproved.get() && (ownedTexture == null || textureDestroyed && textureReleased) && pending == null;
            if (terminal || timedOut || !wait) closePosted = false;
        }
        if (terminal) return; // Visual cover/removal above is still required after an early failure.
        if (timedOut) {
            cleanupUnproved.set(true); drained.completeExceptionally(new CleanupUnproved()); fail();
        } else if (wait) {
            // One finite monotonic close observation. Timeout stops polling, never proves cleanup.
            if (!main.postDelayed(this::finishCloseOnMain, 10)) {
                cleanupUnproved.set(true); drained.completeExceptionally(new CleanupUnproved()); fail();
            }
        } else if (clean) drained.complete(null);
        else drained.completeExceptionally(new CleanupUnproved());
    }
    private static boolean validFrame(VideoFrame frame) {
        int rotation = frame.getRotation();
        return (rotation == 0 || rotation == 90 || rotation == 180 || rotation == 270)
                && validSize(frame.getBuffer().getWidth(), frame.getBuffer().getHeight());
    }
    private static boolean validSize(int width, int height) {
        return width > 0 && height > 0 && width <= MAXIMUM_DIMENSION && height <= MAXIMUM_DIMENSION
                && (long) width * height <= MAXIMUM_PIXELS;
    }
    private static void requireMain() {
        if (Looper.myLooper() != Looper.getMainLooper()) throw new IllegalStateException("Beluga video surface requires main thread");
    }
}
