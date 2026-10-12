package com.elamin.beluga.protocol;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.media.AudioAttributes;
import android.media.AudioDeviceCallback;
import android.media.AudioDeviceInfo;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.media.AudioRouting;
import android.media.AudioTrack;
import android.os.Handler;
import android.os.Looper;
import java.util.Objects;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.RejectedExecutionException;
import java.util.function.BooleanSupplier;

/** Media focus and conservative loss monitoring; never creates a track or changes a device route. */
final class AndroidViewerPlaybackOwnership {
    private AndroidViewerPlaybackOwnership() { }

    /**
     * exactOutput must be the receiver's real, initialized playback AudioTrack, not a probe track.
     * No routed device means no authorization. Since a route may be absent until playback starts,
     * native integration must establish it with media delivery muted; this adapter does not bootstrap it.
     * nativeDrain is the exact output's stopped-after-join receipt, not the parent's final close.
     * The parent's Media.close separately joins native graph and returned owner.drained() cleanup.
     */
    static ViewerPlaybackOwnership create(Context context, AudioTrack exactOutput, BooleanSupplier ownerAdmitted,
            Runnable cancelExactAttempt, CompletionStage<Void> nativeDrain) {
        if (Looper.myLooper() != Looper.getMainLooper()) throw new IllegalStateException("Playback owner requires main thread");
        Context application = Objects.requireNonNull(Objects.requireNonNull(context).getApplicationContext());
        AudioManager audio = Objects.requireNonNull(application.getSystemService(AudioManager.class));
        Handler handler = new Handler(Looper.getMainLooper());
        ViewerPlaybackOwnership.MainPort main = new ViewerPlaybackOwnership.MainPort() {
            @Override public void checkOwner() {
                if (Looper.myLooper() != Looper.getMainLooper()) throw new IllegalStateException("Playback owner requires main thread");
            }
            @Override public void execute(Runnable work) {
                if (!handler.post(work)) throw new RejectedExecutionException("Playback owner unavailable");
            }
        };
        return new ViewerPlaybackOwnership(main, new Platform(application, audio, Objects.requireNonNull(exactOutput), handler),
                ownerAdmitted, cancelExactAttempt, nativeDrain);
    }

    private static final class Platform implements ViewerPlaybackOwnership.Platform {
        private final Context context;
        private final AudioManager audio;
        private final AudioTrack output;
        private final Handler handler;
        private ViewerPlaybackOwnership.Events events;
        private AudioFocusRequest focus;
        private AudioRouting.OnRoutingChangedListener routing;
        private AudioDeviceCallback devices;
        private BroadcastReceiver noisy;
        private boolean routingAttempted, devicesAttempted, noisyAttempted, focusAttempted, released;
        Platform(Context context, AudioManager audio, AudioTrack output, Handler handler) {
            this.context = context; this.audio = audio; this.output = output; this.handler = handler;
        }
        @Override public void register(ViewerPlaybackOwnership.Events sink) {
            if (events != null || released) throw new IllegalStateException("Playback listeners already owned");
            events = Objects.requireNonNull(sink);
            routing = source -> {
                if (source == output) sink.routeChanged(); else sink.unavailable();
            };
            devices = new AudioDeviceCallback() {
                @Override public void onAudioDevicesRemoved(AudioDeviceInfo[] removed) {
                    if (removed == null) { sink.unavailable(); return; }
                    for (AudioDeviceInfo device : removed) {
                        if (device == null) { sink.unavailable(); return; }
                        // Availability is not active-route evidence. Any sink removal conservatively stops.
                        if (device.isSink()) { sink.outputRemoved(); return; }
                    }
                }
            };
            noisy = new BroadcastReceiver() {
                @Override public void onReceive(Context ignored, Intent intent) {
                    if (intent != null && AudioManager.ACTION_AUDIO_BECOMING_NOISY.equals(intent.getAction())) sink.noisy();
                }
            };
            focus = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                    .setAcceptsDelayedFocusGain(false).setWillPauseWhenDucked(true)
                    .setOnAudioFocusChangeListener(change -> sink.focusChanged(change == AudioManager.AUDIOFOCUS_GAIN), handler)
                    .build();
            routingAttempted = true; output.addOnRoutingChangedListener(routing, handler);
            devicesAttempted = true; audio.registerAudioDeviceCallback(devices, handler);
            // This filter contains only a protected system broadcast, exempt from exported flags.
            noisyAttempted = true;
            context.registerReceiver(noisy, new IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY), null, handler);
        }
        @Override public ViewerPlaybackOwnership.Route route() {
            if (released || output.getState() != AudioTrack.STATE_INITIALIZED) return null;
            AudioDeviceInfo device = output.getRoutedDevice();
            if (device == null || !device.isSink()) return null;
            return new ViewerPlaybackOwnership.Route(output, device.getId(), device.getType());
        }
        @Override public boolean requestFocus() {
            if (focus == null || focusAttempted || released) throw new IllegalStateException("Invalid playback focus request");
            focusAttempted = true;
            // Target 35+ top-app / admitted foreground-service restrictions are not bypassed.
            return audio.requestAudioFocus(focus) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED;
        }
        @Override public void release() {
            if (released) return;
            released = true; boolean clean = true;
            if (focusAttempted) try {
                if (audio.abandonAudioFocusRequest(focus) != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) clean = false;
            } catch (RuntimeException unknown) { clean = false; }
            if (routingAttempted) try { output.removeOnRoutingChangedListener(routing); }
            catch (RuntimeException unknown) { clean = false; }
            if (devicesAttempted) try { audio.unregisterAudioDeviceCallback(devices); }
            catch (RuntimeException unknown) { clean = false; }
            if (noisyAttempted) try { context.unregisterReceiver(noisy); }
            catch (RuntimeException unknown) { clean = false; }
            if (!clean) throw new IllegalStateException("Playback platform cleanup unproved");
        }
    }
}
