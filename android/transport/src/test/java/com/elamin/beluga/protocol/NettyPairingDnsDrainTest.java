package com.elamin.beluga.protocol;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;
import io.netty.channel.EventLoopGroup;
import io.netty.channel.MultiThreadIoEventLoopGroup;
import io.netty.channel.embedded.EmbeddedChannel;
import io.netty.channel.local.LocalIoHandler;
import java.net.InetAddress;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.Test;

/** Real worker/registration/session-loop ownership. No DNS, TLS, sockets, Android or storage. */
public final class NettyPairingDnsDrainTest {
    private static final long WAIT_SECONDS = 5;

    @Test public void heldProcessLookupDoesNotBlockDetachedSessionCloseOrResurrectAllocator() throws Exception {
        Gate lookup = new Gate(); AtomicInteger allocations = new AtomicInteger();
        try (Harness harness = new Harness(() -> { lookup.hold(); return address(11); }, () -> { })) {
            harness.releaseOnClose(lookup);
            Observation observation = new Observation(); EventLoopGroup group = harness.group();
            NettyPairingWssTransport owner = harness.owner(group, observation, (exact, resolved) -> allocations.incrementAndGet());
            lookup.awaitEntered();
            assertTrue(harness.resolver.fixtureLookupIsBusy());
            owner.closeAsync().toCompletableFuture().get(WAIT_SECONDS, TimeUnit.SECONDS);
            assertTrue("Native lookup remains owned and held, not cancelled", harness.resolver.fixtureLookupIsBusy());
            assertEquals(0, allocations.get()); assertEquals(1, observation.terminals.get());
            assertEquals(NettyPairingWssTransport.FailureCode.CLOSED, observation.reason.get());
            lookup.release(); awaitLookupIdle(harness.resolver);
            assertEquals(0, allocations.get()); assertEquals(1, observation.terminals.get());
        } finally { lookup.release(); }
    }

    @Test public void queuedResultAfterRetirementCannotAllocateOrDeliverOpen() throws Exception {
        Gate loop = new Gate(); AtomicInteger allocations = new AtomicInteger();
        try (Harness harness = new Harness(() -> address(12), () -> { })) {
            harness.releaseOnClose(loop);
            EventLoopGroup group = harness.group();
            group.next().execute(loop::holdUnchecked); loop.awaitEntered();
            Observation observation = new Observation();
            NettyPairingWssTransport owner = harness.owner(group, observation, (exact, resolved) -> allocations.incrementAndGet());
            awaitLookupIdle(harness.resolver); // Posting completed; real loop delivery is still queued.
            CompletableFuture<Void> close = owner.closeAsync().toCompletableFuture();
            assertFalse("Actual owned-loop barrier remains held", close.isDone());
            loop.release(); close.get(WAIT_SECONDS, TimeUnit.SECONDS);
            assertEquals(0, allocations.get()); assertEquals(0, observation.opens.get());
            assertEquals(1, observation.terminals.get());
        } finally { loop.release(); }
    }

    @Test public void claimedPostingMustReturnBeforeExactCloseCanSucceed() throws Exception {
        Gate claimedPosting = new Gate(); AtomicInteger allocations = new AtomicInteger();
        try (Harness harness = new Harness(() -> address(13), claimedPosting::holdUnchecked)) {
            harness.releaseOnClose(claimedPosting);
            Observation observation = new Observation(); EventLoopGroup group = harness.group();
            NettyPairingWssTransport owner = harness.owner(group, observation, (exact, resolved) -> allocations.incrementAndGet());
            claimedPosting.awaitEntered();
            CompletableFuture<Void> close = owner.closeAsync().toCompletableFuture();
            assertTrue(group.terminationFuture().await(WAIT_SECONDS, TimeUnit.SECONDS));
            assertFalse("Loop termination alone cannot clear claimed posting", close.isDone());
            assertEquals(0, observation.terminals.get());
            claimedPosting.release(); close.get(WAIT_SECONDS, TimeUnit.SECONDS);
            assertEquals(0, allocations.get()); assertEquals(1, observation.terminals.get());
            assertEquals(NettyPairingWssTransport.FailureCode.CLOSED, observation.reason.get());
        } finally { claimedPosting.release(); }
    }

    @Test public void predecessorQueuedJobCannotAllocateForOrCloseSuccessor() throws Exception {
        Gate oldLoop = new Gate(); AtomicInteger lookups = new AtomicInteger();
        AtomicInteger oldAllocations = new AtomicInteger(), newAllocations = new AtomicInteger();
        CountDownLatch newConnected = new CountDownLatch(1);
        try (Harness harness = new Harness(() -> address(20 + lookups.incrementAndGet()), () -> { })) {
            harness.releaseOnClose(oldLoop);
            EventLoopGroup predecessorGroup = harness.group(); predecessorGroup.next().execute(oldLoop::holdUnchecked);
            oldLoop.awaitEntered(); Observation predecessorObservation = new Observation();
            NettyPairingWssTransport predecessor = harness.owner(predecessorGroup, predecessorObservation,
                    (exact, resolved) -> oldAllocations.incrementAndGet());
            awaitLookupIdle(harness.resolver);
            CompletableFuture<Void> oldClose = predecessor.closeAsync().toCompletableFuture();
            EventLoopGroup successorGroup = harness.group(); Observation successorObservation = new Observation();
            NettyPairingWssTransport successor = harness.owner(successorGroup, successorObservation, (exact, resolved) -> {
                assertTrue(successorGroup.next().inEventLoop());
                assertArrayEquals(new byte[] {127, 0, 0, 22}, resolved.getAddress());
                newAllocations.incrementAndGet(); newConnected.countDown();
            });
            assertTrue(newConnected.await(WAIT_SECONDS, TimeUnit.SECONDS));
            assertEquals(2, lookups.get()); assertEquals(1, newAllocations.get());
            assertEquals(0, successorObservation.terminals.get());
            oldLoop.release(); oldClose.get(WAIT_SECONDS, TimeUnit.SECONDS);
            assertEquals(0, oldAllocations.get()); assertEquals(1, newAllocations.get());
            assertEquals(1, predecessorObservation.terminals.get());
            assertEquals("Old terminal callback cannot retire new owner", 0, successorObservation.terminals.get());
            successor.closeAsync().toCompletableFuture().get(WAIT_SECONDS, TimeUnit.SECONDS);
            assertEquals(1, successorObservation.terminals.get());
        } finally { oldLoop.release(); }
    }

    @Test public void inlineConnectorCloseWaitsForExactRegistrationPublicationAndDoesNotResurrect() throws Exception {
        Gate publication = new Gate(); CountDownLatch connectorEntered = new CountDownLatch(1);
        AtomicReference<NettyPairingWssTransport> observedOwner = new AtomicReference<>();
        AtomicReference<CompletableFuture<Void>> callbackClose = new AtomicReference<>();
        CompletableFuture<NettyPairingWssTransport> factory = new CompletableFuture<>();
        Observation observation = new Observation();
        try (Harness harness = new Harness(() -> address(31), () -> { })) {
            harness.releaseOnClose(publication);
            EventLoopGroup group = harness.group();
            Thread caller = new Thread(() -> {
                try {
                    NettyPairingWssTransport result = NettyPairingWssTransport.withResolverForFixture(
                            harness.resolver, group, observation, (owner, resolved) -> {
                                assertTrue(group.next().inEventLoop()); observedOwner.set(owner); harness.remember(owner);
                                CompletableFuture<Void> close = owner.closeAsync().toCompletableFuture();
                                callbackClose.set(close); connectorEntered.countDown();
                            }, publication::holdUnchecked);
                    harness.remember(result); factory.complete(result);
                } catch (Throwable error) { factory.completeExceptionally(error); }
            }, "Beluga synthetic registration publication caller");
            harness.caller(caller); caller.start();
            publication.awaitEntered();
            assertTrue(connectorEntered.await(WAIT_SECONDS, TimeUnit.SECONDS));
            assertFalse(factory.isDone()); assertTrue(callbackClose.get() != null);
            assertFalse("No exact registration publication yet", callbackClose.get().isDone());
            assertTrue(group.terminationFuture().await(WAIT_SECONDS, TimeUnit.SECONDS));
            assertFalse("Owned loop terminated but registration is still unpublished", callbackClose.get().isDone());
            assertEquals(0, observation.terminals.get());
            publication.release();
            NettyPairingWssTransport owner = factory.get(WAIT_SECONDS, TimeUnit.SECONDS);
            assertTrue(owner == observedOwner.get());
            callbackClose.get().get(WAIT_SECONDS, TimeUnit.SECONDS);
            assertEquals(1, observation.terminals.get()); assertEquals(0, observation.opens.get());
            assertCloseFailure(owner.whenOpen(), NettyPairingWssTransport.FailureCode.CLOSED);
        }
    }

    @Test public void firstObservedNativeCloseFailureNeverBecomesFinishedAfterDnsDetachOrDuplicateClose() throws Exception {
        AtomicReference<ObservedEmbeddedChannel> socket = new AtomicReference<>(); CountDownLatch connected = new CountDownLatch(1);
        try (Harness harness = new Harness(() -> address(41), () -> { })) {
            Observation observation = new Observation(); EventLoopGroup group = harness.group();
            NettyPairingWssTransport owner = harness.owner(group, observation, (exact, resolved) -> {
                assertTrue(group.next().inEventLoop());
                ObservedEmbeddedChannel channel = new ObservedEmbeddedChannel(true);
                harness.socket(channel); socket.set(channel);
                exact.observeSocketForFixture(channel, channel.firstNativeClose); connected.countDown();
            });
            assertTrue(connected.await(WAIT_SECONDS, TimeUnit.SECONDS)); awaitLookupIdle(harness.resolver);
            assertCloseFailure(owner.closeAsync(), NettyPairingWssTransport.FailureCode.DRAIN_FAILED);
            assertTrue(socket.get().closeFuture().isSuccess());
            assertTrue("Netty duplicate close alone is not first native-close proof", socket.get().close().isSuccess());
            assertCloseFailure(owner.closeAsync(), NettyPairingWssTransport.FailureCode.DRAIN_FAILED);
            assertEquals(1, observation.terminals.get());
            assertEquals(NettyPairingWssTransport.FailureCode.DRAIN_FAILED, observation.reason.get());
        }
    }

    private static final class Observation implements NettyPairingWssTransport.Listener {
        final AtomicInteger opens = new AtomicInteger(), terminals = new AtomicInteger();
        final AtomicReference<NettyPairingWssTransport.FailureCode> reason = new AtomicReference<>();
        @Override public void onOpen() { opens.incrementAndGet(); }
        @Override public void onText(byte[] bytes) { throw new AssertionError("No network/text is admitted in resolver fixtures"); }
        @Override public void onTerminal(NettyPairingWssTransport.FailureCode terminal) { reason.set(terminal); terminals.incrementAndGet(); }
    }

    private static final class Gate {
        private final CountDownLatch entered = new CountDownLatch(1), release = new CountDownLatch(1);
        void hold() throws InterruptedException {
            entered.countDown(); assertTrue("Synthetic gate released within bounded test", release.await(2 * WAIT_SECONDS, TimeUnit.SECONDS));
        }
        void holdUnchecked() {
            try { hold(); } catch (InterruptedException error) { Thread.currentThread().interrupt(); throw new AssertionError("Synthetic gate interrupted"); }
        }
        void awaitEntered() throws InterruptedException { assertTrue(entered.await(WAIT_SECONDS, TimeUnit.SECONDS)); }
        void release() { release.countDown(); }
    }

    private static final class Harness implements AutoCloseable {
        final ProcessPairingDnsResolver resolver;
        private final List<EventLoopGroup> groups = new ArrayList<>();
        private final List<NettyPairingWssTransport> owners = new ArrayList<>();
        private final List<ObservedEmbeddedChannel> sockets = new ArrayList<>();
        private final List<Gate> gates = new ArrayList<>();
        private final List<Thread> callers = new ArrayList<>();
        Harness(ProcessPairingDnsResolver.Lookup lookup, ProcessPairingDnsResolver.HandoffProbe probe) {
            resolver = ProcessPairingDnsResolver.forFixture(lookup, probe);
        }
        EventLoopGroup group() { EventLoopGroup group = newGroup(); groups.add(group); return group; }
        void releaseOnClose(Gate gate) { gates.add(gate); }
        void caller(Thread caller) { callers.add(caller); }
        synchronized void remember(NettyPairingWssTransport owner) { if (!owners.contains(owner)) owners.add(owner); }
        NettyPairingWssTransport owner(EventLoopGroup group, Observation observation,
                NettyPairingWssTransport.ResolvedConnector connector) throws Exception {
            NettyPairingWssTransport owner = NettyPairingWssTransport.withResolverForFixture(resolver, group, observation, connector);
            remember(owner); return owner;
        }
        synchronized void socket(ObservedEmbeddedChannel socket) { sockets.add(socket); }
        @Override public void close() {
            for (Gate gate : gates) gate.release(); // Before any wait, including failed test paths.
            Cleanup cleanup = new Cleanup();
            cleanup.run(resolver::closeFixtureWhenLookupReturns);
            for (Thread caller : callers) cleanup.run(() -> {
                caller.join(TimeUnit.SECONDS.toMillis(WAIT_SECONDS)); assertFalse(caller.isAlive());
            });
            List<NettyPairingWssTransport> capturedOwners;
            synchronized (this) { capturedOwners = new ArrayList<>(owners); }
            for (NettyPairingWssTransport owner : capturedOwners) cleanup.run(() -> awaitSettled(owner.closeAsync()));
            for (EventLoopGroup group : groups) cleanup.run(() -> group.shutdownGracefully(0, WAIT_SECONDS, TimeUnit.SECONDS));
            for (EventLoopGroup group : groups) {
                cleanup.run(() -> assertTrue(group.terminationFuture().await(WAIT_SECONDS, TimeUnit.SECONDS)));
            }
            cleanup.run(() -> assertTrue(resolver.joinFixtureWorker(WAIT_SECONDS, TimeUnit.SECONDS)));
            synchronized (this) {
                for (ObservedEmbeddedChannel socket : sockets) cleanup.run(socket::finishAndReleaseAll);
            }
            cleanup.finish();
        }
    }

    private interface CleanupAction { void run() throws Exception; }
    /** Attempt every bounded cleanup; try-with-resources preserves an earlier test failure. */
    private static final class Cleanup {
        private AssertionError failure;
        private boolean interrupted = Thread.interrupted();
        void run(CleanupAction action) {
            try { action.run(); }
            catch (InterruptedException error) { interrupted = true; retain(error); }
            catch (Exception | AssertionError error) { retain(error); }
        }
        private void retain(Throwable error) {
            if (failure == null) failure = new AssertionError("Bounded fixture cleanup failed", error);
            else failure.addSuppressed(error);
        }
        void finish() {
            if (interrupted) Thread.currentThread().interrupt();
            if (failure != null) throw failure;
        }
    }

    /** Real Embedded doClose observation only; this is explicitly NOT native OS socket proof. */
    private static final class ObservedEmbeddedChannel extends EmbeddedChannel {
        final CompletableFuture<Void> firstNativeClose = new CompletableFuture<>();
        private final boolean fail;
        ObservedEmbeddedChannel(boolean fail) { this.fail = fail; }
        @Override protected void doClose() throws Exception {
            try {
                super.doClose(); if (fail) throw new IllegalStateException("Fixed synthetic first-close failure");
                firstNativeClose.complete(null);
            } catch (Exception | Error error) { firstNativeClose.completeExceptionally(error); throw error; }
        }
    }

    private static EventLoopGroup newGroup() { return new MultiThreadIoEventLoopGroup(1, LocalIoHandler.newFactory()); }
    private static InetAddress address(int last) throws Exception { return InetAddress.getByAddress(new byte[] {127, 0, 0, (byte) last}); }
    private static void awaitLookupIdle(ProcessPairingDnsResolver resolver) {
        long end = System.nanoTime() + TimeUnit.SECONDS.toNanos(WAIT_SECONDS);
        while (resolver.fixtureLookupIsBusy()) {
            if (System.nanoTime() >= end) fail("Owned fixture lookup/post did not finish within bound");
            Thread.yield();
        }
    }
    private static void awaitSettled(CompletionStage<Void> stage) throws Exception {
        try { stage.toCompletableFuture().get(WAIT_SECONDS, TimeUnit.SECONDS); }
        catch (ExecutionException error) {
            assertTrue(error.getCause() instanceof NettyPairingWssTransport.TransportFailure);
            assertEquals(NettyPairingWssTransport.FailureCode.DRAIN_FAILED,
                    ((NettyPairingWssTransport.TransportFailure) error.getCause()).code());
        }
    }
    private static void assertCloseFailure(CompletionStage<Void> stage, NettyPairingWssTransport.FailureCode expected) throws Exception {
        try { stage.toCompletableFuture().get(WAIT_SECONDS, TimeUnit.SECONDS); fail("Expected exact non-successful transport stage"); }
        catch (ExecutionException error) {
            assertTrue(error.getCause() instanceof NettyPairingWssTransport.TransportFailure);
            NettyPairingWssTransport.TransportFailure failure = (NettyPairingWssTransport.TransportFailure) error.getCause();
            assertEquals(expected, failure.code()); assertEquals(null, failure.getCause()); assertEquals(0, failure.getSuppressed().length);
        }
    }
}
