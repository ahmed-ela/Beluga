package com.elamin.beluga.protocol;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertSame;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.function.BiConsumer;
import org.junit.Test;
import com.elamin.beluga.protocol.ViewerLibraryController.Data;
import com.elamin.beluga.protocol.ViewerLibraryController.Mac;
import com.elamin.beluga.protocol.ViewerLibraryController.PendingEnrollment;
import com.elamin.beluga.protocol.ViewerLibraryController.Phase;
import com.elamin.beluga.protocol.ViewerLibraryController.PairingStatus;
import com.elamin.beluga.protocol.ViewerLibraryController.ConnectionStatus;
import com.elamin.beluga.protocol.ViewerLibraryController.State;
import com.elamin.beluga.protocol.ViewerLibraryController.Status;

/** Actual controller with trusted fake IO; not Android Keystore, persistence, UI, or pairing proof. */
public final class ViewerLibraryControllerTest {
    private static final UUID VIEWER = new UUID(0, 1), HOST = new UUID(0, 2), PAIR = new UUID(0, 3), SLOT = new UUID(0, 4);

    @Test public void unsupportedStorageNeverProbesOrEnqueuesEvenAcrossLifecycle() {
        Fixture f = new Fixture(false); f.controller.start(f.states::add);
        assertEquals(Status.UNSUPPORTED, f.controller.state().status);
        assertFalse(f.controller.initialize(f.controller.state())); assertFalse(f.controller.refresh());
        assertFalse(f.controller.select(HOST, f.controller.state()));
        f.controller.stop(); f.controller.start(f.states::add); f.controller.close();
        assertEquals(0, f.serial.queue.size()); assertEquals(0, f.storage.calls.size()); assertEquals(1, f.serial.closes);
    }
    @Test public void foregroundLoadPublishesOnlyReadbackAndDefensiveMetadata() {
        Fixture f = ready(); State state = f.controller.state();
        assertEquals(Status.READY, state.status); assertEquals(VIEWER, state.viewerID);
        assertEquals("Actual saved Mac", state.macs.get(0).displayName);
        assertEquals(Phase.ACTIVE, state.macs.get(0).phase); assertNull(state.selectedMacID);
        assertEquals(SLOT, state.pendingEnrollments.get(0).slot);
        try { state.macs.clear(); fail("mutable Mac rows"); } catch (UnsupportedOperationException expected) { }
        try { state.pendingEnrollments.clear(); fail("mutable pending rows"); } catch (UnsupportedOperationException expected) { }
        assertEquals("<Beluga library state; not connection proof>", state.toString());
        assertEquals("<saved Mac metadata; not connected>", state.macs.get(0).toString());
    }
    @Test public void loadFailureNeverAutoEnrollsOrRepairsAndInitializeIsExplicit() {
        Fixture f = new Fixture(true); f.storage.failLoad = true;
        f.controller.start(f.states::add); f.drain();
        assertEquals(Status.UNAVAILABLE, f.controller.state().status);
        assertEquals(Collections.singletonList("load"), f.storage.calls);
        State expected = f.controller.state(); assertTrue(f.controller.initialize(expected));
        assertFalse(f.controller.initialize(expected)); f.drain();
        assertEquals(Arrays.asList("load", "initialize"), f.storage.calls);
        assertEquals(Status.READY, f.controller.state().status); assertTrue(f.controller.state().macs.isEmpty());
    }
    @Test public void enrollmentRefusalIsNotSuccessOrAnAutomaticRetry() {
        Fixture f = new Fixture(true); f.storage.failLoad = true; f.storage.failInitialize = true;
        f.controller.start(f.states::add); f.drain();
        assertTrue(f.controller.initialize(f.controller.state())); f.drain();
        assertEquals(Status.UNAVAILABLE, f.controller.state().status);
        assertNull(f.controller.state().viewerID); assertEquals(2, f.storage.calls.size());
        f.drain(); assertEquals(2, f.storage.calls.size());
    }
    @Test public void selectCapturesExactRevisionsAndCannotBorrowOldOrForeignRows() {
        Fixture f = ready(); State old = f.controller.state();
        assertFalse(f.controller.select(new UUID(0, 99), old));
        assertTrue(f.controller.select(HOST, old)); assertFalse(f.controller.forget(HOST, old));
        f.drain(); assertEquals("select", f.storage.lastAction); assertEquals(HOST, f.storage.lastTarget);
        assertEquals(10, f.storage.lastCatalog); assertEquals(20, f.storage.lastSelection);
        assertEquals(HOST, f.controller.state().selectedMacID);
        assertFalse(f.controller.forget(HOST, old)); assertFalse(f.controller.abandon(SLOT, old));
    }
    @Test public void forgetAndAbandonUseSeparateExactTargetsAndFreshSnapshots() {
        Fixture f = ready(); assertFalse(f.controller.abandon(HOST, f.controller.state()));
        assertFalse(f.controller.forget(SLOT, f.controller.state()));
        assertTrue(f.controller.abandon(SLOT, f.controller.state())); f.drain();
        assertEquals("abandon", f.storage.lastAction); assertEquals(SLOT, f.storage.lastTarget);
        assertTrue(f.controller.state().pendingEnrollments.isEmpty()); assertEquals(1, f.controller.state().macs.size());
        assertTrue(f.controller.forget(HOST, f.controller.state())); f.drain();
        assertEquals("forget", f.storage.lastAction); assertTrue(f.controller.state().macs.isEmpty());
    }
    @Test public void stoppedQueuedLoadAndMutationHaveNoStorageEffects() {
        Fixture f = new Fixture(true); f.controller.start(f.states::add); f.controller.stop(); f.drain();
        assertTrue(f.storage.calls.isEmpty()); assertEquals(Status.INACTIVE, f.controller.state().status);
        f.controller.start(f.states::add); f.drain(); State loaded = f.controller.state();
        assertTrue(f.controller.select(HOST, loaded)); f.controller.stop(); f.drain();
        assertEquals(Collections.singletonList("load"), f.storage.calls);
        assertEquals(Status.INACTIVE, f.controller.state().status);
    }
    @Test public void stoppedQueuedEnrollmentNeverCreatesIdentity() {
        Fixture f = new Fixture(true); f.storage.failLoad = true; f.controller.start(f.states::add); f.drain();
        assertTrue(f.controller.initialize(f.controller.state())); f.controller.stop(); f.drain();
        assertEquals(Collections.singletonList("load"), f.storage.calls);
    }
    @Test public void startedAtomicWriteMayFinishButCannotPublishToStoppedOwner() {
        Fixture f = ready(); State before = f.controller.state();
        f.storage.onChange = f.controller::stop;
        assertTrue(f.controller.select(HOST, before)); f.serial.next(); f.main.drain();
        assertEquals(Status.INACTIVE, f.controller.state().status); assertEquals(HOST, f.storage.data.selectedMacID);
        f.storage.onChange = null; f.controller.start(f.states::add); f.drain();
        assertEquals(HOST, f.controller.state().selectedMacID);
        assertEquals(Arrays.asList("load", "select", "load"), f.storage.calls);
    }
    @Test public void oldMainCompletionCannotPopulateNewForegroundAndOneReloadFollows() {
        Fixture f = new Fixture(true); f.controller.start(f.states::add); f.serial.next();
        assertEquals(1, f.main.queue.size());
        f.controller.stop(); f.controller.start(f.states::add); assertEquals(0, f.serial.queue.size());
        f.main.drain(); assertEquals(Status.LOADING, f.controller.state().status);
        assertEquals(1, f.serial.queue.size()); f.drain();
        assertEquals(Status.READY, f.controller.state().status); assertEquals(Arrays.asList("load", "load"), f.storage.calls);
    }
    @Test public void rapidStartStopCoalescesToOneOutstandingOperation() {
        Fixture f = new Fixture(true);
        for (int i = 0; i < 100; i++) { f.controller.start(f.states::add); f.controller.stop(); }
        f.controller.start(f.states::add); assertEquals(1, f.serial.queue.size());
        f.drain(); assertEquals(Collections.singletonList("load"), f.storage.calls);
        assertEquals(Status.READY, f.controller.state().status);
    }
    @Test public void observerReentryRetiresBeforeTheReservedWorkIsDispatched() {
        Fixture f = new Fixture(true);
        f.controller.start(state -> { if (state.status == Status.LOADING) f.controller.stop(); });
        f.drain(); assertTrue(f.storage.calls.isEmpty()); assertEquals(Status.INACTIVE, f.controller.state().status);
    }
    @Test public void closeIsIdempotentAndLateCompletionNeverNotifiesOrReopens() {
        Fixture f = new Fixture(true); f.controller.start(f.states::add); f.serial.next();
        int observations = f.states.size(); f.controller.close(); f.controller.close(); f.main.drain();
        f.controller.start(f.states::add); assertEquals(observations, f.states.size());
        assertEquals(Status.CLOSED, f.controller.state().status); assertEquals(1, f.serial.closes);
        assertFalse(f.controller.refresh()); assertFalse(f.controller.initialize(f.controller.state()));
    }
    @Test public void failedMutationClearsAuthorityAndDoesNotShowRetainedRowsAsSuccess() {
        Fixture f = ready(); f.storage.failChange = true;
        assertTrue(f.controller.forget(HOST, f.controller.state())); f.drain();
        assertEquals(Status.UNAVAILABLE, f.controller.state().status); assertTrue(f.controller.state().macs.isEmpty());
        assertEquals(1, f.storage.data.macs.size()); assertEquals(2, f.storage.calls.size());
    }
    @Test public void publicControllerAPIAndCallbackRequireOwnerPort() {
        Fixture f = new Fixture(true); f.main.owner = false;
        try { f.controller.start(f.states::add); fail("wrong owner"); } catch (IllegalStateException expected) { }
        assertTrue(f.serial.queue.isEmpty()); assertTrue(f.storage.calls.isEmpty());
        f.main.owner = true; f.controller.start(f.states::add); f.serial.next(); f.main.owner = false;
        try { f.main.drain(); fail("callback wrong owner"); } catch (IllegalStateException expected) { }
    }
    @Test public void refreshInvalidatesAllPreviouslyCapturedActionStates() {
        Fixture f = ready(); State old = f.controller.state(); assertTrue(f.controller.refresh()); f.drain();
        assertFalse(f.controller.select(HOST, old)); assertFalse(f.controller.forget(HOST, old));
        assertFalse(f.controller.abandon(SLOT, old)); assertTrue(f.controller.state() != old);
        assertSame(f.controller.state(), f.states.get(f.states.size() - 1));
    }
    @Test public void pairingUsesOnlyExactReadySnapshotAndCapturesPrivateRevisions() {
        Fixture f = ready(), other = ready(); State expected = f.controller.state();
        assertTrue(expected.canPair()); assertFalse(expected.canCancelPairing());
        assertFalse(f.controller.pair(other.controller.state(), invitation()));
        assertFalse(f.controller.pair(expected, null)); assertEquals(0, f.pairing.starts);
        assertTrue(f.controller.pair(expected, invitation()));
        assertEquals(1, f.pairing.starts); assertEquals(10, f.pairing.catalog); assertEquals(20, f.pairing.selection);
        assertEquals(PairingStatus.PAIRING, f.controller.state().pairingStatus);
        assertTrue(f.controller.state().canCancelPairing()); assertFalse(f.controller.state().canPair());
        assertFalse(f.controller.pair(expected, invitation()));
        assertFalse(f.controller.select(HOST, expected)); assertFalse(f.controller.forget(HOST, expected));
        assertFalse(f.controller.abandon(SLOT, expected)); assertFalse(f.controller.initialize(f.controller.state()));
        assertFalse(f.controller.refresh()); assertEquals(Collections.singletonList("load"), f.storage.calls);
    }
    @Test public void oldReadyPairingStateCannotBorrowRevisionsAfterRefreshOrMutation() {
        Fixture f = ready(); State old = f.controller.state(); assertTrue(f.controller.refresh()); f.drain();
        assertFalse(f.controller.pair(old, invitation()));
        State current = f.controller.state(); assertTrue(f.controller.select(HOST, current)); f.drain();
        assertFalse(f.controller.pair(current, invitation()));
        assertTrue(f.controller.pair(f.controller.state(), invitation()));
        assertEquals(11, f.pairing.catalog); assertEquals(21, f.pairing.selection);
    }
    @Test public void capacityAndUnavailableStatesNeverStartPairing() {
        Fixture f = new Fixture(true); List<PendingEnrollment> pending = new ArrayList<>();
        for (int i = 0; i < 32; i++) pending.add(new PendingEnrollment(new UUID(0, 100 + i)));
        f.storage.data = new Data(VIEWER, 10, 20, null, null, Collections.emptyList(), pending);
        f.controller.start(f.states::add); f.drain(); assertFalse(f.controller.state().canPair());
        assertFalse(f.controller.pair(f.controller.state(), invitation())); assertEquals(0, f.pairing.starts);
        f.storage.failLoad = true; assertTrue(f.controller.refresh()); f.drain();
        assertFalse(f.controller.pair(f.controller.state(), invitation()));
        f.controller.stop(); assertFalse(f.controller.pair(f.controller.state(), invitation()));
    }
    @Test public void pairedTerminalRequiresFreshForegroundLibraryReadback() {
        Fixture f = ready(); assertTrue(f.controller.pair(f.controller.state(), invitation()));
        f.pairing.finish(PairingStatus.PAIRED); assertEquals(PairingStatus.PAIRING, f.controller.state().pairingStatus);
        f.main.drain(); assertEquals(Status.LOADING, f.controller.state().status);
        assertEquals(PairingStatus.PAIRED, f.controller.state().pairingStatus);
        assertNull(f.controller.state().viewerID); assertEquals(Collections.singletonList("load"), f.storage.calls);
        f.drain(); assertEquals(Status.READY, f.controller.state().status);
        assertEquals(PairingStatus.PAIRED, f.controller.state().pairingStatus);
        assertEquals(Arrays.asList("load", "load"), f.storage.calls); assertTrue(f.controller.state().canPair());
    }
    @Test public void explicitCancelIsImmediateButHoldsAdmissionUntilActualCompletion() {
        Fixture f = ready(); assertTrue(f.controller.pair(f.controller.state(), invitation()));
        f.controller.cancelPairing(); f.controller.cancelPairing();
        assertEquals(1, f.pairing.current.cancels); assertEquals(PairingStatus.CANCELLING, f.controller.state().pairingStatus);
        assertFalse(f.controller.state().canCancelPairing()); assertFalse(f.controller.refresh());
        assertFalse(f.controller.pair(f.controller.state(), invitation()));
        f.pairing.finish(PairingStatus.PAIRED); f.drain();
        assertEquals(PairingStatus.CANCELLED, f.controller.state().pairingStatus);
        assertEquals(Status.READY, f.controller.state().status);
        assertFalse(f.states.stream().anyMatch(row -> row.pairingStatus == PairingStatus.PAIRED));
    }
    @Test public void stoppedPairingCancelsAndTerminalDoesNotLoadUntilForegroundReturns() {
        Fixture f = ready(); assertTrue(f.controller.pair(f.controller.state(), invitation()));
        int count = f.states.size(); f.controller.stop();
        assertEquals(1, f.pairing.current.cancels); assertEquals(Status.INACTIVE, f.controller.state().status);
        f.pairing.finish(PairingStatus.CANCELLED); f.drain();
        assertEquals(count, f.states.size()); assertEquals(Collections.singletonList("load"), f.storage.calls);
        assertEquals(PairingStatus.IDLE, f.controller.state().pairingStatus);
        f.controller.start(f.states::add); f.drain(); assertEquals(Status.READY, f.controller.state().status);
        assertEquals(Arrays.asList("load", "load"), f.storage.calls);
    }
    @Test public void stalePairedCallbackOnlyReloadsNewForegroundWithoutPublishingSuccess() {
        Fixture f = ready(); assertTrue(f.controller.pair(f.controller.state(), invitation()));
        f.pairing.finish(PairingStatus.PAIRED); f.controller.stop();
        List<State> newForeground = new ArrayList<>(); f.controller.start(newForeground::add);
        assertEquals(PairingStatus.CANCELLING, f.controller.state().pairingStatus);
        assertEquals(1, f.pairing.starts); assertTrue(f.serial.queue.isEmpty());
        f.drain(); assertEquals(Status.READY, f.controller.state().status);
        assertEquals(PairingStatus.IDLE, f.controller.state().pairingStatus);
        assertFalse(newForeground.stream().anyMatch(row -> row.pairingStatus == PairingStatus.PAIRED));
        assertEquals(Arrays.asList("load", "load"), f.storage.calls);
    }
    @Test public void repeatedForegroundWhileCancellingNeverCreatesAnotherAttemptOrLoad() {
        Fixture f = ready(); assertTrue(f.controller.pair(f.controller.state(), invitation()));
        for (int i = 0; i < 50; i++) { f.controller.stop(); f.controller.start(f.states::add); }
        assertEquals(1, f.pairing.starts); assertEquals(1, f.pairing.current.cancels);
        assertEquals(Collections.singletonList("load"), f.storage.calls); assertTrue(f.serial.queue.isEmpty());
        f.pairing.finish(PairingStatus.CANCELLED); f.drain();
        assertEquals(Arrays.asList("load", "load"), f.storage.calls);
    }
    @Test public void observerStopBeforePairStartDoesNotPrepareOrCreateTransport() {
        Fixture f = ready(); State ready = f.controller.state();
        f.controller.start(state -> { if (state.pairingStatus == PairingStatus.PAIRING) f.controller.stop(); });
        f.drain(); ready = f.controller.state();
        assertTrue(f.controller.pair(ready, invitation()));
        assertEquals(0, f.pairing.starts); assertEquals(Status.INACTIVE, f.controller.state().status);
        assertTrue(f.serial.queue.isEmpty());
    }
    @Test public void cancellationDuringStartIsAppliedToReturnedExactAttempt() {
        Fixture f = ready(); f.pairing.onStart = f.controller::stop;
        assertTrue(f.controller.pair(f.controller.state(), invitation()));
        assertEquals(1, f.pairing.current.cancels); assertEquals(Status.INACTIVE, f.controller.state().status);
        f.pairing.finish(PairingStatus.CANCELLED); f.drain(); assertEquals(Collections.singletonList("load"), f.storage.calls);
    }
    @Test public void synchronousTerminalStillUsesMainOwnerAndFreshLoad() {
        Fixture f = ready(); f.pairing.inlineTerminal = PairingStatus.FAILED;
        assertTrue(f.controller.pair(f.controller.state(), invitation()));
        assertEquals(PairingStatus.PAIRING, f.controller.state().pairingStatus); assertEquals(1, f.main.queue.size());
        f.drain(); assertEquals(PairingStatus.FAILED, f.controller.state().pairingStatus);
        assertEquals(Status.READY, f.controller.state().status);
    }
    @Test public void oldDuplicateCompletionCannotRetireOrPopulateSuccessorAttempt() {
        Fixture f = ready(); assertTrue(f.controller.pair(f.controller.state(), invitation()));
        FakeAttempt old = f.pairing.current; f.pairing.finish(PairingStatus.FAILED); f.drain();
        assertTrue(f.controller.pair(f.controller.state(), invitation()));
        assertFalse(old.result.complete(PairingStatus.PAIRED)); f.main.drain();
        assertEquals(PairingStatus.PAIRING, f.controller.state().pairingStatus);
        assertEquals(2, f.pairing.starts); assertFalse(f.controller.refresh());
    }
    @Test public void cleanupUnprovenRemainsStickyAcrossPauseResumeAndAllActions() {
        Fixture f = ready(); State previous = f.controller.state(); assertTrue(f.controller.pair(previous, invitation()));
        f.pairing.finish(PairingStatus.CLEANUP_UNPROVEN); f.drain();
        assertEquals(Status.UNAVAILABLE, f.controller.state().status);
        assertEquals(PairingStatus.CLEANUP_UNPROVEN, f.controller.state().pairingStatus);
        for (int i = 0; i < 3; i++) { f.controller.stop(); f.controller.start(f.states::add); }
        State blocked = f.controller.state(); assertEquals(PairingStatus.CLEANUP_UNPROVEN, blocked.pairingStatus);
        assertFalse(blocked.canInitialize()); assertFalse(blocked.canChangeLibrary()); assertFalse(blocked.canPair());
        assertFalse(f.controller.initialize(blocked)); assertFalse(f.controller.refresh());
        assertFalse(f.controller.select(HOST, previous)); assertFalse(f.controller.forget(HOST, previous));
        assertFalse(f.controller.abandon(SLOT, previous)); assertFalse(f.controller.pair(blocked, invitation()));
        assertEquals(Collections.singletonList("load"), f.storage.calls); assertEquals(1, f.pairing.starts);
    }
    @Test public void exceptionalOrMalformedCompletionCannotAuthorizeRetry() {
        for (PairingStatus invalid : Arrays.asList(null, PairingStatus.IDLE, PairingStatus.PAIRING, PairingStatus.BLOCKED)) {
            Fixture f = ready(); assertTrue(f.controller.pair(f.controller.state(), invitation()));
            f.pairing.finish(invalid); f.drain();
            assertEquals(PairingStatus.CLEANUP_UNPROVEN, f.controller.state().pairingStatus); assertFalse(f.controller.refresh());
        }
        Fixture f = ready(); assertTrue(f.controller.pair(f.controller.state(), invitation()));
        f.pairing.current.result.completeExceptionally(new Exception("fixture")); f.drain();
        assertEquals(PairingStatus.CLEANUP_UNPROVEN, f.controller.state().pairingStatus); assertFalse(f.controller.refresh());
    }
    @Test public void cancelFailureDoesNotBecomeCleanAfterLaterCompletion() {
        Fixture f = ready(); assertTrue(f.controller.pair(f.controller.state(), invitation()));
        f.pairing.current.failCancel = true; f.controller.cancelPairing();
        assertEquals(PairingStatus.CLEANUP_UNPROVEN, f.controller.state().pairingStatus);
        f.pairing.finish(PairingStatus.CANCELLED); f.drain();
        assertEquals(PairingStatus.CLEANUP_UNPROVEN, f.controller.state().pairingStatus);
        assertEquals(Collections.singletonList("load"), f.storage.calls);
    }
    @Test public void freshControllerCannotBypassHeldProcessAttemptWithLibraryMutations() {
        Fixture f = new Fixture(true); f.pairing.busy = true;
        f.controller.start(f.states::add); State blocked = f.controller.state();
        assertEquals(Status.UNAVAILABLE, blocked.status);
        assertEquals(PairingStatus.BLOCKED, blocked.pairingStatus); assertFalse(blocked.canInitialize());
        assertFalse(f.controller.refresh()); assertFalse(f.controller.initialize(blocked));
        assertFalse(f.controller.select(HOST, blocked)); assertFalse(f.controller.forget(HOST, blocked));
        assertFalse(f.controller.abandon(SLOT, blocked)); assertFalse(f.controller.pair(blocked, invitation()));
        assertTrue(f.storage.calls.isEmpty()); assertTrue(f.serial.queue.isEmpty());
        f.pairing.busy = false; assertTrue(f.controller.refresh()); f.drain();
        assertEquals(PairingStatus.IDLE, f.controller.state().pairingStatus); assertEquals(Status.READY, f.controller.state().status);
    }
    @Test public void processAttemptBeginningAfterQueuedLoadPreventsStorageProbe() {
        Fixture f = new Fixture(true); f.controller.start(f.states::add); f.pairing.busy = true; f.drain();
        assertEquals(PairingStatus.BLOCKED, f.controller.state().pairingStatus);
        assertTrue(f.storage.calls.isEmpty()); assertFalse(f.controller.initialize(f.controller.state()));
    }
    @Test public void detectingExternalAttemptAtPublicActionClearsPreviouslyReadyAuthority() {
        Fixture f = ready(); State previous = f.controller.state(); f.pairing.busy = true;
        assertFalse(f.controller.select(HOST, previous));
        State blocked = f.controller.state(); assertEquals(Status.UNAVAILABLE, blocked.status);
        assertEquals(PairingStatus.BLOCKED, blocked.pairingStatus); assertNull(blocked.viewerID);
        assertTrue(blocked.macs.isEmpty()); assertFalse(blocked.canPair()); assertFalse(blocked.canInitialize());
        assertSame(blocked, f.states.get(f.states.size() - 1));
        f.pairing.busy = false; assertFalse(f.controller.pair(previous, invitation()));
        assertTrue(f.controller.refresh()); f.drain(); assertEquals(Status.READY, f.controller.state().status);
    }
    @Test public void closeCancelsExactAttemptAndLateTerminalNeverNotifiesOrLoads() {
        Fixture f = ready(); assertTrue(f.controller.pair(f.controller.state(), invitation()));
        int count = f.states.size(); f.controller.close(); f.controller.close();
        assertEquals(1, f.pairing.current.cancels); f.pairing.finish(PairingStatus.PAIRED); f.drain();
        assertEquals(count, f.states.size()); assertEquals(Status.CLOSED, f.controller.state().status);
        assertEquals(Collections.singletonList("load"), f.storage.calls); assertEquals(1, f.serial.closes);
        assertFalse(f.controller.pair(f.controller.state(), invitation()));
    }
    @Test public void safeStartRefusalReloadsButDoesNotClaimPairedOrInitialize() {
        Fixture f = ready(); f.pairing.failStart = true;
        assertTrue(f.controller.pair(f.controller.state(), invitation())); f.drain();
        assertEquals(PairingStatus.FAILED, f.controller.state().pairingStatus); assertEquals(Status.READY, f.controller.state().status);
        assertEquals(Arrays.asList("load", "load"), f.storage.calls);
        assertFalse(f.states.stream().anyMatch(row -> row.pairingStatus == PairingStatus.PAIRED));
    }
    @Test public void defaultCompositionCannotConnectEvenWithSelectedActiveMac() {
        Fixture f = new Fixture(true); f.selectInitial(Phase.ACTIVE);
        f.controller.start(f.states::add); f.drain();
        assertFalse(f.controller.state().canConnect()); assertFalse(f.controller.connect(f.controller.state()));
        assertEquals(0, f.connection.starts); assertEquals(Collections.singletonList("load"), f.storage.calls);
    }
    @Test public void connectRequiresExactCurrentSelectedActiveSnapshotAndPrivateRevisions() {
        Fixture f = selectedReady(), foreign = selectedReady(); State expected = f.controller.state();
        assertTrue(expected.canConnect()); assertFalse(expected.canDisconnect());
        assertFalse(f.controller.connect(null)); assertFalse(f.controller.connect(foreign.controller.state()));
        assertTrue(f.controller.connect(expected));
        assertEquals(HOST, f.connection.host); assertEquals(10, f.connection.catalog); assertEquals(20, f.connection.selection);
        assertEquals(ConnectionStatus.CONNECTING, f.controller.state().connectionStatus);
        assertEquals(HOST, f.controller.state().selectedMacID); assertEquals(VIEWER, f.controller.state().viewerID);
        assertTrue(f.controller.state().canDisconnect()); assertFalse(f.controller.state().canConnect());
        assertFalse(f.controller.connect(expected)); assertFalse(f.controller.connect(f.controller.state()));
        assertFalse(f.controller.pair(expected, invitation())); assertFalse(f.controller.pair(f.controller.state(), invitation()));
        assertFalse(f.controller.select(HOST, expected)); assertFalse(f.controller.forget(HOST, f.controller.state()));
        assertFalse(f.controller.abandon(SLOT, expected)); assertFalse(f.controller.initialize(f.controller.state()));
        assertFalse(f.controller.refresh()); assertEquals(1, f.connection.starts); assertEquals(0, f.pairing.starts);
        assertEquals(Collections.singletonList("load"), f.storage.calls);
    }
    @Test public void unselectedPendingAcceptedUnsupportedAndBackgroundNeverConnect() {
        for (Phase phase : Arrays.asList(Phase.PENDING, Phase.ACCEPTED_ISSUED)) {
            Fixture f = new Fixture(true, true); f.selectInitial(phase);
            f.controller.start(f.states::add); f.drain();
            assertFalse(f.controller.state().canConnect()); assertFalse(f.controller.connect(f.controller.state()));
            assertEquals(0, f.connection.starts);
        }
        Fixture unselected = new Fixture(true, true); unselected.controller.start(unselected.states::add); unselected.drain();
        assertFalse(unselected.controller.connect(unselected.controller.state()));
        Fixture unsupported = new Fixture(false, true); unsupported.selectInitial(Phase.ACTIVE);
        unsupported.controller.start(unsupported.states::add); assertFalse(unsupported.controller.connect(unsupported.controller.state()));
        assertTrue(unsupported.storage.calls.isEmpty());
        Fixture stopped = selectedReady(); State old = stopped.controller.state(); stopped.controller.stop();
        assertFalse(stopped.controller.connect(old)); assertFalse(stopped.controller.connect(stopped.controller.state()));
        assertEquals(0, stopped.connection.starts);
    }
    @Test public void refreshAndSelectionInvalidateCapturedConnectStateWithoutReenrollment() {
        Fixture f = selectedReady(); State old = f.controller.state();
        assertTrue(f.controller.refresh()); f.drain(); assertFalse(f.controller.connect(old));
        State beforeSelect = f.controller.state(); assertTrue(f.controller.select(HOST, beforeSelect)); f.drain();
        assertFalse(f.controller.connect(beforeSelect)); assertTrue(f.controller.connect(f.controller.state()));
        assertEquals(11, f.connection.catalog); assertEquals(21, f.connection.selection);
        assertEquals(Arrays.asList("load", "load", "select"), f.storage.calls);
        assertEquals(VIEWER, f.storage.data.viewerID); assertEquals(PAIR, f.storage.data.macs.get(0).pairID);
    }
    @Test public void operationalStateIsExplicitAndTerminalStateCannotReleaseOwnership() {
        Fixture f = selectedReady(); assertTrue(f.controller.connect(f.controller.state()));
        f.connection.current.nativeState = ViewerConnectionSession.State.ACTIVE;
        assertEquals(ConnectionStatus.CONNECTING, f.controller.state().connectionStatus);
        assertTrue(f.controller.refreshConnectionStatus()); assertEquals(ConnectionStatus.ACTIVE, f.controller.state().connectionStatus);
        assertFalse(f.controller.pair(f.controller.state(), invitation()));
        f.connection.current.nativeState = ViewerConnectionSession.State.TERMINAL;
        assertTrue(f.controller.refreshConnectionStatus()); assertEquals(ConnectionStatus.CANCELLING, f.controller.state().connectionStatus);
        assertFalse(f.controller.refresh()); assertFalse(f.controller.connect(f.controller.state()));
        f.connection.current.nativeState = ViewerConnectionSession.State.ACTIVE;
        assertFalse(f.controller.refreshConnectionStatus()); assertEquals(ConnectionStatus.CANCELLING, f.controller.state().connectionStatus);
        f.connection.finish(ConnectionStatus.ENDED); assertEquals(ConnectionStatus.CANCELLING, f.controller.state().connectionStatus);
        f.drain(); assertEquals(ConnectionStatus.ENDED, f.controller.state().connectionStatus);
        assertEquals(Status.READY, f.controller.state().status); assertTrue(f.controller.state().canConnect());
        assertEquals(Arrays.asList("load", "load"), f.storage.calls); assertEquals(1, f.connection.starts);
    }
    @Test public void disconnectCancelsOnceAndCannotBeReopenedBeforeActualCompletion() {
        Fixture f = selectedReady(); assertTrue(f.controller.connect(f.controller.state()));
        f.controller.disconnect(); f.controller.disconnect();
        assertEquals(1, f.connection.current.cancels); assertEquals(ConnectionStatus.CANCELLING, f.controller.state().connectionStatus);
        assertFalse(f.controller.state().canDisconnect()); assertFalse(f.controller.refresh());
        f.connection.current.nativeState = ViewerConnectionSession.State.ACTIVE;
        assertFalse(f.controller.refreshConnectionStatus()); assertFalse(f.controller.connect(f.controller.state()));
        f.connection.finish(ConnectionStatus.ENDED); f.drain();
        assertEquals(ConnectionStatus.CANCELLED, f.controller.state().connectionStatus);
        assertFalse(f.states.stream().anyMatch(row -> row.connectionStatus == ConnectionStatus.ENDED));
        assertEquals(1, f.connection.starts); assertTrue(f.controller.state().canConnect());
    }
    @Test public void stoppedConnectionKeepsLeaseAndDoesNotReloadUntilRealCloseAndForeground() {
        Fixture f = selectedReady(); assertTrue(f.controller.connect(f.controller.state())); int count = f.states.size();
        f.controller.stop(); assertEquals(1, f.connection.current.cancels);
        assertEquals(Status.INACTIVE, f.controller.state().status); assertFalse(f.controller.refreshConnectionStatus());
        f.connection.finish(ConnectionStatus.CANCELLED); f.drain();
        assertEquals(count, f.states.size()); assertEquals(Collections.singletonList("load"), f.storage.calls);
        assertEquals(ConnectionStatus.IDLE, f.controller.state().connectionStatus);
        f.controller.start(f.states::add); f.drain(); assertTrue(f.controller.state().canConnect()); assertEquals(1, f.connection.starts);
    }
    @Test public void repeatedForegroundAndLateTerminalCannotReviveOrAutoReconnect() {
        Fixture f = selectedReady(); assertTrue(f.controller.connect(f.controller.state()));
        for (int i = 0; i < 30; i++) { f.controller.stop(); f.controller.start(f.states::add); }
        assertEquals(1, f.connection.current.cancels); assertEquals(1, f.connection.starts); assertTrue(f.serial.queue.isEmpty());
        f.connection.finish(ConnectionStatus.ENDED); f.drain();
        assertEquals(ConnectionStatus.IDLE, f.controller.state().connectionStatus); assertEquals(Status.READY, f.controller.state().status);
        assertFalse(f.states.stream().anyMatch(row -> row.connectionStatus == ConnectionStatus.ENDED));
        assertEquals(Arrays.asList("load", "load"), f.storage.calls);
    }
    @Test public void observerStopBeforeConnectStartAllocatesNothing() {
        Fixture f = selectedReady(); f.controller.start(state -> {
            if (state.connectionStatus == ConnectionStatus.CONNECTING) f.controller.stop();
        }); f.drain();
        assertTrue(f.controller.connect(f.controller.state())); assertEquals(0, f.connection.starts);
        assertEquals(Status.INACTIVE, f.controller.state().status); assertTrue(f.serial.queue.isEmpty());
    }
    @Test public void stopDuringConnectStartCancelsReturnedExactAttemptAndWaits() {
        Fixture f = selectedReady(); f.connection.onStart = f.controller::stop;
        assertTrue(f.controller.connect(f.controller.state())); assertEquals(1, f.connection.current.cancels);
        assertEquals(Status.INACTIVE, f.controller.state().status); assertEquals(Collections.singletonList("load"), f.storage.calls);
        f.connection.finish(ConnectionStatus.CANCELLED); f.drain(); assertEquals(Collections.singletonList("load"), f.storage.calls);
    }
    @Test public void stateQueryReentryCannotPublishActiveAfterClose() {
        Fixture f = selectedReady(); assertTrue(f.controller.connect(f.controller.state()));
        f.connection.current.nativeState = ViewerConnectionSession.State.ACTIVE;
        f.connection.current.onState = f.controller::close; int count = f.states.size();
        assertFalse(f.controller.refreshConnectionStatus()); assertEquals(Status.CLOSED, f.controller.state().status);
        assertEquals(count, f.states.size()); assertEquals(1, f.connection.current.cancels);
        f.connection.finish(ConnectionStatus.ENDED); f.drain(); assertEquals(count, f.states.size()); assertEquals(1, f.serial.closes);
    }
    @Test public void synchronousConnectionTerminalUsesMainOwnerAndFreshReadback() {
        Fixture f = selectedReady(); f.connection.inlineTerminal = ConnectionStatus.FAILED;
        assertTrue(f.controller.connect(f.controller.state())); assertEquals(ConnectionStatus.CONNECTING, f.controller.state().connectionStatus);
        assertEquals(1, f.main.queue.size()); f.drain();
        assertEquals(ConnectionStatus.FAILED, f.controller.state().connectionStatus); assertTrue(f.controller.state().canConnect());
        assertEquals(Arrays.asList("load", "load"), f.storage.calls);
    }
    @Test public void oldConnectionFutureCannotRetireSuccessorOrMutateNewForeground() {
        Fixture f = selectedReady(); assertTrue(f.controller.connect(f.controller.state()));
        FakeConnectionAttempt old = f.connection.current; f.connection.finish(ConnectionStatus.FAILED); f.drain();
        assertTrue(f.controller.connect(f.controller.state())); assertFalse(old.result.complete(ConnectionStatus.ENDED)); f.main.drain();
        assertEquals(ConnectionStatus.CONNECTING, f.controller.state().connectionStatus); assertEquals(2, f.connection.starts);
        f.connection.finish(ConnectionStatus.ENDED); f.controller.stop(); List<State> newer = new ArrayList<>(); f.controller.start(newer::add);
        f.drain(); assertFalse(newer.stream().anyMatch(row -> row.connectionStatus == ConnectionStatus.ENDED));
        assertEquals(ConnectionStatus.IDLE, f.controller.state().connectionStatus); assertEquals(2, f.connection.starts);
    }
    @Test public void malformedOrExceptionalConnectionCompletionBlocksEveryMutation() {
        for (ConnectionStatus invalid : Arrays.asList(null, ConnectionStatus.IDLE, ConnectionStatus.CONNECTING,
                ConnectionStatus.ACTIVE, ConnectionStatus.CANCELLING, ConnectionStatus.CLEANUP_UNPROVEN)) {
            Fixture f = selectedReady(); State before = f.controller.state(); assertTrue(f.controller.connect(before));
            f.connection.finish(invalid); f.drain(); assertConnectionBlocked(f, before);
        }
        Fixture f = selectedReady(); State before = f.controller.state(); assertTrue(f.controller.connect(before));
        f.connection.current.result.completeExceptionally(new IllegalStateException("fixture")); f.drain(); assertConnectionBlocked(f, before);
    }
    @Test public void uncertainConnectionCancellationRemainsStickyAfterCleanTerminal() {
        Fixture f = selectedReady(); State before = f.controller.state(); assertTrue(f.controller.connect(before));
        f.connection.current.failCancel = true; f.controller.disconnect();
        f.connection.finish(ConnectionStatus.CANCELLED); f.drain(); assertConnectionBlocked(f, before);
    }
    @Test public void nullAttemptOrUnobservableCompletionCannotAuthorizeRetry() {
        Fixture missing = selectedReady(); State before = missing.controller.state(); missing.connection.nullAttempt = true;
        assertTrue(missing.controller.connect(before)); missing.drain(); assertConnectionBlocked(missing, before);
        for (int mode = 1; mode <= 3; mode++) {
            Fixture f = selectedReady(); State expected = f.controller.state(); f.connection.completionMode = mode;
            assertTrue(f.controller.connect(expected)); f.drain(); assertConnectionBlocked(f, expected);
            assertEquals(1, f.connection.current.cancels);
        }
    }
    @Test public void connectionStartRefusalReloadsWithoutClaimingConnectionOrChangingIdentity() {
        Fixture f = selectedReady(); f.connection.failStart = true;
        assertTrue(f.controller.connect(f.controller.state())); f.drain();
        assertEquals(ConnectionStatus.FAILED, f.controller.state().connectionStatus); assertTrue(f.controller.state().canConnect());
        assertEquals(Arrays.asList("load", "load"), f.storage.calls); assertEquals(VIEWER, f.storage.data.viewerID);
        assertFalse(f.states.stream().anyMatch(row -> row.connectionStatus == ConnectionStatus.ACTIVE));
    }
    @Test public void pairingAndExternalProcessOwnerPreventConnectBeforeAnyPreparation() {
        Fixture f = selectedReady(); State old = f.controller.state(); assertTrue(f.controller.pair(old, invitation()));
        assertFalse(f.controller.connect(old)); assertFalse(f.controller.connect(f.controller.state())); assertEquals(0, f.connection.starts);
        Fixture external = selectedReady(); State ready = external.controller.state(); external.pairing.busy = true;
        assertFalse(external.controller.connect(ready)); assertEquals(0, external.connection.starts);
        assertEquals(PairingStatus.BLOCKED, external.controller.state().pairingStatus);
    }
    @Test public void connectionAPIsRequireMainOwnerWithoutAllocating() {
        Fixture f = selectedReady(); State ready = f.controller.state(); f.main.owner = false;
        try { f.controller.connect(ready); fail("wrong owner"); } catch (IllegalStateException expected) { }
        try { f.controller.disconnect(); fail("wrong owner"); } catch (IllegalStateException expected) { }
        try { f.controller.refreshConnectionStatus(); fail("wrong owner"); } catch (IllegalStateException expected) { }
        assertEquals(0, f.connection.starts);
    }
    @Test public void inlineTerminalDuringCancelCannotOverwriteFreshReload() {
        Fixture f = selectedReady(); assertTrue(f.controller.connect(f.controller.state())); f.main.inline = true;
        f.connection.current.onCancel = () -> f.connection.finish(ConnectionStatus.CANCELLED);
        f.controller.disconnect(); assertEquals(Status.LOADING, f.controller.state().status);
        assertEquals(ConnectionStatus.CANCELLED, f.controller.state().connectionStatus);
        f.drain(); assertEquals(Status.READY, f.controller.state().status); assertTrue(f.controller.state().canConnect());
        assertEquals(1, f.connection.current.cancels);
    }
    @Test public void terminalInsideThrowingCancelCannotReleaseAdmissionBeforeReturn() {
        Fixture f = selectedReady(); State before = f.controller.state(); assertTrue(f.controller.connect(before));
        f.main.inline = true; f.connection.current.failCancel = true;
        f.connection.current.onCancel = () -> {
            f.connection.finish(ConnectionStatus.CANCELLED);
            assertTrue(f.serial.queue.isEmpty()); assertFalse(f.controller.state().canConnect());
            assertFalse(f.controller.connect(before)); assertFalse(f.controller.pair(f.controller.state(), invitation()));
        };
        f.controller.disconnect(); f.drain(); assertConnectionBlocked(f, before);
        assertEquals(1, f.connection.current.cancels);
    }
    @Test public void reentrantCloseFromRestartCancellationCannotBeOverwrittenByStart() {
        Fixture f = selectedReady(); assertTrue(f.controller.connect(f.controller.state()));
        f.controller.start(state -> {
            if (state.connectionStatus == ConnectionStatus.CANCELLING) f.controller.close();
        });
        assertEquals(Status.CLOSED, f.controller.state().status); assertEquals(1, f.serial.closes);
        assertEquals(1, f.connection.current.cancels); f.connection.finish(ConnectionStatus.CANCELLED); f.drain();
        assertEquals(Status.CLOSED, f.controller.state().status); assertEquals(Collections.singletonList("load"), f.storage.calls);
    }
    @Test public void oldThrowingStateQueryCannotCancelItsReentrantSuccessor() {
        Fixture f = selectedReady(); assertTrue(f.controller.connect(f.controller.state()));
        FakeConnectionAttempt old = f.connection.current; old.failState = true; f.main.inline = true;
        old.onState = () -> {
            f.connection.finish(ConnectionStatus.ENDED); f.drain();
            assertTrue(f.controller.connect(f.controller.state()));
        };
        assertFalse(f.controller.refreshConnectionStatus()); assertEquals(2, f.connection.starts);
        assertEquals(0, f.connection.current.cancels); assertEquals(ConnectionStatus.CONNECTING, f.controller.state().connectionStatus);
    }
    @Test public void inlineCallbackBeforeThrowingAttachmentNeverReleasesAdmission() {
        Fixture f = selectedReady(); State before = f.controller.state(); f.main.inline = true;
        f.connection.completionMode = 3; assertTrue(f.controller.connect(before)); f.drain();
        assertConnectionBlocked(f, before); assertEquals(1, f.connection.current.cancels);
    }
    @Test public void nativeStatusFailureRequestsCloseButStillWaitsForDrain() {
        Fixture f = selectedReady(); assertTrue(f.controller.connect(f.controller.state())); f.connection.current.failState = true;
        assertFalse(f.controller.refreshConnectionStatus()); assertEquals(1, f.connection.current.cancels);
        assertEquals(ConnectionStatus.CANCELLING, f.controller.state().connectionStatus); assertFalse(f.controller.refresh());
        f.connection.finish(ConnectionStatus.CANCELLED); f.drain(); assertTrue(f.controller.state().canConnect());
    }
    @Test public void cancellationWhileObtainingCompletionIsForwardedOnlyOnce() {
        Fixture f = selectedReady(); f.connection.onCompletion = f.controller::stop;
        assertTrue(f.controller.connect(f.controller.state())); assertEquals(1, f.connection.current.cancels);
        assertEquals(Status.INACTIVE, f.controller.state().status);
        f.connection.finish(ConnectionStatus.CANCELLED); f.drain(); assertEquals(Collections.singletonList("load"), f.storage.calls);
    }
    @Test public void closeCancelsConnectionOnceAndLateCompletionCannotPublishOrReload() {
        Fixture f = selectedReady(); assertTrue(f.controller.connect(f.controller.state())); int count = f.states.size();
        f.controller.close(); f.controller.close(); assertEquals(1, f.connection.current.cancels);
        f.connection.finish(ConnectionStatus.ENDED); f.drain(); f.controller.start(f.states::add);
        assertEquals(Status.CLOSED, f.controller.state().status); assertEquals(count, f.states.size()); assertEquals(1, f.serial.closes);
        assertEquals(Collections.singletonList("load"), f.storage.calls); assertFalse(f.controller.connect(f.controller.state()));
    }
    private static void assertConnectionBlocked(Fixture f, State old) {
        assertEquals(ConnectionStatus.CLEANUP_UNPROVEN, f.controller.state().connectionStatus);
        for (int i = 0; i < 3; i++) { f.controller.stop(); f.controller.start(f.states::add); }
        State blocked = f.controller.state(); assertEquals(Status.UNAVAILABLE, blocked.status);
        assertFalse(blocked.canConnect()); assertFalse(blocked.canPair()); assertFalse(blocked.canInitialize());
        assertFalse(blocked.canChangeLibrary()); assertFalse(f.controller.refresh()); assertFalse(f.controller.connect(old));
        assertFalse(f.controller.connect(blocked)); assertFalse(f.controller.pair(blocked, invitation()));
        assertFalse(f.controller.select(HOST, old)); assertFalse(f.controller.forget(HOST, old));
        assertFalse(f.controller.abandon(SLOT, old)); assertFalse(f.controller.initialize(blocked));
        assertEquals(Collections.singletonList("load"), f.storage.calls); assertEquals(1, f.connection.starts);
    }
    private static PairingInvitation invitation() {
        return PairingInvitation.parseManual("04002-0G30G-2GC1R-81450-P30D1-R7H04-8J2EZ-G8AG3");
    }
    private static Fixture ready() {
        Fixture f = new Fixture(true); f.controller.start(f.states::add); f.drain(); return f;
    }
    private static Fixture selectedReady() {
        Fixture f = new Fixture(true, true); f.selectInitial(Phase.ACTIVE);
        f.controller.start(f.states::add); f.drain(); return f;
    }
    private static final class Fixture {
        final FakeStorage storage = new FakeStorage(); final FakeSerial serial = new FakeSerial(); final FakeMain main = new FakeMain();
        final FakePairing pairing = new FakePairing();
        final FakeConnection connection = new FakeConnection(pairing);
        final List<State> states = new ArrayList<>(); final ViewerLibraryController controller;
        Fixture(boolean supported) { this(supported, false); }
        Fixture(boolean supported, boolean connectAvailable) {
            controller = new ViewerLibraryController(storage, serial, main, supported, pairing, connectAvailable ? connection : null);
        }
        void selectInitial(Phase phase) {
            storage.data = new Data(VIEWER, 10, 20, HOST, null,
                    Collections.singletonList(new Mac(HOST, PAIR, "Actual saved Mac", phase)), storage.data.pending);
        }
        void drain() {
            for (int i = 0; i < 20 && (!serial.queue.isEmpty() || !main.queue.isEmpty()); i++) {
                if (!serial.queue.isEmpty()) serial.next(); main.drain();
            }
            assertTrue("unexpected continuing controller work", serial.queue.isEmpty() && main.queue.isEmpty());
        }
    }
    private static final class FakePairing implements ViewerLibraryController.PairingPort {
        boolean busy, failStart; int starts; long catalog, selection; Runnable onStart;
        PairingStatus inlineTerminal; FakeAttempt current;
        @Override public boolean isAttemptInFlight() { return busy; }
        @Override public ViewerLibraryController.PairingAttempt start(PairingInvitation invitation, long catalog, long selection) {
            starts++; this.catalog = catalog; this.selection = selection;
            if (failStart) throw new IllegalStateException("fixture");
            busy = true; current = new FakeAttempt(); if (onStart != null) onStart.run();
            if (inlineTerminal != null) finish(inlineTerminal);
            return current;
        }
        void finish(PairingStatus terminal) {
            busy = terminal == PairingStatus.CLEANUP_UNPROVEN;
            current.result.complete(terminal);
        }
    }
    private static final class FakeAttempt implements ViewerLibraryController.PairingAttempt {
        final CompletableFuture<PairingStatus> result = new CompletableFuture<>(); int cancels; boolean failCancel;
        @Override public void cancel() { cancels++; if (failCancel) throw new IllegalStateException("fixture"); }
        @Override public CompletionStage<PairingStatus> completion() { return result; }
    }
    private static final class FakeConnection implements ViewerLibraryController.ConnectionPort {
        final FakePairing process;
        int starts, completionMode; UUID host; long catalog, selection;
        boolean failStart, nullAttempt; Runnable onStart, onCompletion; ConnectionStatus inlineTerminal; FakeConnectionAttempt current;
        FakeConnection(FakePairing process) { this.process = process; }
        @Override public ViewerLibraryController.ConnectionAttempt start(UUID host, long catalog, long selection) {
            starts++; this.host = host; this.catalog = catalog; this.selection = selection;
            if (failStart) throw new IllegalStateException("preallocation fixture");
            process.busy = true; current = new FakeConnectionAttempt(completionMode);
            current.onCompletion = onCompletion;
            if (onStart != null) onStart.run();
            if (inlineTerminal != null) finish(inlineTerminal);
            return nullAttempt ? null : current;
        }
        void finish(ConnectionStatus terminal) {
            process.busy = terminal != ConnectionStatus.ENDED && terminal != ConnectionStatus.CANCELLED && terminal != ConnectionStatus.FAILED;
            current.result.complete(terminal);
        }
    }
    private static final class FakeConnectionAttempt implements ViewerLibraryController.ConnectionAttempt {
        final CompletableFuture<ConnectionStatus> result;
        final int completionMode;
        int cancels; boolean failCancel, failState; Runnable onState, onCancel, onCompletion;
        ViewerConnectionSession.State nativeState = ViewerConnectionSession.State.PREPARING;
        FakeConnectionAttempt(int completionMode) {
            this.completionMode = completionMode;
            result = completionMode == 3 ? new CompletableFuture<ConnectionStatus>() {
                @Override public CompletableFuture<ConnectionStatus> whenComplete(
                        BiConsumer<? super ConnectionStatus, ? super Throwable> action) {
                    action.accept(ConnectionStatus.ENDED, null);
                    throw new IllegalStateException("attachment failed after inline callback");
                }
            } : new CompletableFuture<>();
        }
        @Override public void cancel() {
            cancels++; if (onCancel != null) onCancel.run(); if (failCancel) throw new IllegalStateException("fixture");
        }
        @Override public ViewerConnectionSession.State state() {
            if (onState != null) onState.run(); if (failState) throw new IllegalStateException("fixture"); return nativeState;
        }
        @Override public CompletionStage<ConnectionStatus> completion() {
            if (onCompletion != null) onCompletion.run();
            if (completionMode == 1) return null;
            if (completionMode == 2) throw new IllegalStateException("fixture");
            return result;
        }
    }
    private static final class FakeSerial implements ViewerLibraryController.SerialPort {
        final ArrayDeque<Runnable> queue = new ArrayDeque<>(); int closes;
        @Override public void execute(Runnable work) { queue.add(work); }
        @Override public void close() { closes++; }
        void next() { queue.remove().run(); }
    }
    private static final class FakeMain implements ViewerLibraryController.MainPort {
        final ArrayDeque<Runnable> queue = new ArrayDeque<>(); boolean owner = true, inline;
        @Override public void checkOwner() { if (!owner) throw new IllegalStateException("wrong owner"); }
        @Override public void execute(Runnable work) { if (inline) work.run(); else queue.add(work); }
        void drain() { while (!queue.isEmpty()) queue.remove().run(); }
    }
    private static final class FakeStorage implements ViewerLibraryController.StoragePort {
        Data data = new Data(VIEWER, 10, 20, null, null,
                Collections.singletonList(new Mac(HOST, PAIR, "Actual saved Mac", Phase.ACTIVE)),
                Collections.singletonList(new PendingEnrollment(SLOT)));
        final List<String> calls = new ArrayList<>(); boolean failLoad, failInitialize, failChange;
        String lastAction; UUID lastTarget; long lastCatalog, lastSelection; Runnable onChange;
        @Override public Data load() throws Exception { calls.add("load"); if (failLoad) throw new Exception("fixture"); return data; }
        @Override public Data initialize() throws Exception {
            calls.add("initialize"); if (failInitialize) throw new Exception("fixture");
            data = new Data(VIEWER, 0, 0, null, null, Collections.emptyList(), Collections.emptyList()); return data;
        }
        private void change(String action, UUID target, long catalog, long selection) throws Exception {
            calls.add(action); lastAction = action; lastTarget = target; lastCatalog = catalog; lastSelection = selection;
            assertEquals(data.catalogRevision, catalog); assertEquals(data.selectionRevision, selection);
            if (failChange) throw new Exception("fixture"); if (onChange != null) onChange.run();
        }
        @Override public Data select(UUID host, long catalog, long selection) throws Exception {
            change("select", host, catalog, selection);
            data = new Data(VIEWER, catalog + 1, selection + 1, host, null, data.macs, data.pending); return data;
        }
        @Override public Data forget(UUID host, long catalog, long selection) throws Exception {
            change("forget", host, catalog, selection);
            data = new Data(VIEWER, catalog + 1, selection + 1, null, null, Collections.emptyList(), data.pending); return data;
        }
        @Override public Data abandon(UUID slot, long catalog, long selection) throws Exception {
            change("abandon", slot, catalog, selection);
            data = new Data(VIEWER, catalog + 1, selection + 1, data.selectedMacID, null, data.macs, Collections.emptyList()); return data;
        }
    }
}
