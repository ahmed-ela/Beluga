package com.elamin.beluga.preview

import java.nio.charset.StandardCharsets
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PairingEntryModelTest {
    private var now = 1_000L
    private fun model() = PairingEntryModel { now }
    private fun codes(): List<String> = requireNotNull(
        javaClass.getResourceAsStream("/pairing-invitations-v1.tsv")
    ).bufferedReader(StandardCharsets.UTF_8).use { input ->
        input.readLines().filter { it.isNotEmpty() && !it.startsWith("#") }
            .map { it.split('\t')[2] }.also { assertEquals(3, it.size) }
    }
    private fun qr(code: String) = "BELUGA-PAIRING-V1\n$code"

    @Test fun initialStateDoesNotClaimPairingOrOpenScanner() {
        val state = model().state
        assertEquals(PairingEntryStatus.Ready, state.status)
        assertEquals("", state.manualInput)
        assertFalse(state.scannerPending)
        assertFalse(state.acceptsScanResult)
        assertTrue(state.canScan)
    }

    @Test fun allSharedManualVectorsValidateOnlyFormatAndDiscardInput() {
        for (code in codes()) {
            val model = model()
            model.changeManualInput(code)
            assertEquals(PairingEntryStatus.Editing, model.state.status)
            model.validateManual()
            assertEquals(PairingEntryStatus.FormatValidNotPaired, model.state.status)
            assertEquals("", model.state.manualInput)
            assertFalse(model.state.scannerPending)
        }
    }

    @Test fun manualHumanAliasesAreCompatible() {
        val model = model()
        val entered = codes().first().lowercase().replace('0', 'O').replace('-', ' ')
        model.changeManualInput(entered)
        model.validateManual()
        assertEquals(PairingEntryStatus.FormatValidNotPaired, model.state.status)
    }

    @Test fun manualOverflowIsRejectedWithoutTruncatingIntoAValidInvitation() {
        val model = model()
        model.changeManualInput(codes().first())
        model.changeManualInput(" ".repeat(257))
        assertEquals("", model.state.manualInput)
        assertEquals(PairingEntryStatus.InvalidInvitation, model.state.status)
        model.validateManual()
        assertEquals(PairingEntryStatus.InvalidInvitation, model.state.status)
    }

    @Test fun hostileManualInputsRemainRedactedAndUnpaired() {
        for (input in listOf("", "https://example.invalid/", "\u0000", "\uff10".repeat(40))) {
            val model = model()
            model.changeManualInput(input)
            model.validateManual()
            assertEquals(PairingEntryStatus.InvalidInvitation, model.state.status)
            assertEquals("", model.state.manualInput)
        }
    }

    @Test fun allSharedQrVectorsValidateAndNeverPopulateInput() {
        for (code in codes()) {
            val model = model()
            val attempt = requireNotNull(model.beginScan())
            assertTrue(model.completeScan(attempt, true, qr(code)))
            assertEquals(PairingEntryStatus.FormatValidNotPaired, model.state.status)
            assertEquals("", model.state.manualInput)
            assertTrue(model.state.canScan)
        }
    }

    @Test fun qrMustBeExactEnvelopeCanonicalAndQrFormat() {
        val code = codes().first()
        for (payload in listOf(
            null, code, qr(code) + "\n", qr(code).lowercase(),
            "https://example.invalid/?code=$code", "A".repeat(100_000),
            "BELUGA-PAIRING-V2\n$code", "BELUGA-PAIRING-V1\n" + "\u00e9".repeat(65),
        )) {
            val model = model()
            val attempt = requireNotNull(model.beginScan())
            assertTrue(model.completeScan(attempt, true, payload))
            assertEquals(PairingEntryStatus.InvalidInvitation, model.state.status)
            assertEquals("", model.state.manualInput)
        }
        val model = model()
        assertTrue(model.completeScan(requireNotNull(model.beginScan()), false, qr(code)))
        assertEquals(PairingEntryStatus.InvalidInvitation, model.state.status)
    }

    @Test fun onlyOneScannerTaskCanBeOwned() {
        val model = model()
        assertNotNull(model.beginScan())
        assertNull(model.beginScan())
        assertTrue(model.state.scannerPending)
        assertFalse(model.state.canScan)
    }

    @Test fun duplicateCompletionCannotChangeValidatedResult() {
        val model = model()
        val attempt = requireNotNull(model.beginScan())
        assertTrue(model.completeScan(attempt, true, qr(codes().first())))
        assertFalse(model.completeScan(attempt, false, null))
        model.scanUnavailable(attempt)
        model.scanCancelled(attempt)
        assertEquals(PairingEntryStatus.FormatValidNotPaired, model.state.status)
    }

    @Test fun staleOrFabricatedAttemptCannotOverwriteNewScanner() {
        val model = model()
        val first = requireNotNull(model.beginScan())
        model.scanCancelled(first)
        val second = requireNotNull(model.beginScan())
        assertFalse(model.completeScan(first, true, qr(codes().first())))
        val fabricated = PairingEntryModel.ScanAttempt(second.startedAt, second.deadline)
        assertFalse(model.completeScan(fabricated, true, qr(codes().first())))
        assertEquals(PairingEntryStatus.Scanning, model.state.status)
        assertTrue(model.state.scannerPending)
        assertTrue(model.completeScan(second, true, qr(codes().last())))
    }

    @Test fun editedManualInputRetiresPendingScannerAuthority() {
        val model = model()
        val attempt = requireNotNull(model.beginScan())
        val code = codes().first()
        model.changeManualInput(code)
        assertFalse(model.state.acceptsScanResult)
        assertFalse(model.completeScan(attempt, false, null))
        assertEquals(code, model.state.manualInput)
        assertEquals(PairingEntryStatus.Editing, model.state.status)
        model.validateManual()
        assertEquals(PairingEntryStatus.FormatValidNotPaired, model.state.status)
    }

    @Test fun clearRetiresResultsButDoesNotLaunchAnOverlappingSdkTask() {
        val model = model()
        val attempt = requireNotNull(model.beginScan())
        model.clear()
        assertNull(model.beginScan())
        assertEquals(PairingEntryStatus.Ready, model.state.status)
        assertTrue(model.state.scannerPending)
        assertFalse(model.completeScan(attempt, true, qr(codes().first())))
        assertEquals(PairingEntryStatus.Ready, model.state.status)
        assertTrue(model.state.canScan)
    }

    @Test fun timeoutRetainsSdkOwnershipAndRejectsLateResult() {
        val model = model()
        val attempt = requireNotNull(model.beginScan())
        now = attempt.deadline + 1
        model.expireScan(attempt)
        assertEquals(PairingEntryStatus.ScanExpired, model.state.status)
        assertFalse(model.state.acceptsScanResult)
        assertNull(model.beginScan())
        assertFalse(model.completeScan(attempt, true, qr(codes().first())))
        assertEquals(PairingEntryStatus.ScanExpired, model.state.status)
        assertTrue(model.state.canScan)
    }

    @Test fun exactDeadlineIsAdmittedButClockRegressionIsNot() {
        val model = model()
        val attempt = requireNotNull(model.beginScan())
        now = attempt.deadline
        assertTrue(model.completeScan(attempt, true, qr(codes().first())))
        val next = requireNotNull(model.beginScan())
        now = next.startedAt - 1
        assertFalse(model.completeScan(next, true, qr(codes().first())))
        assertEquals(PairingEntryStatus.ScanExpired, model.state.status)
    }

    @Test fun badClockOrDeadlineOverflowDoesNotOpenScanner() {
        for (bad in listOf(-1L, Long.MAX_VALUE)) {
            now = bad
            val model = model()
            assertNull(model.beginScan())
            assertEquals(PairingEntryStatus.ScannerUnavailable, model.state.status)
            assertFalse(model.state.scannerPending)
        }
    }

    @Test fun unavailableOrCancelledScannerAllowsManualAlternative() {
        for (unavailable in listOf(true, false)) {
            val model = model()
            val attempt = requireNotNull(model.beginScan())
            if (unavailable) model.scanUnavailable(attempt) else model.scanCancelled(attempt)
            assertEquals(
                if (unavailable) PairingEntryStatus.ScannerUnavailable else PairingEntryStatus.ScanCancelled,
                model.state.status,
            )
            assertTrue(model.state.canScan)
            model.changeManualInput(codes().first())
            model.validateManual()
            assertEquals(PairingEntryStatus.FormatValidNotPaired, model.state.status)
        }
    }

    @Test fun backgroundClearsInputWithoutInvalidatingCurrentScanner() {
        val model = model()
        model.changeManualInput(codes().first())
        model.forgetManualInput()
        assertEquals("", model.state.manualInput)
        assertEquals(PairingEntryStatus.Ready, model.state.status)
        val attempt = requireNotNull(model.beginScan())
        model.forgetManualInput()
        assertTrue(model.state.acceptsScanResult)
        assertTrue(model.completeScan(attempt, true, qr(codes().first())))
    }

    @Test fun disposalRejectsAllCallbacksAndNeverRestoresInput() {
        val model = model()
        val attempt = requireNotNull(model.beginScan())
        model.dispose()
        assertFalse(model.completeScan(attempt, true, qr(codes().first())))
        model.scanUnavailable(attempt)
        model.scanCancelled(attempt)
        model.changeManualInput(codes().first())
        model.validateManual()
        assertNull(model.beginScan())
        assertEquals(PairingEntryStatus.Closed, model.state.status)
        assertEquals("", model.state.manualInput)
    }

    @Test fun stateAndModelDescriptionsNeverExposeEnteredCode() {
        val model = model()
        val code = codes().first()
        model.changeManualInput(code)
        assertFalse(model.state.toString().contains(code))
        assertFalse(model.toString().contains(code))
        assertTrue(model.state.toString().contains("<redacted>"))
    }
}
