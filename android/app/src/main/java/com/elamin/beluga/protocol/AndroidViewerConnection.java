package com.elamin.beluga.protocol;

import android.content.Context;
import java.util.UUID;
import java.util.concurrent.CompletionStage;
import java.util.function.BooleanSupplier;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Owner;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.StoreStamp;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Transport;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.SessionCredential;
import com.elamin.beluga.protocol.ViewerReconnectStorageLifecycle.NativeClose;
import com.elamin.beluga.protocol.ViewerReconnectStorageLifecycle.Reserved;

/**
 * Package-private composition for a selected saved Mac. No UI action exposes it until a compatible
 * native receiver is supplied and verified. No enrollment, automatic retry, selection change,
 * permission request or local microphone capture. Pairing and media share one process lease.
 */
final class AndroidViewerConnection {
    private AndroidViewerConnection() { }

    interface ReceiverFactory {
        ViewerConnectionSession.Media start(Context application, AndroidViewerSecureStore.ReconnectPeer peer,
                SessionCredential credential, BooleanSupplier authorized, ViewerConnectionSession.MediaListener listener)
                throws ViewerConnectionSession.PreallocationRefusal;
    }
    static final class Attempt {
        private final ViewerConnectionSession session;
        private final CompletionStage<ViewerConnectionSession.Result> terminal;
        private Attempt(ViewerConnectionSession session, CompletionStage<ViewerConnectionSession.Result> completion, Object lease) {
            this.session = session;
            terminal = completion.thenApply(result -> {
                if (permitsProcessRelease(result)) AndroidViewerPairing.releaseAttempt(lease);
                return result;
            });
        }
        void cancel() { session.cancel(); }
        ViewerConnectionSession.State state() { return session.state(); }
        CompletionStage<ViewerConnectionSession.Result> completion() { return terminal.thenApply(value -> value); }
        @Override public String toString() { return "<Beluga selected-Mac attempt; no decoded-media claim>"; }
    }
    static Attempt start(Context context, UUID exactHostID, long catalogRevision, long selectionRevision,
            ReceiverFactory receiver) {
        if (context == null || exactHostID == null || (exactHostID.getMostSignificantBits() == 0
                && exactHostID.getLeastSignificantBits() == 0) || catalogRevision < 0 || selectionRevision < 0 || receiver == null)
            throw new IllegalArgumentException("Invalid Beluga saved-Mac connection");
        Context application = context.getApplicationContext();
        if (application == null) throw new IllegalArgumentException("Beluga application context unavailable");
        Object lease = AndroidViewerPairing.acquireAttempt();
        try {
            ExistingStorage storage = new ExistingStorage(application, exactHostID, catalogRevision, selectionRevision);
            ViewerConnectionSession session = ViewerConnectionSession.production((credential, authorized, listener) -> {
                if (!authorized.getAsBoolean() || storage.peer == null) throw new ViewerConnectionSession.PreallocationRefusal();
                return receiver.start(application, storage.peer, credential, authorized, listener);
            });
            CompletionStage<ViewerConnectionSession.Result> completion = session.start(storage::prepare);
            return new Attempt(session, completion, lease);
        } catch (RuntimeException refusedBeforeStartReturned) {
            AndroidViewerPairing.releaseAttempt(lease);
            throw new IllegalStateException("Beluga saved-Mac connection unavailable");
        }
    }
    /** Only exact trusted session results can retire a process lease; exceptional completion cannot. */
    static boolean permitsProcessRelease(ViewerConnectionSession.Result result) {
        if (result == null || result.status == null || result.failure == null) return false;
        switch (result.status) {
            case ENDED: return result.failure == ViewerConnectionSession.Failure.NONE;
            case CANCELLED: return result.failure == ViewerConnectionSession.Failure.CANCELLED;
            case FAILED: return result.failure != ViewerConnectionSession.Failure.NONE
                    && result.failure != ViewerConnectionSession.Failure.CANCELLED;
            case CLEANUP_UNPROVEN: default: return false;
        }
    }
    private static final class ExistingStorage implements ViewerConnectionSession.Storage {
        private Context application;
        private final UUID hostID;
        private final long catalogRevision, selectionRevision;
        private AndroidViewerSecureStore store;
        private AndroidViewerSecureStore.Binding binding;
        private AndroidViewerSecureStore.ReconnectPeer peer;
        ExistingStorage(Context application, UUID hostID, long catalogRevision, long selectionRevision) {
            this.application = application; this.hostID = hostID;
            this.catalogRevision = catalogRevision; this.selectionRevision = selectionRevision;
        }
        ViewerConnectionSession.Storage prepare() throws Exception {
            if (store != null || application == null) throw new IllegalStateException();
            try { store = AndroidViewerSecureStore.openExisting(application); return this; }
            finally { application = null; }
        }
        @Override public void activate(Owner owner, Transport transport, NativeClose close) throws Exception {
            if (binding != null) throw new IllegalStateException();
            // bind is the atomic authority publication; subsequent fallible work belongs to locator().
            binding = store.bindSelectedReconnect(owner, transport, hostID, catalogRevision, selectionRevision, close);
        }
        @Override public ViewerAvailabilityLocator locator() throws Exception {
            peer = store.reconnectPeer(binding);
            return store.reconnectLocator(binding);
        }
        @Override public byte[] retainedActivation() throws Exception { return store.retainedReconnectActivation(binding); }
        @Override public Reserved reserve() throws Exception { return store.reserveSelectedReconnect(binding); }
        @Override public CompletionStage<Void> close() throws Exception { return store.closeReconnect(binding); }
        @Override public void verifyClosed(StoreStamp expected) throws Exception { store.verifyClosedReconnect(binding, expected); }
        @Override public void release() throws Exception { store.releaseRetiredReconnect(binding); peer = null; }
    }
}
