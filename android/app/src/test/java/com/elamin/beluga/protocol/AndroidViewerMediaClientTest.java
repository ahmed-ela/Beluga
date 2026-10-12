package com.elamin.beluga.protocol;

import static org.junit.Assert.*;
import org.junit.Test;
import com.elamin.beluga.protocol.AndroidViewerMediaClient.Ownership;
import com.elamin.beluga.protocol.AndroidViewerMediaClient.Ownership.Token;

/** Actual facade identity fence only; no Android View, JNI, route or rendered-pixel proof. */
public final class AndroidViewerMediaClientTest {
    private static Ownership<Object> foreground() {
        Ownership<Object> owner = new Ownership<>(); owner.accepting(true); return owner;
    }
    @Test public void explicitForegroundAdmissionIsRequiredForNewReceiver() {
        Ownership<Object> owner = new Ownership<>(); assertNull(owner.reserve());
        owner.accepting(true); Token<Object> token = owner.reserve(); assertNotNull(token);
        owner.accepting(false); assertTrue(owner.live(token));
        owner.complete(token, true); assertNull(owner.reserve());
        owner.accepting(true); assertNotNull(owner.reserve());
    }
    @Test public void doubleStartCannotReplaceUnfinishedReceiver() {
        Ownership<Object> owner = foreground(); Token<Object> token = owner.reserve();
        Object receiver = new Object(); assertTrue(owner.attach(token, receiver));
        assertNull(owner.reserve()); assertSame(receiver, owner.attached(token));
        owner.retire(token); assertNull(owner.reserve()); assertFalse(owner.released(token));
    }
    @Test public void activeBeforeAttachmentDoesNotInventAReceiver() {
        Ownership<Object> owner = foreground(); Token<Object> token = owner.reserve();
        assertTrue(owner.active(token)); assertNull(owner.ready(token));
        Object receiver = new Object(); assertTrue(owner.attach(token, receiver));
        assertSame(receiver, owner.ready(token));
    }
    @Test public void attachmentAloneIsNotNativeReadiness() {
        Ownership<Object> owner = foreground(); Token<Object> token = owner.reserve();
        Object receiver = new Object(); owner.attach(token, receiver); assertNull(owner.ready(token));
        assertTrue(owner.active(token)); assertSame(receiver, owner.ready(token));
    }
    @Test public void retirementBeforeAttachmentRejectsLateReadinessButRetainsDrainOwner() {
        Ownership<Object> owner = foreground(); Token<Object> token = owner.reserve();
        assertNull(owner.retire(token)); Object receiver = new Object();
        assertFalse(owner.attach(token, receiver)); assertSame(receiver, owner.attached(token));
        assertFalse(owner.active(token)); assertNull(owner.ready(token)); assertNull(owner.reserve());
        owner.complete(token, true); assertTrue(owner.released(token)); assertNotNull(owner.reserve());
    }
    @Test public void closeBeforeAttachmentRejectsAndRetainsExactLateOwner() {
        Ownership<Object> owner = foreground(); Token<Object> token = owner.reserve();
        assertSame(token, owner.close()); Object receiver = new Object();
        assertFalse(owner.attach(token, receiver)); assertSame(receiver, owner.attached(token));
        owner.complete(token, true); owner.accepting(true); assertNull(owner.reserve());
        assertNull(owner.ready(token));
    }
    @Test public void failedCleanupRemainsBlockedDespiteLaterSuccessOrActiveCallback() {
        Ownership<Object> owner = foreground(); Token<Object> token = owner.reserve();
        Object receiver = new Object(); owner.attach(token, receiver); owner.active(token);
        owner.complete(token, false); owner.complete(token, true);
        assertFalse(owner.released(token)); assertFalse(owner.active(token)); assertNull(owner.ready(token));
        assertNull(owner.reserve()); assertSame(receiver, owner.attached(token));
    }
    @Test public void staleCallbacksCannotPublishOrRetireSuccessor() {
        Ownership<Object> owner = foreground(); Token<Object> old = owner.reserve();
        owner.attach(old, new Object()); owner.active(old); owner.complete(old, true);
        Token<Object> current = owner.reserve(); Object receiver = new Object();
        owner.attach(current, receiver); owner.active(current);
        assertFalse(owner.active(old)); assertNull(owner.retire(old)); owner.complete(old, false);
        assertSame(current, owner.current()); assertSame(receiver, owner.ready(current));
        assertNull(owner.attached(old)); assertFalse(owner.released(old)); assertNull(owner.reserve());
    }
    @Test public void foreignOwnerTokenCannotAffectCurrentLifetime() {
        Ownership<Object> owner = foreground(), foreign = foreground();
        Token<Object> current = owner.reserve(), other = foreign.reserve(); Object receiver = new Object();
        owner.attach(current, receiver); owner.active(current);
        assertFalse(owner.active(other)); assertNull(owner.retire(other)); owner.complete(other, true);
        assertSame(receiver, owner.ready(current));
        assertThrows(IllegalStateException.class, () -> owner.attach(other, new Object()));
    }
    @Test public void noReplacementAttachmentEvenBeforeReady() {
        Ownership<Object> owner = foreground(); Token<Object> token = owner.reserve();
        Object receiver = new Object(); owner.attach(token, receiver);
        assertThrows(IllegalStateException.class, () -> owner.attach(token, new Object()));
        assertSame(receiver, owner.attached(token));
    }
    @Test public void completionBeforeQueuedPublicationCannotReviveRetiredReceiver() {
        Ownership<Object> owner = foreground(); Token<Object> token = owner.reserve();
        owner.attach(token, new Object()); owner.active(token); owner.complete(token, true);
        assertNull(owner.ready(token)); assertFalse(owner.active(token)); assertTrue(owner.released(token));
    }
    @Test public void retirementDuringSnapshotInvalidatesPreviouslyReadReceiver() {
        Ownership<Object> owner = foreground(); Token<Object> token = owner.reserve();
        Object receiver = new Object(); owner.attach(token, receiver); owner.active(token);
        Object sampled = owner.ready(token); assertSame(receiver, sampled);
        owner.retire(token);
        assertNotSame(sampled, owner.ready(token)); assertFalse(owner.live(token));
        assertSame(receiver, owner.attached(token)); assertFalse(owner.released(token));
    }
}
