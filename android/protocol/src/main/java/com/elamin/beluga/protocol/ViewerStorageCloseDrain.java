package com.elamin.beluga.protocol;

import com.elamin.beluga.protocol.ViewerBootstrapReducer.CloseCallback;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.CloseObservation;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.ClosePort;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Closed;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Effect;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Kind;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Owner;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Transport;
import com.elamin.beluga.protocol.ViewerStorageCatalog.Failure;

/** Trusted native ClosePort composition; neither a socket implementation nor physical-close proof by itself. */
final class ViewerStorageCloseDrain implements ClosePort {
    interface Receiver { void acknowledged(Receipt receipt) throws Failure; }
    static final class Receipt {
        private final ViewerStorageCloseDrain issuer;
        private final Effect effect;
        private Receipt(ViewerStorageCloseDrain issuer, Effect effect) { this.issuer = issuer; this.effect = effect; }
        boolean belongsTo(ViewerStorageCloseDrain exactIssuer, Owner exactOwner, Transport exactTransport) {
            return issuer == exactIssuer && issuer.owner == exactOwner && issuer.transport == exactTransport
                    && effect == issuer.captured && effect.kind == Kind.CLOSE
                    && effect.exactTransportForTrustedPort() == exactTransport && exactOwner.isRetired();
        }
        @Override public String toString() { return "<redacted exact trusted close receipt>"; }
    }
    private final Owner owner;
    private final Transport transport;
    private final ClosePort delegate;
    private final Receiver receiver;
    private Effect captured;
    private boolean returned, failed, consumed;
    private CloseObservation pending;
    private CloseCallback completion;
    ViewerStorageCloseDrain(Owner owner, Transport transport, ClosePort trustedDelegate, Receiver receiver) throws Failure {
        ViewerStorageCatalog.demand(owner != null && transport != null && trustedDelegate != null && receiver != null);
        this.owner = owner; this.transport = transport; delegate = trustedDelegate; this.receiver = receiver;
    }
    boolean isFor(Owner exactOwner, Transport exactTransport) { return owner == exactOwner && transport == exactTransport; }
    @Override public void close(Effect effect, CloseCallback callback) {
        synchronized (this) {
            if (captured != null || effect == null || callback == null || effect.kind != Kind.CLOSE
                    || !owner.isRetired() || !effect.ownerRetiredForTrustedPort()
                    || effect.exactTransportForTrustedPort() != transport) return;
            // Capture before invoking the delegate, including when it completes inline.
            captured = effect; completion = callback;
        }
        try { delegate.close(effect, this::observed); }
        catch (RuntimeException refusal) { synchronized (this) { failed = true; pending = null; } return; }
        CloseObservation ready;
        synchronized (this) { returned = true; ready = pending; pending = null; }
        if (ready != null) finish(ready);
    }
    private void observed(CloseObservation observation) {
        boolean finishNow;
        synchronized (this) {
            if (consumed || failed) return;
            consumed = true; pending = observation; finishNow = returned;
            if (finishNow) pending = null;
        }
        if (finishNow) finish(observation);
    }
    private void finish(CloseObservation observation) {
        Effect exact; CloseCallback callback;
        synchronized (this) {
            if (failed || !returned || observation == null || observation.effect != captured
                    || observation.issuer != delegate || observation.transport != transport
                    || observation.result != Closed.FINISHED || !owner.isRetired()) return;
            exact = captured; callback = completion;
        }
        // Receiver takes the storage mutex to acknowledge/drain, but releases it before return.
        // Neither external delegate IO nor the reducer callback is invoked under either monitor.
        try { receiver.acknowledged(new Receipt(this, exact)); }
        catch (Failure | RuntimeException refusal) { return; }
        callback.completed(new CloseObservation(exact, this, transport, Closed.FINISHED));
    }
}
