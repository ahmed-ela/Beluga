package com.elamin.beluga.protocol;

import io.netty.util.concurrent.EventExecutor;
import java.net.InetAddress;
import java.util.Objects;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import java.util.concurrent.TimeUnit;

/**
 * Fixed-host, process-owned platform lookup. Session detach does not cancel native DNS.
 * Production has one worker, one job, one registration, no backlog or replacement workers.
 */
final class ProcessPairingDnsResolver {
    private static final String HOST = "audiostreamer-rendezvous.elaminahmed03.workers.dev";

    enum Failure { BUSY, LOOKUP_FAILED, HANDOFF_FAILED, PROCESS_CLOSED }

    static final class ResolutionFailure extends Exception {
        private static final long serialVersionUID = 1L;
        private final Failure code;
        private ResolutionFailure(Failure code) {
            super("Beluga DNS registration refused: " + code.name()); this.code = code;
        }
        Failure code() { return code; }
    }

    static final class Result {
        private final InetAddress address;
        private final Failure failure;
        private Result(InetAddress address, Failure failure) { this.address = address; this.failure = failure; }
        boolean isSuccess() { return address != null; }
        InetAddress address() { return address; }
        Failure failure() { return failure; }
        @Override public String toString() { return "<redacted Beluga DNS result>"; }
    }

    interface Listener { void onResult(Result result); }

    // Empty exact-object tickets contain no callback, executor, session or capability.
    private static final class Job { }

    /**
     * The worker only consults this registry AFTER the native lookup returns. Detach removes
     * its exact entry and clears its target. No worker job captures an individual registration.
     * Production's private singleton admits one entry; private fixtures are separately owned.
     */
    private static final ConcurrentMap<Job, Registration> HANDOFFS = new ConcurrentHashMap<>();

    private static final class Holder {
        private static final ProcessPairingDnsResolver INSTANCE =
                new ProcessPairingDnsResolver(() -> InetAddress.getByName(HOST), () -> { }, false);
    }

    static ProcessPairingDnsResolver process() { return Holder.INSTANCE; }

    private final Object lock = new Object();
    private final WorkerState worker;
    private final HandoffProbe probe;
    private final boolean fixture;
    private Registration current;
    private boolean closed;

    private ProcessPairingDnsResolver(Lookup lookup, HandoffProbe probe, boolean fixture) {
        this.worker = new WorkerState(lookup);
        this.probe = probe;
        this.fixture = fixture;
    }

    /**
     * Results may be posted to the supplied loop before this method returns. Composition handles
     * them behind its own retirement fence on that loop. If retirement wins before registration
     * publication, it must detach the exact returned ticket once available; a publication
     * continuation is not itself permission to allocate off the supplied loop.
     */
    Registration register(EventExecutor sessionLoop, Listener listener) throws ResolutionFailure {
        Objects.requireNonNull(sessionLoop, "sessionLoop"); Objects.requireNonNull(listener, "listener");
        Registration registration;
        synchronized (lock) {
            if (closed) throw refused(Failure.PROCESS_CLOSED);
            if (current != null) throw refused(Failure.BUSY);
            Job job = new Job();
            if (!worker.reserve(job)) throw refused(worker.isClosed() ? Failure.PROCESS_CLOSED : Failure.BUSY);
            registration = new Registration(this, job, sessionLoop, listener, probe);
            current = registration;
            HANDOFFS.put(job, registration);
        }
        // Thread.start/notification and all injected/external calls stay outside registry locks.
        try { worker.startOrWake(); }
        catch (RuntimeException | Error error) {
            registration.refuseHandoff();
            worker.closeWhenLookupReturns();
            throw refused(Failure.HANDOFF_FAILED);
        }
        return registration;
    }

    private void released(Registration registration) {
        synchronized (lock) { if (current == registration) current = null; }
    }

    static final class Registration {
        private final ProcessPairingDnsResolver owner;
        private final Job job;
        private final HandoffProbe probe;
        private final Object lock = new Object();
        private final CompletableFuture<Void> detached = new CompletableFuture<>();
        private EventExecutor loop;
        private Listener listener;
        private boolean retired;
        private boolean claimed;
        private boolean delivered;
        private int handoffs;
        private int callbacks;
        private boolean handoffFailed;

        private Registration(ProcessPairingDnsResolver owner, Job job, EventExecutor loop,
                Listener listener, HandoffProbe probe) {
            this.owner = owner; this.job = job; this.loop = loop; this.listener = listener; this.probe = probe;
        }

        /** Revokes synchronously; joins claimed posting/active callback, not the process lookup. */
        CompletionStage<Void> detach() {
            synchronized (lock) { retired = true; loop = null; listener = null; }
            HANDOFFS.remove(job, this);
            completeIfRetired();
            return detached.thenApply(ignored -> null);
        }

        private void post(Result result) {
            EventExecutor exactLoop;
            synchronized (lock) {
                if (retired || claimed) return;
                claimed = true; handoffs = 1; exactLoop = loop;
            }
            try {
                probe.beforePost();
                synchronized (lock) { if (retired || loop != exactLoop) return; }
                exactLoop.execute(() -> deliver(exactLoop, result));
            } catch (RuntimeException | Error error) {
                // Rejection after legitimate detach/loop shutdown grants no new effect and is
                // not a failed cleanup. Unretired rejection still refuses the exact handoff.
                synchronized (lock) { if (!retired) handoffFailed = true; }
                detach();
            } finally {
                synchronized (lock) { handoffs = 0; }
                completeIfRetired();
            }
        }

        private void deliver(EventExecutor exactLoop, Result result) {
            // An EventExecutor such as ImmediateEventExecutor can claim inEventLoop while
            // executing inline. Never let that run session/native work on the lookup worker.
            boolean onExactLoop = exactLoop.inEventLoop() && Thread.currentThread() != owner.worker.thread;
            Listener target;
            synchronized (lock) {
                if (retired || delivered || loop != exactLoop) return;
                if (!onExactLoop) {
                    handoffFailed = true; retired = true; loop = null; listener = null; target = null;
                } else {
                    delivered = true; callbacks = 1; target = listener;
                }
            }
            if (target == null) { detach(); return; }
            try { target.onResult(result); }
            catch (RuntimeException | Error error) { synchronized (lock) { handoffFailed = true; } }
            finally {
                synchronized (lock) { callbacks = 0; retired = true; loop = null; listener = null; }
                HANDOFFS.remove(job, this);
                completeIfRetired();
            }
        }

        private void refuseHandoff() {
            synchronized (lock) { handoffFailed = true; }
            detach();
        }

        private void completeIfRetired() {
            boolean finish, failed;
            synchronized (lock) {
                finish = retired && handoffs == 0 && callbacks == 0;
                failed = handoffFailed;
            }
            if (!finish) return;
            owner.released(this);
            // Future consumers may reenter; completion never runs under either metadata lock.
            if (failed) detached.completeExceptionally(refused(Failure.HANDOFF_FAILED));
            else detached.complete(null);
        }

        @Override public String toString() { return "<redacted Beluga DNS registration>"; }
    }

    /**
     * Worker capture is ONLY this state: lookup implementation, empty Job ticket, and scalar
     * lifecycle fields. It has no resolver owner, registry target, loop, listener or session.
     */
    private static final class WorkerState {
        private final Object lock = new Object();
        private final Lookup lookup;
        private final Thread thread;
        private Job job;
        private boolean started;
        private boolean closed;

        WorkerState(Lookup lookup) {
            this.lookup = lookup;
            thread = new Thread(this::run, "Beluga process DNS");
            thread.setDaemon(true);
        }
        boolean reserve(Job candidate) {
            synchronized (lock) {
                if (closed || job != null) return false;
                job = candidate; return true;
            }
        }
        boolean isClosed() { synchronized (lock) { return closed; } }
        void startOrWake() {
            boolean start;
            synchronized (lock) { start = !started; started = true; lock.notifyAll(); }
            if (start) thread.start();
        }
        private void run() {
            try {
                for (;;) {
                    Job exactJob;
                    synchronized (lock) {
                        while (job == null && !closed) lock.wait();
                        if (job == null) return;
                        exactJob = job;
                    }
                    // No registration/target was read or captured before this native call.
                    Result result;
                    try {
                        InetAddress address = lookup.lookupFixedHost();
                        result = address == null ? new Result(null, Failure.LOOKUP_FAILED) : new Result(address, null);
                    } catch (Exception | LinkageError error) { result = new Result(null, Failure.LOOKUP_FAILED); }
                    try { publish(exactJob, result); }
                    finally { synchronized (lock) { if (job == exactJob) job = null; lock.notifyAll(); } }
                }
            } catch (InterruptedException error) {
                // No production interruption is used to pretend platform lookup cancellation.
                Thread.currentThread().interrupt();
            } finally {
                Job abandoned;
                synchronized (lock) { closed = true; abandoned = job; job = null; lock.notifyAll(); }
                if (abandoned != null) failPublication(abandoned);
            }
        }
        void closeWhenLookupReturns() {
            synchronized (lock) { closed = true; lock.notifyAll(); }
        }
        boolean joinForFixture(long millis) throws InterruptedException {
            thread.join(millis); return !thread.isAlive();
        }
        boolean busyForFixture() { synchronized (lock) { return job != null; } }
    }

    private static void publish(Job job, Result result) {
        Registration registration = HANDOFFS.remove(job);
        if (registration != null) registration.post(result);
    }
    private static void failPublication(Job job) {
        Registration registration = HANDOFFS.remove(job);
        if (registration != null) registration.refuseHandoff();
    }
    private static ResolutionFailure refused(Failure code) { return new ResolutionFailure(code); }

    // Package-only owned test composition. Production never creates an instance per session.
    interface Lookup { InetAddress lookupFixedHost() throws Exception; }
    interface HandoffProbe { void beforePost(); }
    static ProcessPairingDnsResolver forFixture(Lookup lookup, HandoffProbe probe) {
        return new ProcessPairingDnsResolver(Objects.requireNonNull(lookup), Objects.requireNonNull(probe), true);
    }
    void closeFixtureWhenLookupReturns() {
        requireFixture();
        Registration registration;
        synchronized (lock) { closed = true; registration = current; }
        if (registration != null) registration.detach();
        worker.closeWhenLookupReturns();
    }
    boolean joinFixtureWorker(long timeout, TimeUnit unit) throws InterruptedException {
        requireFixture();
        if (timeout <= 0 || unit == null) throw new IllegalArgumentException("Bounded positive timeout required");
        return worker.joinForFixture(Math.max(1, unit.toMillis(timeout)));
    }
    boolean fixtureLookupIsBusy() { requireFixture(); return worker.busyForFixture(); }
    private void requireFixture() {
        if (!fixture) throw new IllegalStateException("Owned fixture resolver required");
    }
}
