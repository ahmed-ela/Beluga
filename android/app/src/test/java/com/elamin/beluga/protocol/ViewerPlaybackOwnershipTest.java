package com.elamin.beluga.protocol;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.function.BiConsumer;
import org.junit.Test;
import com.elamin.beluga.protocol.ViewerPlaybackOwnership.Reason;
import com.elamin.beluga.protocol.ViewerPlaybackOwnership.Route;
import com.elamin.beluga.protocol.ViewerPlaybackOwnership.State;

/** Actual ownership logic with explicit platform doubles; no Android focus, routing or PCM proof. */
public final class ViewerPlaybackOwnershipTest {
    @Test public void admissionRegistersBeforeReadingExactRouteAndRequestingFocus() {
        Fixture f = new Fixture(); assertFalse(f.owner.authorized()); assertTrue(f.owner.start());
        assertEquals(Arrays.asList("register", "route", "focus", "route"), f.platform.calls);
        assertTrue(f.owner.authorized()); assertEquals(State.AUTHORIZED, f.owner.state()); assertEquals(Reason.NONE, f.owner.reason());
        assertFalse(f.owner.start()); assertEquals(1, f.platform.requests); assertEquals(0, f.cancels);
    }
    @Test public void focusRefusalNeverAdmitsAndKeepsMonitorsUntilNativeDrain() {
        Fixture f = new Fixture(); f.platform.granted = false;
        assertFalse(f.owner.start()); assertFalse(f.owner.authorized()); assertEquals(Reason.FOCUS_REFUSED, f.owner.reason());
        assertEquals(1, f.cancels); assertEquals(0, f.platform.releases); assertFalse(f.closed().isDone());
        f.nativeDrain.complete(null); assertEquals(0, f.platform.releases); f.main.drain();
        assertEquals(State.CLOSED, f.owner.state()); assertEquals(1, f.platform.releases); assertFalse(f.closed().isCompletedExceptionally());
    }
    @Test public void focusLossAndSubsequentGainCannotResumeThisLifetime() {
        Fixture f = started(); f.platform.events.focusChanged(false);
        assertFalse(f.owner.authorized()); assertEquals(1, f.cancels); assertEquals(Reason.FOCUS_LOST, f.owner.reason());
        f.platform.events.focusChanged(true); f.platform.events.focusChanged(false); f.owner.verifyOwnerAdmission();
        assertFalse(f.owner.authorized()); assertFalse(f.owner.start()); assertEquals(1, f.cancels); assertEquals(1, f.platform.requests);
    }
    @Test public void lossInsideGrantedFocusRequestCannotBeOverwrittenByGrant() {
        Fixture f = new Fixture(); f.platform.duringFocus = () -> f.platform.events.focusChanged(false);
        assertFalse(f.owner.start()); assertEquals(State.REVOKED, f.owner.state()); assertFalse(f.owner.authorized());
        assertEquals(1, f.cancels); assertEquals(Arrays.asList("register", "route", "focus"), f.platform.calls);
    }
    @Test public void gainCallbackAloneNeverSuppliesFocusOrRoutePermission() {
        Fixture f = new Fixture(); f.platform.granted = false;
        f.platform.duringRegister = () -> { f.platform.events.focusChanged(true); assertFalse(f.owner.authorized()); };
        assertFalse(f.owner.start()); assertEquals(Reason.FOCUS_REFUSED, f.owner.reason()); assertEquals(1, f.cancels);
    }
    @Test public void unknownOrChangedExactOutputRouteRefusesAdmission() {
        for (int variant = 0; variant < 5; variant++) {
            Fixture f = new Fixture();
            if (variant == 0) f.platform.before = null;
            if (variant == 1) f.platform.after = null;
            if (variant == 2) f.platform.after = new Route(new Object(), 7, 3);
            if (variant == 3) f.platform.after = new Route(f.platform.output, 8, 3);
            if (variant == 4) f.platform.after = new Route(f.platform.output, 7, 4);
            assertFalse(f.owner.start()); assertEquals(Reason.ROUTE_UNPROVED, f.owner.reason());
            assertFalse(f.owner.authorized()); assertEquals(1, f.cancels); assertEquals(0, f.platform.releases);
        }
    }
    @Test public void malformedRouteIdentityIsNeverAcceptedAsAnOutput() {
        try { new Route(null, 1, 3); fail("missing output"); } catch (NullPointerException expected) { }
        try { new Route(new Object(), 0, 3); fail("missing device"); } catch (IllegalArgumentException expected) { }
        try { new Route(new Object(), 1, 0); fail("unknown type"); } catch (IllegalArgumentException expected) { }
    }
    @Test public void routeNoisyAndOutputRemovalRevokeBeforeCancellingExactAttempt() {
        for (int event = 0; event < 3; event++) {
            Fixture f = started(); f.duringCancel = () -> assertFalse(f.owner.authorized());
            if (event == 0) f.platform.events.routeChanged();
            if (event == 1) f.platform.events.noisy();
            if (event == 2) f.platform.events.outputRemoved();
            assertFalse(f.owner.authorized()); assertEquals(1, f.cancels); assertEquals(0, f.platform.releases);
            f.platform.events.focusChanged(true); assertFalse(f.owner.authorized());
        }
    }
    @Test public void routeCallbackDuringRegistrationPreventsFocusRequest() {
        Fixture f = new Fixture(); f.platform.duringRegister = () -> f.platform.events.routeChanged();
        assertFalse(f.owner.start()); assertEquals(0, f.platform.requests); assertEquals(1, f.cancels);
        assertEquals(Arrays.asList("register"), f.platform.calls);
    }
    @Test public void ownerAdmissionIsExplicitAndLossRequiresAnotherLifetime() {
        Fixture refused = new Fixture(); refused.admitted = false; assertFalse(refused.owner.start());
        assertTrue(refused.platform.calls.isEmpty()); assertEquals(1, refused.cancels);
        Fixture f = started(); f.admitted = false; f.owner.verifyOwnerAdmission();
        assertFalse(f.owner.authorized()); assertEquals(Reason.OWNER_LOST, f.owner.reason());
        f.admitted = true; f.owner.verifyOwnerAdmission(); assertFalse(f.owner.authorized()); assertEquals(1, f.cancels);
    }
    @Test public void reentrantOwnerLossBeforeRegistrationAllocatesNoPlatformWork() {
        Fixture f = new Fixture(); f.duringAdmission = f.owner::ownerLost;
        assertFalse(f.owner.start()); assertTrue(f.platform.calls.isEmpty()); assertEquals(1, f.cancels);
        assertFalse(f.owner.authorized());
    }
    @Test public void lossBeforeStartStillObservesNativeDrainWithoutRequestingFocus() {
        Fixture f = new Fixture(); f.owner.ownerLost();
        assertTrue(f.platform.calls.isEmpty()); assertEquals(1, f.cancels); assertFalse(f.owner.start());
        f.nativeDrain.complete(null); f.main.drain(); assertEquals(State.CLOSED, f.owner.state());
    }
    @Test public void nativeEndRevokesGateBeforeMainDeliveryAndThenReleasesOnce() {
        Fixture f = started(); f.nativeDrain.complete(null);
        assertFalse(f.owner.authorized()); assertEquals(0, f.platform.releases); assertFalse(f.closed().isDone());
        f.main.drain(); assertEquals(State.CLOSED, f.owner.state()); assertEquals(1, f.platform.releases);
        f.owner.ownerLost(); f.platform.events.focusChanged(false); f.platform.events.routeChanged();
        assertEquals(0, f.cancels); assertEquals(1, f.platform.releases);
    }
    @Test public void exceptionalNativeDrainNeverPretendsListenersOrFocusWereReleased() {
        Fixture f = started(); f.nativeDrain.completeExceptionally(new IllegalStateException("fixture")); f.main.drain();
        assertFalse(f.owner.authorized()); assertEquals(State.CLEANUP_UNPROVEN, f.owner.state());
        assertEquals(0, f.platform.releases); assertTrue(f.closed().isCompletedExceptionally()); assertFalse(f.owner.start());
    }
    @Test public void platformReleaseFailureIsNotAResourceDrainReceipt() {
        Fixture f = started(); f.platform.failRelease = true; f.nativeDrain.complete(null); f.main.drain();
        assertEquals(State.CLEANUP_UNPROVEN, f.owner.state()); assertTrue(f.closed().isCompletedExceptionally());
        assertEquals(1, f.platform.releases); f.owner.ownerLost(); assertEquals(1, f.platform.releases);
    }
    @Test public void operationalFailureCanStillHaveAProvedOrdinaryResourceDrain() {
        Fixture f = started(); f.platform.events.unavailable(); assertEquals(1, f.cancels);
        f.nativeDrain.complete(null); f.main.drain(); assertEquals(State.CLOSED, f.owner.state());
        assertEquals(Reason.PLATFORM_FAILURE, f.owner.reason()); assertFalse(f.closed().isCompletedExceptionally());
    }
    @Test public void platformExceptionsRevokeButStillWaitForExactNativeDrain() {
        for (int boundary = 1; boundary <= 3; boundary++) {
            Fixture f = new Fixture(); f.platform.failAt = boundary;
            assertFalse(f.owner.start()); assertFalse(f.owner.authorized()); assertEquals(1, f.cancels);
            assertEquals(0, f.platform.releases); assertFalse(f.closed().isDone());
            f.nativeDrain.complete(null); f.main.drain(); assertEquals(1, f.platform.releases);
        }
    }
    @Test public void cancelTerminalThenThrowCannotPublishCleanDrainInsideCancel() {
        Fixture f = started(); f.main.inline = true; f.failCancel = true;
        f.duringCancel = () -> {
            f.nativeDrain.complete(null); assertEquals(0, f.platform.releases); assertFalse(f.closed().isDone());
        };
        f.owner.ownerLost(); assertEquals(1, f.platform.releases); assertTrue(f.closed().isCompletedExceptionally());
        assertEquals(State.CLEANUP_UNPROVEN, f.owner.state());
    }
    @Test public void terminalDuringFocusCannotReleaseBeforeFocusCallReturns() {
        Fixture f = new Fixture(); f.main.inline = true;
        f.platform.duringFocus = () -> {
            f.nativeDrain.complete(null); assertEquals(0, f.platform.releases); assertFalse(f.closed().isDone());
        };
        assertFalse(f.owner.start()); assertFalse(f.owner.authorized()); assertEquals(State.CLOSED, f.owner.state());
        assertEquals(1, f.platform.releases); assertEquals(0, f.cancels);
    }
    @Test public void completedNativeLifetimeNeverRequestsFocusOrAdmitsPlayback() {
        Fixture f = new Fixture(); f.main.inline = true; f.nativeDrain.complete(null);
        assertFalse(f.owner.start()); assertEquals(State.CLOSED, f.owner.state()); assertEquals(0, f.platform.requests);
        assertEquals(Arrays.asList("release"), f.platform.calls);
    }
    @Test public void throwingAttachmentAfterInlineTerminalCannotCreateCleanCompletion() {
        CompletableFuture<Void> malformed = new CompletableFuture<Void>() {
            @Override public CompletableFuture<Void> whenComplete(BiConsumer<? super Void, ? super Throwable> action) {
                action.accept(null, null); throw new IllegalStateException("attachment fixture");
            }
        };
        Fixture f = new Fixture(malformed); f.main.inline = true;
        assertFalse(f.owner.start()); assertEquals(State.CLEANUP_UNPROVEN, f.owner.state());
        assertTrue(f.closed().isCompletedExceptionally()); assertTrue(f.platform.calls.isEmpty());
    }
    @Test public void dependentDrainFutureCannotForgeOwnerCompletion() {
        Fixture f = started(); CompletableFuture<Void> borrowed = f.closed(); assertTrue(borrowed.complete(null));
        assertFalse(f.closed().isDone()); assertEquals(State.AUTHORIZED, f.owner.state()); assertEquals(0, f.platform.releases);
        f.nativeDrain.complete(null); f.main.drain(); assertEquals(State.CLOSED, f.owner.state());
    }
    @Test public void lateEventsBelongOnlyToTheRetiredAttemptNeverItsSuccessor() {
        Fixture old = started(); old.owner.ownerLost(); old.nativeDrain.complete(null); old.main.drain();
        Fixture next = started(); old.platform.events.focusChanged(true); old.platform.events.routeChanged(); old.platform.events.noisy();
        assertEquals(1, old.cancels); assertEquals(0, next.cancels); assertTrue(next.owner.authorized());
    }
    @Test public void rejectedMainDeliveryClosesGateWithoutInventingCleanup() {
        Fixture f = started(); f.main.reject = true; f.nativeDrain.complete(null);
        assertFalse(f.owner.authorized()); assertTrue(f.closed().isCompletedExceptionally());
        assertEquals(0, f.platform.releases); assertEquals(0, f.cancels);
    }
    @Test public void ownerMethodsAndEventsRequireMainButGateAndFutureAreCrossThreadSafe() {
        Fixture f = started(); f.main.owner = false;
        try { f.owner.ownerLost(); fail("wrong owner"); } catch (IllegalStateException expected) { }
        try { f.owner.start(); fail("wrong owner"); } catch (IllegalStateException expected) { }
        try { f.platform.events.noisy(); fail("wrong callback owner"); } catch (IllegalStateException expected) { }
        assertTrue(f.owner.authorized()); assertFalse(f.closed().isDone()); assertEquals(0, f.cancels);
    }

    private static Fixture started() { Fixture f = new Fixture(); assertTrue(f.owner.start()); return f; }
    private static final class Fixture {
        final Main main = new Main(); final Platform platform = new Platform();
        final CompletableFuture<Void> nativeDrain; final ViewerPlaybackOwnership owner;
        boolean admitted = true, failCancel; int cancels; Runnable duringCancel, duringAdmission;
        Fixture() { this(new CompletableFuture<>()); }
        Fixture(CompletableFuture<Void> nativeDrain) {
            this.nativeDrain = nativeDrain;
            owner = new ViewerPlaybackOwnership(main, platform, () -> {
                if (duringAdmission != null) duringAdmission.run(); return admitted;
            }, () -> { cancels++; if (duringCancel != null) duringCancel.run(); if (failCancel) throw new IllegalStateException("fixture"); }, nativeDrain);
        }
        CompletableFuture<Void> closed() { return owner.drained().toCompletableFuture(); }
    }
    private static final class Main implements ViewerPlaybackOwnership.MainPort {
        final ArrayDeque<Runnable> queue = new ArrayDeque<>(); boolean owner = true, inline, reject;
        @Override public void checkOwner() { if (!owner) throw new IllegalStateException("owner fixture"); }
        @Override public void execute(Runnable work) {
            if (reject) throw new IllegalStateException("dispatch fixture"); if (inline) work.run(); else queue.add(work);
        }
        void drain() { while (!queue.isEmpty()) queue.remove().run(); }
    }
    private static final class Platform implements ViewerPlaybackOwnership.Platform {
        final Object output = new Object(); final List<String> calls = new ArrayList<>();
        Route before = new Route(output, 7, 3), after = before;
        ViewerPlaybackOwnership.Events events;
        boolean granted = true, failRelease; int reads, requests, releases, failAt;
        Runnable duringRegister, duringFocus;
        @Override public void register(ViewerPlaybackOwnership.Events events) {
            calls.add("register"); this.events = events; if (duringRegister != null) duringRegister.run();
            if (failAt == 1) throw new IllegalStateException("register fixture");
        }
        @Override public Route route() {
            calls.add("route"); if (failAt == 2) throw new IllegalStateException("route fixture");
            return reads++ == 0 ? before : after;
        }
        @Override public boolean requestFocus() {
            calls.add("focus"); requests++; if (duringFocus != null) duringFocus.run();
            if (failAt == 3) throw new IllegalStateException("focus fixture"); return granted;
        }
        @Override public void release() {
            calls.add("release"); releases++; if (failRelease) throw new IllegalStateException("release fixture");
        }
    }
}
