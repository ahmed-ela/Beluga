package com.elamin.beluga.protocol;

import java.util.Objects;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.BooleanSupplier;

/** Bridges one real native output to asynchronous main-thread ownership and two separate receipts. */
final class ViewerPlaybackOutputLifetime<T> {
    static final int ROUTE_ATTEMPTS = 20;
    static final long ROUTE_RETRY_MILLIS = 25;
    interface Main {
        void checkOwner();
        void execute(Runnable work);
        void later(Runnable work, long millis);
    }
    interface Owner {
        boolean start();
        boolean authorized();
        CompletionStage<Void> drained();
    }
    interface Platform<T> {
        boolean routed(T exactOutput);
        Owner create(T exactOutput, BooleanSupplier admitted, Runnable cancel,
                CompletionStage<Void> outputStopped);
    }

    private final Main main;
    private final Platform<T> platform;
    private final BooleanSupplier admitted;
    private final Runnable cancel;
    private final Object fence = new Object();
    private final AtomicBoolean revoked = new AtomicBoolean(), cancelled = new AtomicBoolean();
    private final CompletableFuture<Void> outputStopped = new CompletableFuture<>();
    private final CompletableFuture<Void> mainDrained = new CompletableFuture<>();
    private volatile T exact;
    private volatile Owner owner;
    private volatile boolean stopped, uncertain, finished;
    private boolean requested;

    ViewerPlaybackOutputLifetime(Main main, Platform<T> platform, BooleanSupplier admitted, Runnable cancel) {
        this.main = Objects.requireNonNull(main); this.platform = Objects.requireNonNull(platform);
        this.admitted = Objects.requireNonNull(admitted); this.cancel = Objects.requireNonNull(cancel);
    }

    void markPlayoutRequested() {
        synchronized (fence) {
            if (requested || finished || revoked.get()) throw new IllegalStateException("Output lifetime retired");
            requested = true;
        }
    }
    void started(T output) {
        boolean valid;
        synchronized (fence) {
            valid = output != null && requested && exact == null && !finished && !uncertain;
            if (valid) exact = output;
        }
        if (!valid) { cleanupUnproved(); cancelOnce(); return; }
        try { main.execute(() -> acquire(output, ROUTE_ATTEMPTS)); }
        catch (RuntimeException unavailable) { cleanupUnproved(); cancelOnce(); }
    }
    private void acquire(T output, int remaining) {
        main.checkOwner();
        if (uncertain) { mainDrained.completeExceptionally(unproved()); return; }
        // No focus or monitor was allocated. A late dispatch must still settle its receipt.
        if (revoked.get() || stopped) { mainDrained.complete(null); return; }
        try {
            if (output != exact) { cleanupUnproved(); cancelOnce(); return; }
            if (!isAdmitted()) { mainDrained.complete(null); return; }
            if (!platform.routed(output)) {
                if (remaining <= 1) { cancelFromOwner(); mainDrained.complete(null); }
                else main.later(() -> acquire(output, remaining - 1), ROUTE_RETRY_MILLIS);
                return;
            }
            Owner created = Objects.requireNonNull(platform.create(output, this::isAdmitted,
                    this::cancelFromOwner, outputStopped.thenApply(ignored -> null)));
            owner = created;
            created.drained().whenComplete((ignored, failure) -> {
                if (failure == null) mainDrained.complete(null);
                else { uncertain = true; revoke(); mainDrained.completeExceptionally(unproved()); }
            });
            // start attaches the native receipt even if cancellation won during construction.
            if (!created.start()) cancelFromOwner();
        } catch (RuntimeException | LinkageError unavailable) {
            // Construction or registration may have partially allocated platform resources.
            cleanupUnproved(); cancelOnce();
        }
    }
    private boolean isAdmitted() {
        if (revoked.get() || stopped || uncertain || finished) return false;
        boolean accepted;
        try { accepted = admitted.getAsBoolean(); }
        catch (RuntimeException unavailable) { accepted = false; }
        // Explicit retirement and an admission failure race at this atomic commit, not later
        // callback delivery. A completed stop must not be reclassified by an in-flight read.
        if (!accepted && revoked.compareAndSet(false, true)) cancelOnce();
        return accepted;
    }
    boolean authorized(T output) {
        Owner current = owner;
        if (output == null || output != exact || current == null || !isAdmitted()) return false;
        return current.authorized() && !revoked.get() && !stopped && !uncertain && !finished;
    }
    boolean authorized() { return authorized(exact); }
    void revoke() { revoked.set(true); }
    private void cancelFromOwner() { if (revoked.compareAndSet(false, true)) cancelOnce(); }
    private void cancelOnce() {
        if (!cancelled.compareAndSet(false, true)) return;
        try { cancel.run(); }
        catch (RuntimeException unavailable) { cleanupUnproved(); }
    }
    void stopped(T output) {
        boolean valid;
        synchronized (fence) {
            valid = output != null && output == exact && !stopped && !uncertain && !finished;
            if (valid) stopped = true;
        }
        boolean unexpected = revoked.compareAndSet(false, true);
        if (valid) { outputStopped.complete(null); if (unexpected) cancelOnce(); }
        else { cleanupUnproved(); cancelOnce(); }
    }
    void failure(T output, boolean cleanupUnproved) {
        revoke();
        if (cleanupUnproved || (exact != null && output != exact)) cleanupUnproved();
        cancelOnce();
    }
    /** Called only after the synchronous native stop returns, before any native graph destruction. */
    boolean finishOutputStop() {
        boolean clean, absent;
        synchronized (fence) {
            absent = !requested && exact == null;
            clean = !uncertain && (absent || stopped);
            finished = true;
        }
        revoke();
        if (!clean) cleanupUnproved();
        else if (absent) { outputStopped.complete(null); mainDrained.complete(null); }
        return clean;
    }
    void cleanupUnproved() {
        uncertain = true; revoke();
        outputStopped.completeExceptionally(unproved());
        mainDrained.completeExceptionally(unproved());
    }
    CompletionStage<Void> drained() { return mainDrained.thenApply(ignored -> null); }
    private static IllegalStateException unproved() { return new IllegalStateException("Playback output cleanup unproved"); }
}
