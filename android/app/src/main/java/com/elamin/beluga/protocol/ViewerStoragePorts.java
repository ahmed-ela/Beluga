package com.elamin.beluga.protocol;

import java.util.Arrays;
import com.elamin.beluga.protocol.AndroidViewerSecureStore.AdmissionResult;
import com.elamin.beluga.protocol.AndroidViewerSecureStore.Binding;
import com.elamin.beluga.protocol.AndroidViewerSecureStore.WriteResult;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.AdmissionCallback;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.AdmissionObservation;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Cleaned;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.CloseCallback;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.CloseObservation;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.ClosePort;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Closed;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.CleanupCallback;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.CleanupObservation;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Effect;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Owner;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.StoreStamp;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Transport;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.WriteCallback;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.WriteObservation;
import com.elamin.beluga.protocol.ViewerStorageCatalog.Failure;

/** Trusted composition only; package visibility is not authentication against same-process code. */
final class ViewerStoragePorts implements ViewerPairingSession.Storage {
    private final AndroidViewerSecureStore store;
    private final Owner owner;
    private final Transport transport;
    private final StoreStamp initial;
    private final ClosePort nativeClose;
    private boolean activationStarted;
    private Binding binding;
    private ViewerStorageCloseDrain closeDrain;

    /** Pure preparation: reducer.bootstrap must validate this composition before activate. */
    ViewerStoragePorts(AndroidViewerSecureStore store, Owner exactOwner, Transport exactTransport, StoreStamp initial,
            ClosePort trustedNativeClose) throws Failure {
        ViewerStorageCatalog.demand(store != null && exactOwner != null && exactTransport != null
                && initial != null && trustedNativeClose != null);
        this.store = store; owner = exactOwner; transport = exactTransport;
        this.initial = initial; nativeClose = trustedNativeClose;
    }
    /** One-shot; no socket/effect may begin before this returns normally. */
    @Override public synchronized void activate() throws Failure {
        ViewerStorageCatalog.demand(!activationStarted);
        activationStarted = true;
        Binding installed = store.bindBootstrap(owner, transport, initial, nativeClose);
        binding = installed;
        closeDrain = installed.closeDrainForTrustedPorts();
    }
    private synchronized Binding activeBinding() throws Failure {
        ViewerStorageCatalog.demand(binding != null && closeDrain != null);
        return binding;
    }
    private synchronized ViewerStorageCloseDrain activeCloseDrain() throws Failure {
        ViewerStorageCatalog.demand(binding != null && closeDrain != null);
        return closeDrain;
    }
    @Override public void persist(Effect exactWrite, WriteCallback callback) {
        WriteResult result;
        try { result = store.write(activeBinding(), exactWrite); }
        catch (Failure | RuntimeException refused) { callback.failed(); return; }
        // store.write has returned: no storage lock/owned I/O section is held across reducer callbacks.
        try { callback.committed(new WriteObservation(exactWrite, this, result.before, result.after, result.readback)); }
        finally { Arrays.fill(result.readback, (byte) 0); }
    }
    @Override public void persist(Effect exactAdmission, AdmissionCallback callback) {
        AdmissionResult result;
        try { result = store.admit(activeBinding(), exactAdmission); }
        catch (Failure | RuntimeException refused) { callback.failed(); return; }
        callback.committed(new AdmissionObservation(exactAdmission, this, result.stamp, result.before, result.after, result.invitation));
    }
    @Override public void clean(Effect exactCleanup, CleanupCallback callback) {
        try { store.verifyCleanup(activeBinding(), exactCleanup); }
        catch (Failure | RuntimeException refused) { callback.failed(); return; }
        // This adapter never owned the scanner/UI raw code. It cannot claim that code was erased.
        // Retain bounded admission/fingerprint evidence; reducer accepts this conservative outcome.
        callback.completed(new CleanupObservation(exactCleanup, this, exactCleanup.expectedStoreForTrustedPort(),
                exactCleanup.invitationForTrustedPort(), Cleaned.RETAINED));
    }
    @Override public void close(Effect exactClose, CloseCallback callback) {
        if (callback == null) return;
        ViewerStorageCloseDrain drain;
        try { drain = activeCloseDrain(); }
        catch (Failure refused) { return; }
        // The wrapped delegate must finish/join its actual captured transport. This class does
        // not implement sockets or treat a requested close as a completed close.
        drain.close(exactClose, observation -> callback.completed(new CloseObservation(exactClose, this,
                exactClose.exactTransportForTrustedPort(), Closed.FINISHED)));
    }
    void releaseAfterOwnerRetirement() throws Failure { store.releaseRetiredBootstrap(activeBinding()); }
    @Override public void release() throws Failure { releaseAfterOwnerRetirement(); }
}
