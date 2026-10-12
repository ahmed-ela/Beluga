package com.elamin.beluga.protocol;

import android.content.Context;
import android.media.AudioDeviceInfo;
import android.media.AudioTrack;
import android.os.Handler;
import android.os.Looper;
import java.util.Objects;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.RejectedExecutionException;
import java.util.function.BooleanSupplier;
import org.webrtc.audio.PlaybackOutputObserver;

/** Exact M150 output callback adapter. Never allocates an output or changes a route. */
final class AndroidViewerPlaybackOutput implements PlaybackOutputObserver {
    private final ViewerPlaybackOutputLifetime<AudioTrack> lifetime;
    AndroidViewerPlaybackOutput(Context context, BooleanSupplier admitted, Runnable cancelExactAttempt) {
        Context application = Objects.requireNonNull(context.getApplicationContext());
        Handler handler = new Handler(Looper.getMainLooper());
        ViewerPlaybackOutputLifetime.Main main = new ViewerPlaybackOutputLifetime.Main() {
            @Override public void checkOwner() {
                if (Looper.myLooper() != Looper.getMainLooper()) throw new IllegalStateException("Main thread required");
            }
            @Override public void execute(Runnable task) {
                if (!handler.post(task)) throw new RejectedExecutionException("Main unavailable");
            }
            @Override public void later(Runnable task, long millis) {
                if (!handler.postDelayed(task, millis)) throw new RejectedExecutionException("Main unavailable");
            }
        };
        lifetime = new ViewerPlaybackOutputLifetime<>(main, new ViewerPlaybackOutputLifetime.Platform<AudioTrack>() {
            @Override public boolean routed(AudioTrack exact) {
                if (exact.getState() != AudioTrack.STATE_INITIALIZED) return false;
                AudioDeviceInfo device = exact.getRoutedDevice();
                return device != null && device.isSink();
            }
            @Override public ViewerPlaybackOutputLifetime.Owner create(AudioTrack exact, BooleanSupplier guard,
                    Runnable cancel, CompletionStage<Void> stopped) {
                ViewerPlaybackOwnership owner = AndroidViewerPlaybackOwnership.create(application, exact, guard, cancel, stopped);
                return new ViewerPlaybackOutputLifetime.Owner() {
                    @Override public boolean start() { return owner.start(); }
                    @Override public boolean authorized() { return owner.authorized(); }
                    @Override public CompletionStage<Void> drained() { return owner.drained(); }
                };
            }
        }, admitted, cancelExactAttempt);
    }
    @Override public void onPlaybackOutputStarted(AudioTrack output) { lifetime.started(output); }
    @Override public boolean isPlaybackAuthorized(AudioTrack output) { return lifetime.authorized(output); }
    @Override public void onPlaybackOutputStopped(AudioTrack output) { lifetime.stopped(output); }
    @Override public void onPlaybackOutputFailure(AudioTrack output, boolean unproved) { lifetime.failure(output, unproved); }
    void markPlayoutRequested() { lifetime.markPlayoutRequested(); }
    boolean authorized() { return lifetime.authorized(); }
    void revoke() { lifetime.revoke(); }
    boolean finishOutputStop() { return lifetime.finishOutputStop(); }
    CompletionStage<Void> drained() { return lifetime.drained(); }
    void cleanupUnproved() { lifetime.cleanupUnproved(); }
}
