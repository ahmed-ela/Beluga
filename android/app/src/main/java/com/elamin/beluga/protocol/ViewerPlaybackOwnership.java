package com.elamin.beluga.protocol;

import java.util.Objects;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.BooleanSupplier;

/** One native output lifetime. A logical gate is not proof that queued device audio was retracted. */
final class ViewerPlaybackOwnership {
    enum State { NEW, ACQUIRING, AUTHORIZED, REVOKED, CLOSING, CLOSED, CLEANUP_UNPROVEN }
    enum Reason { NONE, OWNER_LOST, FOCUS_REFUSED, FOCUS_LOST, ROUTE_UNPROVED, ROUTE_CHANGED, NOISY, PLATFORM_FAILURE }
    interface MainPort { void checkOwner(); void execute(Runnable work); }
    interface Events {
        void focusChanged(boolean gain);
        void routeChanged();
        void noisy();
        void outputRemoved();
        void unavailable();
    }
    interface Platform {
        /** Install all exact-output/device/noisy listeners before requesting focus or reading route. */
        void register(Events events);
        /** Actual native output's route, never an inventory or recommended-device prediction. */
        Route route();
        /** Only immediate, granted media focus is true; delayed focus is not admitted. */
        boolean requestFocus();
        /** Abandon exact focus and remove exact listeners, only after native drainage. */
        void release();
    }
    static final class Route {
        final Object nativeOutput;
        final int deviceID, deviceType;
        Route(Object nativeOutput, int deviceID, int deviceType) {
            this.nativeOutput = Objects.requireNonNull(nativeOutput);
            if (deviceID <= 0 || deviceType <= 0) throw new IllegalArgumentException("Unproved playback route");
            this.deviceID = deviceID; this.deviceType = deviceType;
        }
        boolean same(Route other) {
            return other != null && nativeOutput == other.nativeOutput && deviceID == other.deviceID && deviceType == other.deviceType;
        }
    }

    private final MainPort main;
    private final Platform platform;
    private final BooleanSupplier ownerAdmitted;
    private final Runnable cancelExactAttempt;
    private final CompletionStage<Void> nativeDrain;
    private final AtomicBoolean authorized = new AtomicBoolean(), retired = new AtomicBoolean();
    private final CompletableFuture<Void> drained = new CompletableFuture<>();
    private State state = State.NEW;
    private Reason reason = Reason.NONE;
    private boolean attached, nativeEnded, nativeFailed, cancelRequested, cleanupUncertain, releaseStarted;
    private int callDepth;

    ViewerPlaybackOwnership(MainPort main, Platform platform, BooleanSupplier ownerAdmitted,
            Runnable cancelExactAttempt, CompletionStage<Void> nativeDrain) {
        this.main = Objects.requireNonNull(main); this.platform = Objects.requireNonNull(platform);
        this.ownerAdmitted = Objects.requireNonNull(ownerAdmitted); this.cancelExactAttempt = Objects.requireNonNull(cancelExactAttempt);
        this.nativeDrain = Objects.requireNonNull(nativeDrain);
    }
    /** Owner admission may represent a visible activity or a separately admitted playback service. */
    boolean start() {
        main.checkOwner(); if (state != State.NEW) return false;
        state = State.ACQUIRING; callDepth++;
        try {
            nativeDrain.whenComplete((ignored, failure) -> {
                retired.set(true); authorized.set(false);
                try { main.execute(() -> nativeEnded(failure != null)); }
                catch (RuntimeException unavailable) {
                    authorized.set(false);
                    // Completing the receipt is thread-safe; unavailable main dispatch cannot prove cleanup.
                    failDrain();
                }
            });
            attached = true;
            if (nativeEnded) return false;
            if (retired.get()) { deny(reason == Reason.NONE ? Reason.OWNER_LOST : reason); return false; }
            if (!admitted()) { deny(Reason.OWNER_LOST); return false; }
            if (!acquiring()) return false;
            platform.register(events);
            if (!acquiring()) return false;
            Route before = platform.route();
            if (!acquiring()) return false;
            if (before == null) { deny(Reason.ROUTE_UNPROVED); return false; }
            boolean focus = platform.requestFocus();
            if (!acquiring()) return false;
            if (!focus) { deny(Reason.FOCUS_REFUSED); return false; }
            Route after = platform.route();
            if (!acquiring()) return false;
            if (!before.same(after)) { deny(Reason.ROUTE_UNPROVED); return false; }
            if (!admitted()) { deny(Reason.OWNER_LOST); return false; }
            if (!acquiring()) return false;
            state = State.AUTHORIZED; authorized.set(true); return true;
        } catch (RuntimeException uncertain) {
            if (!attached) cleanupUncertain = true;
            deny(Reason.PLATFORM_FAILURE); return false;
        } finally {
            callDepth--;
            if (!attached) { authorized.set(false); state = State.CLEANUP_UNPROVEN; failDrain(); }
            else settle();
        }
    }
    boolean authorized() { return authorized.get() && !retired.get(); }
    State state() { main.checkOwner(); return state; }
    Reason reason() { main.checkOwner(); return reason; }
    CompletionStage<Void> drained() { return drained.thenApply(ignored -> null); }
    /** Explicit loss notification; gain never restarts this lifetime. */
    void ownerLost() {
        main.checkOwner();
        if (state == State.NEW) { retired.set(true); reason = Reason.OWNER_LOST; start(); }
        else deny(Reason.OWNER_LOST);
    }
    void verifyOwnerAdmission() {
        main.checkOwner();
        if ((state == State.ACQUIRING || state == State.AUTHORIZED) && !admitted()) deny(Reason.OWNER_LOST);
    }
    private boolean admitted() {
        try { return ownerAdmitted.getAsBoolean(); }
        catch (RuntimeException unavailable) { return false; }
    }
    private boolean acquiring() { return state == State.ACQUIRING && !retired.get() && !nativeEnded; }
    private final Events events = new Events() {
        @Override public void focusChanged(boolean gain) { main.checkOwner(); if (!gain) deny(Reason.FOCUS_LOST); }
        @Override public void routeChanged() { main.checkOwner(); deny(Reason.ROUTE_CHANGED); }
        @Override public void noisy() { main.checkOwner(); deny(Reason.NOISY); }
        @Override public void outputRemoved() { main.checkOwner(); deny(Reason.ROUTE_CHANGED); }
        @Override public void unavailable() { main.checkOwner(); deny(Reason.PLATFORM_FAILURE); }
    };
    private void deny(Reason why) {
        retired.set(true); authorized.set(false);
        if (state == State.CLOSED || state == State.CLOSING || state == State.CLEANUP_UNPROVEN) return;
        if (reason == Reason.NONE) reason = why;
        state = State.REVOKED;
        if (!cancelRequested && !nativeEnded) {
            cancelRequested = true; callDepth++;
            try { cancelExactAttempt.run(); }
            catch (RuntimeException uncertain) { cleanupUncertain = true; }
            finally { callDepth--; }
        }
        settle();
    }
    private void nativeEnded(boolean failed) {
        main.checkOwner(); if (nativeEnded) return;
        authorized.set(false); nativeEnded = true; nativeFailed = failed; settle();
    }
    private void settle() {
        if (!attached || !nativeEnded || callDepth != 0 || releaseStarted || drained.isDone()) return;
        authorized.set(false);
        if (nativeFailed) { state = State.CLEANUP_UNPROVEN; failDrain(); return; }
        releaseStarted = true; state = State.CLOSING; callDepth++;
        try { platform.release(); }
        catch (RuntimeException uncertain) { cleanupUncertain = true; }
        finally { callDepth--; }
        if (cleanupUncertain) { state = State.CLEANUP_UNPROVEN; failDrain(); }
        else { state = State.CLOSED; drained.complete(null); }
    }
    private void failDrain() { drained.completeExceptionally(new IllegalStateException("Beluga playback cleanup unproved")); }
}
