package com.elamin.beluga.protocol;

import static org.junit.Assert.*;
import java.util.ArrayDeque;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.function.BooleanSupplier;
import org.junit.Test;

public final class ViewerPlaybackOutputLifetimeTest {
    private static final class Harness implements ViewerPlaybackOutputLifetime.Main, ViewerPlaybackOutputLifetime.Platform<Object> {
        final Object output = new Object();
        final ArrayDeque<Runnable> queue = new ArrayDeque<>();
        final ViewerPlaybackOutputLifetime<Object> subject = new ViewerPlaybackOutputLifetime<>(this, this,
                () -> { this.onAdmissionRead.run(); return this.admitted; }, () -> this.cancelled++);
        Runnable onAdmissionRead = () -> { };
        final CompletableFuture<Void> ownerDrain = new CompletableFuture<>();
        CompletionStage<Void> nativeReceipt;
        BooleanSupplier guard;
        Runnable ownerCancel;
        boolean admitted = true, routed = true, grants = true, ownerAuthorized, rejectDispatch, creationThrows;
        int cancelled, routeReads, creations, starts, delays;
        @Override public void checkOwner() { }
        @Override public void execute(Runnable work) {
            if (rejectDispatch) throw new IllegalStateException("main unavailable");
            queue.add(work);
        }
        @Override public void later(Runnable work, long millis) {
            assertEquals(25, millis); delays++; execute(work);
        }
        @Override public boolean routed(Object exact) { assertSame(output, exact); routeReads++; return routed; }
        @Override public ViewerPlaybackOutputLifetime.Owner create(Object exact, BooleanSupplier admitted,
                Runnable cancel, CompletionStage<Void> stopped) {
            assertSame(output, exact); creations++;
            if (creationThrows) throw new IllegalStateException("partial allocation");
            guard = admitted; ownerCancel = cancel; nativeReceipt = stopped;
            return new ViewerPlaybackOutputLifetime.Owner() {
                @Override public boolean start() { starts++; ownerAuthorized = grants && guard.getAsBoolean(); return ownerAuthorized; }
                @Override public boolean authorized() { return ownerAuthorized; }
                @Override public CompletionStage<Void> drained() { return ownerDrain; }
            };
        }
        void publish() { subject.markPlayoutRequested(); subject.started(output); }
        void next() { queue.remove().run(); }
        void own() { publish(); next(); assertTrue(subject.authorized(output)); }
        void stop() { subject.revoke(); subject.stopped(output); assertTrue(subject.finishOutputStop()); }
        void failedDrain() { assertTrue(subject.drained().toCompletableFuture().isCompletedExceptionally()); }
    }
    @Test public void remainsSilentUntilActualMainOwnerAdmission() {
        Harness h = new Harness(); assertFalse(h.subject.authorized()); h.publish();
        assertFalse(h.subject.authorized(h.output)); h.next();
        assertTrue(h.subject.authorized(h.output)); assertFalse(h.subject.authorized(new Object()));
        assertEquals(1, h.starts); assertEquals(0, h.cancelled);
    }
    @Test public void exactOutputStopAndMainCleanupAreSeparateReceipts() {
        Harness h = new Harness(); h.own(); h.stop();
        assertTrue(h.nativeReceipt.toCompletableFuture().isDone());
        assertFalse(h.subject.drained().toCompletableFuture().isDone());
        h.ownerDrain.complete(null); h.subject.drained().toCompletableFuture().join();
        assertFalse(h.subject.authorized());
    }
    @Test public void outputRouteCanAppearDuringBoundedMutedBootstrap() {
        Harness h = new Harness(); h.routed = false; h.publish(); h.next();
        assertEquals(0, h.creations); assertFalse(h.subject.authorized());
        h.routed = true; h.next(); assertTrue(h.subject.authorized());
        assertEquals(1, h.delays); assertEquals(1, h.creations);
    }
    @Test public void missingRouteHasAnExactBoundAndDoesNotAcquireFocus() {
        Harness h = new Harness(); h.routed = false; h.publish();
        for (int i = 0; i < 20; i++) h.next();
        assertTrue(h.queue.isEmpty()); assertEquals(20, h.routeReads); assertEquals(19, h.delays);
        assertEquals(0, h.creations); assertEquals(1, h.cancelled); assertFalse(h.subject.authorized());
        h.stop(); h.subject.drained().toCompletableFuture().join();
    }
    @Test public void nativeStopBeforeMainDispatchProvesNoPlatformAllocation() {
        Harness h = new Harness(); h.publish(); h.stop();
        assertFalse(h.subject.drained().toCompletableFuture().isDone()); h.next();
        assertEquals(0, h.creations); assertEquals(0, h.routeReads); h.subject.drained().toCompletableFuture().join();
    }
    @Test public void revokedBeforeMainDispatchDoesNotAcquireFocus() {
        Harness h = new Harness(); h.publish(); h.subject.revoke(); h.next();
        assertEquals(0, h.creations); assertFalse(h.subject.authorized()); h.stop();
        h.subject.drained().toCompletableFuture().join();
    }
    @Test public void missingStoppedReceiptQuarantinesAnAttemptedLifetime() {
        Harness h = new Harness(); h.own(); h.subject.revoke();
        assertFalse(h.subject.finishOutputStop()); h.failedDrain();
        assertTrue(h.nativeReceipt.toCompletableFuture().isCompletedExceptionally());
    }
    @Test public void attemptedButNeverPublishedIsNotProofOfNoNativeAllocation() {
        Harness h = new Harness(); h.subject.markPlayoutRequested();
        assertFalse(h.subject.finishOutputStop()); h.failedDrain();
    }
    @Test public void neverAttemptedIsCleanAbsence() {
        Harness h = new Harness(); assertTrue(h.subject.finishOutputStop());
        h.subject.drained().toCompletableFuture().join(); assertEquals(0, h.creations);
        assertThrows(IllegalStateException.class, h.subject::markPlayoutRequested);
    }
    @Test public void wrongOutputReceiptCannotFreeExactOwner() {
        Harness h = new Harness(); h.own(); h.subject.stopped(new Object());
        assertFalse(h.subject.finishOutputStop()); h.failedDrain(); assertFalse(h.subject.authorized());
    }
    @Test public void duplicatePublicationFailsSticky() {
        Harness h = new Harness(); h.publish(); h.subject.started(h.output); h.next();
        assertFalse(h.subject.finishOutputStop()); h.failedDrain(); assertEquals(0, h.creations); assertEquals(1, h.cancelled);
    }
    @Test public void failedStopNeverBecomesSuccessfulFromALaterCallback() {
        Harness h = new Harness(); h.own(); h.subject.failure(h.output, true); h.subject.stopped(h.output);
        assertFalse(h.subject.finishOutputStop()); h.failedDrain(); assertEquals(1, h.cancelled);
    }
    @Test public void operationalFailureStillRequiresIndependentStopProof() {
        Harness h = new Harness(); h.own(); h.subject.failure(h.output, false);
        assertFalse(h.subject.authorized()); h.stop(); h.ownerDrain.complete(null);
        h.subject.drained().toCompletableFuture().join(); assertEquals(1, h.cancelled);
    }
    @Test public void operationalFailureWithoutStopProofIsUnproved() {
        Harness h = new Harness(); h.own(); h.subject.failure(h.output, false);
        assertFalse(h.subject.finishOutputStop()); h.failedDrain();
    }
    @Test public void rejectedMainDispatchIsUnprovedNotUnallocated() {
        Harness h = new Harness(); h.rejectDispatch = true; h.publish(); h.failedDrain();
        assertFalse(h.subject.finishOutputStop()); assertEquals(1, h.cancelled);
    }
    @Test public void partialMainCreationIsUnproved() {
        Harness h = new Harness(); h.creationThrows = true; h.publish(); h.next(); h.failedDrain();
        assertEquals(1, h.cancelled); assertFalse(h.subject.finishOutputStop());
    }
    @Test public void focusRefusalCannotUnmute() {
        Harness h = new Harness(); h.grants = false; h.publish(); h.next();
        assertFalse(h.subject.authorized()); assertEquals(1, h.cancelled); h.stop();
        assertFalse(h.subject.drained().toCompletableFuture().isDone()); h.ownerDrain.complete(null);
        h.subject.drained().toCompletableFuture().join();
    }
    @Test public void ownerLossIsStickyEvenIfAdmissionReturns() {
        Harness h = new Harness(); h.own(); h.admitted = false; assertFalse(h.subject.authorized());
        h.admitted = true; assertFalse(h.subject.authorized()); assertEquals(1, h.cancelled);
    }
    @Test public void focusOrRouteLossStopsExactReceiverWithoutGainResume() {
        Harness h = new Harness(); h.own(); h.ownerCancel.run();
        assertFalse(h.subject.authorized()); h.ownerAuthorized = true; assertFalse(h.subject.authorized());
        assertEquals(1, h.cancelled);
    }
    @Test public void unexpectedNativeStopCancelsReceiver() {
        Harness h = new Harness(); h.own(); h.subject.stopped(h.output);
        assertEquals(1, h.cancelled); assertFalse(h.subject.authorized());
        assertTrue(h.subject.finishOutputStop()); h.ownerDrain.complete(null); h.subject.drained().toCompletableFuture().join();
    }
    @Test public void platformCleanupFailureCannotBecomeSuccess() {
        Harness h = new Harness(); h.own(); h.stop(); h.ownerDrain.completeExceptionally(new IllegalStateException());
        h.failedDrain(); assertFalse(h.subject.authorized());
    }
    @Test public void explicitRetirementWinsAnInFlightAdmissionSample() {
        Harness h = new Harness(); h.own();
        h.onAdmissionRead = () -> { h.subject.revoke(); h.admitted = false; };
        assertFalse(h.subject.authorized()); assertEquals(0, h.cancelled);
        h.stop(); h.ownerDrain.complete(null); h.subject.drained().toCompletableFuture().join();
    }
    @Test public void lateOwnerLossAfterExplicitRetirementDoesNotReclassifyCancellation() {
        Harness h = new Harness(); h.own(); h.subject.revoke(); h.ownerCancel.run();
        assertFalse(h.subject.authorized()); assertEquals(0, h.cancelled);
    }
    @Test public void explicitRetirementDuringMainAdmissionDoesNotReclassifyCancellation() {
        Harness h = new Harness(); h.publish();
        h.onAdmissionRead = () -> { h.subject.revoke(); h.admitted = false; };
        h.next(); assertEquals(0, h.cancelled); assertEquals(0, h.creations);
        h.stop(); h.subject.drained().toCompletableFuture().join();
    }
    @Test public void explicitRetirementDuringOwnerStartDoesNotReclassifyCancellation() {
        Harness h = new Harness(); h.publish();
        h.onAdmissionRead = new Runnable() {
            int reads;
            @Override public void run() { if (++reads == 2) { h.subject.revoke(); h.admitted = false; } }
        };
        h.next(); assertEquals(0, h.cancelled); assertEquals(1, h.creations);
        h.stop(); h.ownerDrain.complete(null); h.subject.drained().toCompletableFuture().join();
    }
    @Test public void realOwnershipCleanupFollowsOutputReceiptWithoutWaitingForFinalReceiver() {
        ArrayDeque<Runnable> main = new ArrayDeque<>(); Object exact = new Object(); int[] releases = {0};
        ViewerPlaybackOwnership.MainPort ownerMain = new ViewerPlaybackOwnership.MainPort() {
            @Override public void checkOwner() { }
            @Override public void execute(Runnable work) { main.add(work); }
        };
        ViewerPlaybackOutputLifetime.Main mainPort = new ViewerPlaybackOutputLifetime.Main() {
            @Override public void checkOwner() { }
            @Override public void execute(Runnable work) { main.add(work); }
            @Override public void later(Runnable work, long millis) { main.add(work); }
        };
        ViewerPlaybackOutputLifetime<Object> lifetime = new ViewerPlaybackOutputLifetime<>(mainPort,
                new ViewerPlaybackOutputLifetime.Platform<Object>() {
                    @Override public boolean routed(Object output) { return true; }
                    @Override public ViewerPlaybackOutputLifetime.Owner create(Object output, BooleanSupplier admitted,
                            Runnable cancel, CompletionStage<Void> stopped) {
                        ViewerPlaybackOwnership owner = new ViewerPlaybackOwnership(ownerMain,
                                new ViewerPlaybackOwnership.Platform() {
                                    @Override public void register(ViewerPlaybackOwnership.Events events) { }
                                    @Override public ViewerPlaybackOwnership.Route route() {
                                        return new ViewerPlaybackOwnership.Route(output, 1, 2);
                                    }
                                    @Override public boolean requestFocus() { return true; }
                                    @Override public void release() { releases[0]++; }
                                }, admitted, cancel, stopped);
                        return new ViewerPlaybackOutputLifetime.Owner() {
                            @Override public boolean start() { return owner.start(); }
                            @Override public boolean authorized() { return owner.authorized(); }
                            @Override public CompletionStage<Void> drained() { return owner.drained(); }
                        };
                    }
                }, () -> true, () -> fail("No unexpected cancellation"));
        lifetime.markPlayoutRequested(); lifetime.started(exact); main.remove().run(); assertTrue(lifetime.authorized());
        lifetime.revoke(); lifetime.stopped(exact); assertTrue(lifetime.finishOutputStop());
        assertEquals(0, releases[0]); assertFalse(lifetime.drained().toCompletableFuture().isDone());
        main.remove().run(); assertEquals(1, releases[0]); lifetime.drained().toCompletableFuture().join();
        assertTrue(main.isEmpty());
    }
}
