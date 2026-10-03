package com.elamin.beluga.protocol;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import org.junit.Test;

/** The actual production policy only. No Android IO/provider/runtime or fake platform authority. */
public final class ViewerStoragePlatformPolicyTest {
    @Test public void secureStorageRefusesBelowPublicCloseOnExecAPI() {
        for (int api : new int[] { Integer.MIN_VALUE, -1, 0, 21, 23, 24, 25, 26 })
            assertFalse(AndroidViewerSecureStore.supportsSecureStorage(api));
        for (int api : new int[] { 27, 28, 30, 33, 36, Integer.MAX_VALUE })
            assertTrue(AndroidViewerSecureStore.supportsSecureStorage(api));
    }
}
