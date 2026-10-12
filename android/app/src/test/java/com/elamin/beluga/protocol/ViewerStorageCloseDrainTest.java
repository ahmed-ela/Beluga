package com.elamin.beluga.protocol;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;
import org.junit.Test;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.CloseCallback;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.CloseObservation;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.ClosePort;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.CloseReason;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Closed;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Effect;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Invitation;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Owner;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Ports;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.StoreStamp;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Transport;
import com.elamin.beluga.protocol.ViewerStorageCatalog.Failure;

/** Tests actual wrapper admission with explicitly fake trusted close ports; NOT physical WSS-close proof. */
public final class ViewerStorageCloseDrainTest {
    @Test public void retiredAndHeldCloseCannotAcknowledgeUntilExactDelegateCompletion() throws Exception {
        Fixture f = new Fixture(); HeldClose delegate = new HeldClose(); List<ViewerStorageCloseDrain.Receipt> receipts = new ArrayList<>();
        ViewerStorageCloseDrain drain = new ViewerStorageCloseDrain(f.owner, f.transport, delegate, receipts::add);
        List<CloseObservation> completed = new ArrayList<>(); drain.close(f.close, completed::add);
        assertTrue(f.owner.isRetired()); assertEquals(1, delegate.calls); assertTrue(receipts.isEmpty()); assertTrue(completed.isEmpty());
        delegate.finish(new CloseObservation(f.close, delegate, f.transport, Closed.FINISHED));
        assertEquals(1, receipts.size()); assertTrue(receipts.get(0).belongsTo(drain, f.owner, f.transport));
        assertEquals(1, completed.size()); assertTrue(completed.get(0).issuer == drain && completed.get(0).effect == f.close);
    }
    @Test public void foreignCloseNeverCallsDelegateOrReplacesCapturedClose() throws Exception {
        Fixture f = new Fixture(), foreign = new Fixture(); HeldClose delegate = new HeldClose();
        ViewerStorageCloseDrain drain = new ViewerStorageCloseDrain(f.owner, f.transport, delegate, receipt -> { });
        drain.close(foreign.close, observation -> { throw new AssertionError("foreign close completed"); }); assertEquals(0, delegate.calls);
        drain.close(f.close, observation -> { }); drain.close(foreign.close, observation -> { });
        assertEquals(1, delegate.calls); assertTrue(delegate.effect == f.close);
    }
    @Test public void malformedOrForeignFirstCompletionPoisonsThatOneCloseAttempt() throws Exception {
        for (int mutant = 0; mutant < 5; mutant++) {
            Fixture f = new Fixture(), foreign = new Fixture(); HeldClose delegate = new HeldClose();
            List<ViewerStorageCloseDrain.Receipt> receipts = new ArrayList<>(); List<CloseObservation> completed = new ArrayList<>();
            ViewerStorageCloseDrain drain = new ViewerStorageCloseDrain(f.owner, f.transport, delegate, receipts::add);
            drain.close(f.close, completed::add);
            CloseObservation wrong = mutant == 4 ? null : new CloseObservation(mutant == 0 ? foreign.close : f.close,
                    mutant == 1 ? new Object() : delegate, mutant == 2 ? foreign.transport : f.transport,
                    mutant == 3 ? null : Closed.FINISHED);
            delegate.finish(wrong); delegate.finish(new CloseObservation(f.close, delegate, f.transport, Closed.FINISHED));
            assertTrue(receipts.isEmpty()); assertTrue(completed.isEmpty());
            drain.close(f.close, completed::add); assertEquals(1, delegate.calls);
        }
    }
    @Test public void duplicateInvocationAndCompletionCannotMintAnotherReceipt() throws Exception {
        Fixture f = new Fixture(); HeldClose delegate = new HeldClose(); List<ViewerStorageCloseDrain.Receipt> receipts = new ArrayList<>();
        ViewerStorageCloseDrain drain = new ViewerStorageCloseDrain(f.owner, f.transport, delegate, receipts::add);
        List<CloseObservation> first = new ArrayList<>(), duplicate = new ArrayList<>();
        drain.close(f.close, first::add); drain.close(f.close, duplicate::add); assertEquals(1, delegate.calls);
        CloseObservation exact = new CloseObservation(f.close, delegate, f.transport, Closed.FINISHED);
        delegate.finish(exact); delegate.finish(exact); drain.close(f.close, duplicate::add);
        assertEquals(1, receipts.size()); assertEquals(1, first.size()); assertTrue(duplicate.isEmpty());
    }
    @Test public void inlineCompletionIsAdmittedOnlyAfterDelegateReturnsNormally() throws Exception {
        Fixture f = new Fixture(); List<ViewerStorageCloseDrain.Receipt> receipts = new ArrayList<>(); List<CloseObservation> completed = new ArrayList<>();
        InlineClose delegate = new InlineClose(f.transport, false);
        ViewerStorageCloseDrain drain = new ViewerStorageCloseDrain(f.owner, f.transport, delegate, receipt -> {
            assertTrue(delegate.returningNormally); receipts.add(receipt);
        });
        drain.close(f.close, completed::add); assertEquals(1, receipts.size()); assertEquals(1, completed.size());
    }
    @Test public void throwAfterInlineCompletionLeavesNoAcknowledgementAuthority() throws Exception {
        Fixture f = new Fixture(); List<ViewerStorageCloseDrain.Receipt> receipts = new ArrayList<>(); List<CloseObservation> completed = new ArrayList<>();
        InlineClose delegate = new InlineClose(f.transport, true);
        ViewerStorageCloseDrain drain = new ViewerStorageCloseDrain(f.owner, f.transport, delegate, receipts::add);
        drain.close(f.close, completed::add); drain.close(f.close, completed::add);
        assertEquals(1, delegate.calls); assertTrue(receipts.isEmpty()); assertTrue(completed.isEmpty());
    }
    @Test public void refusedBindingAcknowledgementCannotForwardReducerSuccess() throws Exception {
        Fixture f = new Fixture(); HeldClose delegate = new HeldClose(); List<CloseObservation> completed = new ArrayList<>();
        ViewerStorageCloseDrain drain = new ViewerStorageCloseDrain(f.owner, f.transport, delegate, receipt -> { throw new Failure(); });
        drain.close(f.close, completed::add); delegate.finish(new CloseObservation(f.close, delegate, f.transport, Closed.FINISHED));
        assertTrue(completed.isEmpty());
    }
    private static final class HeldClose implements ClosePort {
        int calls; Effect effect; CloseCallback callback;
        @Override public void close(Effect exact, CloseCallback completion) { calls++; effect = exact; callback = completion; }
        void finish(CloseObservation observation) { callback.completed(observation); }
    }
    private static final class InlineClose implements ClosePort {
        final Transport transport; final boolean throwsAfter; int calls; boolean returningNormally;
        InlineClose(Transport transport, boolean throwsAfter) { this.transport = transport; this.throwsAfter = throwsAfter; }
        @Override public void close(Effect effect, CloseCallback callback) {
            calls++; callback.completed(new CloseObservation(effect, this, transport, Closed.FINISHED));
            if (throwsAfter) throw new IllegalStateException("fixed synthetic close failure"); returningNormally = true;
        }
    }
    private static final class Fixture {
        final Owner owner = new Owner(UUID.randomUUID(), 1);
        final Transport transport = new Transport(owner, new Object());
        final Effect close;
        Fixture() throws Exception {
            UUID viewer = new UUID(1, 2); byte[] seed = repeat(0x22, 32), secret = repeat(0x33, 20);
            ViewerBootstrapReducer reducer = ViewerBootstrapReducer.bootstrap(owner, transport,
                    ViewerPairingAuthenticator.prepare(viewer, "Fixed public viewer", seed, secret, repeat(0x44, 32), repeat(0x55, 32)),
                    ViewerPairingAuthenticator.viewerIdentity(viewer, seed), new Invitation(repeat(0x66, 32)),
                    new StoreStamp(new UUID(3, 4), viewer, 0, 0, null, null, null, null), null, null, 1700000000.25,
                    new Ports((effect, callback) -> callback.failed(), (effect, callback) -> callback.failed(),
                            (effect, callback) -> callback.failed(), (effect, callback) -> callback.failed(), (effect, callback) -> { }));
            close = reducer.close(CloseReason.CANCELLED).close; assertTrue(close != null);
        }
    }
    private static byte[] repeat(int value, int count) { byte[] bytes = new byte[count]; Arrays.fill(bytes, (byte) value); return bytes; }
}
