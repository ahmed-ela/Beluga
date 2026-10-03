package com.elamin.beluga.protocol;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.ByteBuffer;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.TreeMap;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.BiConsumer;
import org.junit.Test;
import com.elamin.beluga.protocol.PairingPayloadDecoder.CommitPayload;
import com.elamin.beluga.protocol.PairingPayloadDecoder.ConfirmationPayload;
import com.elamin.beluga.protocol.PairingPayloadDecoder.HelloPayload;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Owner;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.StoreStamp;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.Transport;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.Agreement;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.AuthFailure;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.FailureCode;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.PreparedViewer;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.ReconnectPreparation;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.ViewerIdentity;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.ViewerPairRecord;
import com.elamin.beluga.protocol.ViewerReconnectStorageLifecycle.CloseReceipt;
import com.elamin.beluga.protocol.ViewerReconnectStorageLifecycle.NativeClose;
import com.elamin.beluga.protocol.ViewerReconnectStorageLifecycle.Publication;
import com.elamin.beluga.protocol.ViewerReconnectStorageLifecycle.Reserved;
import com.elamin.beluga.protocol.ViewerStorageCatalog.Failure;

/** Actual transaction/lifecycle helper; fake publication/close adapters are NOT Android or socket proof. */
public final class ViewerReconnectStorageLifecycleTest {
    private static final UUID VIEWER = UUID.fromString("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE");
    private static final UUID SLOT = UUID.fromString("12345678-1234-5678-ABCD-123456789ABC");
    private static final String PAIRING_SHA = "7d8a58cd34400271d0c68ac1e263450c4ad4978337ae1bb87246362a6d0ec06a";
    private static final String RECONNECT_SHA = "3c8ef42139c81e4cff10fcc1957aa0460a7548792ce7e952498966eff51c629e";
    private static final List<String> PUBLICATION_STEPS = Arrays.asList("intent-create", "intent-sync", "write",
            "file-sync-close", "predecessor", "rename", "directory-sync", "readback", "decrypt-readback",
            "intent-unlink", "intent-directory-sync", "close", "catalog-readback");

    @Test public void exactRequestOnlyAdmittedAfterWholePublicationAndMatchingCatalogReadback() throws Exception {
        try (ViewerStorageCatalog predecessor = catalog()) {
            Fixture f = new Fixture(predecessor.stamp(SLOT));
            ReconnectPreparation preparation = prepare(predecessor);
            byte[] original = predecessor.encode(), exactCandidate = preparation.candidateEncoding().copyForPrivateStorage();
            FakePublication publication = new FakePublication(null);
            Reserved reserved = f.lifecycle.reserve(predecessor, preparation, publication);
            assertEquals(PUBLICATION_STEPS, publication.steps);
            assertTrue(reserved.canSend());
            assertArrayEquals(reconnect("reconnect.first.request.payload"), reserved.requestPayloadForTrustedSender());
            assertArrayEquals(original, predecessor.encode());
            try (ViewerStorageCatalog durableFixture = ViewerStorageCatalog.decode(publication.published)) {
                assertArrayEquals(exactCandidate, durableFixture.entry(SLOT).bytes());
                assertEquals("2", durableFixture.entry(SLOT).record.nextOutboundReconnectSequence());
                assertEquals("0", durableFixture.entry(SLOT).record.highestAcceptedReconnectSequence());
                assertTrue(reserved.afterStamp().same(durableFixture.stamp(SLOT)));
                assertEquals(predecessor.catalogRevision + 1, durableFixture.catalogRevision);
                assertEquals(predecessor.selectionRevision, durableFixture.selectionRevision);
                assertEquals(1, durableFixture.admissionRevision(SLOT));
                assertEquals(SLOT, durableFixture.selectedSlot);
            }
            byte[] payload = reserved.requestPayloadForTrustedSender(); Arrays.fill(payload, (byte) 0);
            assertArrayEquals(reconnect("reconnect.first.request.payload"), reserved.requestPayloadForTrustedSender());
            finish(f);
            assertFalse(reserved.canSend()); refused(reserved::requestPayloadForTrustedSender);
        }
    }

    @Test public void heldFinalReadbackCannotReturnARequestCapabilityEarly() throws Exception {
        try (ViewerStorageCatalog predecessor = catalog()) {
            Fixture f = new Fixture(predecessor.stamp(SLOT));
            HeldReadback publication = new HeldReadback(); AtomicReference<Reserved> exposed = new AtomicReference<>();
            ExecutorService writer = Executors.newSingleThreadExecutor(); Future<?> work = null;
            try {
                ReconnectPreparation preparation = prepare(predecessor);
                work = writer.submit(() -> { exposed.set(f.lifecycle.reserve(predecessor, preparation, publication)); return null; });
                assertTrue(publication.entered.await(3, TimeUnit.SECONDS));
                assertNull(exposed.get()); assertFalse(work.isDone());
                publication.release.countDown(); work.get(3, TimeUnit.SECONDS);
                assertNotNull(exposed.get()); assertTrue(exposed.get().canSend());
                assertArrayEquals(reconnect("reconnect.first.request.payload"), exposed.get().requestPayloadForTrustedSender());
            } finally { publication.release.countDown(); join(writer, work); finish(f); }
        }
    }

    @Test public void everyPublicationFailureAndMismatchedReadbackKeepsRequestUnadmitted() throws Exception {
        for (String stage : PUBLICATION_STEPS) {
            if (stage.equals("close")) continue;
            try (ViewerStorageCatalog predecessor = catalog()) {
                Fixture f = new Fixture(predecessor.stamp(SLOT)); ReconnectPreparation preparation = prepare(predecessor);
                FakePublication publication = new FakePublication(stage);
                refused(() -> f.lifecycle.reserve(predecessor, preparation, publication));
                assertTrue(f.owner.isRetired());
                assertTrue(publication.steps.contains(stage));
                authRefused(() -> preparation.complete(ReconnectMessages.decodeResponse(reconnect("reconnect.first.response.full"))));
                refused(() -> f.lifecycle.reserve(predecessor, prepare(predecessor), new FakePublication(null)));
                finish(f);
            }
        }
        for (int mismatch = 0; mismatch < 4; mismatch++) {
            try (ViewerStorageCatalog predecessor = catalog()) {
                Fixture f = new Fixture(predecessor.stamp(SLOT)); FakePublication publication = new FakePublication(null);
                publication.mismatch = mismatch + 1; publication.oldCatalog = predecessor.encode();
                refused(() -> f.lifecycle.reserve(predecessor, prepare(predecessor), publication));
                assertTrue(f.owner.isRetired()); assertTrue(f.lifecycle.readbackDiscrepancyForStore()); finish(f);
            }
        }
    }

    @Test public void validDifferentWholeCatalogWithSameSelectedStampIsRejected() throws Exception {
        try (ViewerStorageCatalog predecessor = catalog()) {
            Fixture f = new Fixture(predecessor.stamp(SLOT)); FakePublication publication = new FakePublication(null);
            publication.mismatch = 5;
            refused(() -> f.lifecycle.reserve(predecessor, prepare(predecessor), publication));
            assertTrue(publication.validDifferentCatalogObserved); assertTrue(f.owner.isRetired());
            assertTrue(f.lifecycle.readbackDiscrepancyForStore()); finish(f);
        }
    }

    @Test public void staleSelectionOrUnselectedRecordCannotPublishOrSpendCounter() throws Exception {
        try (ViewerStorageCatalog predecessor = catalog()) {
            StoreStamp old = predecessor.stamp(SLOT);
            try (ViewerStorageCatalog unselected = predecessor.select(null, predecessor.catalogRevision, predecessor.selectionRevision);
                 ViewerStorageCatalog selectedAgain = unselected.select(predecessor.entry(SLOT).record.hostDeviceID(),
                         unselected.catalogRevision, unselected.selectionRevision)) {
                for (ViewerStorageCatalog current : new ViewerStorageCatalog[] { unselected, selectedAgain }) {
                    Fixture f = new Fixture(old); FakePublication publication = new FakePublication(null);
                    byte[] before = current.encode();
                    refused(() -> f.lifecycle.reserve(current, prepare(current), publication));
                    assertTrue(publication.steps.isEmpty()); assertArrayEquals(before, current.encode()); finish(f);
                }
            }
        }
    }

    @Test public void oneShotReservationCannotReuseExactOrFreshPreparation() throws Exception {
        try (ViewerStorageCatalog predecessor = catalog()) {
            Fixture f = new Fixture(predecessor.stamp(SLOT)); ReconnectPreparation preparation = prepare(predecessor);
            FakePublication publication = new FakePublication(null);
            Reserved first = f.lifecycle.reserve(predecessor, preparation, publication);
            FakePublication forbidden = new FakePublication(null);
            refused(() -> f.lifecycle.reserve(predecessor, preparation, forbidden));
            refused(() -> f.lifecycle.reserve(predecessor, prepare(predecessor), forbidden));
            assertTrue(forbidden.steps.isEmpty());
            // A second reserve may revoke the first capability; it can never publish a replacement.
            if (first.canSend()) assertArrayEquals(reconnect("reconnect.first.request.payload"), first.requestPayloadForTrustedSender());
            finish(f); assertFalse(first.canSend());
        }
    }

    @Test public void cancellationBeforeReservationRefusesWithoutInvokingPublication() throws Exception {
        try (ViewerStorageCatalog predecessor = catalog()) {
            Fixture f = new Fixture(predecessor.stamp(SLOT)); f.owner.retire(); FakePublication publication = new FakePublication(null);
            refused(() -> f.lifecycle.reserve(predecessor, prepare(predecessor), publication));
            assertTrue(publication.steps.isEmpty()); finish(f);
        }
    }

    @Test public void cancellationAtRenameOrFinalReadbackCannotMintRequestCapability() throws Exception {
        for (String stage : new String[] { "predecessor", "rename", "catalog-readback" }) {
            try (ViewerStorageCatalog predecessor = catalog()) {
                Fixture f = new Fixture(predecessor.stamp(SLOT)); FakePublication publication = new FakePublication(null);
                publication.onStep = name -> { if (name.equals(stage)) f.owner.retire(); };
                refused(() -> f.lifecycle.reserve(predecessor, prepare(predecessor), publication));
                assertTrue(f.owner.isRetired()); finish(f);
            }
        }
    }

    @Test public void cancellationAfterCommittedPublicationDoesNotResetAlreadySpentCounter() throws Exception {
        try (ViewerStorageCatalog predecessor = catalog()) {
            Fixture f = new Fixture(predecessor.stamp(SLOT)); FakePublication publication = new FakePublication(null);
            publication.onStep = stage -> { if (stage.equals("catalog-readback")) f.owner.retire(); };
            refused(() -> f.lifecycle.reserve(predecessor, prepare(predecessor), publication));
            assertTrue(f.owner.isRetired()); assertFalse(f.lifecycle.readbackDiscrepancyForStore());
            finish(f);
            try (ViewerStorageCatalog reloadedCommittedFixture = ViewerStorageCatalog.decode(publication.published)) {
                assertEquals("2", reloadedCommittedFixture.entry(SLOT).record.nextOutboundReconnectSequence());
                Fixture next = new Fixture(reloadedCommittedFixture.stamp(SLOT)); FakePublication secondPublication = new FakePublication(null);
                Reserved second = next.lifecycle.reserve(reloadedCommittedFixture, prepare(reloadedCommittedFixture, "second"), secondPublication);
                assertTrue(second.canSend()); assertArrayEquals(reconnect("reconnect.second.request.payload"), second.requestPayloadForTrustedSender());
                try (ViewerStorageCatalog third = ViewerStorageCatalog.decode(secondPublication.published)) {
                    assertEquals("3", third.entry(SLOT).record.nextOutboundReconnectSequence());
                }
                assertEquals("2", reloadedCommittedFixture.entry(SLOT).record.nextOutboundReconnectSequence()); finish(next);
            }
        }
    }

    @Test public void retiringHeldReadbackMakesItsLaterCompletionInert() throws Exception {
        try (ViewerStorageCatalog predecessor = catalog()) {
            Fixture f = new Fixture(predecessor.stamp(SLOT)); HeldReadback publication = new HeldReadback();
            ExecutorService writer = Executors.newSingleThreadExecutor(); Future<?> work = null;
            try {
                ReconnectPreparation preparation = prepare(predecessor);
                work = writer.submit(() -> { refused(() -> f.lifecycle.reserve(predecessor, preparation, publication)); return null; });
                assertTrue(publication.entered.await(3, TimeUnit.SECONDS));
                CompletionStage<CloseReceipt> drain = f.lifecycle.retireAndClose();
                assertTrue(f.owner.isRetired()); assertFalse(drain.toCompletableFuture().isDone());
                publication.release.countDown(); work.get(3, TimeUnit.SECONDS);
                f.close.future.complete(null);
                assertTrue(drain.toCompletableFuture().get(3, TimeUnit.SECONDS).belongsTo(f.lifecycle));
            } finally { publication.release.countDown(); join(writer, work); finish(f); }
        }
    }

    @Test public void exactNativeFutureMustCompleteBeforeCloseReceiptAndCallsCoalesce() throws Exception {
        try (ViewerStorageCatalog predecessor = catalog()) {
            Fixture f = new Fixture(predecessor.stamp(SLOT));
            Reserved reserved = f.lifecycle.reserve(predecessor, prepare(predecessor), new FakePublication(null));
            CompletionStage<CloseReceipt> first = f.lifecycle.retireAndClose(), second = f.lifecycle.retireAndClose();
            assertTrue(f.owner.isRetired()); assertFalse(reserved.canSend()); refused(reserved::requestPayloadForTrustedSender);
            assertEquals(1, f.close.calls); assertTrue(f.close.captured == f.transport);
            assertFalse(first.toCompletableFuture().isDone()); assertFalse(second.toCompletableFuture().isDone());
            f.close.future.complete(null);
            CloseReceipt receipt = first.toCompletableFuture().get(3, TimeUnit.SECONDS);
            assertTrue(receipt.belongsTo(f.lifecycle)); assertTrue(second.toCompletableFuture().get(3, TimeUnit.SECONDS) == receipt);
            Fixture foreign = new Fixture(predecessor.stamp(SLOT)); assertFalse(receipt.belongsTo(foreign.lifecycle)); finish(foreign);
            assertTrue(f.lifecycle.retireAndClose().toCompletableFuture().get(3, TimeUnit.SECONDS) == receipt);
            assertEquals(1, f.close.calls);
        }
    }

    @Test public void failedCancelledMissingOrThrowingNativeCloseNeverProducesReceipt() throws Exception {
        try (ViewerStorageCatalog predecessor = catalog()) {
            for (int mutant = 0; mutant < 5; mutant++) {
                Fixture f = new Fixture(predecessor.stamp(SLOT)); f.close.mutant = mutant;
                CompletionStage<CloseReceipt> drain = f.lifecycle.retireAndClose();
                if (mutant == 0) f.close.future.completeExceptionally(new IllegalStateException("fixed synthetic native-close failure"));
                if (mutant == 1) f.close.future.cancel(false);
                failedDrain(drain); assertTrue(f.owner.isRetired()); assertEquals(1, f.close.calls);
                failedDrain(f.lifecycle.retireAndClose()); assertEquals(1, f.close.calls);
            }
        }
    }

    @Test public void callerCompletionOfCopiedStageCannotMintAnIssuerOwnedCloseReceipt() throws Exception {
        try (ViewerStorageCatalog predecessor = catalog()) {
            Fixture f = new Fixture(predecessor.stamp(SLOT));
            CompletableFuture<CloseReceipt> callerCopy = f.lifecycle.retireAndClose().toCompletableFuture();
            assertTrue(callerCopy.complete(null)); assertNull(callerCopy.get(3, TimeUnit.SECONDS));
            CompletionStage<CloseReceipt> independent = f.lifecycle.retireAndClose();
            assertFalse(independent.toCompletableFuture().isDone()); assertEquals(1, f.close.calls);
            f.close.future.complete(null);
            CloseReceipt actual = independent.toCompletableFuture().get(3, TimeUnit.SECONDS);
            assertNotNull(actual); assertTrue(actual.belongsTo(f.lifecycle));
        }
    }

    @Test public void wrongPhaseAndIncompleteStampCannotConstructLifecycle() throws Exception {
        try (ViewerStorageCatalog predecessor = catalog()) {
            StoreStamp active = predecessor.stamp(SLOT); Owner owner = new Owner(UUID.randomUUID(), 1);
            Transport transport = new Transport(owner, new Object()); HeldClose close = new HeldClose();
            for (StoreStamp invalid : new StoreStamp[] { null,
                    new StoreStamp(active.target, active.localID, active.catalogRevision, active.selectionRevision,
                            null, null, null, null),
                    new StoreStamp(active.target, active.localID, active.catalogRevision, active.selectionRevision,
                            active.pairID, ViewerPairingAuthenticator.RecordPhase.PENDING, active.recordDigest(), active.invitationDigest()) }) {
                refused(() -> new ViewerReconnectStorageLifecycle(owner, transport, invalid, close));
            }
            assertEquals(0, close.calls);
        }
    }

    @Test public void differentOwnerCannotBorrowAnExistingExactTransport() throws Exception {
        try (ViewerStorageCatalog predecessor = catalog()) {
            Owner transportOwner = new Owner(UUID.randomUUID(), 1), other = new Owner(UUID.randomUUID(), 1);
            Transport transport = new Transport(transportOwner, new Object()); HeldClose close = new HeldClose();
            refused(() -> new ViewerReconnectStorageLifecycle(other, transport, predecessor.stamp(SLOT), close));
            assertEquals(0, close.calls); assertFalse(transportOwner.isRetired()); assertFalse(other.isRetired());
        }
    }

    private static final class Fixture {
        final Owner owner = new Owner(UUID.randomUUID(), 1);
        final Transport transport = new Transport(owner, new Object());
        final HeldClose close = new HeldClose();
        final ViewerReconnectStorageLifecycle lifecycle;
        Fixture(StoreStamp stamp) throws Failure { lifecycle = new ViewerReconnectStorageLifecycle(owner, transport, stamp, close); }
    }
    private static final class HeldClose implements NativeClose {
        final CompletableFuture<Void> future = new CompletableFuture<>(); int calls, mutant = -1; Transport captured;
        @Override public CompletionStage<Void> close(Transport exact) {
            calls++; captured = exact;
            if (mutant == 2) return null;
            if (mutant == 3) throw new IllegalStateException("fixed synthetic close invocation failure");
            if (mutant == 4) return new InlineThenThrowFuture();
            return future;
        }
    }
    private static final class InlineThenThrowFuture extends CompletableFuture<Void> {
        @Override public CompletableFuture<Void> whenComplete(BiConsumer<? super Void, ? super Throwable> action) {
            action.accept(null, null);
            throw new IllegalStateException("fixed synthetic callback attachment failure");
        }
    }
    private interface Step { void run(String stage); }
    private static class FakePublication implements Publication, CheckedCatalogPublication.Boundary {
        final List<String> steps = new ArrayList<>(); final String failure;
        byte[] published, oldCatalog; StoreStamp publishedStamp; int mismatch;
        boolean validDifferentCatalogObserved; Step onStep = stage -> { };
        FakePublication(String failure) { this.failure = failure; }
        void step(String stage) throws Failure { steps.add(stage); onStep.run(stage); if (stage.equals(failure)) throw new Failure(); }
        @Override public void publish(ViewerStorageCatalog candidate) throws Failure {
            publishedStamp = candidate.stamp(SLOT);
            CheckedCatalogPublication.publish(this, candidate.encode(), ViewerStorageCatalog.MAXIMUM_BYTES);
        }
        @Override public byte[] readbackCatalog() throws Failure {
            step("catalog-readback");
            if (mismatch == 1) return new byte[0];
            if (mismatch == 2) { byte[] bad = published.clone(); bad[0] ^= 1; return bad; }
            if (mismatch == 3) return Arrays.copyOf(published, published.length + 1);
            if (mismatch == 4) return oldCatalog.clone();
            if (mismatch == 5) {
                // Synthetic private readback differs ONLY in file revision; it is valid and
                // has the same selected stamp. This isolates the whole-catalog equality guard.
                byte[] divergent = published.clone(); ByteBuffer bytes = ByteBuffer.wrap(divergent);
                bytes.putLong(88, bytes.getLong(88) + 1);
                try (ViewerStorageCatalog decoded = ViewerStorageCatalog.decode(divergent)) {
                    assertTrue(publishedStamp.same(decoded.stamp(SLOT)));
                    assertArrayEquals(divergent, decoded.encode()); assertFalse(Arrays.equals(published, divergent));
                }
                validDifferentCatalogObserved = true; return divergent;
            }
            return published.clone();
        }
        @Override public void createAndSyncIntent(byte[] bytes) throws Failure { step("intent-create"); step("intent-sync"); }
        @Override public void writeExclusive(byte[] bytes) throws Failure { step("write"); published = bytes.clone(); }
        @Override public void syncAndCloseFile() throws Failure { step("file-sync-close"); }
        @Override public void recheckPredecessorAndOwner() throws Failure { step("predecessor"); }
        @Override public void rename() throws Failure { step("rename"); }
        @Override public void syncDirectory() throws Failure { step("directory-sync"); }
        @Override public byte[] boundedReadback() throws Failure { step("readback"); return published.clone(); }
        @Override public void verifyDecryptedReadback(byte[] bytes) throws Failure { step("decrypt-readback"); }
        @Override public void clearAndSyncIntent() throws Failure { step("intent-unlink"); step("intent-directory-sync"); }
        @Override public void closeOwnedDescriptors() { steps.add("close"); }
    }
    private static final class HeldReadback extends FakePublication {
        final CountDownLatch entered = new CountDownLatch(1), release = new CountDownLatch(1);
        HeldReadback() { super(null); }
        @Override public byte[] readbackCatalog() throws Failure {
            entered.countDown();
            try { if (!release.await(3, TimeUnit.SECONDS)) throw new Failure(); }
            catch (InterruptedException interrupted) { Thread.currentThread().interrupt(); throw new Failure(); }
            return super.readbackCatalog();
        }
    }
    private static void finish(Fixture fixture) throws Exception {
        CompletionStage<CloseReceipt> drain = fixture.lifecycle.retireAndClose();
        fixture.close.future.complete(null); assertTrue(drain.toCompletableFuture().get(3, TimeUnit.SECONDS).belongsTo(fixture.lifecycle));
    }
    private static void join(ExecutorService executor, Future<?> work) throws Exception {
        executor.shutdown();
        if (!executor.awaitTermination(3, TimeUnit.SECONDS)) { executor.shutdownNow(); assertTrue(executor.awaitTermination(3, TimeUnit.SECONDS)); }
        if (work != null) work.get(3, TimeUnit.SECONDS);
    }
    private static void failedDrain(CompletionStage<CloseReceipt> stage) throws Exception {
        try { stage.toCompletableFuture().get(3, TimeUnit.SECONDS); fail("uncertain native cleanup produced a receipt"); }
        catch (ExecutionException expected) { assertNotNull(expected.getCause()); }
    }
    private interface Attempt { void run() throws Exception; }
    private static void refused(Attempt attempt) throws Exception {
        try { attempt.run(); fail("unproved reconnect storage unexpectedly admitted"); }
        catch (Failure expected) { assertEquals("Beluga private storage refused", expected.getMessage()); }
    }
    private static void authRefused(Attempt attempt) throws Exception {
        try { attempt.run(); fail("retired preparation unexpectedly authenticated"); }
        catch (AuthFailure expected) { assertEquals(FailureCode.INVALID_RECONNECT, expected.code()); }
    }
    private static ReconnectPreparation prepare(ViewerStorageCatalog catalog) throws Exception {
        return prepare(catalog, "first");
    }
    private static ReconnectPreparation prepare(ViewerStorageCatalog catalog, String name) throws Exception {
        String prefix = "reconnect." + name + ".";
        return catalog.entry(SLOT).record.authenticateRetainedReconnect(identity(),
                reconnect(prefix + "input.viewer-ephemeral-private"), reconnect(prefix + "input.viewer-nonce"),
                ReconnectMessages.decodeRequest(reconnect(prefix + "request.full")));
    }
    private static ViewerIdentity identity() throws Exception { return ViewerPairingAuthenticator.viewerIdentity(VIEWER, pairing("input.viewer-signing-seed")); }
    private static ViewerStorageCatalog catalog() throws Exception {
        ViewerIdentity identity = identity();
        PreparedViewer viewer = ViewerPairingAuthenticator.authenticateRetainedLocalHello(VIEWER, "Test iPhone",
                pairing("input.viewer-signing-seed"), pairing("input.invitation-secret"), pairing("input.viewer-ephemeral-private"), pairing("input.viewer-nonce"),
                (HelloPayload) PairingPayloadDecoder.decode(pairing("hello.viewer.payload")));
        Agreement agreement = ViewerPairingAuthenticator.acceptHost(viewer, (HelloPayload) PairingPayloadDecoder.decode(pairing("hello.host.payload")));
        ViewerPairRecord pending = agreement.makePendingRecord(agreement.authenticateHostConfirmation(
                (ConfirmationPayload) PairingPayloadDecoder.decode(pairing("confirmation.host.payload"))), 1700000000.25);
        ViewerPairRecord accepted = pending.prepareAcknowledgement((CommitPayload) PairingPayloadDecoder.decode(pairing("commit.proposal.payload")), identity).record();
        ViewerPairRecord active = accepted.acceptCompletion((CommitPayload) PairingPayloadDecoder.decode(pairing("commit.completion.payload")), identity).record();
        ViewerStorageCatalog[] chain = new ViewerStorageCatalog[6];
        try {
            chain[0] = ViewerStorageCatalog.firstEnrollment(VIEWER, pairing("input.viewer-signing-seed"));
            chain[1] = chain[0].begin(SLOT, repeat(0x33, 32), 0, 0);
            chain[2] = chain[1].write(chain[1].stamp(SLOT), pending.encodeForPrivateStorage(identity).copyForPrivateStorage());
            chain[3] = chain[2].write(chain[2].stamp(SLOT), accepted.encodeForPrivateStorage(identity).copyForPrivateStorage());
            chain[4] = chain[3].admit(chain[3].stamp(SLOT), 0, repeat(0x33, 32));
            chain[5] = chain[4].write(chain[4].stamp(SLOT), active.encodeForPrivateStorage(identity).copyForPrivateStorage());
            return chain[5];
        } finally { for (int i = 0; i < 5; i++) if (chain[i] != null) chain[i].close(); }
    }
    private static byte[] repeat(int value, int length) { byte[] bytes = new byte[length]; Arrays.fill(bytes, (byte) value); return bytes; }
    private static byte[] pairing(String key) throws Exception { return value(fixtures("public-swift-engine-v1.tsv", PAIRING_SHA, 45), key); }
    private static byte[] reconnect(String key) throws Exception { return value(fixtures("public-swift-saved-pair-reconnect-v1.tsv", RECONNECT_SHA, 98), key); }
    private static byte[] value(Map<String, byte[]> rows, String key) { byte[] bytes = rows.get(key); assertNotNull(bytes); return bytes.clone(); }
    private static Map<String, byte[]> fixtures(String name, String sha, int rows) throws Exception {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        try (InputStream input = ViewerReconnectStorageLifecycleTest.class.getResourceAsStream("/" + name)) {
            assertNotNull("exact existing public fixture resource required", input); byte[] chunk = new byte[4096]; int n;
            while ((n = input.read(chunk)) != -1) { assertTrue(output.size() + n <= 131072); output.write(chunk, 0, n); }
        }
        byte[] bytes = output.toByteArray(); StringBuilder actual = new StringBuilder();
        for (byte value : MessageDigest.getInstance("SHA-256").digest(bytes)) actual.append(String.format(Locale.ROOT, "%02x", value & 255));
        assertEquals(sha, actual.toString()); Map<String, byte[]> decoded = new TreeMap<>(); String previous = "";
        for (String line : new String(bytes, StandardCharsets.US_ASCII).split("\n")) {
            if (line.startsWith("#")) continue;
            String[] parts = line.split("\t", -1); assertEquals(2, parts.length); assertTrue(parts[0].compareTo(previous) > 0);
            byte[] raw = Base64.getDecoder().decode(parts[1]); assertTrue(raw.length > 0 && raw.length <= 8192);
            assertEquals(parts[1], Base64.getEncoder().encodeToString(raw)); assertNull(decoded.put(parts[0], raw)); previous = parts[0];
        }
        assertEquals(rows, decoded.size()); return decoded;
    }
}
