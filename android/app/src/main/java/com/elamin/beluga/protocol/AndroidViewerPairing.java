package com.elamin.beluga.protocol;

import android.content.Context;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.UUID;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.ClosePort;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Owner;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.StoreStamp;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Transport;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.PreparedViewer;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.ViewerIdentity;

/**
 * Foreground, one-use NEW-Mac pairing facade. Storage must already be explicitly enrolled.
 * No enrollment/reset, Activity retention, permission request, reconnect or media is performed.
 * Terminal PAIRED means authenticated durable bootstrap plus exact transport drain, not connected.
 */
public final class AndroidViewerPairing {
    private static final AtomicReference<Object> IN_FLIGHT = new AtomicReference<>();
    private AndroidViewerPairing() { }

    /** Read-only lifecycle gate; only exact session completion may release this lease. */
    static boolean isAttemptInFlight() { return IN_FLIGHT.get() != null; }

    // Package-owned process admission is shared with the saved-Mac media session.
    // Normal availability closure must not release this longer-lived lease.
    static Object acquireAttempt() {
        Object lease = new Object();
        if (!IN_FLIGHT.compareAndSet(null, lease)) throw new IllegalStateException("Beluga connection unavailable");
        return lease;
    }
    static void releaseAttempt(Object lease) {
        if (lease != null) IN_FLIGHT.compareAndSet(lease, null);
    }

    public enum Status { PAIRED, CANCELLED, FAILED, CLEANUP_UNPROVEN }
    public enum Failure { NONE, CANCELLED, PREPARATION, PROTOCOL, NETWORK, OVERFLOW, TIMEOUT, DRAIN, RELEASE }

    /** Nonsecret immutable terminal metadata. No invitation, signing key, root or record escapes. */
    public static final class Terminal {
        private final Status status;
        private final Failure failure;
        private final UUID pairID, hostID;
        private final String displayName;
        private Terminal(Status status, Failure failure, UUID pairID, UUID hostID, String displayName) {
            this.status = status; this.failure = failure;
            this.pairID = pairID; this.hostID = hostID; this.displayName = displayName;
        }
        public Status status() { return status; }
        public Failure failure() { return failure; }
        public UUID pairID() { return pairID; }
        public UUID hostID() { return hostID; }
        public String displayName() { return displayName; }
        @Override public String toString() { return "<redacted Beluga pairing terminal; not media connectivity>"; }

        static Terminal from(ViewerPairingSession.Result result) {
            if (result == null || result.status == null || result.failure == null) return refusedTerminal();
            Status status = Status.valueOf(result.status.name());
            Failure failure = Failure.valueOf(result.failure.name());
            if (status == Status.PAIRED) {
                if (failure != Failure.NONE || !nonzero(result.pairID) || !nonzero(result.hostID)) return refusedTerminal();
                return new Terminal(status, failure, result.pairID, result.hostID, sanitizedDisplayName(result.displayName));
            }
            if (failure == Failure.NONE || (status == Status.CANCELLED && failure != Failure.CANCELLED)) return refusedTerminal();
            return new Terminal(status, failure, null, null, null);
        }
        private static Terminal refusedTerminal() { return new Terminal(Status.FAILED, Failure.PROTOCOL, null, null, null); }
    }

    /** cancel() revokes immediately; unproven cleanup cannot release successor admission. */
    public static final class Attempt {
        private final ViewerPairingSession session;
        private final CompletionStage<Terminal> terminal;
        private Attempt(ViewerPairingSession session, CompletionStage<ViewerPairingSession.Result> completion, Object lease) {
            this.session = session;
            terminal = completion.thenApply(result -> {
                Terminal projected = Terminal.from(result);
                // The exact raw session terminal owns release, never a sanitized failure substitute.
                if (terminalPermitsProcessRelease(result, projected)) IN_FLIGHT.compareAndSet(lease, null);
                return projected;
            });
        }
        public void cancel() { session.cancel(); }
        public CompletionStage<Terminal> completion() { return terminal.thenApply(value -> value); }
        @Override public String toString() { return "<redacted one-use Beluga pairing attempt>"; }
    }

    /** Only the application Context is retained; all secure storage and crypto run on the session worker. */
    public static Attempt start(Context context, PairingInvitation invitation,
            long expectedCatalogRevision, long expectedSelectionRevision) {
        if (context == null || invitation == null || expectedCatalogRevision < 0 || expectedSelectionRevision < 0)
            throw new IllegalArgumentException("Invalid Beluga pairing request");
        Context application = context.getApplicationContext();
        if (application == null) throw new IllegalArgumentException("Beluga application context unavailable");
        Object lease = acquireAttempt();
        ViewerPairingSession session;
        CompletionStage<ViewerPairingSession.Result> completion;
        try {
            session = ViewerPairingSession.production();
            ExistingPreparation preparation = new ExistingPreparation(application, invitation,
                    expectedCatalogRevision, expectedSelectionRevision);
            completion = session.start(invitation, preparation);
        } catch (RuntimeException refusedBeforeStartReturned) {
            // Session.start either returns its terminal stage or refuses before worker ownership;
            // its Thread.start refusal is internally terminalized. Never clear a successor token.
            IN_FLIGHT.compareAndSet(lease, null);
            throw new IllegalStateException("Beluga pairing preparation unavailable");
        }
        return new Attempt(session, completion, lease);
    }

    private static final class ExistingPreparation implements ViewerPairingSession.Preparation {
        private Context application;
        private PairingInvitation invitation;
        private final long catalogRevision, selectionRevision;
        private final AtomicBoolean begun = new AtomicBoolean();
        ExistingPreparation(Context application, PairingInvitation invitation, long catalogRevision, long selectionRevision) {
            this.application = application; this.invitation = invitation;
            this.catalogRevision = catalogRevision; this.selectionRevision = selectionRevision;
        }
        @Override public ViewerPairingSession.Prepared prepare(Owner owner, Transport transport,
                ClosePort nativeClose) throws Exception {
            if (!begun.compareAndSet(false, true)) throw new PreparationRefused();
            byte[] secret = null, fingerprint = null;
            try {
                requireLive(owner);
                AndroidViewerSecureStore store = AndroidViewerSecureStore.openExisting(application);
                requireLive(owner);
                AndroidViewerSecureStore.Snapshot before = store.snapshot();
                requireLive(owner);
                if (before.catalogRevision != catalogRevision || before.selectionRevision != selectionRevision)
                    throw new PreparationRefused();
                ViewerIdentity identity = store.identity();
                requireLive(owner);
                secret = invitation.copySecretForPairing();
                PreparedViewer viewer;
                try { viewer = store.prepareViewer(secret, "Beluga Android"); }
                finally { Arrays.fill(secret, (byte) 0); secret = null; }
                requireLive(owner);
                fingerprint = invitation.admissionFingerprint();
                requireLive(owner);
                // This transaction rechecks exact revisions. A stale precheck cannot reserve a slot.
                StoreStamp initial = store.beginNewMac(UUID.randomUUID(), fingerprint, catalogRevision, selectionRevision);
                requireLive(owner);
                ViewerStoragePorts ports = new ViewerStoragePorts(store, owner, transport, initial, nativeClose);
                requireLive(owner);
                // Pure ports only: reducer validation precedes session-owned activate().
                return new ViewerPairingSession.Prepared(viewer, identity, initial, ports);
            } finally {
                if (secret != null) Arrays.fill(secret, (byte) 0);
                if (fingerprint != null) Arrays.fill(fingerprint, (byte) 0);
                invitation = null; application = null;
            }
        }
    }
    private static final class PreparationRefused extends Exception {
        private static final long serialVersionUID = 1L;
        PreparationRefused() { super("Beluga pairing preparation refused"); }
    }
    private static void requireLive(Owner owner) throws PreparationRefused {
        if (owner == null || owner.isRetired()) throw new PreparationRefused();
    }
    private static boolean nonzero(UUID value) {
        return value != null && (value.getMostSignificantBits() != 0 || value.getLeastSignificantBits() != 0);
    }

    /** Pure policy used only after completion of this exact trusted Session result stage. */
    static boolean terminalPermitsProcessRelease(ViewerPairingSession.Result result, Terminal projected) {
        if (result == null || result.status == null || result.failure == null || projected == null
                || result.status == ViewerPairingSession.Status.CLEANUP_UNPROVEN) return false;
        // Reject malformed/inconsistent result projections; exceptional completion never enters here.
        return projected.status.name().equals(result.status.name())
                && projected.failure.name().equals(result.failure.name());
    }

    /** UI-only label projection; never alters authenticated transcript or catalog data. */
    static String sanitizedDisplayName(String value) {
        final String fallback = "Paired Mac";
        if (value == null || value.length() > 128 || value.getBytes(StandardCharsets.UTF_8).length > 128) return fallback;
        StringBuilder result = new StringBuilder(64); int count = 0;
        for (int offset = 0; offset < value.length() && count < 64;) {
            char first = value.charAt(offset);
            if (Character.isLowSurrogate(first) || (Character.isHighSurrogate(first)
                    && (offset + 1 == value.length() || !Character.isLowSurrogate(value.charAt(offset + 1))))) return fallback;
            int scalar = value.codePointAt(offset); offset += Character.charCount(scalar);
            int type = Character.getType(scalar);
            if (Character.isISOControl(scalar) || type == Character.FORMAT
                    || type == Character.LINE_SEPARATOR || type == Character.PARAGRAPH_SEPARATOR) continue;
            result.appendCodePoint(scalar); count++;
        }
        String label = result.toString().trim(); return label.isEmpty() ? fallback : label;
    }
}
