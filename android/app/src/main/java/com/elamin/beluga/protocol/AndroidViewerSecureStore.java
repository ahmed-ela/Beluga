package com.elamin.beluga.protocol;

import android.content.Context;
import android.os.Build;
import android.os.Process;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.system.ErrnoException;
import android.system.Os;
import android.system.OsConstants;
import android.system.StructStat;
import java.io.File;
import java.io.FileDescriptor;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.KeyStore;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Effect;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Owner;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.StoreStamp;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Transport;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.AuthFailure;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.PreparedViewer;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.RecordPhase;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.ReconnectPreparation;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.ViewerIdentity;
import com.elamin.beluga.protocol.ViewerStorageCatalog.Entry;
import com.elamin.beluga.protocol.ViewerStorageCatalog.Failure;

/**
 * PRIVATE secure storage requires API27; the separate preview may retain minSDK23.
 * No UI, permission request, transport, recovery/reset, or auto-enrollment.
 * One process owns mutations; its process-wide mutex covers ALL instances. This is not cross-process CAS.
 * Keystore AES material is non-exportable; the separately wrapped Ed25519 seed DOES enter JVM memory.
 */
final class AndroidViewerSecureStore {
    private static final Object SERIAL = new Object();
    private static final Map<String, Binding> OWNERS = new HashMap<>();
    private static final Set<String> UNCERTAIN = new HashSet<>();
    private static final String ALIAS = "com.elamin.beluga.viewer.storage.v1";
    private static final String DIRECTORY = "beluga-viewer-v1", FILE = "catalog.aead", INTENT = "publication.intent";
    private static final byte[] MAGIC = "BVS-AE1\0".getBytes(StandardCharsets.US_ASCII);
    private static final int MAXIMUM_CIPHERTEXT_BYTES = ViewerStorageCatalog.MAXIMUM_BYTES + 40;
    private final File directory, file, intent;
    private final byte[] aad;
    private final SecretKey key;
    private final StructStat directoryPin;

    static final class Mac {
        final UUID deviceID, pairID;
        final String displayName;
        final RecordPhase phase;
        private Mac(Entry entry) {
            deviceID = entry.record.hostDeviceID(); pairID = entry.record.pairID();
            displayName = entry.record.hostDisplayName(); phase = entry.record.phase();
        }
        @Override public String toString() { return "<saved Mac metadata; not connected>"; }
    }
    /** A local unbound reservation only. No authenticated host, invitation, or key is exposed. */
    static final class PendingEnrollment {
        final UUID slot;
        private PendingEnrollment(UUID slot) { this.slot = slot; }
        @Override public String toString() { return "<unbound enrollment slot; not an authenticated Mac>"; }
    }
    static final class Snapshot {
        final UUID viewerID, selectedMacID, selectedEnrollmentSlot;
        final long catalogRevision, selectionRevision;
        final List<Mac> macs;
        final List<PendingEnrollment> pendingEnrollments;
        private Snapshot(ViewerStorageCatalog catalog) throws Failure {
            viewerID = catalog.deviceID; catalogRevision = catalog.catalogRevision; selectionRevision = catalog.selectionRevision;
            List<Mac> rows = new ArrayList<>(); List<PendingEnrollment> pending = new ArrayList<>();
            UUID selected = null, selectedPending = null;
            for (Entry entry : catalog.entries()) {
                if (entry.record == null) {
                    pending.add(new PendingEnrollment(entry.slot));
                    if (entry.slot.equals(catalog.selectedSlot)) selectedPending = entry.slot;
                } else {
                    rows.add(new Mac(entry));
                    if (entry.slot.equals(catalog.selectedSlot)) selected = entry.record.hostDeviceID();
                }
            }
            selectedMacID = selected; selectedEnrollmentSlot = selectedPending;
            macs = java.util.Collections.unmodifiableList(rows);
            pendingEnrollments = java.util.Collections.unmodifiableList(pending);
        }
        /** Actual store mapping; pure host tests can inspect it without Android/Keystore calls. */
        static Snapshot fromCatalog(ViewerStorageCatalog catalog) throws Failure {
            ViewerStorageCatalog.demand(catalog != null); return new Snapshot(catalog);
        }
        @Override public String toString() { return "<saved catalog metadata; not pairing or connection proof>"; }
    }
    static final class Binding {
        private final AndroidViewerSecureStore store;
        private final Owner owner;
        private final Transport transport;
        private final UUID slot;
        private ViewerStorageCloseDrain closeDrain;
        private ViewerStorageCloseDrain.Receipt closeReceipt;
        private ViewerReconnectStorageLifecycle reconnect;
        private StoreStamp reconnectInitial;
        private ViewerReconnectStorageLifecycle.Reserved reconnectReserved;
        private ViewerReconnectStorageLifecycle.CloseReceipt reconnectCloseReceipt;
        private CompletableFuture<Void> reconnectCloseResult;
        private ReconnectPeer reconnectPeer;
        private Binding(AndroidViewerSecureStore store, Owner owner, Transport transport, UUID slot) {
            this.store = store; this.owner = owner; this.transport = transport; this.slot = slot;
        }
        ViewerStorageCloseDrain closeDrainForTrustedPorts() { return closeDrain; }
        @Override public String toString() { return "<redacted exact storage owner binding>"; }
    }
    /** Public identities pinned when the exact selected ACTIVE binding is acquired. */
    static final class ReconnectPeer {
        final UUID viewerID, hostID;
        private final byte[] viewerPublicKey, hostPublicKey;
        private ReconnectPeer(ViewerPairingAuthenticator.ViewerPairRecord record) {
            viewerID = record.viewerDeviceID(); hostID = record.hostDeviceID();
            viewerPublicKey = record.viewerSigningPublicKey(); hostPublicKey = record.hostSigningPublicKey();
        }
        byte[] copyViewerPublicKey() { return viewerPublicKey.clone(); }
        byte[] copyHostPublicKey() { return hostPublicKey.clone(); }
        @Override public String toString() { return "<selected Beluga media peer identity>"; }
    }
    static final class WriteResult {
        final StoreStamp before, after;
        final byte[] readback;
        private WriteResult(StoreStamp before, StoreStamp after, byte[] bytes) { this.before = before; this.after = after; readback = bytes.clone(); }
    }
    static final class AdmissionResult {
        final StoreStamp stamp;
        final long before, after;
        final byte[] invitation;
        private AdmissionResult(StoreStamp stamp, long before, long after, byte[] invitation) {
            this.stamp = stamp; this.before = before; this.after = after; this.invitation = invitation.clone();
        }
    }

    private AndroidViewerSecureStore(Context context, File directory, SecretKey key) throws Failure {
        this.directory = directory; file = new File(directory, FILE); intent = new File(directory, INTENT); this.key = key;
        String packageName = context.getPackageName();
        ViewerStorageCatalog.demand(packageName != null && packageName.length() <= 128
                && packageName.matches("[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)+"));
        aad = ("Beluga.Android.ViewerCatalog.AES-GCM.v1\0" + packageName).getBytes(StandardCharsets.US_ASCII);
        directoryPin = statDirectory(directory);
    }

    /** Does not create a key, directory, or replacement identity. Missing/ambiguous halves refuse. */
    static AndroidViewerSecureStore openExisting(Context context) throws Failure {
        requireSecurePlatform(); // BEFORE Context directory acquisition, KeyStore access, or filesystem use
        synchronized (SERIAL) {
            try {
                File directory = location(context);
                KeyStore keystore = keyStore();
                ViewerStorageCatalog.demand(!absent(directory) && keystore.containsAlias(ALIAS));
                java.security.Key candidate = keystore.getKey(ALIAS, null);
                ViewerStorageCatalog.demand(candidate instanceof SecretKey && "AES".equals(candidate.getAlgorithm()));
                AndroidViewerSecureStore store = new AndroidViewerSecureStore(context, directory, (SecretKey) candidate);
                Image current = store.load(); current.close(); return store;
            } catch (GeneralSecurityException | IOException | RuntimeException refused) { throw new Failure(); }
        }
    }

    /** Explicit first-use action, allowed ONLY when both the key and entire namespace are absent. */
    static AndroidViewerSecureStore enrollFirstUse(Context context) throws Failure {
        requireSecurePlatform(); // unsupported devices never begin enrollment/mint a replacement identity
        synchronized (SERIAL) {
            byte[] seed = new byte[32]; ViewerStorageCatalog catalog = null;
            File directory = location(context);
            boolean enrollmentStarted = false;
            try {
                KeyStore keystore = keyStore();
                ViewerStorageCatalog.demand(absent(directory) && !keystore.containsAlias(ALIAS));
                // The namespace is committed first. Interrupted enrollment is evidence, never automatic repair.
                enrollmentStarted = true;
                Os.mkdir(directory.getPath(), 0700); syncOwnedDirectory(directory.getParentFile());
                KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
                generator.init(new KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                        .setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                        .setRandomizedEncryptionRequired(true).setUserAuthenticationRequired(false).build());
                SecretKey key = generator.generateKey();
                new SecureRandom().nextBytes(seed);
                catalog = ViewerStorageCatalog.firstEnrollment(UUID.randomUUID(), seed);
                AndroidViewerSecureStore store = new AndroidViewerSecureStore(context, directory, key);
                store.publish(null, catalog, null);
                try (Image committed = store.load()) {
                    ViewerStorageCatalog.demand(committed.catalog.deviceID.equals(catalog.deviceID)
                            && Arrays.equals(committed.catalog.publicKey(), catalog.publicKey()));
                }
                return store;
            } catch (GeneralSecurityException | ErrnoException | IOException | RuntimeException refused) {
                if (enrollmentStarted) UNCERTAIN.add(directory.getPath()); throw new Failure();
            }
            catch (Failure refused) { if (enrollmentStarted) UNCERTAIN.add(directory.getPath()); throw refused; }
            finally { Arrays.fill(seed, (byte) 0); if (catalog != null) catalog.close(); }
        }
    }

    ViewerIdentity identity() throws Failure { synchronized (SERIAL) { try (Image image = load()) { return image.catalog.identity(); } } }
    PreparedViewer prepareViewer(byte[] invitationSecret, String displayName) throws Failure {
        synchronized (SERIAL) {
            byte[] seed = null, ephemeral = new byte[32], nonce = new byte[32];
            try (Image image = load()) {
                seed = image.catalog.seedForTrustedPreparation(); SecureRandom random = new SecureRandom();
                random.nextBytes(ephemeral); random.nextBytes(nonce);
                return ViewerPairingAuthenticator.prepare(image.catalog.deviceID, displayName, seed, invitationSecret, ephemeral, nonce);
            } catch (AuthFailure refused) { throw new Failure(); }
            finally { if (seed != null) Arrays.fill(seed, (byte) 0); Arrays.fill(ephemeral, (byte) 0); Arrays.fill(nonce, (byte) 0); }
        }
    }
    Snapshot snapshot() throws Failure { synchronized (SERIAL) { try (Image image = load()) { return Snapshot.fromCatalog(image.catalog); } } }
    StoreStamp beginNewMac(UUID opaqueSlot, byte[] invitationDigest, long catalogRevision, long selectionRevision) throws Failure {
        synchronized (SERIAL) {
            requireNoOwner();
            try (Image prior = load(); ViewerStorageCatalog next = prior.catalog.begin(opaqueSlot, invitationDigest, catalogRevision, selectionRevision)) {
                publish(prior, next, null);
                try (Image readback = load()) { return readback.catalog.stamp(opaqueSlot); }
            }
        }
    }
    void selectMac(UUID hostID, long catalogRevision, long selectionRevision) throws Failure {
        synchronized (SERIAL) {
            requireNoOwner();
            try (Image prior = load(); ViewerStorageCatalog next = prior.catalog.select(hostID, catalogRevision, selectionRevision)) { publish(prior, next, null); }
        }
    }
    void forgetMac(UUID hostID, long catalogRevision, long selectionRevision) throws Failure {
        synchronized (SERIAL) {
            requireNoOwner();
            try (Image prior = load(); ViewerStorageCatalog next = prior.catalog.forget(hostID, catalogRevision, selectionRevision)) { publish(prior, next, null); }
        }
    }
    void abandonEnrollment(UUID opaqueSlot, long catalogRevision, long selectionRevision) throws Failure {
        synchronized (SERIAL) {
            // A retired owner still blocks until explicit release has drained its pending IO.
            requireNoOwner();
            try (Image prior = load(); ViewerStorageCatalog next = prior.catalog.abandon(opaqueSlot, catalogRevision, selectionRevision)) { publish(prior, next, null); }
        }
    }
    Binding bindBootstrap(Owner exactOwner, Transport exactTransport, StoreStamp expected,
            ViewerBootstrapReducer.ClosePort trustedNativeClose) throws Failure {
        synchronized (SERIAL) {
            requireNoOwner(); ViewerStorageCatalog.demand(exactOwner != null && !exactOwner.isRetired()
                    && exactTransport != null && expected != null && trustedNativeClose != null);
            try (Image image = load()) {
                ViewerStorageCatalog.demand(expected.pairID == null && expected.same(image.catalog.stamp(expected.target))
                        && expected.target.equals(image.catalog.selectedSlot));
            }
            // Trusted composition passes the same Owner/Transport to reducer.bootstrap, which
            // verifies their relationship. A different transport cannot borrow this slot binding.
            Binding binding = new Binding(this, exactOwner, exactTransport, expected.target);
            binding.closeDrain = new ViewerStorageCloseDrain(exactOwner, exactTransport, trustedNativeClose,
                    receipt -> acknowledgeClosed(binding, receipt));
            // All IO/validation and close-path construction precede publication. Cancellation
            // shares this short owner fence; no owner monitor spans filesystem or delegate IO.
            synchronized (exactOwner) {
                ViewerStorageCatalog.demand(!exactOwner.isRetired());
                OWNERS.put(directory.getPath(), binding);
            }
            return binding;
        }
    }

    /**
     * Owns exactly the currently selected ACTIVE Mac, without changing selection or allocating
     * transport. The trusted future session must construct matching Owner/Transport and supply
     * an exact native-close adapter; a pure fixture adapter is not physical close evidence.
     */
    Binding bindSelectedReconnect(Owner exactOwner, Transport exactTransport, UUID exactHostID,
            long expectedCatalogRevision, long expectedSelectionRevision,
            ViewerReconnectStorageLifecycle.NativeClose trustedNativeClose) throws Failure {
        synchronized (SERIAL) {
            requireNoOwner(); ViewerStorageCatalog.demand(exactOwner != null && !exactOwner.isRetired()
                    && exactTransport != null && exactTransport.ownedBy(exactOwner)
                    && ViewerStorageCatalog.nonzero(exactHostID) && trustedNativeClose != null);
            try (Image image = load()) {
                ViewerStorageCatalog catalog = image.catalog;
                ViewerStorageCatalog.demand(catalog.catalogRevision == expectedCatalogRevision
                        && catalog.selectionRevision == expectedSelectionRevision && catalog.selectedSlot != null);
                Entry selected = catalog.entry(catalog.selectedSlot);
                ViewerStorageCatalog.demand(selected.record != null && selected.record.phase() == RecordPhase.ACTIVE
                        && selected.record.hostDeviceID().equals(exactHostID) && selected.admissionRevision == 1);
                StoreStamp initial = catalog.stamp(selected.slot);
                Binding binding = new Binding(this, exactOwner, exactTransport, selected.slot);
                binding.reconnectInitial = initial;
                binding.reconnect = new ViewerReconnectStorageLifecycle(exactOwner, exactTransport, initial, trustedNativeClose);
                binding.reconnectPeer = new ReconnectPeer(selected.record);
                synchronized (exactOwner) {
                    ViewerStorageCatalog.demand(!exactOwner.isRetired());
                    OWNERS.put(directory.getPath(), binding);
                }
                return binding;
            }
        }
    }

    /** Only before availability retirement; the parent retains this public, exact-record value. */
    ReconnectPeer reconnectPeer(Binding binding) throws Failure {
        synchronized (SERIAL) {
            requireReconnectBinding(binding);
            synchronized (binding.owner) {
                ViewerStorageCatalog.demand(!binding.owner.isRetired() && binding.reconnectPeer != null);
                return binding.reconnectPeer;
            }
        }
    }

    /** Derives viewer-only routing from the exact bound ACTIVE record; never exposes its root. */
    ViewerAvailabilityLocator reconnectLocator(Binding binding) throws Failure {
        synchronized (SERIAL) {
            requireReconnectBinding(binding);
            try (Image image = load()) {
                ViewerStorageCatalog.demand(binding.reconnectInitial.same(image.catalog.stamp(binding.slot))
                        && binding.slot.equals(image.catalog.selectedSlot));
                ViewerAvailabilityLocator locator = image.catalog.entry(binding.slot).record.availabilityLocator();
                synchronized (binding.owner) {
                    if (binding.owner.isRetired()) { locator.close(); throw new Failure(); }
                    return locator;
                }
            } catch (AuthFailure refused) { throw new Failure(); }
        }
    }

    /** Exact retained ACTIVE acknowledgement, before reserving the next reconnect counter. */
    byte[] retainedReconnectActivation(Binding binding) throws Failure {
        synchronized (SERIAL) {
            requireReconnectBinding(binding);
            try (Image image = load()) {
                ViewerStorageCatalog.demand(binding.reconnectInitial.same(image.catalog.stamp(binding.slot))
                        && binding.slot.equals(image.catalog.selectedSlot));
                Entry selected = image.catalog.entry(binding.slot);
                ViewerStorageCatalog.demand(selected.record.phase() == RecordPhase.ACTIVE
                        && selected.admissionRevision == 1);
                byte[] retained = selected.record.recoveryAction().unsentRetainedPayload();
                synchronized (binding.owner) {
                    if (retained == null || binding.owner.isRetired()) {
                        if (retained != null) Arrays.fill(retained, (byte) 0);
                        throw new Failure();
                    }
                    return retained;
                }
            }
        }
    }

    /** After exact close, re-read selection and complete committed record before reporting verification. */
    void verifyClosedReconnect(Binding binding, StoreStamp expected) throws Failure {
        synchronized (SERIAL) {
            ViewerStorageCatalog.demand(binding != null && binding.store == this
                    && OWNERS.get(directory.getPath()) == binding && binding.owner.isRetired()
                    && binding.reconnectCloseReceipt != null && expected != null
                    && binding.slot.equals(expected.target) && binding.reconnectReserved != null
                    && binding.reconnectReserved.afterStamp().same(expected));
            try (Image image = load()) {
                ViewerStorageCatalog.demand(binding.slot.equals(image.catalog.selectedSlot)
                        && expected.same(image.catalog.stamp(binding.slot))
                        && image.catalog.admissionRevision(binding.slot) == 1);
            }
        }
    }

    /** Native encrypted +1 publication/readback. No admitted request escapes on uncertainty/cancel. */
    ViewerReconnectStorageLifecycle.Reserved reserveSelectedReconnect(Binding binding) throws Failure {
        synchronized (SERIAL) {
            requireReconnectBinding(binding);
            ReconnectPreparation preparation = null;
            byte[] ephemeral = new byte[32], nonce = new byte[32];
            try {
                ViewerReconnectStorageLifecycle.Reserved result;
                try (Image prior = load()) {
                    ViewerStorageCatalog.demand(binding.reconnectInitial.same(prior.catalog.stamp(binding.slot))
                            && binding.slot.equals(prior.catalog.selectedSlot));
                    Entry selected = prior.catalog.entry(binding.slot);
                    ViewerStorageCatalog.demand(selected.record != null && selected.record.phase() == RecordPhase.ACTIVE
                            && selected.admissionRevision == 1);
                    SecureRandom random = new SecureRandom(); random.nextBytes(ephemeral); random.nextBytes(nonce);
                    preparation = selected.record.prepareReconnect(prior.catalog.identity(), ephemeral, nonce);
                    result = binding.reconnect.reserve(prior.catalog, preparation, new ViewerReconnectStorageLifecycle.Publication() {
                        @Override public void publish(ViewerStorageCatalog exactNext) throws Failure {
                            requireReconnectBinding(binding);
                            AndroidViewerSecureStore.this.publish(prior, exactNext, binding);
                        }
                        @Override public byte[] readbackCatalog() throws Failure {
                            requireReconnectBinding(binding);
                            try (Image actual = load()) { return actual.catalog.encode(); }
                            catch (Failure | RuntimeException corrupt) {
                                UNCERTAIN.add(directory.getPath()); throw new Failure();
                            }
                        }
                    });
                }
                // SERIAL excludes selection/catalog successors. This final short owner fence
                // prevents a cancelled publication from yielding usable request authority.
                synchronized (binding.owner) {
                    requireReconnectBinding(binding); binding.reconnectReserved = result; return result;
                }
            } catch (Failure | AuthFailure | RuntimeException refused) {
                binding.owner.retire(); if (preparation != null) preparation.close();
                if (binding.reconnect.readbackDiscrepancyForStore()) UNCERTAIN.add(directory.getPath());
                throw new Failure();
            } finally { Arrays.fill(ephemeral, (byte) 0); Arrays.fill(nonce, (byte) 0); }
        }
    }

    /**
     * Retires immediately; external native work/continuations never run under SERIAL. Storage
     * drainage may await already-begun OS IO; no bounded native shutdown is claimed here.
     */
    CompletionStage<Void> closeReconnect(Binding binding) throws Failure {
        ViewerStorageCatalog.demand(binding != null && binding.store == this && binding.reconnect != null);
        binding.owner.retire();
        CompletableFuture<Void> completion; boolean begin;
        synchronized (SERIAL) {
            ViewerStorageCatalog.demand(OWNERS.get(directory.getPath()) == binding);
            begin = binding.reconnectCloseResult == null;
            if (begin) binding.reconnectCloseResult = new CompletableFuture<>();
            completion = binding.reconnectCloseResult;
        }
        if (begin) {
            try {
                binding.reconnect.retireAndClose().whenComplete((receipt, error) -> {
                    if (error != null) { completion.completeExceptionally(new Failure()); return; }
                    try { acknowledgeReconnectClosed(binding, receipt); }
                    catch (Failure | RuntimeException refused) { completion.completeExceptionally(new Failure()); return; }
                    completion.complete(null);
                });
            } catch (RuntimeException refused) { completion.completeExceptionally(new Failure()); }
        }
        return completion.thenApply(value -> value);
    }
    private void acknowledgeReconnectClosed(Binding binding, ViewerReconnectStorageLifecycle.CloseReceipt receipt) throws Failure {
        synchronized (SERIAL) {
            // Acquiring SERIAL drains every already-begun publication before a successor can start.
            ViewerStorageCatalog.demand(binding != null && binding.store == this && OWNERS.get(directory.getPath()) == binding
                    && binding.reconnect != null && binding.owner.isRetired() && binding.reconnectCloseReceipt == null
                    && receipt != null && receipt.belongsTo(binding.reconnect));
            binding.reconnectCloseReceipt = receipt;
        }
    }
    void releaseRetiredReconnect(Binding binding) throws Failure {
        synchronized (SERIAL) {
            ViewerStorageCatalog.demand(binding != null && binding.store == this && OWNERS.get(directory.getPath()) == binding
                    && binding.reconnect != null && binding.owner.isRetired() && binding.reconnectCloseReceipt != null
                    && binding.reconnectCloseReceipt.belongsTo(binding.reconnect));
            OWNERS.remove(directory.getPath());
        }
    }
    private void requireReconnectBinding(Binding binding) throws Failure {
        ViewerStorageCatalog.demand(binding != null && binding.store == this && OWNERS.get(directory.getPath()) == binding
                && binding.reconnect != null && binding.reconnectInitial != null && !binding.owner.isRetired());
    }
    /** Selection/forget stay blocked until explicit release of this EXACT retired owner. */
    void releaseRetiredBootstrap(Binding binding) throws Failure {
        synchronized (SERIAL) {
            ViewerStorageCatalog.demand(binding != null && binding.store == this && OWNERS.get(directory.getPath()) == binding
                    && binding.reconnect == null && binding.owner.isRetired() && binding.closeReceipt != null
                    && binding.closeReceipt.belongsTo(binding.closeDrain, binding.owner, binding.transport));
            OWNERS.remove(directory.getPath());
        }
    }
    void acknowledgeClosed(Binding binding, ViewerStorageCloseDrain.Receipt receipt) throws Failure {
        synchronized (SERIAL) {
            // This acquisition also drains any already-begun publication before successor admission.
            ViewerStorageCatalog.demand(binding != null && binding.store == this && OWNERS.get(directory.getPath()) == binding
                    && binding.closeDrain != null && binding.closeReceipt == null && receipt != null
                    && receipt.belongsTo(binding.closeDrain, binding.owner, binding.transport));
            binding.closeReceipt = receipt;
        }
    }
    WriteResult write(Binding binding, Effect effect) throws Failure {
        synchronized (SERIAL) {
            requireBinding(binding, effect);
            ViewerStorageCatalog.demand(effect.kind == ViewerBootstrapReducer.Kind.WRITE_PENDING
                    || effect.kind == ViewerBootstrapReducer.Kind.WRITE_ACCEPTED || effect.kind == ViewerBootstrapReducer.Kind.WRITE_ACTIVE);
            byte[] bytes = effect.exactBytesForTrustedPort();
            try (Image prior = load(); ViewerStorageCatalog next = prior.catalog.write(effect.expectedStoreForTrustedPort(), bytes)) {
                ViewerStorageCatalog.demand(Arrays.equals(prior.catalog.entry(binding.slot).invitation(), effect.invitationForTrustedPort())
                        && Arrays.equals(ViewerStorageCatalog.sha256(bytes), effect.exactDigestForTrustedPort())
                        && ((effect.kind == ViewerBootstrapReducer.Kind.WRITE_PENDING && next.entry(binding.slot).record.phase() == RecordPhase.PENDING)
                            || (effect.kind == ViewerBootstrapReducer.Kind.WRITE_ACCEPTED && next.entry(binding.slot).record.phase() == RecordPhase.ACCEPTED_ISSUED)
                            || (effect.kind == ViewerBootstrapReducer.Kind.WRITE_ACTIVE && next.entry(binding.slot).record.phase() == RecordPhase.ACTIVE)));
                publish(prior, next, binding);
                try (Image readback = load()) {
                    byte[] actual = readback.catalog.entry(binding.slot).bytes();
                    ViewerStorageCatalog.demand(Arrays.equals(bytes, actual));
                    return new WriteResult(prior.catalog.stamp(binding.slot), readback.catalog.stamp(binding.slot), actual);
                }
            } finally { if (bytes != null) Arrays.fill(bytes, (byte) 0); }
        }
    }
    AdmissionResult admit(Binding binding, Effect effect) throws Failure {
        synchronized (SERIAL) {
            requireBinding(binding, effect); ViewerStorageCatalog.demand(effect.kind == ViewerBootstrapReducer.Kind.ADMISSION);
            long before = effect.expectedAdmissionRevisionForTrustedPort(); byte[] invitation = effect.invitationForTrustedPort();
            try (Image prior = load(); ViewerStorageCatalog next = prior.catalog.admit(effect.expectedStoreForTrustedPort(), before, invitation)) {
                publish(prior, next, binding);
                try (Image readback = load()) {
                    ViewerStorageCatalog.demand(effect.expectedStoreForTrustedPort().same(readback.catalog.stamp(binding.slot))
                            && readback.catalog.admissionRevision(binding.slot) == before + 1);
                    return new AdmissionResult(readback.catalog.stamp(binding.slot), before, before + 1, invitation);
                }
            }
        }
    }
    void verifyCleanup(Binding binding, Effect effect) throws Failure {
        synchronized (SERIAL) {
            requireBinding(binding, effect); ViewerStorageCatalog.demand(effect.kind == ViewerBootstrapReducer.Kind.CLEANUP);
            try (Image image = load()) { ViewerStorageCatalog.demand(effect.expectedStoreForTrustedPort().same(image.catalog.stamp(binding.slot))
                    && image.catalog.entry(binding.slot).record.phase() == RecordPhase.ACTIVE
                    && Arrays.equals(image.catalog.entry(binding.slot).invitation(), effect.invitationForTrustedPort())); }
        }
    }
    private void requireBinding(Binding binding, Effect effect) throws Failure {
            ViewerStorageCatalog.demand(binding != null && binding.store == this && OWNERS.get(directory.getPath()) == binding
                && binding.reconnect == null && !binding.owner.isRetired() && effect != null && !effect.ownerRetiredForTrustedPort()
                && effect.exactTransportForTrustedPort() == binding.transport
                && effect.expectedStoreForTrustedPort().target.equals(binding.slot));
    }
    private void requireNoOwner() throws Failure { ViewerStorageCatalog.demand(!OWNERS.containsKey(directory.getPath())); }

    private Image load() throws Failure {
        ViewerStorageCatalog.demand(!UNCERTAIN.contains(directory.getPath()) && absent(intent)); revalidateDirectory();
        byte[] encrypted = readCiphertext(), plain = null;
        try { plain = decrypt(encrypted); return new Image(encrypted, ViewerStorageCatalog.decode(plain)); }
        catch (Failure refused) { Arrays.fill(encrypted, (byte) 0); throw refused; }
        finally { if (plain != null) Arrays.fill(plain, (byte) 0); }
    }
    private static final class Image implements AutoCloseable {
        final byte[] encrypted;
        final ViewerStorageCatalog catalog;
        Image(byte[] encrypted, ViewerStorageCatalog catalog) { this.encrypted = encrypted; this.catalog = catalog; }
        @Override public void close() { Arrays.fill(encrypted, (byte) 0); catalog.close(); }
    }
    private byte[] encrypt(byte[] plain) throws Failure {
        try {
            ViewerStorageCatalog.demand(plain.length <= ViewerStorageCatalog.MAXIMUM_BYTES);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, key); cipher.updateAAD(aad);
            byte[] iv = cipher.getIV(), ciphertext = cipher.doFinal(plain);
            ViewerStorageCatalog.demand(iv != null && iv.length == 12 && ciphertext.length == plain.length + 16);
            return ByteBuffer.allocate(MAGIC.length + 12 + 4 + ciphertext.length).put(MAGIC).put(iv).putInt(ciphertext.length).put(ciphertext).array();
        } catch (GeneralSecurityException | RuntimeException refused) { throw new Failure(); }
    }
    private byte[] decrypt(byte[] encrypted) throws Failure {
        try {
            ViewerStorageCatalog.demand(encrypted.length <= MAXIMUM_CIPHERTEXT_BYTES && encrypted.length > MAGIC.length + 12 + 4 + 16);
            ByteBuffer in = ByteBuffer.wrap(encrypted); byte[] magic = new byte[MAGIC.length], iv = new byte[12]; in.get(magic).get(iv);
            int length = in.getInt(); ViewerStorageCatalog.demand(Arrays.equals(magic, MAGIC) && length == in.remaining() && length > 16);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(128, iv)); cipher.updateAAD(aad);
            // Do not expose update() output. Plaintext is returned only after authenticated doFinal.
            return cipher.doFinal(encrypted, in.position(), length);
        } catch (GeneralSecurityException | RuntimeException refused) { throw new Failure(); }
    }
    private void publish(Image predecessor, ViewerStorageCatalog next, Binding binding) throws Failure {
        byte[] plain = next.encode(), encrypted = null;
        try {
            encrypted = encrypt(plain);
            CheckedCatalogPublication.publish(new OsPublication(predecessor, binding, plain), encrypted, MAXIMUM_CIPHERTEXT_BYTES);
        } catch (Failure | RuntimeException refused) { UNCERTAIN.add(directory.getPath()); throw new Failure(); }
        finally { Arrays.fill(plain, (byte) 0); if (encrypted != null) Arrays.fill(encrypted, (byte) 0); }
    }
    private final class OsPublication implements CheckedCatalogPublication.Boundary {
        private final Image predecessor;
        private final Binding binding;
        private final byte[] expectedPlain; // borrowed for this synchronous call only
        private final File temporary = new File(directory, "catalog-" + UUID.randomUUID() + ".pending");
        private FileDescriptor writer, parent;
        private StructStat writtenPin, intentPin;
        private byte[] expectedIntent;
        OsPublication(Image predecessor, Binding binding, byte[] plain) { this.predecessor = predecessor; this.binding = binding; expectedPlain = plain; }
        @Override public void createAndSyncIntent(byte[] encrypted) throws Failure {
            FileDescriptor descriptor = null;
            try {
                revalidateDirectory(); parent = openChecked(directory.getPath(), OsConstants.O_RDONLY | OsConstants.O_NOFOLLOW | OsConstants.O_NONBLOCK, 0);
                ViewerStorageCatalog.demand(sameNode(directoryPin, Os.fstat(parent)));
                // Fixed44 bytes: magic/version + ciphertext byte count + SHA256. No seed/root/code.
                expectedIntent = ByteBuffer.allocate(44).put("BVS-INT1".getBytes(StandardCharsets.US_ASCII))
                        .putInt(encrypted.length).put(ViewerStorageCatalog.sha256(encrypted)).array();
                descriptor = openChecked(intent.getPath(), OsConstants.O_WRONLY | OsConstants.O_CREAT | OsConstants.O_EXCL | OsConstants.O_NOFOLLOW, 0600);
                validFile(Os.fstat(descriptor), expectedIntent.length, false);
                int offset = 0;
                while (offset < expectedIntent.length) {
                    int count = Os.write(descriptor, expectedIntent, offset, expectedIntent.length - offset);
                    ViewerStorageCatalog.demand(count > 0); offset += count;
                }
                Os.fsync(descriptor); intentPin = Os.fstat(descriptor);
                validFile(intentPin, expectedIntent.length, true); ViewerStorageCatalog.demand(intentPin.st_size == expectedIntent.length);
                FileDescriptor owned = descriptor; descriptor = null; Os.close(owned);
                Os.fsync(parent); revalidateDirectory(); validateIntent();
            } catch (ErrnoException | java.io.InterruptedIOException refused) { throw new Failure(); }
            finally { closeQuietly(descriptor); }
        }
        @Override public void writeExclusive(byte[] encrypted) throws Failure {
            try {
                revalidateDirectory(); validateIntent();
                writer = openChecked(temporary.getPath(), OsConstants.O_WRONLY | OsConstants.O_CREAT | OsConstants.O_EXCL | OsConstants.O_NOFOLLOW, 0600);
                validFile(Os.fstat(writer), encrypted.length, false);
                int offset = 0;
                while (offset < encrypted.length) { int count = Os.write(writer, encrypted, offset, encrypted.length - offset); ViewerStorageCatalog.demand(count > 0); offset += count; }
                writtenPin = Os.fstat(writer); validFile(writtenPin, encrypted.length, true);
                ViewerStorageCatalog.demand(writtenPin.st_size == encrypted.length
                        && sameNode(writtenPin, Os.lstat(temporary.getPath())));
            } catch (ErrnoException | java.io.InterruptedIOException refused) { throw new Failure(); }
        }
        @Override public void syncAndCloseFile() throws Failure {
            try { Os.fsync(writer); FileDescriptor owned = writer; writer = null; Os.close(owned); }
            catch (ErrnoException refused) { throw new Failure(); }
        }
        @Override public void recheckPredecessorAndOwner() throws Failure {
            revalidateDirectory(); validateIntent();
            try {
                StructStat named = Os.lstat(temporary.getPath());
                ViewerStorageCatalog.demand(writtenPin != null && sameNode(writtenPin, named)
                        && named.st_size == writtenPin.st_size && named.st_mtime == writtenPin.st_mtime
                        && named.st_ctime == writtenPin.st_ctime);
            } catch (ErrnoException refused) { throw new Failure(); }
            ViewerStorageCatalog.demand(binding == null || (OWNERS.get(directory.getPath()) == binding && !binding.owner.isRetired()));
            if (predecessor == null) ViewerStorageCatalog.demand(absent(file));
            else { byte[] current = readCiphertext(); try { ViewerStorageCatalog.demand(Arrays.equals(predecessor.encrypted, current)); } finally { Arrays.fill(current, (byte) 0); } }
        }
        @Override public void rename() throws Failure {
            // Retirement may race after this check. The retained SERIAL+Binding prevents any
            // successor selection/release from overtaking this already-begun publication;
            // the unchanged reducer ignores its late callbacks. No owner monitor is held over IO.
            ViewerStorageCatalog.demand(binding == null || (OWNERS.get(directory.getPath()) == binding && !binding.owner.isRetired()));
            try { Os.rename(temporary.getPath(), file.getPath()); }
            catch (ErrnoException refused) { throw new Failure(); }
        }
        @Override public void syncDirectory() throws Failure {
            try {
                ViewerStorageCatalog.demand(sameNode(directoryPin, Os.fstat(parent))); Os.fsync(parent); revalidateDirectory();
            }
            catch (ErrnoException refused) { throw new Failure(); }
        }
        @Override public byte[] boundedReadback() throws Failure { return readCiphertext(); }
        @Override public void verifyDecryptedReadback(byte[] encrypted) throws Failure {
            byte[] actual = decrypt(encrypted);
            try { ViewerStorageCatalog.demand(Arrays.equals(expectedPlain, actual)); }
            finally { Arrays.fill(actual, (byte) 0); }
        }
        @Override public void clearAndSyncIntent() throws Failure {
            validateIntent(); revalidateDirectory();
            try {
                // Unlink is authorized only after file+directory sync and decrypted exact readback.
                // A failed final directory sync is still an error, never continuation authority.
                // Power loss may restore the intent (blocks) OR leave it absent: the catalog's
                // data publication had already completed before this cleanup began.
                StructStat named = Os.lstat(intent.getPath()); validFile(named, 44, true);
                ViewerStorageCatalog.demand(sameNode(intentPin, named) && named.st_size == 44);
                // Public remove is called ONLY for our exact validated regular intent; never a
                // directory/recursive fallback. Existing same-UID race limitations still apply.
                Os.remove(intent.getPath()); Os.fsync(parent); revalidateDirectory();
                FileDescriptor owned = parent; parent = null; Os.close(owned);
            } catch (ErrnoException refused) { throw new Failure(); }
        }
        private void validateIntent() throws Failure {
            try { ViewerStorageCatalog.demand(intentPin != null && sameNode(intentPin, Os.lstat(intent.getPath()))); }
            catch (ErrnoException refused) { throw new Failure(); }
            byte[] actual = readPrivateFile(intent, 44);
            try { ViewerStorageCatalog.demand(Arrays.equals(expectedIntent, actual)); }
            finally { Arrays.fill(actual, (byte) 0); }
        }
        @Override public void closeOwnedDescriptors() {
            closeQuietly(writer); writer = null; closeQuietly(parent); parent = null;
            if (expectedIntent != null) Arrays.fill(expectedIntent, (byte) 0);
        }
    }
    private byte[] readCiphertext() throws Failure { return readPrivateFile(file, MAXIMUM_CIPHERTEXT_BYTES); }
    private byte[] readPrivateFile(File path, int maximum) throws Failure {
        FileDescriptor descriptor = null;
        try {
            revalidateDirectory(); StructStat named = Os.lstat(path.getPath()); validFile(named, maximum, true);
            descriptor = openChecked(path.getPath(), OsConstants.O_RDONLY | OsConstants.O_NOFOLLOW | OsConstants.O_NONBLOCK, 0);
            StructStat before = Os.fstat(descriptor); validFile(before, maximum, true);
            ViewerStorageCatalog.demand(sameNode(named, before) && before.st_size == named.st_size);
            // Size is checked on the held regular FD BEFORE allocation or crypto.
            byte[] result = new byte[(int) before.st_size]; int offset = 0;
            while (offset < result.length) { int count = Os.read(descriptor, result, offset, result.length - offset); ViewerStorageCatalog.demand(count > 0); offset += count; }
            byte[] extra = new byte[1]; ViewerStorageCatalog.demand(Os.read(descriptor, extra, 0, 1) == 0);
            StructStat after = Os.fstat(descriptor), namedAfter = Os.lstat(path.getPath());
            ViewerStorageCatalog.demand(sameNode(before, after) && sameNode(after, namedAfter)
                    && before.st_size == after.st_size && after.st_size == namedAfter.st_size
                    && before.st_mtime == after.st_mtime && before.st_ctime == after.st_ctime);
            revalidateDirectory(); FileDescriptor owned = descriptor; descriptor = null; Os.close(owned); return result;
        } catch (ErrnoException | java.io.InterruptedIOException refused) { throw new Failure(); }
        finally { closeQuietly(descriptor); }
    }
    private void revalidateDirectory() throws Failure { ViewerStorageCatalog.demand(sameNode(directoryPin, statDirectory(directory))); }
    private static StructStat statDirectory(File directory) throws Failure {
        try {
            ViewerStorageCatalog.demand(directory.getPath().equals(directory.getCanonicalPath()));
            StructStat stat = Os.lstat(directory.getPath());
            ViewerStorageCatalog.demand(OsConstants.S_ISDIR(stat.st_mode) && stat.st_uid == Process.myUid() && (stat.st_mode & 07777) == 0700);
            return stat;
        } catch (ErrnoException | IOException refused) { throw new Failure(); }
    }
    private static void validFile(StructStat stat, int maximum, boolean nonempty) throws Failure {
        ViewerStorageCatalog.demand(OsConstants.S_ISREG(stat.st_mode) && stat.st_uid == Process.myUid()
                && (stat.st_mode & 07777) == 0600 && stat.st_nlink == 1 && stat.st_size >= (nonempty ? 1 : 0) && stat.st_size <= maximum);
    }
    private static boolean sameNode(StructStat a, StructStat b) {
        return a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_uid == b.st_uid && a.st_mode == b.st_mode && a.st_nlink == b.st_nlink;
    }
    private static void syncOwnedDirectory(File directory) throws Failure {
        FileDescriptor descriptor = null;
        try {
            // noBackupFilesDir belongs to the app; its exact mode can be platform-managed, not forced.
            StructStat named = Os.lstat(directory.getPath()); ViewerStorageCatalog.demand(OsConstants.S_ISDIR(named.st_mode) && named.st_uid == Process.myUid());
            descriptor = openChecked(directory.getPath(), OsConstants.O_RDONLY | OsConstants.O_NOFOLLOW | OsConstants.O_NONBLOCK, 0);
            ViewerStorageCatalog.demand(sameNode(named, Os.fstat(descriptor))); Os.fsync(descriptor);
            FileDescriptor owned = descriptor; descriptor = null; Os.close(owned);
        } catch (ErrnoException refused) { throw new Failure(); }
        finally { closeQuietly(descriptor); }
    }
    /** Pure production admission policy; callers cannot supply the actual platform value to enrollment. */
    static boolean supportsSecureStorage(int platformAPI) { return platformAPI >= 27; }
    private static void requireSecurePlatform() throws Failure {
        ViewerStorageCatalog.demand(supportsSecureStorage(Build.VERSION.SDK_INT));
    }
    private static FileDescriptor openChecked(String path, int flags, int mode) throws ErrnoException, Failure {
        requireSecurePlatform();
        // Explicit platform guard keeps this public API27 field unreachable on23-26. No
        // numeric hidden flag, reflective method, or API30 fcntlInt fallback is used.
        if (Build.VERSION.SDK_INT >= 27) return Os.open(path, flags | OsConstants.O_CLOEXEC, mode);
        throw new Failure();
    }
    private static File location(Context context) throws Failure {
        ViewerStorageCatalog.demand(context != null);
        ViewerStorageCatalog.demand(Build.VERSION.SDK_INT < 24 || !context.isDeviceProtectedStorage());
        try {
            File base = context.getNoBackupFilesDir(); ViewerStorageCatalog.demand(base != null);
            return new File(base.getCanonicalFile(), DIRECTORY);
        }
        catch (IOException refused) { throw new Failure(); }
    }
    private static KeyStore keyStore() throws GeneralSecurityException, IOException {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore"); store.load(null); return store;
    }
    private static boolean absent(File path) throws Failure {
        try { Os.lstat(path.getPath()); return false; }
        catch (ErrnoException refused) { if (refused.errno == OsConstants.ENOENT) return true; throw new Failure(); }
    }
    private static void closeQuietly(FileDescriptor descriptor) {
        if (descriptor != null) try { Os.close(descriptor); } catch (ErrnoException ignored) { /* no continuation authority */ }
    }
}
