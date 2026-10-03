package com.elamin.beluga.protocol;

import java.util.Arrays;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Owner;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.StoreStamp;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Transport;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.ReconnectPreparation;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.RecordPhase;
import com.elamin.beluga.protocol.ViewerStorageCatalog.Failure;

/**
 * Narrow trusted storage composition for one selected ACTIVE reconnect reservation.
 * Publication is supplied by the real encrypted store. Test ports do not prove Android durability.
 * NativeClose must join this exact captured transport; this class implements no socket itself.
 * Package visibility/echoed bytes do not authenticate hostile code in the same process.
 */
final class ViewerReconnectStorageLifecycle {
    interface Publication {
        void publish(ViewerStorageCatalog exactNext) throws Failure;
        byte[] readbackCatalog() throws Failure;
    }
    interface NativeClose {
        /** Actual exact transport/callback drain, not close requested or a caller boolean. */
        CompletionStage<Void> close(Transport exactTransport);
    }
    static final class Reserved {
        private final ViewerReconnectStorageLifecycle issuer;
        private final ReconnectPreparation preparation;
        private final StoreStamp after;
        private Reserved(ViewerReconnectStorageLifecycle issuer, ReconnectPreparation preparation, StoreStamp after) {
            this.issuer = issuer; this.preparation = preparation; this.after = after;
        }
        StoreStamp afterStamp() { return after; }
        byte[] requestPayloadForTrustedSender() throws Failure {
            synchronized (issuer) {
                ViewerStorageCatalog.demand(issuer.reserved == this && !issuer.failed && !issuer.owner.isRetired());
                return preparation.requestPayload();
            }
        }
        /** Final queued-send guard, not storage authority or a native connection-health claim. */
        boolean canSend() {
            synchronized (issuer) { return issuer.reserved == this && !issuer.failed && !issuer.owner.isRetired(); }
        }
        @Override public String toString() { return "<redacted exact committed reconnect reservation; not connected>"; }
    }
    static final class CloseReceipt {
        private final ViewerReconnectStorageLifecycle issuer;
        private CloseReceipt(ViewerReconnectStorageLifecycle issuer) { this.issuer = issuer; }
        boolean belongsTo(ViewerReconnectStorageLifecycle exact) {
            synchronized (issuer) { return issuer == exact && issuer.closeReceipt == this && issuer.owner.isRetired(); }
        }
        @Override public String toString() { return "<redacted exact reconnect close receipt>"; }
    }

    private final Owner owner;
    private final Transport transport;
    private final StoreStamp initial;
    private final NativeClose nativeClose;
    private final CompletableFuture<CloseReceipt> closeResult = new CompletableFuture<>();
    private ReconnectPreparation pending;
    private Reserved reserved;
    private CloseReceipt closeReceipt;
    private boolean started, failed, readbackDiscrepancy, closeStarted, closeAttached, closeObserved, closeFailed;

    ViewerReconnectStorageLifecycle(Owner exactOwner, Transport exactTransport, StoreStamp exactSelected,
            NativeClose trustedClose) throws Failure {
        ViewerStorageCatalog.demand(exactOwner != null && !exactOwner.isRetired() && exactTransport != null
                && exactTransport.ownedBy(exactOwner)
                && exactSelected != null && exactSelected.phase == RecordPhase.ACTIVE
                && exactSelected.pairID != null && trustedClose != null);
        owner = exactOwner; transport = exactTransport; initial = exactSelected; nativeClose = trustedClose;
    }

    Reserved reserve(ViewerStorageCatalog predecessor, ReconnectPreparation preparation, Publication publication)
            throws Failure {
        synchronized (this) {
            ViewerStorageCatalog.demand(!started && !failed && !owner.isRetired()
                    && predecessor != null && preparation != null && publication != null);
            started = true; pending = preparation;
        }
        byte[] expected = null, observed = null;
        try (ViewerStorageCatalog next = predecessor.reserveReconnect(initial, preparation)) {
            expected = next.encode();
            StoreStamp after = next.stamp(initial.target);
            requireLive(); publication.publish(next); requireLive();
            observed = publication.readbackCatalog();
            try {
                ViewerStorageCatalog.demand(observed != null && observed.length > 0
                        && observed.length <= ViewerStorageCatalog.MAXIMUM_BYTES && Arrays.equals(expected, observed));
                try (ViewerStorageCatalog actual = ViewerStorageCatalog.decode(observed)) {
                    ViewerStorageCatalog.demand(after.same(actual.stamp(initial.target))
                            && initial.target.equals(actual.selectedSlot));
                }
            } catch (Failure | RuntimeException corrupt) {
                synchronized (this) { readbackDiscrepancy = true; }
                throw new Failure();
            }
            // No owner monitor spans native IO. Cancellation shares only this final short
            // acknowledgement fence; retirement after it revokes all eventual queued sends.
            synchronized (owner) {
                synchronized (this) {
                    ViewerStorageCatalog.demand(!failed && !owner.isRetired() && reserved == null);
                    reserved = new Reserved(this, preparation, after); return reserved;
                }
            }
        } catch (Failure | RuntimeException refused) {
            owner.retire(); synchronized (this) { failed = true; }
            preparation.close(); throw new Failure();
        } finally {
            if (expected != null) Arrays.fill(expected, (byte) 0);
            if (observed != null) Arrays.fill(observed, (byte) 0);
        }
    }

    private void requireLive() throws Failure {
        synchronized (this) { ViewerStorageCatalog.demand(!failed && !owner.isRetired()); }
    }
    /** Failure classification only; never persistence/success authority supplied by a caller. */
    synchronized boolean readbackDiscrepancyForStore() { return readbackDiscrepancy; }

    /** Retirement is synchronous; native work and CompletionStage attachment occur outside locks. */
    CompletionStage<CloseReceipt> retireAndClose() {
        owner.retire();
        ReconnectPreparation cleanup;
        synchronized (this) {
            if (closeStarted) return closeResult.thenApply(value -> value);
            closeStarted = true; cleanup = pending;
        }
        if (cleanup != null) cleanup.close();
        try {
            CompletionStage<Void> nativeCompletion = nativeClose.close(transport);
            if (nativeCompletion == null) throw new IllegalStateException();
            nativeCompletion.whenComplete((ignored, error) -> observeClose(error));
            synchronized (this) { closeAttached = true; }
            finishCloseIfReady();
        } catch (RuntimeException refusal) {
            synchronized (this) { closeFailed = true; }
            closeResult.completeExceptionally(new Failure());
        }
        return closeResult.thenApply(value -> value);
    }
    private void observeClose(Throwable error) {
        synchronized (this) {
            if (closeObserved || closeFailed) return;
            closeObserved = true; if (error != null) closeFailed = true;
        }
        finishCloseIfReady();
    }
    private void finishCloseIfReady() {
        CloseReceipt receipt = null; boolean refusal;
        synchronized (this) {
            if (!closeAttached || !closeObserved || closeReceipt != null) return;
            refusal = closeFailed || !owner.isRetired();
            if (!refusal) { closeReceipt = new CloseReceipt(this); receipt = closeReceipt; }
        }
        // Future consumers may take SERIAL to drain IO, but never from inside this monitor.
        if (refusal) closeResult.completeExceptionally(new Failure()); else closeResult.complete(receipt);
    }
    @Override public String toString() { return "<redacted selected reconnect storage lifetime>"; }
}
