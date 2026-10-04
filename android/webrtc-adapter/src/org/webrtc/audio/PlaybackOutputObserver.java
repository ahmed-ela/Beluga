package org.webrtc.audio;

import android.media.AudioTrack;

/**
 * Opt-in to Beluga's exact-output patch; this interface alone does not modify the stock AAR.
 * Opted-in users receive the exact-output callbacks, not the inherited no-argument callbacks.
 */
public interface PlaybackOutputObserver extends JavaAudioDeviceModule.AudioTrackStateCallback {
  /** Audio thread, after play begins and before pulling PCM. Dispatch platform ownership to main. */
  void onPlaybackOutputStarted(AudioTrack exactOutput);

  /** Audio thread, immediately before each write. Nonblocking; false substitutes silence. */
  boolean isPlaybackAuthorized(AudioTrack exactOutput);

  /** Native control thread, only after successful thread join, stop and release. */
  void onPlaybackOutputStopped(AudioTrack exactOutput);

  /**
   * Nonblocking, sticky failure notification. Cancel this attempt, never resume automatically.
   * cleanupUnproved=true requires quarantine BEFORE peer.close/dispose/factory/ADM release.
   * Returning false from native StopPlayout does not prevent native destruction by itself.
   * The caller must keep the entire native graph strongly owned and report failed cleanup.
   * A missing stopped receipt is also unproved, even if this failure callback itself throws.
   * exactOutput may be null if failure occurs before a valid output is published.
   */
  void onPlaybackOutputFailure(AudioTrack exactOutput, boolean cleanupUnproved);

  @Override default void onWebRtcAudioTrackStart() { }
  @Override default void onWebRtcAudioTrackStop() { }
}
