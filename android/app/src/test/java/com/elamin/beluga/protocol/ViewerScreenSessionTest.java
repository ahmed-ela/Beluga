package com.elamin.beluga.protocol;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import java.util.function.BiConsumer;
import java.util.function.BooleanSupplier;
import java.util.function.Consumer;
import org.junit.Test;
import com.elamin.beluga.protocol.ViewerScreenSession.Failure;
import com.elamin.beluga.protocol.ViewerScreenSession.PresentationLease;
import com.elamin.beluga.protocol.ViewerScreenSession.Scene;
import com.elamin.beluga.protocol.ViewerScreenSession.State;

/** Fake exact native-write boundaries only; no rendered frames, input, socket or device proof. */
public final class ViewerScreenSessionTest {
    @Test public void startsInactiveAndNeedsExplicitHealthyActiveShow() {
        Fixture f = new Fixture();
        assertEquals(State.INACTIVE, f.session.snapshot().state);
        assertNull(f.session.show()); assertNull(f.session.requestKeyFrame());
        f.session.scene(Scene.ACTIVE);
        assertNull(f.session.show()); assertEquals(0, f.transport.writes.size());
        assertFalse(f.session.admitHealthy(new Object(), f.control));
        assertFalse(f.session.admitHealthy(f.peer, new Object()));
        assertTrue(f.session.admitHealthy(f.peer, f.control));
        assertEquals(0, f.transport.writes.size()); assertEquals("1", f.session.show());
        assertEquals("{\"command\":{\"command\":\"showScreen\",\"id\":1},\"kind\":\"command\",\"version\":2}", f.write(0).text());
        assertEquals(State.SHOW_PENDING, f.session.snapshot().state);
        assertNull(f.session.presentationLease()); assertNull(f.session.show());
        assertEquals(1, f.transport.writes.size()); assertTrue(f.failures.isEmpty());
    }

    @Test public void earlyMatchingAckCannotPresentBeforeExactWriteCompletes() {
        Fixture f = ready(); f.session.show(); f.ack("1", true);
        assertNull(f.session.presentationLease()); assertFalse(f.session.snapshot().presentationAllowed);
        assertEquals(State.SHOW_PENDING, f.session.snapshot().state);
        f.write(0).succeed(); assertVisible(f);
        assertTrue(f.failures.isEmpty());
    }

    @Test public void exactWriteCannotPresentBeforeFreshCurrentActiveAck() {
        Fixture f = ready(); f.session.show(); f.write(0).succeed();
        assertNull(f.session.presentationLease()); f.ack("99", true);
        assertNull(f.session.presentationLease()); f.ack("1", true); assertVisible(f);
    }

    @Test public void inlineAckAndCompletionWaitForNormalCallbackAttachmentReturn() {
        Fixture f = ready();
        f.transport.duringSend = write -> { f.ack("1", true); write.succeed(); };
        assertEquals("1", f.session.show()); assertVisible(f);
        assertEquals(1, f.transport.writes.size()); assertTrue(f.failures.isEmpty());
    }

    @Test public void throwingAttachmentAfterInlineSuccessDoesNotGrantPresentation() {
        Fixture f = ready(); f.transport.throwAfterInlineCompletion = true;
        f.transport.duringSend = write -> { f.ack("1", true); write.succeed(); };
        f.session.show(); assertClosed(f, Failure.SEND);
        assertNull(f.session.presentationLease()); assertFalse(f.write(0).guard.getAsBoolean());
    }

    @Test public void backgroundBeforeShowWriteCompletesQueuesRequiredHideAndRevokesShowGuard() {
        Fixture f = ready(); f.session.show(); f.ack("1", true);
        f.session.scene(Scene.BACKGROUND);
        assertEquals(State.HIDE_PENDING, f.session.snapshot().state);
        assertFalse(f.write(0).guard.getAsBoolean()); assertNull(f.session.presentationLease());
        assertEquals("2", f.session.snapshot().currentRequestID);
        assertEquals(1, f.transport.writes.size());
        f.ack("1", true); assertFalse(f.session.snapshot().presentationAllowed);
        f.write(0).refuse(); // Expected revoked old write; cannot erase the queued Hide.
        assertEquals(2, f.transport.writes.size()); assertTrue(f.write(1).guard.getAsBoolean());
        assertEquals("{\"command\":{\"command\":\"hideScreen\",\"id\":2},\"kind\":\"command\",\"version\":2}", f.write(1).text());
        f.ack("2", false); assertEquals(State.HIDE_PENDING, f.session.snapshot().state);
        f.write(1).succeed(); assertEquals(State.INACTIVE, f.session.snapshot().state);
        assertTrue(f.failures.isEmpty()); assertNull(f.session.presentationLease());
        f.session.scene(Scene.ACTIVE); assertEquals(2, f.transport.writes.size());
        assertNull(f.session.presentationLease()); // No automatic Show on foregrounding.
    }

    @Test public void inactiveRetainsAcknowledgedShowButInvalidatesOldPresentationLease() {
        Fixture f = shown(); PresentationLease before = f.session.presentationLease();
        f.session.scene(Scene.INACTIVE);
        assertEquals(State.ACTIVE, f.session.snapshot().state); assertFalse(f.session.snapshot().presentationAllowed);
        assertFalse(f.session.permits(before, f.peer, f.control, f.track));
        assertNull(f.session.presentationLease()); assertEquals(1, f.transport.writes.size());
        f.session.scene(Scene.ACTIVE); assertEquals(1, f.transport.writes.size());
        assertFalse(f.session.permits(before, f.peer, f.control, f.track));
        assertVisible(f); // Fresh lease for the retained acknowledged Show, not a new Show.
    }

    @Test public void hideAcceptanceSynchronouslyRevokesEvenBeforeItsWriteOrAck() {
        Fixture f = shown(); PresentationLease before = f.session.presentationLease();
        assertEquals("2", f.session.hide());
        assertFalse(f.session.permits(before, f.peer, f.control, f.track));
        assertNull(f.session.presentationLease()); assertEquals(State.HIDE_PENDING, f.session.snapshot().state);
        assertEquals("2", f.session.hide()); assertEquals(2, f.transport.writes.size());
        f.write(1).succeed(); assertEquals(State.HIDE_PENDING, f.session.snapshot().state);
        f.ack("2", false); assertEquals(State.INACTIVE, f.session.snapshot().state);
        assertNull(f.session.hide()); assertEquals(2, f.transport.writes.size());
    }

    @Test public void activeForHideFailsParentOnceAndLateCallbacksCannotRevive() {
        Fixture f = shown(); f.session.hide(); f.ack("2", true);
        assertClosed(f, Failure.ACKNOWLEDGEMENT); assertFalse(f.write(1).guard.getAsBoolean());
        f.write(1).future.complete(null); f.ack("2", false); f.ack("1", true);
        f.session.scene(Scene.ACTIVE); assertNull(f.session.show()); assertClosed(f, Failure.ACKNOWLEDGEMENT);
    }

    @Test public void duplicateSameAckIsHarmlessButConflictingCurrentAckFailsClosed() {
        Fixture f = shown(); f.ack("1", true); f.ack("1", true); assertVisible(f);
        f.ack("1", false); assertClosed(f, Failure.ACKNOWLEDGEMENT);
    }

    @Test public void staleAndUnknownAckCannotReviveANewerVisibilityOperation() {
        Fixture f = shown(); PresentationLease first = f.session.presentationLease();
        f.session.hide(); f.write(1).succeed(); f.ack("2", false);
        assertEquals("3", f.session.show()); f.write(2).succeed();
        f.ack("1", true); f.ack("2", true); f.ack("999", true);
        assertNull(f.session.presentationLease()); assertTrue(f.failures.isEmpty());
        f.ack("3", true); assertVisible(f);
        assertFalse(f.session.permits(first, f.peer, f.control, f.track));
    }

    @Test public void wrongPeerControlOrTrackNeverGrantsOrPoisonsCurrentLifetime() {
        Fixture f = ready(); f.session.show(); f.write(0).succeed();
        f.session.receive(new Object(), f.control, ack("1", true));
        f.session.receive(f.peer, new Object(), ack("1", true));
        f.session.receive(new Object(), new Object(), new byte[] {(byte) 0xff});
        assertNull(f.session.presentationLease()); assertTrue(f.failures.isEmpty());
        f.session.loseHealth(new Object(), f.control); f.ack("1", true); assertVisible(f);
        PresentationLease lease = f.session.presentationLease();
        assertFalse(f.session.permits(lease, new Object(), f.control, f.track));
        assertFalse(f.session.permits(lease, f.peer, new Object(), f.track));
        assertFalse(f.session.permits(lease, f.peer, f.control, new Object()));
        Fixture other = shown(); assertFalse(f.session.permits(other.session.presentationLease(), f.peer, f.control, f.track));
        f.session.loseHealth(f.peer, f.control); assertClosed(f, Failure.HEALTH);
    }

    @Test public void lateAckWithoutPollFailsInsteadOfGrantingPresentation() {
        Fixture f = ready(); f.session.show(); f.write(0).succeed();
        f.clock.set(ViewerScreenSession.ACKNOWLEDGEMENT_NANOS); f.ack("1", true);
        assertClosed(f, Failure.TIMEOUT); assertNull(f.session.presentationLease());
    }

    @Test public void earlyAckThenLateCompletionWithoutPollCannotGrantPresentation() {
        Fixture f = ready(); f.session.show(); f.ack("1", true); assertTrue(f.write(0).guard.getAsBoolean());
        f.clock.set(ViewerScreenSession.ACKNOWLEDGEMENT_NANOS);
        f.write(0).future.complete(null); assertClosed(f, Failure.TIMEOUT);
    }

    @Test public void lateNativeWriteGuardAndLeaseCheckExpireUnfinishedRequestsWithoutPoll() {
        Fixture f = ready(); f.session.show();
        f.clock.set(ViewerScreenSession.ACKNOWLEDGEMENT_NANOS);
        assertFalse(f.write(0).guard.getAsBoolean()); assertClosed(f, Failure.TIMEOUT);
        Fixture g = shown(); PresentationLease lease = g.session.presentationLease();
        assertEquals("2", g.session.requestKeyFrame());
        g.clock.set(ViewerScreenSession.ACKNOWLEDGEMENT_NANOS);
        assertFalse(g.session.permits(lease, g.peer, g.control, g.track)); assertClosed(g, Failure.TIMEOUT);
    }

    @Test public void pollingTimeoutAndClockRollbackPublishOnlyOneParentFailure() {
        Fixture f = ready(); f.session.show();
        f.clock.set(ViewerScreenSession.ACKNOWLEDGEMENT_NANOS - 1); f.session.poll();
        assertEquals(State.SHOW_PENDING, f.session.snapshot().state);
        f.clock.incrementAndGet(); f.session.poll(); f.session.poll(); assertClosed(f, Failure.TIMEOUT);
        Fixture g = shown(); g.clock.set(-1); g.session.poll(); assertClosed(g, Failure.CLOCK);
    }

    @Test public void refusedCurrentHideFailsWhileParentCloseSimplyRevokes() {
        Fixture f = shown(); f.session.hide(); f.write(1).refuse(); assertClosed(f, Failure.SEND);
        Fixture g = shown(); PresentationLease lease = g.session.presentationLease();
        g.session.close(); assertFalse(g.session.permits(lease, g.peer, g.control, g.track));
        g.ack("1", true); assertNull(g.session.show()); assertTrue(g.failures.isEmpty());
    }

    @Test public void inactiveShowAckIsNotPresentationAndAllowsOnlyExplicitRetry() {
        Fixture f = ready(); f.session.show(); f.write(0).succeed(); f.ack("1", false);
        assertEquals(State.INACTIVE, f.session.snapshot().state); assertNull(f.session.presentationLease());
        assertTrue(f.failures.isEmpty()); assertEquals(1, f.transport.writes.size());
        assertEquals("2", f.session.show()); f.write(1).succeed(); f.ack("2", true); assertVisible(f);
    }

    @Test public void keyFrameNeedsCurrentShowAndDoesNotReplaceItsPresentationLease() {
        Fixture f = ready(); assertNull(f.session.requestKeyFrame()); f.session.show();
        assertNull(f.session.requestKeyFrame()); f.write(0).succeed(); f.ack("1", true);
        PresentationLease lease = f.session.presentationLease(); assertEquals("2", f.session.requestKeyFrame());
        assertEquals("{\"command\":{\"command\":\"requestKeyFrame\",\"id\":2},\"kind\":\"command\",\"version\":2}", f.write(1).text());
        assertTrue(f.session.permits(lease, f.peer, f.control, f.track));
        f.write(1).succeed(); f.ack("2", true);
        assertTrue(f.session.permits(lease, f.peer, f.control, f.track));
        f.session.scene(Scene.INACTIVE); assertNull(f.session.requestKeyFrame());
    }

    @Test public void hideSupersedesHeldKeyFrameAndLateKeyFrameCannotRevive() {
        Fixture f = shown(); f.session.requestKeyFrame(); f.session.hide();
        assertEquals("3", f.session.snapshot().currentRequestID); assertNull(f.session.presentationLease());
        assertFalse(f.write(1).guard.getAsBoolean()); f.ack("2", true); f.write(1).refuse();
        assertEquals(3, f.transport.writes.size()); f.write(2).succeed(); f.ack("3", false);
        assertEquals(State.INACTIVE, f.session.snapshot().state); assertTrue(f.failures.isEmpty());
    }

    @Test public void unsignedIDsCrossSignedBoundaryButNeverEmitMaximumOrWrap() {
        Fixture high = ready("9223372036854775808");
        assertEquals("9223372036854775808", high.session.show());
        assertTrue(high.write(0).text().contains("\"id\":9223372036854775808"));
        high.write(0).succeed(); high.ack("9223372036854775808", true); assertVisible(high);
        assertEquals("9223372036854775809", high.session.hide());
        Fixture last = ready("18446744073709551614");
        assertEquals("18446744073709551614", last.session.show());
        last.write(0).succeed(); last.ack("18446744073709551614", true); assertVisible(last);
        assertNull(last.session.hide()); assertClosed(last, Failure.ID_EXHAUSTED);
        assertEquals(1, last.transport.writes.size());
        Fixture exhausted = ready("18446744073709551615");
        assertNull(exhausted.session.show()); assertEquals(0, exhausted.transport.writes.size());
        assertClosed(exhausted, Failure.ID_EXHAUSTED);
        for (String invalid : new String[] {"0", "01", "-1", "+1", "1.0", "1e0", "18446744073709551616"}) {
            try { new Fixture(invalid); fail("Accepted noncanonical or overflowing ID"); }
            catch (IllegalArgumentException expected) { assertEquals("Invalid Beluga screen-control lifetime", expected.getMessage()); }
        }
    }

    @Test public void malformedOrUnsupportedCurrentScreenMessageFailsWithoutInputAuthority() {
        Fixture f = ready(); f.session.show(); f.session.receive(f.peer, f.control, new byte[] {(byte) 0xff});
        assertClosed(f, Failure.PROTOCOL);
        Fixture g = shown(); g.session.receive(g.peer, g.control,
                "{\"version\":2,\"kind\":\"screenMediaReady\",\"screenMediaReady\":{}}".getBytes(StandardCharsets.UTF_8));
        assertClosed(g, Failure.PROTOCOL);
        Fixture h = shown(); h.session.receive(h.peer, h.control,
                "{\"version\":2,\"kind\":\"remoteMediaState\",\"remoteMediaState\":{}}".getBytes(StandardCharsets.UTF_8));
        assertVisible(h); assertTrue(h.failures.isEmpty());
    }

    @Test(timeout = 5_000) public void concurrentClockReadsAreSerializedWithStateObservation() throws Exception {
        OrderedClock clock = new OrderedClock(); FakeTransport transport = new FakeTransport();
        List<Failure> failures = new ArrayList<>(); Object peer = new Object(), control = new Object();
        ViewerScreenSession session = new ViewerScreenSession(peer, control, new Object(), transport, clock, failures::add);
        assertTrue(session.admitHealthy(peer, control)); clock.armed = true;
        Thread first = new Thread(() -> session.scene(Scene.ACTIVE), "Beluga test clock first");
        CountDownLatch secondStarted = new CountDownLatch(1);
        Thread second = new Thread(() -> { secondStarted.countDown(); session.poll(); }, "Beluga test clock second");
        first.start(); assertTrue(clock.firstRead.await(1, TimeUnit.SECONDS)); second.start();
        try {
            assertTrue(secondStarted.await(1, TimeUnit.SECONDS));
            assertFalse("Second caller sampled outside state lock", clock.secondRead.await(100, TimeUnit.MILLISECONDS));
        } finally { clock.releaseFirst.countDown(); first.join(1_000); second.join(1_000); }
        assertFalse(first.isAlive()); assertFalse(second.isAlive()); assertTrue(failures.isEmpty());
        assertEquals(Scene.ACTIVE, session.snapshot().scene); assertEquals(State.INACTIVE, session.snapshot().state);
    }

    private static Fixture ready() { return ready("1"); }
    private static Fixture ready(String initialID) {
        Fixture f = new Fixture(initialID); assertTrue(f.session.admitHealthy(f.peer, f.control));
        f.session.scene(Scene.ACTIVE); return f;
    }
    private static Fixture shown() {
        Fixture f = ready(); f.session.show(); f.write(0).succeed(); f.ack("1", true); assertVisible(f); return f;
    }
    private static void assertVisible(Fixture f) {
        PresentationLease lease = f.session.presentationLease(); assertNotNull(lease);
        assertTrue(f.session.permits(lease, f.peer, f.control, f.track));
        assertTrue(f.session.snapshot().presentationAllowed); assertEquals(State.ACTIVE, f.session.snapshot().state);
    }
    private static void assertClosed(Fixture f, Failure reason) {
        assertEquals(State.CLOSED, f.session.snapshot().state); assertFalse(f.session.snapshot().presentationAllowed);
        assertNull(f.session.presentationLease()); assertEquals(1, f.failures.size()); assertEquals(reason, f.failures.get(0));
    }
    private static byte[] ack(String id, boolean active) {
        return ("{\"version\":2,\"kind\":\"ack\",\"acknowledgement\":{\"id\":" + id
                + ",\"state\":\"" + (active ? "active" : "inactive") + "\"}}").getBytes(StandardCharsets.UTF_8);
    }
    private static final class Fixture {
        final Object peer = new Object(), control = new Object(), track = new Object();
        final AtomicLong clock = new AtomicLong(); final FakeTransport transport = new FakeTransport();
        final List<Failure> failures = new ArrayList<>(); final ViewerScreenSession session;
        Fixture() { this("1"); }
        Fixture(String initialID) { session = new ViewerScreenSession(peer, control, track, transport, clock::get, failures::add, initialID); }
        Write write(int index) { return transport.writes.get(index); }
        void ack(String id, boolean active) { session.receive(peer, control, ViewerScreenSessionTest.ack(id, active)); }
    }
    private static final class Write {
        final byte[] bytes; final BooleanSupplier guard; final CompletableFuture<Void> future;
        Write(byte[] bytes, BooleanSupplier guard, CompletableFuture<Void> future) { this.bytes = bytes.clone(); this.guard = guard; this.future = future; }
        String text() { return new String(bytes, StandardCharsets.UTF_8); }
        void succeed() { assertTrue("Exact native-write authorization refused", guard.getAsBoolean()); future.complete(null); }
        void refuse() { future.completeExceptionally(new IllegalStateException("Fake exact write refused")); }
    }
    private static final class FakeTransport implements ViewerScreenSession.Transport {
        final List<Write> writes = new ArrayList<>(); Consumer<Write> duringSend;
        boolean throwAfterInlineCompletion;
        @Override public CompletionStage<Void> send(byte[] bytes, BooleanSupplier guard) {
            CompletableFuture<Void> future = throwAfterInlineCompletion ? new ThrowingAttachmentFuture() : new CompletableFuture<>();
            Write write = new Write(bytes, guard, future); writes.add(write);
            if (duringSend != null) duringSend.accept(write); return future;
        }
    }
    private static final class ThrowingAttachmentFuture extends CompletableFuture<Void> {
        @Override public CompletableFuture<Void> whenComplete(BiConsumer<? super Void, ? super Throwable> action) {
            super.whenComplete(action); throw new IllegalStateException("Fake attachment unproved");
        }
    }
    private static final class OrderedClock implements ViewerScreenSession.Clock {
        final AtomicLong sequence = new AtomicLong(); final CountDownLatch firstRead = new CountDownLatch(1);
        final CountDownLatch secondRead = new CountDownLatch(1), releaseFirst = new CountDownLatch(1);
        volatile boolean armed;
        @Override public long nanoTime() {
            long sample = sequence.incrementAndGet();
            if (armed && sample == 2) {
                firstRead.countDown();
                try { if (!releaseFirst.await(2, TimeUnit.SECONDS)) throw new IllegalStateException("Fake clock hold expired"); }
                catch (InterruptedException interrupted) { Thread.currentThread().interrupt(); throw new IllegalStateException("Fake clock interrupted"); }
            } else if (armed && sample == 3) secondRead.countDown();
            return sample;
        }
    }
}
