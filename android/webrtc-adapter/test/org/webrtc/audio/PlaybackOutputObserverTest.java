package org.webrtc.audio;

import static org.junit.Assert.*;
import android.media.AudioTrack;
import java.lang.reflect.Field;
import org.junit.Test;
import sun.misc.Unsafe;

/** Tests the actual patched helper, not JNI, AudioTrack writes, routing or physical cleanup. */
public final class PlaybackOutputObserverTest {
  // Identity-only SDK objects: no constructor, Android method, native load or device operation.
  private static AudioTrack identity() throws Exception {
    Field field = Unsafe.class.getDeclaredField("theUnsafe");
    field.setAccessible(true);
    return (AudioTrack) ((Unsafe) field.get(null)).allocateInstance(AudioTrack.class);
  }
  private static final class Observer implements PlaybackOutputObserver {
    boolean allowed, throwStart, throwGate, throwStop, throwFailure;
    int starts, gates, stops, failures;
    boolean unproved;
    AudioTrack startIdentity, gateIdentity, stopIdentity, failureIdentity;
    @Override public void onPlaybackOutputStarted(AudioTrack output) {
      starts++; startIdentity = output;
      if (throwStart) throw new IllegalStateException("synthetic private detail");
    }
    @Override public boolean isPlaybackAuthorized(AudioTrack output) {
      gates++; gateIdentity = output;
      if (throwGate) throw new IllegalStateException("synthetic private detail");
      return allowed;
    }
    @Override public void onPlaybackOutputStopped(AudioTrack output) {
      stops++; stopIdentity = output;
      if (throwStop) throw new IllegalStateException("synthetic private detail");
    }
    @Override public void onPlaybackOutputFailure(AudioTrack output, boolean cleanupUnproved) {
      failures++; failureIdentity = output; unproved = cleanupUnproved;
      if (throwFailure) throw new IllegalStateException("synthetic private detail");
    }
  }
  @Test public void unstartedOutputCannotAskForAdmission() throws Exception {
    Observer o = new Observer(); o.allowed = true;
    WebRtcAudioTrack.OutputLease lease = new WebRtcAudioTrack.OutputLease(o);
    assertFalse(lease.allows(identity())); assertEquals(0, o.gates);
    assertFalse(lease.published()); assertFalse(lease.failed());
  }
  @Test public void mutedBootstrapCanBecomeAuthorizedOnlyThroughExactObserver() throws Exception {
    Observer o = new Observer(); AudioTrack track = identity();
    WebRtcAudioTrack.OutputLease lease = new WebRtcAudioTrack.OutputLease(o);
    assertTrue(lease.started(track)); assertSame(track, o.startIdentity);
    assertFalse(lease.allows(track)); o.allowed = true; assertTrue(lease.allows(track));
    assertEquals(2, o.gates); assertSame(track, o.gateIdentity);
    o.allowed = false; assertFalse(lease.allows(track));
  }
  @Test public void wrongOutputFailsBeforeCallingAuthorityForAnotherTrack() throws Exception {
    Observer o = new Observer(); o.allowed = true; AudioTrack track = identity();
    WebRtcAudioTrack.OutputLease lease = new WebRtcAudioTrack.OutputLease(o);
    assertTrue(lease.started(track)); assertFalse(lease.allows(identity()));
    assertEquals(0, o.gates); assertTrue(lease.failed()); assertTrue(lease.cleanupUnproved());
    assertSame(track, o.failureIdentity); assertFalse(lease.allows(track));
  }
  @Test public void gateExceptionIsStickyEvenAfterObserverRecovers() throws Exception {
    Observer o = new Observer(); AudioTrack track = identity();
    WebRtcAudioTrack.OutputLease lease = new WebRtcAudioTrack.OutputLease(o);
    assertTrue(lease.started(track)); o.throwGate = true; assertFalse(lease.allows(track));
    assertTrue(lease.failed()); assertFalse(lease.cleanupUnproved());
    o.throwGate = false; o.allowed = true; assertFalse(lease.allows(track));
    assertEquals(1, o.gates); assertEquals(1, o.failures);
  }
  @Test public void replacementStartReportsTheOriginalOwnedOutputNotTheIntruder() throws Exception {
    Observer o = new Observer(); AudioTrack owned = identity(), replacement = identity();
    WebRtcAudioTrack.OutputLease lease = new WebRtcAudioTrack.OutputLease(o);
    assertTrue(lease.started(owned)); assertFalse(lease.started(replacement));
    assertEquals(1, o.starts); assertSame(owned, o.failureIdentity);
    assertTrue(lease.cleanupUnproved()); assertFalse(lease.allows(owned));
  }
  @Test public void startExceptionBlocksWritesButDoesNotInventNativeCleanupFailure() throws Exception {
    Observer o = new Observer(); o.throwStart = true; AudioTrack track = identity();
    WebRtcAudioTrack.OutputLease lease = new WebRtcAudioTrack.OutputLease(o);
    assertFalse(lease.started(track)); assertTrue(lease.failed());
    assertFalse(lease.cleanupUnproved()); assertFalse(lease.allows(track));
    // Only the real stop path may invoke this after independently successful join/stop/release.
    assertTrue(lease.stopped(track)); assertEquals(1, o.stops);
  }
  @Test public void failedNativeJoinCannotPublishStoppedOrReopenPlayback() throws Exception {
    Observer o = new Observer(); AudioTrack track = identity();
    WebRtcAudioTrack.OutputLease lease = new WebRtcAudioTrack.OutputLease(o);
    assertTrue(lease.started(track)); lease.failure(track, true);
    assertFalse(lease.stopped(track)); assertFalse(lease.allows(track));
    assertEquals(0, o.stops); assertTrue(lease.cleanupUnproved()); assertEquals(1, o.failures);
    assertFalse(lease.started(identity())); assertEquals(1, o.starts);
  }
  @Test public void failedCleanupEscalatesOperationalFailureExactlyOnce() throws Exception {
    Observer o = new Observer(); AudioTrack track = identity();
    WebRtcAudioTrack.OutputLease lease = new WebRtcAudioTrack.OutputLease(o);
    assertTrue(lease.started(track)); lease.failure(track, false); assertEquals(1, o.failures);
    lease.failure(track, true); assertEquals(2, o.failures); assertTrue(o.unproved);
    lease.failure(track, true); lease.failure(track, false); assertEquals(2, o.failures);
    assertFalse(lease.stopped(track)); assertEquals(0, o.stops);
  }
  @Test public void stoppedReceiptCarriesExactReleasedIdentityAndIsSingleUse() throws Exception {
    Observer o = new Observer(); o.allowed = true; AudioTrack track = identity();
    WebRtcAudioTrack.OutputLease lease = new WebRtcAudioTrack.OutputLease(o);
    assertTrue(lease.started(track)); assertTrue(lease.allows(track)); assertTrue(lease.stopped(track));
    assertSame(track, o.stopIdentity); assertFalse(lease.allows(track));
    assertFalse(lease.stopped(track)); assertEquals(1, o.stops);
    assertFalse(lease.started(track)); assertEquals(1, o.starts);
  }
  @Test public void stoppedCallbackFailureIsNotACompletedReceipt() throws Exception {
    Observer o = new Observer(); o.throwStop = true; AudioTrack track = identity();
    WebRtcAudioTrack.OutputLease lease = new WebRtcAudioTrack.OutputLease(o);
    assertTrue(lease.started(track)); assertFalse(lease.stopped(track));
    assertTrue(lease.failed()); assertTrue(lease.cleanupUnproved()); assertEquals(1, o.failures);
    assertFalse(lease.allows(track));
  }
  @Test public void failureCallbackExceptionNeverEscapesOrReopensGate() throws Exception {
    Observer o = new Observer(); o.throwFailure = true; AudioTrack track = identity();
    WebRtcAudioTrack.OutputLease lease = new WebRtcAudioTrack.OutputLease(o);
    assertTrue(lease.started(track)); lease.failure(track, false);
    assertTrue(lease.failed()); assertTrue(lease.cleanupUnproved());
    assertFalse(lease.stopped(track)); assertFalse(lease.allows(track));
  }
  @Test public void missingAndUnpublishedOutputsCannotPublishStopped() throws Exception {
    Observer o = new Observer(); WebRtcAudioTrack.OutputLease lease = new WebRtcAudioTrack.OutputLease(o);
    assertFalse(lease.stopped(identity())); assertEquals(0, o.stops); assertTrue(lease.cleanupUnproved());
    Observer missing = new Observer(); WebRtcAudioTrack.OutputLease second = new WebRtcAudioTrack.OutputLease(missing);
    assertFalse(second.started(null)); assertEquals(0, missing.starts); assertTrue(second.failed());
  }
  @Test public void retiredLifetimeCannotAffectSuccessor() throws Exception {
    Observer old = new Observer(), next = new Observer(); AudioTrack oldTrack = identity(), nextTrack = identity();
    WebRtcAudioTrack.OutputLease first = new WebRtcAudioTrack.OutputLease(old), second = new WebRtcAudioTrack.OutputLease(next);
    assertTrue(first.started(oldTrack)); assertTrue(first.stopped(oldTrack));
    assertTrue(second.started(nextTrack)); next.allowed = true;
    first.failure(oldTrack, true); assertTrue(second.allows(nextTrack)); assertEquals(0, next.failures);
  }
}
