package com.elamin.beluga.protocol;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import java.nio.charset.StandardCharsets;
import org.junit.Test;

/** Pure projection checks only. No Context, Keystore, storage, session or transport execution. */
public final class AndroidViewerPairingTest {
    @Test public void pairingAndConnectionShareExactProcessLease() {
        assertFalse(AndroidViewerPairing.isAttemptInFlight());
        Object first = AndroidViewerPairing.acquireAttempt();
        try {
            assertTrue(AndroidViewerPairing.isAttemptInFlight());
            AndroidViewerPairing.releaseAttempt(new Object());
            AndroidViewerPairing.releaseAttempt(null);
            assertTrue(AndroidViewerPairing.isAttemptInFlight());
            try { AndroidViewerPairing.acquireAttempt(); org.junit.Assert.fail("Duplicate admitted"); }
            catch (IllegalStateException expected) { }
        } finally { AndroidViewerPairing.releaseAttempt(first); }
        Object second = AndroidViewerPairing.acquireAttempt();
        try {
            AndroidViewerPairing.releaseAttempt(first);
            assertTrue(AndroidViewerPairing.isAttemptInFlight());
        } finally { AndroidViewerPairing.releaseAttempt(second); }
        assertFalse(AndroidViewerPairing.isAttemptInFlight());
    }
    @Test public void absentConnectionResultCannotReleaseProcessLease() {
        assertFalse(AndroidViewerConnection.permitsProcessRelease(null));
    }
    @Test public void terminalFailureHasNoPairingMetadataOrSecretDiagnostics() {
        for (ViewerPairingSession.Failure failure : ViewerPairingSession.Failure.values()) {
            if (failure == ViewerPairingSession.Failure.NONE) continue;
            AndroidViewerPairing.Terminal terminal = AndroidViewerPairing.Terminal.from(
                    new ViewerPairingSession.Result(ViewerPairingSession.Status.FAILED, failure, null));
            assertEquals(AndroidViewerPairing.Status.FAILED, terminal.status());
            assertEquals(failure.name(), terminal.failure().name());
            assertNull(terminal.pairID()); assertNull(terminal.hostID()); assertNull(terminal.displayName());
            assertEquals("<redacted Beluga pairing terminal; not media connectivity>", terminal.toString());
        }
    }
    @Test public void pairedWithoutExactMetadataCannotBeProjectedAsSuccess() {
        AndroidViewerPairing.Terminal terminal = AndroidViewerPairing.Terminal.from(
                new ViewerPairingSession.Result(ViewerPairingSession.Status.PAIRED, ViewerPairingSession.Failure.NONE, null));
        assertEquals(AndroidViewerPairing.Status.FAILED, terminal.status());
        assertEquals(AndroidViewerPairing.Failure.PROTOCOL, terminal.failure());
        assertNull(terminal.hostID()); assertNull(terminal.pairID());
    }
    @Test public void malformedOrInconsistentTerminalRefuses() {
        assertEquals(AndroidViewerPairing.Failure.PROTOCOL, AndroidViewerPairing.Terminal.from(null).failure());
        for (ViewerPairingSession.Status status : new ViewerPairingSession.Status[] {
                ViewerPairingSession.Status.FAILED, ViewerPairingSession.Status.CANCELLED, ViewerPairingSession.Status.CLEANUP_UNPROVEN }) {
            AndroidViewerPairing.Terminal terminal = AndroidViewerPairing.Terminal.from(
                    new ViewerPairingSession.Result(status, ViewerPairingSession.Failure.NONE, null));
            assertEquals(AndroidViewerPairing.Status.FAILED, terminal.status());
            assertEquals(AndroidViewerPairing.Failure.PROTOCOL, terminal.failure());
        }
    }
    @Test public void cancellationAndUnprovenCleanupRemainDistinct() {
        AndroidViewerPairing.Terminal cancelled = AndroidViewerPairing.Terminal.from(
                new ViewerPairingSession.Result(ViewerPairingSession.Status.CANCELLED, ViewerPairingSession.Failure.CANCELLED, null));
        AndroidViewerPairing.Terminal unproven = AndroidViewerPairing.Terminal.from(
                new ViewerPairingSession.Result(ViewerPairingSession.Status.CLEANUP_UNPROVEN, ViewerPairingSession.Failure.DRAIN, null));
        assertEquals(AndroidViewerPairing.Status.CANCELLED, cancelled.status());
        assertEquals(AndroidViewerPairing.Status.CLEANUP_UNPROVEN, unproven.status());
        assertNull(cancelled.hostID()); assertNull(unproven.hostID());
    }
    @Test public void rawUnprovenOrMalformedCompletionNeverReleasesProcessAdmission() {
        for (ViewerPairingSession.Failure failure : ViewerPairingSession.Failure.values()) {
            ViewerPairingSession.Result raw = new ViewerPairingSession.Result(
                    ViewerPairingSession.Status.CLEANUP_UNPROVEN, failure, null);
            assertFalse(AndroidViewerPairing.terminalPermitsProcessRelease(raw, AndroidViewerPairing.Terminal.from(raw)));
        }
        ViewerPairingSession.Result malformed = new ViewerPairingSession.Result(null, null, null);
        assertFalse(AndroidViewerPairing.terminalPermitsProcessRelease(malformed, AndroidViewerPairing.Terminal.from(malformed)));
        assertFalse(AndroidViewerPairing.terminalPermitsProcessRelease(null, AndroidViewerPairing.Terminal.from(null)));
        ViewerPairingSession.Result incompleteSuccess = new ViewerPairingSession.Result(
                ViewerPairingSession.Status.PAIRED, ViewerPairingSession.Failure.NONE, null);
        assertFalse(AndroidViewerPairing.terminalPermitsProcessRelease(incompleteSuccess,
                AndroidViewerPairing.Terminal.from(incompleteSuccess)));
    }
    @Test public void exactValidFailureAndCancellationTerminalPermitReleaseOnlyAsTheirOwnStatus() {
        ViewerPairingSession.Result failed = new ViewerPairingSession.Result(
                ViewerPairingSession.Status.FAILED, ViewerPairingSession.Failure.PREPARATION, null);
        ViewerPairingSession.Result cancelled = new ViewerPairingSession.Result(
                ViewerPairingSession.Status.CANCELLED, ViewerPairingSession.Failure.CANCELLED, null);
        assertTrue(AndroidViewerPairing.terminalPermitsProcessRelease(failed, AndroidViewerPairing.Terminal.from(failed)));
        assertTrue(AndroidViewerPairing.terminalPermitsProcessRelease(cancelled, AndroidViewerPairing.Terminal.from(cancelled)));
        assertFalse(AndroidViewerPairing.terminalPermitsProcessRelease(failed, AndroidViewerPairing.Terminal.from(cancelled)));
    }
    @Test public void displayLabelRemovesControlsAndBidiFormattingWithoutTouchingWireData() {
        String original = "  Mac\u202e\u2066\u0000\n\u2028\u2029\u200dBook  ";
        assertEquals("MacBook", AndroidViewerPairing.sanitizedDisplayName(original));
        assertTrue(original.contains("\u202e"));
        assertEquals("Caf\u00e9 \uD83D\uDE00", AndroidViewerPairing.sanitizedDisplayName("Caf\u00e9 \uD83D\uDE00"));
    }
    @Test public void displayLabelHasStrictInputAndOutputBounds() {
        assertEquals("Paired Mac", AndroidViewerPairing.sanitizedDisplayName(null));
        assertEquals("Paired Mac", AndroidViewerPairing.sanitizedDisplayName("\uD800"));
        assertEquals("Paired Mac", AndroidViewerPairing.sanitizedDisplayName("\uDC00"));
        assertEquals("Paired Mac", AndroidViewerPairing.sanitizedDisplayName("\u202e\n "));
        assertEquals("Paired Mac", AndroidViewerPairing.sanitizedDisplayName(repeat("a", 129)));
        assertEquals("Paired Mac", AndroidViewerPairing.sanitizedDisplayName(repeat("\u00e9", 65)));
        String label = AndroidViewerPairing.sanitizedDisplayName(repeat("a", 128));
        assertEquals(64, label.codePointCount(0, label.length()));
        assertTrue(label.getBytes(StandardCharsets.UTF_8).length <= 128);
        assertFalse(label.contains("\u202e"));
    }
    private static String repeat(String value, int count) {
        StringBuilder result = new StringBuilder(); for (int i = 0; i < count; i++) result.append(value); return result.toString();
    }
}
