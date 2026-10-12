package com.elamin.beluga.protocol;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertSame;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import io.netty.util.concurrent.DefaultEventExecutor;
import io.netty.util.concurrent.ImmediateEventExecutor;
import java.lang.reflect.Field;
import java.net.InetAddress;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ConcurrentMap;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.Test;

/** Owned real worker/executor threads with fake native lookup; no platform DNS or sockets. */
public final class ProcessPairingDnsResolverTest {
    @Test public void productionSingletonHasNoPerSessionConstructionOrFixtureShutdown() {
        assertSame(ProcessPairingDnsResolver.process(), ProcessPairingDnsResolver.process());
        try { ProcessPairingDnsResolver.process().closeFixtureWhenLookupReturns(); fail("Expected fixture boundary"); }
        catch (IllegalStateException expected) { assertEquals("Owned fixture resolver required", expected.getMessage()); }
    }

    @Test public void heldLookupIsOneJobAndBusyHasNoBacklogOrReplacement() throws Exception {
        HeldLookup lookup = new HeldLookup();
        try (Owned fixture = new Owned(lookup, () -> { })) {
            fixture.releaseOnClose.add(lookup.release);
            AtomicInteger callbacks = new AtomicInteger();
            ProcessPairingDnsResolver.Registration registration = fixture.resolver.register(fixture.loop, result -> callbacks.incrementAndGet());
            await(lookup.entered);
            for (int i = 0; i < 100; i++) assertRegisterRefused(fixture, ProcessPairingDnsResolver.Failure.BUSY);
            assertEquals(1, lookup.calls.get());
            assertTrue(fixture.resolver.fixtureLookupIsBusy());
            complete(registration.detach());
            assertTargetCleared(fixture.resolver, registration);
            // Detach joins the session registration, never claims native cancellation.
            assertTrue(fixture.resolver.fixtureLookupIsBusy());
            assertRegisterRefused(fixture, ProcessPairingDnsResolver.Failure.BUSY);
            lookup.release.countDown(); awaitIdle(fixture.resolver);
            fixture.loop.submit(() -> { }).get(5, TimeUnit.SECONDS);
            assertEquals(0, callbacks.get());
        }
    }

    @Test public void resultRunsOnExactLoopOnceAndWorkerIsReused() throws Exception {
        AtomicInteger lookups = new AtomicInteger();
        AtomicReference<Thread> firstWorker = new AtomicReference<>();
        try (Owned fixture = new Owned(() -> {
            Thread current = Thread.currentThread();
            if (firstWorker.get() == null) firstWorker.set(current); else assertSame(firstWorker.get(), current);
            return address(lookups.incrementAndGet());
        }, () -> { })) {
            for (int i = 1; i <= 2; i++) {
                CompletableFuture<ProcessPairingDnsResolver.Result> delivered = new CompletableFuture<>();
                ProcessPairingDnsResolver.Registration registration = fixture.resolver.register(fixture.loop, result -> {
                    assertTrue(fixture.loop.inEventLoop()); delivered.complete(result);
                });
                ProcessPairingDnsResolver.Result result = delivered.get(5, TimeUnit.SECONDS);
                assertTrue(result.isSuccess()); assertEquals(null, result.failure());
                assertArrayEquals(address(i).getAddress(), result.address().getAddress());
                assertEquals("<redacted Beluga DNS result>", result.toString());
                complete(registration.detach()); awaitIdle(fixture.resolver);
            }
            assertEquals(2, lookups.get());
        }
    }

    @Test public void lookupFailureHasNoNativeExceptionOrAddressLeak() throws Exception {
        try (Owned fixture = new Owned(() -> { throw new IllegalStateException("public synthetic lookup error"); }, () -> { })) {
            CompletableFuture<ProcessPairingDnsResolver.Result> delivered = new CompletableFuture<>();
            ProcessPairingDnsResolver.Registration registration = fixture.resolver.register(fixture.loop, delivered::complete);
            ProcessPairingDnsResolver.Result result = delivered.get(5, TimeUnit.SECONDS);
            assertFalse(result.isSuccess()); assertEquals(null, result.address());
            assertEquals(ProcessPairingDnsResolver.Failure.LOOKUP_FAILED, result.failure());
            assertEquals("<redacted Beluga DNS result>", result.toString());
            complete(registration.detach());
        }
    }

    @Test public void detachJoinsAlreadyClaimedPostingAndThenDropsIt() throws Exception {
        CountDownLatch claimed = new CountDownLatch(1), release = new CountDownLatch(1);
        AtomicInteger delivered = new AtomicInteger();
        try (Owned fixture = new Owned(() -> address(1), () -> { claimed.countDown(); awaitUnchecked(release); })) {
            fixture.releaseOnClose.add(release);
            ProcessPairingDnsResolver.Registration registration = fixture.resolver.register(fixture.loop, result -> delivered.incrementAndGet());
            await(claimed);
            CompletionStage<Void> first = registration.detach(), second = registration.detach();
            assertFalse(first.toCompletableFuture().isDone()); assertFalse(second.toCompletableFuture().isDone());
            assertRegisterRefused(fixture, ProcessPairingDnsResolver.Failure.BUSY);
            release.countDown(); complete(first); complete(second); awaitIdle(fixture.resolver);
            fixture.loop.submit(() -> { }).get(5, TimeUnit.SECONDS);
            assertEquals(0, delivered.get());
        }
    }

    @Test public void ownedLoopMayTerminateAfterDetachWithoutFalseHandoffFailure() throws Exception {
        CountDownLatch claimed = new CountDownLatch(1), release = new CountDownLatch(1);
        try (Owned fixture = new Owned(() -> address(1), () -> { claimed.countDown(); awaitUnchecked(release); })) {
            fixture.releaseOnClose.add(release);
            AtomicInteger callbacks = new AtomicInteger();
            ProcessPairingDnsResolver.Registration registration = fixture.resolver.register(fixture.loop, result -> callbacks.incrementAndGet());
            await(claimed); CompletionStage<Void> detached = registration.detach();
            assertTrue(fixture.loop.shutdownGracefully(0, 1, TimeUnit.SECONDS).await(5, TimeUnit.SECONDS));
            release.countDown(); complete(detached); awaitIdle(fixture.resolver);
            assertEquals(0, callbacks.get());
        }
    }

    @Test public void detachedQueuedOldResultCannotTargetSuccessor() throws Exception {
        AtomicInteger lookups = new AtomicInteger();
        CountDownLatch blocked = new CountDownLatch(1), releaseLoop = new CountDownLatch(1);
        try (Owned fixture = new Owned(() -> address(lookups.incrementAndGet()), () -> { })) {
            fixture.releaseOnClose.add(releaseLoop);
            fixture.loop.execute(() -> { blocked.countDown(); awaitUnchecked(releaseLoop); }); await(blocked);
            AtomicInteger oldDeliveries = new AtomicInteger();
            ProcessPairingDnsResolver.Registration old = fixture.resolver.register(fixture.loop, result -> oldDeliveries.incrementAndGet());
            awaitIdle(fixture.resolver); complete(old.detach());
            CompletableFuture<ProcessPairingDnsResolver.Result> delivered = new CompletableFuture<>();
            ProcessPairingDnsResolver.Registration successor = fixture.resolver.register(fixture.loop, delivered::complete);
            awaitIdle(fixture.resolver); assertEquals(2, lookups.get());
            // Repeating the old completion cannot clear current=successor.
            complete(old.detach()); assertRegisterRefused(fixture, ProcessPairingDnsResolver.Failure.BUSY);
            releaseLoop.countDown();
            ProcessPairingDnsResolver.Result result = delivered.get(5, TimeUnit.SECONDS);
            assertArrayEquals(address(2).getAddress(), result.address().getAddress());
            assertEquals(0, oldDeliveries.get()); complete(successor.detach());
        }
    }

    @Test public void detachJoinsCallbackAlreadyExecutingWithoutHoldingMetadataLock() throws Exception {
        CountDownLatch entered = new CountDownLatch(1), release = new CountDownLatch(1);
        try (Owned fixture = new Owned(() -> address(1), () -> { })) {
            fixture.releaseOnClose.add(release);
            ProcessPairingDnsResolver.Registration registration = fixture.resolver.register(fixture.loop, result -> {
                entered.countDown(); awaitUnchecked(release);
            });
            await(entered); CompletionStage<Void> detached = registration.detach();
            assertFalse(detached.toCompletableFuture().isDone());
            assertRegisterRefused(fixture, ProcessPairingDnsResolver.Failure.BUSY);
            release.countDown(); complete(detached);
        }
    }

    @Test public void callbackCanDetachItselfWithoutCompletingBeforeReturn() throws Exception {
        HeldLookup lookup = new HeldLookup();
        try (Owned fixture = new Owned(lookup, () -> { })) {
            fixture.releaseOnClose.add(lookup.release);
            AtomicReference<ProcessPairingDnsResolver.Registration> published = new AtomicReference<>();
            CompletableFuture<CompletionStage<Void>> observed = new CompletableFuture<>();
            ProcessPairingDnsResolver.Registration registration = fixture.resolver.register(fixture.loop, result -> {
                CompletionStage<Void> detached = published.get().detach();
                assertFalse(detached.toCompletableFuture().isDone()); observed.complete(detached);
            });
            published.set(registration); await(lookup.entered); lookup.release.countDown();
            complete(observed.get(5, TimeUnit.SECONDS));
        }
    }

    @Test public void unretiredExecutorRejectionIsExceptionalDetachNotSuccessfulLookup() throws Exception {
        try (Owned fixture = new Owned(() -> address(1), () -> { })) {
            assertTrue(fixture.loop.shutdownGracefully(0, 1, TimeUnit.SECONDS).await(5, TimeUnit.SECONDS));
            AtomicInteger callbacks = new AtomicInteger();
            ProcessPairingDnsResolver.Registration registration = fixture.resolver.register(fixture.loop, result -> callbacks.incrementAndGet());
            awaitIdle(fixture.resolver);
            assertDetachFailure(registration.detach(), ProcessPairingDnsResolver.Failure.HANDOFF_FAILED);
            assertEquals(0, callbacks.get());
        }
    }

    @Test public void callbackExceptionIsRedactedExceptionalDetach() throws Exception {
        CountDownLatch callback = new CountDownLatch(1);
        try (Owned fixture = new Owned(() -> address(1), () -> { })) {
            ProcessPairingDnsResolver.Registration registration = fixture.resolver.register(fixture.loop, result -> {
                callback.countDown(); throw new IllegalArgumentException("public synthetic callback failure");
            });
            await(callback); fixture.loop.submit(() -> { }).get(5, TimeUnit.SECONDS);
            assertDetachFailure(registration.detach(), ProcessPairingDnsResolver.Failure.HANDOFF_FAILED);
        }
    }

    @Test public void inlineExecutorCanNeverRunSessionCallbackOnLookupWorker() throws Exception {
        try (Owned fixture = new Owned(() -> address(1), () -> { })) {
            AtomicInteger callbacks = new AtomicInteger();
            ProcessPairingDnsResolver.Registration registration = fixture.resolver.register(
                    ImmediateEventExecutor.INSTANCE, result -> callbacks.incrementAndGet());
            awaitIdle(fixture.resolver);
            assertDetachFailure(registration.detach(), ProcessPairingDnsResolver.Failure.HANDOFF_FAILED);
            assertEquals(0, callbacks.get());
        }
    }

    @Test public void processShutdownScopeWaitsForLookupAndNeverInterruptsIt() throws Exception {
        HeldLookup lookup = new HeldLookup();
        try (Owned fixture = new Owned(lookup, () -> { })) {
            fixture.releaseOnClose.add(lookup.release);
            AtomicInteger callbacks = new AtomicInteger();
            ProcessPairingDnsResolver.Registration registration = fixture.resolver.register(fixture.loop, result -> callbacks.incrementAndGet());
            await(lookup.entered); fixture.resolver.closeFixtureWhenLookupReturns();
            complete(registration.detach());
            assertFalse(fixture.resolver.joinFixtureWorker(20, TimeUnit.MILLISECONDS));
            assertEquals(0, lookup.interrupted.get());
            assertRegisterRefused(fixture, ProcessPairingDnsResolver.Failure.PROCESS_CLOSED);
            lookup.release.countDown(); assertTrue(fixture.resolver.joinFixtureWorker(5, TimeUnit.SECONDS));
            fixture.loop.submit(() -> { }).get(5, TimeUnit.SECONDS);
            assertEquals(0, callbacks.get());
        }
    }

    private static final class HeldLookup implements ProcessPairingDnsResolver.Lookup {
        final CountDownLatch entered = new CountDownLatch(1), release = new CountDownLatch(1);
        final AtomicInteger calls = new AtomicInteger(), interrupted = new AtomicInteger();
        @Override public InetAddress lookupFixedHost() throws Exception {
            calls.incrementAndGet(); entered.countDown();
            try { if (!release.await(5, TimeUnit.SECONDS)) throw new IllegalStateException("Public fixture gate timed out"); }
            catch (InterruptedException error) { interrupted.incrementAndGet(); throw error; }
            return address(1);
        }
    }

    private static final class Owned implements AutoCloseable {
        final DefaultEventExecutor loop = new DefaultEventExecutor();
        final ProcessPairingDnsResolver resolver;
        final List<CountDownLatch> releaseOnClose = new ArrayList<>();
        Owned(ProcessPairingDnsResolver.Lookup lookup, ProcessPairingDnsResolver.HandoffProbe probe) {
            resolver = ProcessPairingDnsResolver.forFixture(lookup, probe);
        }
        @Override public void close() {
            for (CountDownLatch release : releaseOnClose) release.countDown();
            resolver.closeFixtureWhenLookupReturns();
            try {
                assertTrue("Owned fake lookup worker must actually exit", resolver.joinFixtureWorker(5, TimeUnit.SECONDS));
                assertTrue("Owned callback loop must actually terminate", loop.shutdownGracefully(0, 1, TimeUnit.SECONDS).await(5, TimeUnit.SECONDS));
            } catch (InterruptedException error) {
                Thread.currentThread().interrupt(); throw new AssertionError("Owned cleanup interrupted", error);
            }
        }
    }

    private static InetAddress address(int last) throws Exception {
        // Public TEST-NET-1 bytes; getByAddress performs no host lookup.
        return InetAddress.getByAddress(new byte[] {(byte) 192, 0, 2, (byte) last});
    }
    private static void await(CountDownLatch latch) throws InterruptedException {
        assertTrue("Bounded owned fixture signal required", latch.await(5, TimeUnit.SECONDS));
    }
    private static void awaitUnchecked(CountDownLatch latch) {
        try { await(latch); }
        catch (InterruptedException error) { Thread.currentThread().interrupt(); throw new AssertionError("Owned fixture interrupted", error); }
    }
    private static void awaitIdle(ProcessPairingDnsResolver resolver) throws InterruptedException {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5);
        while (resolver.fixtureLookupIsBusy() && System.nanoTime() < deadline) Thread.sleep(1);
        assertFalse("Exact native job must have returned", resolver.fixtureLookupIsBusy());
    }
    private static void complete(CompletionStage<Void> stage) throws Exception {
        stage.toCompletableFuture().get(5, TimeUnit.SECONDS);
    }
    private static void assertRegisterRefused(Owned fixture, ProcessPairingDnsResolver.Failure expected) {
        try { fixture.resolver.register(fixture.loop, result -> { throw new AssertionError("Refused registration cannot deliver"); }); fail("Expected prompt refusal"); }
        catch (ProcessPairingDnsResolver.ResolutionFailure error) {
            assertEquals(expected, error.code()); assertEquals(null, error.getCause()); assertEquals(0, error.getSuppressed().length);
        }
    }
    private static void assertDetachFailure(CompletionStage<Void> stage, ProcessPairingDnsResolver.Failure expected) throws Exception {
        try { complete(stage); fail("Expected exceptional detach"); }
        catch (ExecutionException error) {
            assertTrue(error.getCause() instanceof ProcessPairingDnsResolver.ResolutionFailure);
            ProcessPairingDnsResolver.ResolutionFailure failure = (ProcessPairingDnsResolver.ResolutionFailure) error.getCause();
            assertEquals(expected, failure.code()); assertEquals(null, failure.getCause()); assertEquals(0, failure.getSuppressed().length);
        }
    }
    private static void assertTargetCleared(ProcessPairingDnsResolver resolver,
            ProcessPairingDnsResolver.Registration registration) throws Exception {
        Object registrationLock = field(registration, "lock");
        synchronized (registrationLock) {
            assertEquals(null, field(registration, "listener"));
            assertEquals(null, field(registration, "loop"));
        }
        Object resolverLock = field(resolver, "lock");
        synchronized (resolverLock) { assertEquals(null, field(resolver, "current")); }
        Field registry = ProcessPairingDnsResolver.class.getDeclaredField("HANDOFFS"); registry.setAccessible(true);
        assertFalse(((ConcurrentMap<?, ?>) registry.get(null)).containsKey(field(registration, "job")));
    }
    private static Object field(Object instance, String name) throws Exception {
        Field field = instance.getClass().getDeclaredField(name); field.setAccessible(true); return field.get(instance);
    }
}
