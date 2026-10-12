package com.elamin.beluga.protocol;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import com.elamin.beluga.protocol.ViewerBootstrapReducer.StoreStamp;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.AuthFailure;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.RecordPhase;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.ReconnectPreparation;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.ViewerIdentity;
import com.elamin.beluga.protocol.ViewerPairingAuthenticator.ViewerPairRecord;

/** Private local schema, never a wire format or proof of storage. Owns managed-memory secrets. */
final class ViewerStorageCatalog implements AutoCloseable {
    static final int MAXIMUM_BYTES = 256 * 1024;
    static final int MAXIMUM_MACS = 32;
    private static final byte[] MAGIC = "BVS-CAT1".getBytes(StandardCharsets.US_ASCII);
    final UUID deviceID, selectedSlot;
    final long fileRevision, catalogRevision, selectionRevision;
    private final byte[] seed, publicKey;
    private final List<Entry> entries;

    static final class Failure extends Exception {
        private static final long serialVersionUID = 1L;
        Failure() { super("Beluga private storage refused"); }
    }
    static final class Entry {
        final UUID slot;
        final long admissionRevision;
        private final byte[] invitation, recordBytes;
        final ViewerPairRecord record;
        Entry(UUID slot, byte[] invitation, long admissionRevision, byte[] bytes, ViewerIdentity identity) throws Failure {
            demand(nonzero(slot) && invitation != null && invitation.length == 32 && admissionRevision >= 0 && admissionRevision <= 1);
            demand(bytes == null || (bytes.length > 0 && bytes.length <= ViewerPairRecord.MAXIMUM_PRIVATE_RECORD_BYTES));
            this.slot = slot; this.invitation = invitation.clone(); this.admissionRevision = admissionRevision;
            recordBytes = bytes == null ? null : bytes.clone();
            try { record = bytes == null ? null : ViewerPairRecord.restore(bytes, identity); }
            catch (AuthFailure refused) { throw new Failure(); }
            demand(record != null || admissionRevision == 0);
            demand(admissionRevision == 0 || record.phase() != RecordPhase.PENDING);
            demand(record == null || record.phase() != RecordPhase.ACTIVE || admissionRevision == 1);
        }
        byte[] bytes() { return recordBytes == null ? null : recordBytes.clone(); }
        byte[] invitation() { return invitation.clone(); }
        @Override public String toString() { return "<redacted private catalog entry>"; }
    }

    private ViewerStorageCatalog(UUID id, byte[] privateSeed, byte[] expectedPublic, long file,
            long catalog, long selection, UUID selected, List<Entry> rows) throws Failure {
        demand(nonzero(id) && privateSeed != null && privateSeed.length == 32 && expectedPublic != null
                && expectedPublic.length == 32 && file > 0 && catalog >= 0 && selection >= 0
                && file >= catalog && catalog >= selection && rows.size() <= MAXIMUM_MACS);
        deviceID = id; seed = privateSeed.clone(); publicKey = expectedPublic.clone();
        fileRevision = file; catalogRevision = catalog; selectionRevision = selection; selectedSlot = selected;
        entries = new ArrayList<>(rows);
        ViewerIdentity identity = identity();
        demand(Arrays.equals(publicKey, identity.signingPublicKey()));
        Set<UUID> slots = new HashSet<>(), hosts = new HashSet<>(), pairs = new HashSet<>();
        for (Entry entry : entries) {
            demand(slots.add(entry.slot));
            if (entry.record != null) demand(hosts.add(entry.record.hostDeviceID()) && pairs.add(entry.record.pairID()));
        }
        for (int i = 0; i < entries.size(); i++) for (int j = 0; j < i; j++)
            demand(!Arrays.equals(entries.get(i).invitation, entries.get(j).invitation));
        demand(selected == null || slots.contains(selected));
        demand(encodedSize() <= MAXIMUM_BYTES);
    }
    static ViewerStorageCatalog firstEnrollment(UUID id, byte[] seed) throws Failure {
        try {
            ViewerIdentity identity = ViewerPairingAuthenticator.viewerIdentity(id, seed);
            return new ViewerStorageCatalog(id, seed, identity.signingPublicKey(), 1, 0, 0, null, new ArrayList<>());
        } catch (AuthFailure refused) { throw new Failure(); }
    }
    ViewerIdentity identity() throws Failure {
        try { return ViewerPairingAuthenticator.viewerIdentity(deviceID, seed); }
        catch (AuthFailure refused) { throw new Failure(); }
    }
    byte[] seedForTrustedPreparation() { return seed.clone(); }
    byte[] publicKey() { return publicKey.clone(); }
    List<Entry> entries() { return new ArrayList<>(entries); }
    Entry entry(UUID slot) throws Failure {
        for (Entry row : entries) if (row.slot.equals(slot)) return row;
        throw new Failure();
    }
    StoreStamp stamp(UUID slot) throws Failure {
        Entry row = entry(slot);
        return new StoreStamp(slot, deviceID, catalogRevision, selectionRevision,
                row.record == null ? null : row.record.pairID(), row.record == null ? null : row.record.phase(),
                row.recordBytes == null ? null : sha256(row.recordBytes), row.record == null ? null : row.invitation);
    }
    long admissionRevision(UUID slot) throws Failure { return entry(slot).admissionRevision; }

    ViewerStorageCatalog begin(UUID slot, byte[] invitation, long expectedCatalog, long expectedSelection) throws Failure {
        checkRevision(expectedCatalog, expectedSelection);
        demand(nonzero(slot) && entries.size() < MAXIMUM_MACS);
        for (Entry row : entries) demand(!row.slot.equals(slot) && !Arrays.equals(row.invitation, invitation));
        List<Entry> next = entries(); next.add(new Entry(slot, invitation, 0, null, identity()));
        return successor(increment(catalogRevision), increment(selectionRevision), slot, next);
    }
    ViewerStorageCatalog write(StoreStamp expected, byte[] exactBytes) throws Failure {
        demand(expected != null && expected.same(stamp(expected.target)) && expected.target.equals(selectedSlot));
        Entry prior = entry(expected.target);
        Entry next = new Entry(prior.slot, prior.invitation, prior.admissionRevision, exactBytes, identity());
        demand(next.record != null);
        if (prior.record == null) {
            demand(next.record.phase() == RecordPhase.PENDING);
            for (Entry other : entries) demand(other.record == null || !other.record.hostDeviceID().equals(next.record.hostDeviceID()));
        } else {
            ViewerPairRecord old = prior.record, fresh = next.record;
            demand(old.pairID().equals(fresh.pairID()) && old.commitID().equals(fresh.commitID())
                    && old.hostDeviceID().equals(fresh.hostDeviceID()) && old.viewerDeviceID().equals(fresh.viewerDeviceID())
                    && Objects.equals(old.hostDisplayName(), fresh.hostDisplayName())
                    && Double.doubleToLongBits(old.createdAtEpochSeconds()) == Double.doubleToLongBits(fresh.createdAtEpochSeconds())
                    && old.nextOutboundReconnectSequence().equals(fresh.nextOutboundReconnectSequence())
                    && old.highestAcceptedReconnectSequence().equals(fresh.highestAcceptedReconnectSequence())
                    && ((old.phase() == RecordPhase.PENDING && fresh.phase() == RecordPhase.ACCEPTED_ISSUED)
                        || (old.phase() == RecordPhase.ACCEPTED_ISSUED && fresh.phase() == RecordPhase.ACCEPTED_ISSUED
                            && Arrays.equals(prior.recordBytes, exactBytes))
                        || (old.phase() == RecordPhase.ACCEPTED_ISSUED && fresh.phase() == RecordPhase.ACTIVE
                            && prior.admissionRevision == 1)));
        }
        return replace(next, increment(catalogRevision), selectionRevision, selectedSlot);
    }
    ViewerStorageCatalog admit(StoreStamp expected, long priorRevision, byte[] invitation) throws Failure {
        demand(expected != null && expected.same(stamp(expected.target)) && expected.target.equals(selectedSlot));
        Entry row = entry(expected.target);
        demand(row.record != null && row.record.phase() == RecordPhase.ACCEPTED_ISSUED && priorRevision == 0
                && row.admissionRevision == priorRevision && Arrays.equals(row.invitation, invitation));
        return replace(new Entry(row.slot, row.invitation, 1, row.recordBytes, identity()), catalogRevision, selectionRevision, selectedSlot);
    }
    /**
     * Separate ACTIVE-only counter candidate transition. Never broadens bootstrap write().
     * This returns plaintext catalog data, NOT a durable acknowledgement or send permission.
     * The real store must fence current ownership/selection and atomically publish/read back it.
     */
    ViewerStorageCatalog reserveReconnect(StoreStamp expected, ReconnectPreparation preparation) throws Failure {
        demand(expected != null && preparation != null && expected.same(stamp(expected.target))
                && expected.target.equals(selectedSlot));
        Entry prior = entry(expected.target);
        demand(prior.record != null && prior.record.phase() == RecordPhase.ACTIVE && prior.admissionRevision == 1);
        byte[] frozen = null;
        try {
            demand(preparation.matchesPredecessor(prior.record));
            frozen = preparation.candidateEncoding().copyForPrivateStorage();
            Entry next = new Entry(prior.slot, prior.invitation, prior.admissionRevision, frozen, identity());
            // The private factory has already authenticated identity and creates only the exact
            // predecessor's +1 outbound successor. Restore above also verifies the frozen bytes.
            demand(next.record != null && next.record.phase() == RecordPhase.ACTIVE
                    && next.record.nextOutboundReconnectSequence().equals(preparation.candidate().nextOutboundReconnectSequence())
                    && next.record.highestAcceptedReconnectSequence().equals(prior.record.highestAcceptedReconnectSequence()));
            return replace(next, increment(catalogRevision), selectionRevision, selectedSlot);
        } catch (AuthFailure refused) { throw new Failure(); }
        finally { if (frozen != null) Arrays.fill(frozen, (byte) 0); }
    }
    ViewerStorageCatalog select(UUID hostID, long expectedCatalog, long expectedSelection) throws Failure {
        checkRevision(expectedCatalog, expectedSelection);
        UUID slot = null;
        if (hostID != null) {
            for (Entry row : entries) if (row.record != null && row.record.hostDeviceID().equals(hostID)) slot = row.slot;
            demand(slot != null);
        }
        return successor(increment(catalogRevision), increment(selectionRevision), slot, entries());
    }
    ViewerStorageCatalog forget(UUID hostID, long expectedCatalog, long expectedSelection) throws Failure {
        checkRevision(expectedCatalog, expectedSelection); demand(nonzero(hostID));
        List<Entry> next = entries(); UUID removed = null;
        for (int i = 0; i < next.size(); i++) {
            Entry row = next.get(i);
            if (row.record != null && row.record.hostDeviceID().equals(hostID)) { removed = row.slot; next.remove(i); break; }
        }
        demand(removed != null);
        boolean selected = removed.equals(selectedSlot);
        return successor(increment(catalogRevision), selected ? increment(selectionRevision) : selectionRevision,
                selected ? null : selectedSlot, next);
    }
    /** Explicit quiescent cancellation only; never forget a host-bound record through a slot ID. */
    ViewerStorageCatalog abandon(UUID slot, long expectedCatalog, long expectedSelection) throws Failure {
        checkRevision(expectedCatalog, expectedSelection);
        Entry row = entry(slot); demand(row.record == null && row.admissionRevision == 0);
        List<Entry> next = entries(); next.remove(row);
        boolean selected = slot.equals(selectedSlot);
        return successor(increment(catalogRevision), selected ? increment(selectionRevision) : selectionRevision,
                selected ? null : selectedSlot, next);
    }
    private void checkRevision(long expectedCatalog, long expectedSelection) throws Failure {
        demand(expectedCatalog == catalogRevision && expectedSelection == selectionRevision);
    }
    private ViewerStorageCatalog replace(Entry row, long catalog, long selection, UUID selected) throws Failure {
        List<Entry> next = entries();
        for (int i = 0; i < next.size(); i++) if (next.get(i).slot.equals(row.slot)) next.set(i, row);
        return successor(catalog, selection, selected, next);
    }
    private ViewerStorageCatalog successor(long catalog, long selection, UUID selected, List<Entry> rows) throws Failure {
        return new ViewerStorageCatalog(deviceID, seed, publicKey, increment(fileRevision), catalog, selection, selected, rows);
    }
    private int encodedSize() throws Failure {
        long size = MAGIC.length + 16 + 32 + 32 + 24 + 1 + (selectedSlot == null ? 0 : 16) + 4;
        for (Entry row : entries) size += 16 + 32 + 8 + 4 + (row.recordBytes == null ? 0 : row.recordBytes.length);
        demand(size <= MAXIMUM_BYTES); return (int) size;
    }
    byte[] encode() throws Failure {
        ByteBuffer out = ByteBuffer.allocate(encodedSize());
        out.put(MAGIC); putID(out, deviceID); out.put(seed).put(publicKey).putLong(fileRevision).putLong(catalogRevision).putLong(selectionRevision);
        out.put((byte) (selectedSlot == null ? 0 : 1)); if (selectedSlot != null) putID(out, selectedSlot);
        out.putInt(entries.size());
        for (Entry row : entries) {
            putID(out, row.slot); out.put(row.invitation).putLong(row.admissionRevision).putInt(row.recordBytes == null ? 0 : row.recordBytes.length);
            if (row.recordBytes != null) out.put(row.recordBytes);
        }
        return out.array();
    }
    static ViewerStorageCatalog decode(byte[] encoded) throws Failure {
        demand(encoded != null && encoded.length > 0 && encoded.length <= MAXIMUM_BYTES);
        byte[] owned = encoded.clone(), seed = null, canonical = null;
        try {
            ByteBuffer in = ByteBuffer.wrap(owned);
            demand(Arrays.equals(fixed(in, MAGIC.length), MAGIC));
            UUID id = id(in); seed = fixed(in, 32); byte[] publicKey = fixed(in, 32);
            ViewerIdentity identity = ViewerPairingAuthenticator.viewerIdentity(id, seed);
            demand(Arrays.equals(publicKey, identity.signingPublicKey()));
            long file = in.getLong(), catalog = in.getLong(), selection = in.getLong();
            int hasSelected = in.get() & 0xff; demand(hasSelected <= 1);
            UUID selected = hasSelected == 0 ? null : id(in);
            int count = in.getInt(); demand(count >= 0 && count <= MAXIMUM_MACS);
            List<Entry> rows = new ArrayList<>();
            for (int i = 0; i < count; i++) {
                UUID slot = id(in); byte[] invitation = fixed(in, 32); long admission = in.getLong();
                int length = in.getInt(); demand(length >= 0 && length <= ViewerPairRecord.MAXIMUM_PRIVATE_RECORD_BYTES && length <= in.remaining());
                rows.add(new Entry(slot, invitation, admission, length == 0 ? null : fixed(in, length), identity));
            }
            demand(!in.hasRemaining());
            ViewerStorageCatalog result = new ViewerStorageCatalog(id, seed, publicKey, file, catalog, selection, selected, rows);
            canonical = result.encode();
            if (!Arrays.equals(canonical, owned)) { result.close(); throw new Failure(); }
            return result;
        } catch (AuthFailure | java.nio.BufferUnderflowException | IllegalArgumentException refused) { throw new Failure(); }
        finally { Arrays.fill(owned, (byte) 0); if (seed != null) Arrays.fill(seed, (byte) 0); if (canonical != null) Arrays.fill(canonical, (byte) 0); }
    }
    private static byte[] fixed(ByteBuffer buffer, int count) throws Failure {
        demand(count >= 0 && count <= buffer.remaining()); byte[] result = new byte[count]; buffer.get(result); return result;
    }
    private static UUID id(ByteBuffer buffer) throws Failure { UUID id = new UUID(buffer.getLong(), buffer.getLong()); demand(nonzero(id)); return id; }
    private static void putID(ByteBuffer buffer, UUID id) { buffer.putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()); }
    static boolean nonzero(UUID id) { return id != null && (id.getMostSignificantBits() != 0 || id.getLeastSignificantBits() != 0); }
    static byte[] sha256(byte[] input) throws Failure {
        demand(input != null);
        try { return MessageDigest.getInstance("SHA-256").digest(input); }
        catch (NoSuchAlgorithmException unavailable) { throw new Failure(); }
    }
    static long increment(long value) throws Failure { demand(value >= 0 && value < Long.MAX_VALUE); return value + 1; }
    static void demand(boolean allowed) throws Failure { if (!allowed) throw new Failure(); }
    @Override public void close() { Arrays.fill(seed, (byte) 0); }
    @Override public String toString() { return "<redacted encrypted-catalog plaintext>"; }
}
