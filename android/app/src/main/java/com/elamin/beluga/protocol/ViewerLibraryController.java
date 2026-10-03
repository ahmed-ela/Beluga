package com.elamin.beluga.protocol;

import android.content.Context;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.atomic.AtomicBoolean;

/** Foreground library and explicit pairing orchestration; saved rows are not connection proof. */
public final class ViewerLibraryController implements AutoCloseable {
    public enum Status { INACTIVE, UNSUPPORTED, LOADING, READY, WORKING, UNAVAILABLE, CLOSED }
    public enum Phase { PENDING, ACCEPTED_ISSUED, ACTIVE }
    public enum PairingStatus { IDLE, PAIRING, CANCELLING, PAIRED, CANCELLED, FAILED, CLEANUP_UNPROVEN, BLOCKED }
    public interface Listener { void onState(State state); }

    public static final class Mac {
        public final UUID deviceID, pairID;
        public final String displayName;
        public final Phase phase;
        Mac(UUID deviceID, UUID pairID, String displayName, Phase phase) {
            this.deviceID = nonzero(deviceID); this.pairID = nonzero(pairID);
            this.displayName = displayName; this.phase = java.util.Objects.requireNonNull(phase);
        }
        @Override public String toString() { return "<saved Mac metadata; not connected>"; }
    }
    public static final class PendingEnrollment {
        public final UUID slot;
        PendingEnrollment(UUID slot) { this.slot = nonzero(slot); }
        @Override public String toString() { return "<unbound enrollment; not paired>"; }
    }
    public static final class State {
        public final Status status;
        public final PairingStatus pairingStatus;
        public final UUID viewerID, selectedMacID, selectedEnrollmentSlot;
        public final List<Mac> macs;
        public final List<PendingEnrollment> pendingEnrollments;
        private final Data data;
        private State(Status status, Data data, PairingStatus pairingStatus) {
            this.status = status; this.data = data; this.pairingStatus = pairingStatus;
            viewerID = data == null ? null : data.viewerID;
            selectedMacID = data == null ? null : data.selectedMacID;
            selectedEnrollmentSlot = data == null ? null : data.selectedEnrollmentSlot;
            macs = data == null ? Collections.emptyList() : data.macs;
            pendingEnrollments = data == null ? Collections.emptyList() : data.pending;
        }
        public boolean canInitialize() { return status == Status.UNAVAILABLE && !pairingBlocksActions(); }
        public boolean canChangeLibrary() { return status == Status.READY && !pairingBlocksActions(); }
        public boolean canPair() { return canChangeLibrary() && macs.size() + pendingEnrollments.size() < 32; }
        public boolean canCancelPairing() { return pairingStatus == PairingStatus.PAIRING; }
        private boolean pairingBlocksActions() {
            return pairingStatus == PairingStatus.PAIRING || pairingStatus == PairingStatus.CANCELLING
                    || pairingStatus == PairingStatus.CLEANUP_UNPROVEN || pairingStatus == PairingStatus.BLOCKED;
        }
        @Override public String toString() { return "<Beluga library state; not connection proof>"; }
    }

    interface StoragePort {
        Data load() throws Exception;
        Data initialize() throws Exception;
        Data select(UUID host, long catalog, long selection) throws Exception;
        Data forget(UUID host, long catalog, long selection) throws Exception;
        Data abandon(UUID slot, long catalog, long selection) throws Exception;
    }
    interface SerialPort { void execute(Runnable work); void close(); }
    interface MainPort { void checkOwner(); void execute(Runnable work); }
    // Trusted composition: terminal status is projected from the real facade, not UI input.
    interface PairingPort {
        boolean isAttemptInFlight();
        PairingAttempt start(PairingInvitation invitation, long catalog, long selection);
    }
    interface PairingAttempt {
        void cancel();
        CompletionStage<PairingStatus> completion();
    }
    static final class Data {
        final UUID viewerID, selectedMacID, selectedEnrollmentSlot;
        final long catalogRevision, selectionRevision;
        final List<Mac> macs;
        final List<PendingEnrollment> pending;
        Data(UUID viewerID, long catalog, long selection, UUID selectedMac, UUID selectedSlot,
                List<Mac> macs, List<PendingEnrollment> pending) {
            this.viewerID = nonzero(viewerID);
            if (catalog < 0 || selection < 0 || macs == null || pending == null
                    || macs.size() + pending.size() > 32 || (selectedMac != null && selectedSlot != null))
                throw new IllegalArgumentException("Invalid library metadata");
            Set<UUID> hosts = new HashSet<>(), pairs = new HashSet<>(), slots = new HashSet<>();
            for (Mac mac : macs) if (mac == null || !hosts.add(mac.deviceID) || !pairs.add(mac.pairID))
                throw new IllegalArgumentException("Invalid library metadata");
            for (PendingEnrollment row : pending) if (row == null || !slots.add(row.slot))
                throw new IllegalArgumentException("Invalid library metadata");
            if ((selectedMac != null && !hosts.contains(selectedMac)) || (selectedSlot != null && !slots.contains(selectedSlot)))
                throw new IllegalArgumentException("Invalid library selection");
            catalogRevision = catalog; selectionRevision = selection;
            selectedMacID = selectedMac; selectedEnrollmentSlot = selectedSlot;
            this.macs = Collections.unmodifiableList(new ArrayList<>(macs));
            this.pending = Collections.unmodifiableList(new ArrayList<>(pending));
        }
    }

    private enum Kind { LOAD, INITIALIZE, SELECT, FORGET, ABANDON }
    private static final class Operation {
        final Kind kind;
        final long foreground;
        final UUID target;
        final Data expected;
        final AtomicBoolean retired = new AtomicBoolean();
        Operation(Kind kind, long foreground, UUID target, Data expected) {
            this.kind = kind; this.foreground = foreground; this.target = target; this.expected = expected;
        }
    }
    private static final class PairingOperation {
        final long foreground;
        PairingAttempt attempt;
        boolean cancelled;
        PairingOperation(long foreground) { this.foreground = foreground; }
    }
    private final StoragePort storage;
    private final SerialPort serial;
    private final MainPort main;
    private final boolean supported;
    private final PairingPort pairing;
    private State state = new State(Status.INACTIVE, null, PairingStatus.IDLE);
    private PairingStatus pairingStatus = PairingStatus.IDLE;
    private PairingOperation pendingPairing;
    private boolean cleanupUnproven;
    private Listener listener;
    private Operation pending;
    private long foreground;
    private boolean observing, closed, reloadAfterPending;

    public static ViewerLibraryController create(Context context) {
        java.util.Objects.requireNonNull(context);
        Handler handler = new Handler(Looper.getMainLooper());
        MainPort main = new MainPort() {
            @Override public void checkOwner() {
                if (Looper.myLooper() != Looper.getMainLooper()) throw new IllegalStateException("Library UI requires the main thread");
            }
            @Override public void execute(Runnable work) {
                if (!handler.post(work)) throw new RejectedExecutionException("Library UI is unavailable");
            }
        };
        ExecutorService worker = Executors.newSingleThreadExecutor();
        SerialPort serial = new SerialPort() {
            @Override public void execute(Runnable work) { worker.execute(work); }
            @Override public void close() { worker.shutdown(); }
        };
        boolean supported = AndroidViewerSecureStore.supportsSecureStorage(Build.VERSION.SDK_INT);
        // Unsupported platforms never open/probe the namespace or Keystore.
        StoragePort storage = supported ? new NativeStorage(context.getApplicationContext()) : null;
        Context application = java.util.Objects.requireNonNull(context.getApplicationContext());
        return new ViewerLibraryController(storage, serial, main, supported, new PairingPort() {
            @Override public boolean isAttemptInFlight() { return AndroidViewerPairing.isAttemptInFlight(); }
            @Override public PairingAttempt start(PairingInvitation invitation, long catalog, long selection) {
                AndroidViewerPairing.Attempt attempt = AndroidViewerPairing.start(application, invitation, catalog, selection);
                return new PairingAttempt() {
                    @Override public void cancel() { attempt.cancel(); }
                    @Override public CompletionStage<PairingStatus> completion() {
                        return attempt.completion().thenApply(terminal -> {
                            if (terminal == null || terminal.status() == null) return PairingStatus.CLEANUP_UNPROVEN;
                            switch (terminal.status()) {
                                case PAIRED: return PairingStatus.PAIRED;
                                case CANCELLED: return PairingStatus.CANCELLED;
                                case FAILED: return PairingStatus.FAILED;
                                case CLEANUP_UNPROVEN: return PairingStatus.CLEANUP_UNPROVEN;
                                default: return PairingStatus.CLEANUP_UNPROVEN;
                            }
                        });
                    }
                };
            }
        });
    }
    ViewerLibraryController(StoragePort storage, SerialPort serial, MainPort main, boolean supported) {
        this(storage, serial, main, supported, new PairingPort() {
            @Override public boolean isAttemptInFlight() { return false; }
            @Override public PairingAttempt start(PairingInvitation invitation, long catalog, long selection) {
                throw new IllegalStateException("Beluga pairing unavailable");
            }
        });
    }
    ViewerLibraryController(StoragePort storage, SerialPort serial, MainPort main, boolean supported, PairingPort pairing) {
        if (supported && storage == null) throw new IllegalArgumentException("Storage is required");
        this.storage = storage; this.serial = java.util.Objects.requireNonNull(serial);
        this.main = java.util.Objects.requireNonNull(main); this.supported = supported;
        this.pairing = java.util.Objects.requireNonNull(pairing);
    }
    public State state() { main.checkOwner(); return state; }
    public void start(Listener observer) {
        main.checkOwner(); if (closed) return;
        listener = java.util.Objects.requireNonNull(observer); observing = true;
        advanceForeground();
        if (!supported) { publish(snapshot(Status.UNSUPPORTED, null)); return; }
        if (pendingPairing != null) {
            cancelPairing(); publish(snapshot(Status.WORKING, null)); return;
        }
        if (pairingBlocked()) { publish(snapshot(Status.WORKING, null)); return; }
        pairingStatus = PairingStatus.IDLE;
        if (pending != null) {
            pending.retired.set(true); reloadAfterPending = true; publish(snapshot(Status.LOADING, null));
        } else begin(Kind.LOAD, null, null);
    }
    public void stop() {
        main.checkOwner(); if (closed) return;
        observing = false; listener = null; reloadAfterPending = false; advanceForeground();
        if (pending != null) pending.retired.set(true);
        cancelPairing(); state = snapshot(Status.INACTIVE, null);
    }
    public boolean refresh() {
        main.checkOwner();
        if (!available() || pending != null) return false;
        pairingStatus = PairingStatus.IDLE;
        begin(Kind.LOAD, null, null); return true;
    }
    public boolean initialize(State expected) {
        main.checkOwner();
        if (!available() || pending != null || expected != state || !state.canInitialize()) return false;
        begin(Kind.INITIALIZE, null, null); return true;
    }
    public boolean select(UUID host, State expected) { return change(Kind.SELECT, host, expected); }
    public boolean forget(UUID host, State expected) { return change(Kind.FORGET, host, expected); }
    public boolean abandon(UUID slot, State expected) { return change(Kind.ABANDON, slot, expected); }
    public boolean pair(State expected, PairingInvitation invitation) {
        main.checkOwner();
        if (!available() || pending != null || expected != state || !state.canPair() || invitation == null) return false;
        Data captured = state.data;
        PairingOperation operation = new PairingOperation(foreground);
        pendingPairing = operation; pairingStatus = PairingStatus.PAIRING;
        publish(snapshot(Status.WORKING, null));
        // A reentrant observer can stop before any preparation or transport begins.
        if (operation.cancelled || closed || !observing) {
            finishPairing(operation, PairingStatus.CANCELLED, null); return true;
        }
        PairingAttempt attempt;
        try { attempt = pairing.start(invitation, captured.catalogRevision, captured.selectionRevision); }
        catch (RuntimeException refused) {
            // The real facade only throws from start before an owned attempt exists.
            finishPairing(operation, PairingStatus.FAILED, null); return true;
        }
        if (attempt == null) { finishPairing(operation, PairingStatus.CLEANUP_UNPROVEN, null); return true; }
        operation.attempt = attempt;
        try {
            java.util.Objects.requireNonNull(attempt.completion()).whenComplete((terminal, failure) -> {
                try { main.execute(() -> finishPairing(operation, terminal, failure)); }
                catch (RuntimeException unavailable) { /* Keep owned admission blocked without a main-owner completion. */ }
            });
            if (operation.cancelled) requestCancel(operation);
        } catch (RuntimeException refused) {
            requestCancel(operation);
            finishPairing(operation, PairingStatus.CLEANUP_UNPROVEN, null);
        }
        return true;
    }
    public void cancelPairing() {
        main.checkOwner();
        PairingOperation operation = pendingPairing;
        if (operation == null || operation.cancelled) return;
        operation.cancelled = true; pairingStatus = PairingStatus.CANCELLING;
        requestCancel(operation);
        if (observing && !closed) publish(snapshot(Status.WORKING, null));
    }
    private void requestCancel(PairingOperation operation) {
        if (operation.attempt == null) return;
        try { operation.attempt.cancel(); }
        catch (RuntimeException unknown) { cleanupUnproven = true; pairingStatus = PairingStatus.CLEANUP_UNPROVEN; }
    }
    private void finishPairing(PairingOperation operation, PairingStatus terminal, Throwable failure) {
        main.checkOwner(); if (pendingPairing != operation) return;
        pendingPairing = null;
        if (failure != null || (terminal != PairingStatus.PAIRED && terminal != PairingStatus.CANCELLED
                && terminal != PairingStatus.FAILED)) cleanupUnproven = true;
        if (cleanupUnproven) {
            pairingStatus = PairingStatus.CLEANUP_UNPROVEN;
            if (closed) state = snapshot(Status.CLOSED, null);
            else if (!observing) state = snapshot(Status.INACTIVE, null);
            else publish(snapshot(Status.WORKING, null));
            return;
        }
        boolean current = operation.foreground == foreground && observing && !closed;
        pairingStatus = current ? (operation.cancelled ? PairingStatus.CANCELLED : terminal) : PairingStatus.IDLE;
        if (closed) { state = snapshot(Status.CLOSED, null); return; }
        if (!observing) { state = snapshot(Status.INACTIVE, null); return; }
        if (pairingBlocked()) { publish(snapshot(Status.WORKING, null)); return; }
        begin(Kind.LOAD, null, null);
    }
    private boolean change(Kind kind, UUID target, State expected) {
        main.checkOwner();
        if (!available() || pending != null || expected != state || !state.canChangeLibrary() || target == null) return false;
        boolean found = false;
        if (kind == Kind.ABANDON) {
            for (PendingEnrollment row : state.pendingEnrollments) if (row.slot.equals(target)) found = true;
        } else {
            for (Mac row : state.macs) if (row.deviceID.equals(target)) found = true;
        }
        if (!found) return false;
        begin(kind, target, state.data); return true;
    }
    private boolean available() {
        if (closed || !observing || !supported) return false;
        if (!pairingBlocked()) return true;
        if (pendingPairing == null) publish(snapshot(Status.UNAVAILABLE, null));
        return false;
    }
    private boolean pairingBlocked() {
        if (cleanupUnproven || pendingPairing != null) return true;
        try {
            if (pairing.isAttemptInFlight()) { pairingStatus = PairingStatus.BLOCKED; return true; }
        } catch (RuntimeException unavailable) { pairingStatus = PairingStatus.BLOCKED; return true; }
        return false;
    }
    private State snapshot(Status status, Data data) {
        if (status == Status.WORKING && (pairingStatus == PairingStatus.BLOCKED
                || pairingStatus == PairingStatus.CLEANUP_UNPROVEN)) status = Status.UNAVAILABLE;
        return new State(status, data, pairingStatus);
    }
    private void begin(Kind kind, UUID target, Data expected) {
        Operation operation = new Operation(kind, foreground, target, expected);
        pending = operation; reloadAfterPending = false;
        publish(snapshot(kind == Kind.LOAD ? Status.LOADING : Status.WORKING, null));
        try { serial.execute(() -> perform(operation)); }
        catch (RuntimeException refused) { finish(operation, null); }
    }
    private void perform(Operation operation) {
        Data result = null;
        try {
            // Already-entered atomic storage work may finish after stop; only queued work is revoked.
            if (!operation.retired.get() && !pairing.isAttemptInFlight()) {
                switch (operation.kind) {
                    case LOAD: result = storage.load(); break;
                    case INITIALIZE: result = storage.initialize(); break;
                    case SELECT: result = storage.select(operation.target, operation.expected.catalogRevision, operation.expected.selectionRevision); break;
                    case FORGET: result = storage.forget(operation.target, operation.expected.catalogRevision, operation.expected.selectionRevision); break;
                    case ABANDON: result = storage.abandon(operation.target, operation.expected.catalogRevision, operation.expected.selectionRevision); break;
                    default: throw new IllegalStateException("Invalid library operation");
                }
            }
        } catch (Exception refused) { result = null; }
        Data captured = result;
        try { main.execute(() -> finish(operation, captured)); }
        catch (RuntimeException unavailable) { operation.retired.set(true); }
    }
    private void finish(Operation operation, Data result) {
        main.checkOwner(); if (pending != operation) return;
        pending = null;
        if (closed) return;
        if (operation.retired.get() || operation.foreground != foreground || !observing) {
            if (observing && reloadAfterPending && !pairingBlocked()) begin(Kind.LOAD, null, null);
            return;
        }
        if (pairingBlocked()) { publish(snapshot(Status.WORKING, null)); return; }
        publish(snapshot(result == null ? Status.UNAVAILABLE : Status.READY, result));
    }
    private void publish(State next) {
        state = next;
        Listener observer = listener;
        if (observing && observer != null) observer.onState(next);
    }
    private void advanceForeground() {
        if (foreground == Long.MAX_VALUE) throw new IllegalStateException("Library lifecycle exhausted");
        foreground++;
    }
    @Override public void close() {
        main.checkOwner(); if (closed) return;
        stop(); closed = true; state = snapshot(Status.CLOSED, null); serial.close();
    }
    private static UUID nonzero(UUID id) {
        if (id == null || (id.getMostSignificantBits() == 0 && id.getLeastSignificantBits() == 0))
            throw new IllegalArgumentException("Invalid library identity");
        return id;
    }
    private static final class NativeStorage implements StoragePort {
        private final Context application;
        private AndroidViewerSecureStore store;
        NativeStorage(Context application) { this.application = java.util.Objects.requireNonNull(application); }
        @Override public Data load() throws Exception { store = AndroidViewerSecureStore.openExisting(application); return readback(); }
        @Override public Data initialize() throws Exception { store = AndroidViewerSecureStore.enrollFirstUse(application); return readback(); }
        @Override public Data select(UUID host, long catalog, long selection) throws Exception {
            java.util.Objects.requireNonNull(store).selectMac(host, catalog, selection); return readback();
        }
        @Override public Data forget(UUID host, long catalog, long selection) throws Exception {
            java.util.Objects.requireNonNull(store).forgetMac(host, catalog, selection); return readback();
        }
        @Override public Data abandon(UUID slot, long catalog, long selection) throws Exception {
            java.util.Objects.requireNonNull(store).abandonEnrollment(slot, catalog, selection); return readback();
        }
        private Data readback() throws Exception {
            AndroidViewerSecureStore.Snapshot snapshot = java.util.Objects.requireNonNull(store).snapshot();
            List<Mac> macs = new ArrayList<>(); List<PendingEnrollment> pending = new ArrayList<>();
            for (AndroidViewerSecureStore.Mac row : snapshot.macs)
                macs.add(new Mac(row.deviceID, row.pairID, AndroidViewerPairing.sanitizedDisplayName(row.displayName),
                        Phase.valueOf(row.phase.name())));
            for (AndroidViewerSecureStore.PendingEnrollment row : snapshot.pendingEnrollments) pending.add(new PendingEnrollment(row.slot));
            return new Data(snapshot.viewerID, snapshot.catalogRevision, snapshot.selectionRevision,
                    snapshot.selectedMacID, snapshot.selectedEnrollmentSlot, macs, pending);
        }
    }
}
