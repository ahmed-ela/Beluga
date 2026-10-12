package com.elamin.beluga.protocol;

import java.util.Arrays;
import com.elamin.beluga.protocol.ViewerStorageCatalog.Failure;

/** Checked order, not a filesystem simulator. Android implements every boundary with real Os calls. */
final class CheckedCatalogPublication {
    interface Boundary {
        void createAndSyncIntent(byte[] encrypted) throws Failure;
        void writeExclusive(byte[] encrypted) throws Failure;
        void syncAndCloseFile() throws Failure;
        void recheckPredecessorAndOwner() throws Failure;
        void rename() throws Failure;
        void syncDirectory() throws Failure;
        byte[] boundedReadback() throws Failure;
        void verifyDecryptedReadback(byte[] encrypted) throws Failure;
        void clearAndSyncIntent() throws Failure;
        void closeOwnedDescriptors();
    }
    private CheckedCatalogPublication() { }
    static void publish(Boundary boundary, byte[] encrypted, int maximum) throws Failure {
        ViewerStorageCatalog.demand(boundary != null && encrypted != null && encrypted.length > 0 && encrypted.length <= maximum);
        byte[] readback = null;
        try {
            boundary.createAndSyncIntent(encrypted);
            boundary.writeExclusive(encrypted);
            boundary.syncAndCloseFile();
            boundary.recheckPredecessorAndOwner();
            boundary.rename();
            boundary.syncDirectory();
            readback = boundary.boundedReadback();
            ViewerStorageCatalog.demand(Arrays.equals(encrypted, readback));
            boundary.verifyDecryptedReadback(readback);
            // No cleanup/marker removal is attempted until EVERY data/durability proof passed.
            boundary.clearAndSyncIntent();
        } finally {
            if (readback != null) Arrays.fill(readback, (byte) 0);
            boundary.closeOwnedDescriptors();
        }
    }
}
