package com.elamin.beluga.protocol;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.UUID;
import org.junit.Test;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Confirmation;
import com.elamin.beluga.protocol.PairingCanonicalCodec.ConfirmationFields;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Hello;
import com.elamin.beluga.protocol.PairingCanonicalCodec.HelloFields;
import com.elamin.beluga.protocol.PairingCanonicalCodec.Role;
import com.elamin.beluga.protocol.PairingPayloadDecoder.CommitPayload;
import com.elamin.beluga.protocol.PairingPayloadDecoder.ConfirmationPayload;
import com.elamin.beluga.protocol.PairingPayloadDecoder.HelloPayload;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.StoreStamp;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.Agreement;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.PreparedViewer;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.RecordPhase;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.ViewerIdentity;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.ViewerPairRecord;
import com.elamin.beluga.protocol.ViewerStorageCatalog.Failure;

/** Existing JUnit4 only. Public fixed vectors; fake publication tests are NOT Android durability proof. */
public final class ViewerStorageCatalogTest {
    private static final UUID VIEWER = UUID.fromString("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE");
    private static final UUID SLOT = UUID.fromString("99999999-8888-7777-6666-555555555555");
    private static final byte[] INVITATION = repeat(0x55, 32);
    private static final String FIXTURE_SHA = "7d8a58cd34400271d0c68ac1e263450c4ad4978337ae1bb87246362a6d0ec06a";

    @Test public void enrollmentIsExactDefensiveAndHasNoSelectedFallback() throws Exception {
        byte[] seed = repeat(0x22, 32);
        try (ViewerStorageCatalog catalog = ViewerStorageCatalog.firstEnrollment(VIEWER, seed)) {
            byte[] before = catalog.encode(); Arrays.fill(seed, (byte) 0);
            assertArrayEquals(before, catalog.encode()); assertNull(catalog.selectedSlot); assertTrue(catalog.entries().isEmpty());
            try (ViewerStorageCatalog decoded = ViewerStorageCatalog.decode(before)) {
                assertArrayEquals(before, decoded.encode()); assertEquals(VIEWER, decoded.identity().deviceID());
                assertArrayEquals(catalog.identity().signingPublicKey(), decoded.identity().signingPublicKey());
            }
            assertEquals("<redacted encrypted-catalog plaintext>", catalog.toString());
        }
    }
    @Test public void strictBoundedParserRejectsTypesAliasesTrailingAndIdentityDrift() throws Exception {
        try (ViewerStorageCatalog catalog = fresh()) {
            byte[] original = catalog.encode();
            for (int cut : new int[] { 0, 1, 8, 24, original.length - 1 }) refused(() -> ViewerStorageCatalog.decode(Arrays.copyOf(original, cut)));
            refused(() -> ViewerStorageCatalog.decode(Arrays.copyOf(original, original.length + 1)));
            refused(() -> ViewerStorageCatalog.decode(new byte[ViewerStorageCatalog.MAXIMUM_BYTES + 1]));
            for (int offset : new int[] { 0, 24, 56, 88, 112 }) {
                byte[] changed = original.clone(); changed[offset] ^= (byte) 0xff; refused(() -> ViewerStorageCatalog.decode(changed));
            }
            byte[] count = original.clone(); ByteBuffer.wrap(count).putInt(113, Integer.MAX_VALUE); refused(() -> ViewerStorageCatalog.decode(count));
            byte[] negative = original.clone(); ByteBuffer.wrap(negative).putLong(88, -1); refused(() -> ViewerStorageCatalog.decode(negative));
        }
    }
    @Test public void reservationsUseExactCASAndCannotEvictOrExceedCapacity() throws Exception {
        ViewerStorageCatalog current = fresh();
        try {
            for (int i = 1; i <= ViewerStorageCatalog.MAXIMUM_MACS; i++) {
                ViewerStorageCatalog next = current.begin(new UUID(0, i), repeat(i, 32), current.catalogRevision, current.selectionRevision);
                current.close(); current = next;
            }
            assertEquals(32, current.entries().size()); assertEquals(new UUID(0, 32), current.selectedSlot);
            final ViewerStorageCatalog full = current;
            refused(() -> full.begin(new UUID(0, 33), INVITATION, full.catalogRevision, full.selectionRevision));
            refused(() -> full.begin(new UUID(0, 32), INVITATION, full.catalogRevision, full.selectionRevision));
            refused(() -> full.select(null, full.catalogRevision - 1, full.selectionRevision));
            refused(() -> full.select(null, full.catalogRevision, full.selectionRevision - 1));
            refused(() -> full.select(SLOT, full.catalogRevision, full.selectionRevision));
        } finally { current.close(); }
    }
    @Test public void explicitAbandonmentRestoresCapacityWithoutEvictingBoundMacs() throws Exception {
        ViewerStorageCatalog current = fresh();
        try {
            for (int i = 1; i <= 32; i++) {
                ViewerStorageCatalog next = current.begin(new UUID(0, i), repeat(i, 32), current.catalogRevision, current.selectionRevision);
                current.close(); current = next;
            }
            final ViewerStorageCatalog full = current;
            refused(() -> full.abandon(new UUID(0, 32), full.catalogRevision - 1, full.selectionRevision));
            for (int i = 1; i <= 32; i++) {
                ViewerStorageCatalog next = current.abandon(new UUID(0, i), current.catalogRevision, current.selectionRevision);
                current.close(); current = next;
            }
            assertTrue(current.entries().isEmpty()); assertNull(current.selectedSlot);
            try (ViewerStorageCatalog reusable = current.begin(SLOT, INVITATION, current.catalogRevision, current.selectionRevision);
                 ViewerStorageCatalog bound = reusable.write(reusable.stamp(SLOT), records().pending);
                 ViewerStorageCatalog other = bound.begin(new UUID(0, 2), repeat(2, 32), bound.catalogRevision, bound.selectionRevision);
                 ViewerStorageCatalog abandoned = other.abandon(new UUID(0, 2), other.catalogRevision, other.selectionRevision)) {
                refused(() -> bound.abandon(SLOT, bound.catalogRevision, bound.selectionRevision));
                assertEquals(1, abandoned.entries().size()); assertArrayEquals(bound.entry(SLOT).bytes(), abandoned.entry(SLOT).bytes());
                assertNull(abandoned.selectedSlot); assertArrayEquals(bound.publicKey(), abandoned.publicKey());
            }
        } finally { current.close(); }
    }
    @Test public void actualSnapshotEnumeratesReloadedUnboundSlotsAndRestoresFullCapacity() throws Exception {
        ViewerStorageCatalog current = fresh(); byte[] originalPublic = current.publicKey();
        try {
            for (int i = 1; i <= 32; i++) {
                ViewerStorageCatalog next = current.begin(new UUID(0, i), repeat(i, 32), current.catalogRevision, current.selectionRevision);
                current.close(); current = next;
            }
            ViewerStorageCatalog reloaded = ViewerStorageCatalog.decode(current.encode()); current.close(); current = reloaded;
            AndroidViewerSecureStore.Snapshot captured = AndroidViewerSecureStore.Snapshot.fromCatalog(current);
            assertTrue(captured.macs.isEmpty()); assertNull(captured.selectedMacID);
            assertEquals(new UUID(0, 32), captured.selectedEnrollmentSlot); assertEquals(32, captured.pendingEnrollments.size());
            try { captured.pendingEnrollments.clear(); fail("snapshot list was mutable"); }
            catch (UnsupportedOperationException expected) { /* immutable actual store mapping */ }
            int number = 1;
            for (AndroidViewerSecureStore.PendingEnrollment pending : captured.pendingEnrollments) {
                assertEquals(new UUID(0, number++), pending.slot);
                assertEquals("<unbound enrollment slot; not an authenticated Mac>", pending.toString());
                AndroidViewerSecureStore.Snapshot exact = AndroidViewerSecureStore.Snapshot.fromCatalog(current);
                ViewerStorageCatalog next = current.abandon(pending.slot, exact.catalogRevision, exact.selectionRevision);
                current.close(); current = next;
                if (number == 2) {
                    final ViewerStorageCatalog afterFirst = current;
                    refused(() -> afterFirst.abandon(new UUID(0, 2), captured.catalogRevision, captured.selectionRevision));
                }
            }
            AndroidViewerSecureStore.Snapshot empty = AndroidViewerSecureStore.Snapshot.fromCatalog(current);
            assertTrue(empty.pendingEnrollments.isEmpty()); assertNull(empty.selectedEnrollmentSlot);
            assertArrayEquals(originalPublic, current.publicKey());
            try (ViewerStorageCatalog capacityRestored = current.begin(SLOT, INVITATION, empty.catalogRevision, empty.selectionRevision)) {
                assertEquals(1, capacityRestored.entries().size());
            }
        } finally { current.close(); }
    }
    @Test public void actualSnapshotNeverExposesHostBoundRecordsAsAbandonableSlots() throws Exception {
        Records original = records(); UUID secondHost = new UUID(0x7777777777777777L, 0x1111111111111111L);
        UUID otherSlot = new UUID(0, 2), unboundSlot = new UUID(0, 3); byte[] secondBytes = syntheticPending(secondHost, 0x61);
        try (ViewerStorageCatalog initial = fresh(); ViewerStorageCatalog first = initial.begin(SLOT, INVITATION, 0, 0);
             ViewerStorageCatalog stored = first.write(first.stamp(SLOT), original.pending);
             ViewerStorageCatalog other = stored.begin(otherSlot, repeat(2, 32), stored.catalogRevision, stored.selectionRevision);
             ViewerStorageCatalog both = other.write(other.stamp(otherSlot), secondBytes);
             ViewerStorageCatalog pending = both.begin(unboundSlot, repeat(3, 32), both.catalogRevision, both.selectionRevision);
             ViewerStorageCatalog reloaded = ViewerStorageCatalog.decode(pending.encode())) {
            AndroidViewerSecureStore.Snapshot view = AndroidViewerSecureStore.Snapshot.fromCatalog(reloaded);
            assertEquals(2, view.macs.size()); assertEquals(1, view.pendingEnrollments.size());
            assertEquals(unboundSlot, view.pendingEnrollments.get(0).slot); assertEquals(unboundSlot, view.selectedEnrollmentSlot);
            assertNull(view.selectedMacID); assertEquals(reloaded.catalogRevision, view.catalogRevision);
            assertEquals(reloaded.selectionRevision, view.selectionRevision);
            refused(() -> reloaded.abandon(SLOT, view.catalogRevision, view.selectionRevision));
            try (ViewerStorageCatalog abandoned = reloaded.abandon(view.pendingEnrollments.get(0).slot, view.catalogRevision, view.selectionRevision)) {
                AndroidViewerSecureStore.Snapshot after = AndroidViewerSecureStore.Snapshot.fromCatalog(abandoned);
                assertTrue(after.pendingEnrollments.isEmpty()); assertEquals(2, after.macs.size());
                assertArrayEquals(original.pending, abandoned.entry(SLOT).bytes()); assertArrayEquals(secondBytes, abandoned.entry(otherSlot).bytes());
                assertArrayEquals(initial.publicKey(), abandoned.publicKey()); assertNull(after.selectedEnrollmentSlot); assertNull(after.selectedMacID);
            }
        }
    }
    @Test public void exactPendingAcceptedAdmissionActiveAndReplayBytesArePreserved() throws Exception {
        Records records = records();
        try (ViewerStorageCatalog empty = fresh(); ViewerStorageCatalog reserved = empty.begin(SLOT, INVITATION, 0, 0)) {
            StoreStamp emptyStamp = reserved.stamp(SLOT);
            try (ViewerStorageCatalog pending = reserved.write(emptyStamp, records.pending);
                 ViewerStorageCatalog accepted = pending.write(pending.stamp(SLOT), records.accepted);
                 ViewerStorageCatalog admitted = accepted.admit(accepted.stamp(SLOT), 0, INVITATION);
                 ViewerStorageCatalog replay = admitted.write(admitted.stamp(SLOT), records.accepted);
                 ViewerStorageCatalog active = replay.write(replay.stamp(SLOT), records.active)) {
                assertNull(emptyStamp.pairID); assertFalse(SLOT.equals(records.host));
                assertEquals(records.host, pending.entry(SLOT).record.hostDeviceID());
                assertArrayEquals(records.pending, pending.entry(SLOT).bytes());
                assertArrayEquals(records.accepted, accepted.entry(SLOT).bytes());
                assertTrue(accepted.stamp(SLOT).same(admitted.stamp(SLOT))); assertEquals(1, admitted.admissionRevision(SLOT));
                assertArrayEquals(records.accepted, replay.entry(SLOT).bytes()); assertArrayEquals(records.active, active.entry(SLOT).bytes());
                assertEquals(RecordPhase.ACTIVE, active.entry(SLOT).record.phase());
                assertEquals("1", active.entry(SLOT).record.nextOutboundReconnectSequence());
                assertEquals("0", active.entry(SLOT).record.highestAcceptedReconnectSequence());
                try (ViewerStorageCatalog reopened = ViewerStorageCatalog.decode(active.encode())) {
                    assertArrayEquals(records.active, reopened.entry(SLOT).bytes()); assertEquals(1, reopened.admissionRevision(SLOT));
                }
                refused(() -> active.write(active.stamp(SLOT), records.pending));
                refused(() -> accepted.write(emptyStamp, records.active));
                refused(() -> accepted.admit(accepted.stamp(SLOT), 1, INVITATION));
                refused(() -> accepted.admit(accepted.stamp(SLOT), 0, repeat(0, 32)));
                refused(() -> admitted.admit(admitted.stamp(SLOT), 0, INVITATION));
            }
            try (ViewerStorageCatalog pending = reserved.write(emptyStamp, records.pending);
                 ViewerStorageCatalog accepted = pending.write(pending.stamp(SLOT), records.accepted)) {
                refused(() -> accepted.write(accepted.stamp(SLOT), records.active));
            }
        }
    }
    @Test public void hostCollisionAndStaleSlotCannotReplaceAnotherMac() throws Exception {
        Records records = records();
        try (ViewerStorageCatalog initial = fresh(); ViewerStorageCatalog first = initial.begin(SLOT, INVITATION, 0, 0);
             ViewerStorageCatalog stored = first.write(first.stamp(SLOT), records.pending);
             ViewerStorageCatalog second = stored.begin(new UUID(0, 2), repeat(2, 32), stored.catalogRevision, stored.selectionRevision)) {
            refused(() -> second.write(second.stamp(new UUID(0, 2)), records.pending));
            refused(() -> second.write(stored.stamp(SLOT), records.accepted));
            assertArrayEquals(records.pending, second.entry(SLOT).bytes());
            assertNull(second.entry(new UUID(0, 2)).record);
            try (ViewerStorageCatalog selected = second.select(records.host, second.catalogRevision, second.selectionRevision);
                 ViewerStorageCatalog forgotten = selected.forget(records.host, selected.catalogRevision, selected.selectionRevision)) {
                assertEquals(SLOT, selected.selectedSlot); assertNull(forgotten.selectedSlot);
                assertEquals(1, forgotten.entries().size()); assertNull(forgotten.entries().get(0).record);
                assertEquals(VIEWER, forgotten.deviceID); assertArrayEquals(initial.publicKey(), forgotten.publicKey());
                refused(() -> forgotten.select(records.host, forgotten.catalogRevision, forgotten.selectionRevision));
            }
        }
    }
    @Test public void twoAuthenticatedMacsSurviveSelectionReloadAndPerMacForget() throws Exception {
        Records original = records(); UUID secondHost = new UUID(0x7777777777777777L, 0x1111111111111111L), secondSlot = new UUID(0, 2);
        byte[] otherPending = syntheticPending(secondHost, 0x61);
        try (ViewerStorageCatalog initial = fresh(); ViewerStorageCatalog first = initial.begin(SLOT, INVITATION, 0, 0);
             ViewerStorageCatalog firstStored = first.write(first.stamp(SLOT), original.pending);
             ViewerStorageCatalog second = firstStored.begin(secondSlot, repeat(2, 32), firstStored.catalogRevision, firstStored.selectionRevision);
             ViewerStorageCatalog both = second.write(second.stamp(secondSlot), otherPending);
             ViewerStorageCatalog reopened = ViewerStorageCatalog.decode(both.encode());
             ViewerStorageCatalog selectedFirst = reopened.select(original.host, reopened.catalogRevision, reopened.selectionRevision);
             ViewerStorageCatalog forgotFirst = selectedFirst.forget(original.host, selectedFirst.catalogRevision, selectedFirst.selectionRevision);
             ViewerStorageCatalog selectedOther = forgotFirst.select(secondHost, forgotFirst.catalogRevision, forgotFirst.selectionRevision)) {
            assertEquals(2, reopened.entries().size()); assertEquals(secondSlot, reopened.selectedSlot);
            assertArrayEquals(original.pending, reopened.entry(SLOT).bytes()); assertArrayEquals(otherPending, reopened.entry(secondSlot).bytes());
            assertEquals(SLOT, selectedFirst.selectedSlot); assertNull(forgotFirst.selectedSlot);
            assertEquals(1, forgotFirst.entries().size()); assertArrayEquals(otherPending, forgotFirst.entry(secondSlot).bytes());
            assertEquals(secondSlot, selectedOther.selectedSlot); assertEquals(VIEWER, selectedOther.deviceID);
            assertArrayEquals(initial.publicKey(), selectedOther.publicKey());
            refused(() -> selectedOther.forget(original.host, selectedOther.catalogRevision, selectedOther.selectionRevision));
            refused(() -> selectedOther.begin(new UUID(0, 3), repeat(2, 32), selectedOther.catalogRevision, selectedOther.selectionRevision));
            // Existing real active record with no admission is not a valid local catalog state.
            try (ViewerStorageCatalog accepted = firstStored.write(firstStored.stamp(SLOT), original.accepted);
                 ViewerStorageCatalog admitted = accepted.admit(accepted.stamp(SLOT), 0, INVITATION);
                 ViewerStorageCatalog active = admitted.write(admitted.stamp(SLOT), original.active)) {
                byte[] badAdmission = active.encode(); ByteBuffer.wrap(badAdmission).putLong(133 + 16 + 32, 0);
                final byte[] malformed = badAdmission; refused(() -> ViewerStorageCatalog.decode(malformed));
            }
        }
    }
    @Test public void duplicateSlotsAndRecordTamperAreRefused() throws Exception {
        Records records = records();
        try (ViewerStorageCatalog initial = fresh(); ViewerStorageCatalog one = initial.begin(SLOT, INVITATION, 0, 0);
             ViewerStorageCatalog two = one.begin(new UUID(0, 2), repeat(2, 32), one.catalogRevision, one.selectionRevision)) {
            byte[] encoded = two.encode();
            // Selected UUID adds16: first entry starts133; empty entry is60 bytes.
            System.arraycopy(encoded, 133, encoded, 193, 16); refused(() -> ViewerStorageCatalog.decode(encoded));
            byte[] bad = records.pending.clone(); bad[bad.length - 1] ^= 1; refused(() -> one.write(one.stamp(SLOT), bad));
        }
    }
    @Test public void everyCheckedBoundaryFailureStopsAndNeverReturnsSuccess() throws Exception {
        List<String> ordered = Arrays.asList("intent-create", "intent-sync", "write", "file-sync-close", "predecessor", "rename",
                "directory-sync", "readback", "decrypt-readback", "intent-unlink", "intent-directory-sync");
        for (String stage : ordered) {
            FakeBoundary boundary = new FakeBoundary(stage, false);
            refused(() -> CheckedCatalogPublication.publish(boundary, new byte[] { 1, 2, 3 }, 10));
            assertEquals("close", boundary.steps.get(boundary.steps.size() - 1));
            List<String> expected = new ArrayList<>(ordered.subList(0, ordered.indexOf(stage) + 1)); expected.add("close");
            assertEquals(expected, boundary.steps);
            if (!stage.equals("intent-create") && !stage.equals("intent-directory-sync")) {
                assertTrue(boundary.intentPresent); refused(() -> ViewerStorageCatalog.demand(!boundary.intentPresent));
            }
            if (stage.equals("intent-directory-sync")) {
                assertFalse(boundary.intentPresent); assertTrue(boundary.verifiedPublication);
            }
        }
        FakeBoundary mismatch = new FakeBoundary(null, true);
        refused(() -> CheckedCatalogPublication.publish(mismatch, new byte[] { 1, 2, 3 }, 10));
        FakeBoundary good = new FakeBoundary(null, false);
        CheckedCatalogPublication.publish(good, new byte[] { 1, 2, 3 }, 10);
        List<String> success = new ArrayList<>(ordered); success.add("close"); assertEquals(success, good.steps);
        assertFalse(good.intentPresent); assertTrue(good.verifiedPublication);
        refused(() -> CheckedCatalogPublication.publish(new FakeBoundary(null, false), new byte[11], 10));
    }
    private static final class FakeBoundary implements CheckedCatalogPublication.Boundary {
        final List<String> steps = new ArrayList<>(); final String failure; final boolean mismatch; byte[] written;
        boolean intentPresent, verifiedPublication;
        FakeBoundary(String failure, boolean mismatch) { this.failure = failure; this.mismatch = mismatch; }
        void step(String stage) throws Failure { steps.add(stage); if (stage.equals(failure)) throw new Failure(); }
        @Override public void createAndSyncIntent(byte[] bytes) throws Failure { step("intent-create"); intentPresent = true; step("intent-sync"); }
        @Override public void writeExclusive(byte[] bytes) throws Failure { step("write"); written = bytes.clone(); }
        @Override public void syncAndCloseFile() throws Failure { step("file-sync-close"); }
        @Override public void recheckPredecessorAndOwner() throws Failure { step("predecessor"); }
        @Override public void rename() throws Failure { step("rename"); }
        @Override public void syncDirectory() throws Failure { step("directory-sync"); }
        @Override public byte[] boundedReadback() throws Failure { step("readback"); byte[] value = written.clone(); if (mismatch) value[0] ^= 1; return value; }
        @Override public void verifyDecryptedReadback(byte[] bytes) throws Failure { step("decrypt-readback"); verifiedPublication = true; }
        @Override public void clearAndSyncIntent() throws Failure { step("intent-unlink"); intentPresent = false; step("intent-directory-sync"); }
        @Override public void closeOwnedDescriptors() { steps.add("close"); }
    }
    private static ViewerStorageCatalog fresh() throws Failure { return ViewerStorageCatalog.firstEnrollment(VIEWER, repeat(0x22, 32)); }
    private static byte[] repeat(int value, int length) { byte[] result = new byte[length]; Arrays.fill(result, (byte) value); return result; }
    private interface Attempt { void run() throws Exception; }
    private static void refused(Attempt attempt) throws Exception {
        try { attempt.run(); fail("private storage unexpectedly admitted"); }
        catch (Failure expected) { assertEquals("Beluga private storage refused", expected.getMessage()); }
    }
    private static final class Records {
        final byte[] pending, accepted, active; final UUID host;
        Records(byte[] pending, byte[] accepted, byte[] active, UUID host) { this.pending = pending; this.accepted = accepted; this.active = active; this.host = host; }
    }
    private static Records records() throws Exception {
        Map<String, byte[]> rows = fixtures(); ViewerIdentity identity = ViewerPairingAuthenticator.viewerIdentity(VIEWER, rows.get("input.viewer-signing-seed"));
        PreparedViewer prepared = ViewerPairingAuthenticator.authenticateRetainedLocalHello(VIEWER, "Test iPhone", rows.get("input.viewer-signing-seed"),
                rows.get("input.invitation-secret"), rows.get("input.viewer-ephemeral-private"), rows.get("input.viewer-nonce"),
                (HelloPayload) PairingPayloadDecoder.decode(rows.get("hello.viewer.payload")));
        Agreement agreement = ViewerPairingAuthenticator.acceptHost(prepared, (HelloPayload) PairingPayloadDecoder.decode(rows.get("hello.host.payload")));
        ViewerPairRecord pending = agreement.makePendingRecord(agreement.authenticateHostConfirmation(
                (ConfirmationPayload) PairingPayloadDecoder.decode(rows.get("confirmation.host.payload"))), 1700000000.25);
        ViewerPairRecord accepted = pending.prepareAcknowledgement((CommitPayload) PairingPayloadDecoder.decode(rows.get("commit.proposal.payload")), identity).record();
        ViewerPairRecord active = accepted.acceptCompletion((CommitPayload) PairingPayloadDecoder.decode(rows.get("commit.completion.payload")), identity).record();
        return new Records(pending.encodeForPrivateStorage(identity).copyForPrivateStorage(), accepted.encodeForPrivateStorage(identity).copyForPrivateStorage(),
                active.encodeForPrivateStorage(identity).copyForPrivateStorage(), pending.hostDeviceID());
    }
    /** Synthetic second host uses reviewed primitives and the actual viewer auth API; no mocked authenticated record. */
    private static byte[] syntheticPending(UUID hostID, int hostSeedByte) throws Exception {
        byte[] hostSeed = repeat(hostSeedByte, 32), hostEphemeral = repeat(0x63, 32), viewerEphemeral = repeat(0x64, 32);
        byte[] invitation = repeat(0x65, 20), viewerSeed = repeat(0x22, 32);
        PreparedViewer viewer = ViewerPairingAuthenticator.prepare(VIEWER, "Test viewer", viewerSeed, invitation, viewerEphemeral, repeat(0x66, 32));
        HelloFields hostFields = new HelloFields(1, hostID, Role.HOST, "Second test Mac", BouncyCastlePairingCrypto.ed25519PublicKey(hostSeed),
                BouncyCastlePairingCrypto.x25519PublicKey(hostEphemeral), repeat(0x67, 32));
        byte[] helloTag = BouncyCastlePairingCrypto.hmacSha256(invitation, PairingCanonicalCodec.helloPskInput(hostFields));
        Hello unsigned = new Hello(hostFields, helloTag, new byte[64]);
        Hello host = new Hello(hostFields, helloTag, BouncyCastlePairingCrypto.ed25519Sign(hostSeed, PairingCanonicalCodec.helloSignatureInput(unsigned)));
        Agreement agreement = ViewerPairingAuthenticator.acceptHost(viewer, (HelloPayload) PairingPayloadDecoder.decode(PairingCanonicalCodec.helloPayload(host)));
        HelloPayload viewerHello = (HelloPayload) PairingPayloadDecoder.decode(viewer.helloPayload());
        byte[] shared = BouncyCastlePairingCrypto.x25519Agreement(hostEphemeral, viewerHello.ephemeralKeyAgreementPublicKey());
        byte[] ikm = new byte[52]; System.arraycopy(invitation, 0, ikm, 0, 20); System.arraycopy(shared, 0, ikm, 20, 32);
        byte[] transcript = agreement.transcriptHash();
        byte[] root = BouncyCastlePairingCrypto.hkdfSha256(ikm, transcript, "AudioStreamer.Pairing.Root.v1".getBytes(StandardCharsets.UTF_8), 32);
        byte[] confirmationKey = BouncyCastlePairingCrypto.hkdfSha256(root, transcript, "AudioStreamer.Pairing.Confirmation.host.v1".getBytes(StandardCharsets.UTF_8), 32);
        ConfirmationFields fields = new ConfirmationFields(1, agreement.pairID(), hostID, Role.HOST, VIEWER, transcript);
        byte[] tag = BouncyCastlePairingCrypto.hmacSha256(confirmationKey, PairingCanonicalCodec.confirmationMacInput(fields));
        Confirmation unsignedConfirmation = new Confirmation(fields, tag, new byte[64]);
        Confirmation full = new Confirmation(fields, tag, BouncyCastlePairingCrypto.ed25519Sign(hostSeed, PairingCanonicalCodec.confirmationSignatureInput(unsignedConfirmation)));
        ViewerPairRecord record = agreement.makePendingRecord(agreement.authenticateHostConfirmation(
                (ConfirmationPayload) PairingPayloadDecoder.decode(PairingCanonicalCodec.confirmationPayload(full))), 1700000001.25);
        return record.encodeForPrivateStorage(ViewerPairingAuthenticator.viewerIdentity(VIEWER, viewerSeed)).copyForPrivateStorage();
    }
    private static Map<String, byte[]> fixtures() throws Exception {
        byte[] bytes;
        try (InputStream input = ViewerStorageCatalogTest.class.getResourceAsStream("/public-swift-engine-v1.tsv")) {
            assertTrue("existing public fixture resource is required", input != null);
            ByteArrayOutputStream out = new ByteArrayOutputStream(); byte[] chunk = new byte[4096]; int count;
            while ((count = input.read(chunk)) != -1) { assertTrue(out.size() + count <= 256 * 1024); out.write(chunk, 0, count); }
            bytes = out.toByteArray();
        }
        StringBuilder sha = new StringBuilder(); for (byte value : MessageDigest.getInstance("SHA-256").digest(bytes)) sha.append(String.format(java.util.Locale.ROOT, "%02x", value & 0xff));
        assertEquals(FIXTURE_SHA, sha.toString()); Map<String, byte[]> rows = new TreeMap<>();
        for (String line : new String(bytes, StandardCharsets.UTF_8).split("\n")) if (!line.isEmpty() && !line.startsWith("#")) {
            String[] parts = line.split("\t", -1); assertEquals(2, parts.length); assertNull(rows.put(parts[0], Base64.getDecoder().decode(parts[1])));
        }
        assertEquals(45, rows.size()); return rows;
    }
}
