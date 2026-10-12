package com.elamin.beluga.preview

import com.elamin.beluga.protocol.ViewerLibraryController.ConnectionStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class ConnectionMessageTest {
    @Test fun readinessDoesNotClaimVisiblePixels() {
        val message = connectionMessage(ConnectionStatus.ACTIVE)
        assertEquals("Connected. Audio is enabled; use Show for the Mac screen.", message)
        assertFalse(message.contains("live", ignoreCase = true))
    }

    @Test fun cancellationDoesNotClaimCleanupBeforeItCompletes() {
        assertEquals("Disconnecting and waiting for cleanup…", connectionMessage(ConnectionStatus.CANCELLING))
        assertEquals("Disconnected.", connectionMessage(ConnectionStatus.CANCELLED))
    }

    @Test fun failedCleanupAndOrdinaryFailureRemainDifferent() {
        assertEquals("Connection failed. Nothing will retry automatically.", connectionMessage(ConnectionStatus.FAILED))
        assertEquals("Connection cleanup is unverified. Further connections and library changes are blocked.",
            connectionMessage(ConnectionStatus.CLEANUP_UNPROVEN))
    }
}
