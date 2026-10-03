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
        assertFalse(state.canConfirmScan)
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

    @Test fun manualPairActionReturnsParsedInvitationOnceAndClearsRawInput() {
        for (code in codes()) {
            val model = model()
            model.changeManualInput(code.lowercase().replace('-', ' '))
            assertEquals(code, requireNotNull(model.takeManualInvitation()).exportedCode())
            assertEquals("", model.state.manualInput)
            assertEquals(PairingEntryStatus.FormatValidNotPaired, model.state.status)
            assertFalse(model.state.canConfirmScan)
            assertNull(model.takeManualInvitation())
        }
    }

    @Test fun invalidManualPairActionReturnsNoInvitationAndDiscardsRawInput() {
        for (input in listOf("", "https://example.invalid/", "\u0000", " ".repeat(257))) {
            val model = model()
            model.changeManualInput(input)
            assertNull(model.takeManualInvitation())
            assertEquals("", model.state.manualInput)
            assertEquals(PairingEntryStatus.InvalidInvitation, model.state.status)
            assertFalse(model.state.canConfirmScan)
        }
    }

    @Test fun scanCompletionStagesOnlyAnExplicitOneUseConfirmation() {
        for (code in codes()) {
            val model = model()
            val attempt = requireNotNull(model.beginScan())
            assertTrue(model.completeScan(attempt, true, qr(code)))
            assertTrue(model.state.canConfirmScan)
            assertEquals("", model.state.manualInput)
            assertFalse(model.state.scannerPending)
            assertEquals(PairingEntryStatus.FormatValidNotPaired, model.state.status)
            assertEquals(code, requireNotNull(model.takeScannedInvitation()).exportedCode())
            assertFalse(model.state.canConfirmScan)
            assertNull(model.takeScannedInvitation())
            assertFalse(model.completeScan(attempt, true, qr(code)))
            assertFalse(model.state.canConfirmScan)
        }
    }

    @Test fun malformedScanCanNeverOfferConfirmation() {
        val code = codes().first()
        for (payload in listOf(null, code, qr(code) + "\n", qr(code).lowercase())) {
            val model = model()
            assertTrue(model.completeScan(requireNotNull(model.beginScan()), true, payload))
            assertFalse(model.state.canConfirmScan)
            assertNull(model.takeScannedInvitation())
        }
        val model = model()
        assertTrue(model.completeScan(requireNotNull(model.beginScan()), false, qr(code)))
        assertFalse(model.state.canConfirmScan)
        assertNull(model.takeScannedInvitation())
    }

    @Test fun stagedAdmissionExpiresAfterSdkOwnershipEnded() {
        val model = model()
        val attempt = requireNotNull(model.beginScan())
        assertTrue(model.completeScan(attempt, true, qr(codes().first())))
        assertFalse(model.state.scannerPending)
        now = attempt.deadline + 1
        model.expireScan(attempt)
        assertEquals(PairingEntryStatus.ScanExpired, model.state.status)
        assertFalse(model.state.canConfirmScan)
        assertNull(model.takeScannedInvitation())
    }

    @Test fun stateReadAndTakeIndependentlyRecheckStagedDeadline() {
        for (readStateFirst in listOf(true, false)) {
            val model = model()
            val attempt = requireNotNull(model.beginScan())
            assertTrue(model.completeScan(attempt, true, qr(codes().first())))
            now = attempt.deadline + 1
            if (readStateFirst) assertFalse(model.state.canConfirmScan)
            assertNull(model.takeScannedInvitation())
            assertEquals(PairingEntryStatus.ScanExpired, model.state.status)
        }
    }

    @Test fun confirmationAtExactOriginalDeadlineIsAllowedWithoutExtendingWindow() {
        val model = model()
        val attempt = requireNotNull(model.beginScan())
        now = attempt.deadline - 1
        assertTrue(model.completeScan(attempt, true, qr(codes().first())))
        now = attempt.deadline
        assertEquals(codes().first(), requireNotNull(model.takeScannedInvitation()).exportedCode())
        assertFalse(model.state.canConfirmScan)
    }

    @Test fun rollbackAfterScanOrStateObservationRevokesStagedAdmission() {
        for (readStateFirst in listOf(true, false)) {
            val model = model()
            val attempt = requireNotNull(model.beginScan())
            now = attempt.startedAt + 100
            assertTrue(model.completeScan(attempt, true, qr(codes().first())))
            now += 100
            assertTrue(model.state.canConfirmScan)
            now -= 1 // Still after startedAt, but no longer monotonic.
            if (readStateFirst) assertFalse(model.state.canConfirmScan)
            assertNull(model.takeScannedInvitation())
            assertEquals(PairingEntryStatus.ScanExpired, model.state.status)
        }
    }

    @Test fun clearEditNewScanAndDisposeEachRevokeStagedConfirmation() {
        for (action in 0..3) {
            val model = model()
            val attempt = requireNotNull(model.beginScan())
            assertTrue(model.completeScan(attempt, true, qr(codes().first())))
            when (action) {
                0 -> model.clear()
                1 -> model.changeManualInput(codes().last())
                2 -> assertNotNull(model.beginScan())
                3 -> model.dispose()
            }
            assertFalse(model.state.canConfirmScan)
            assertNull(model.takeScannedInvitation())
            assertFalse(model.completeScan(attempt, true, qr(codes().first())))
            assertFalse(model.state.canConfirmScan)
        }
    }

    @Test fun backgroundRevokesStagedInvitationButPreservesPendingExternalScanner() {
        val model = model()
        val attempt = requireNotNull(model.beginScan())
        model.forgetSensitiveInput()
        assertTrue(model.state.scannerPending)
        assertTrue(model.state.acceptsScanResult)
        assertTrue(model.completeScan(attempt, true, qr(codes().first())))
        assertTrue(model.state.canConfirmScan)
        model.forgetSensitiveInput()
        assertFalse(model.state.canConfirmScan)
        assertEquals("", model.state.manualInput)
        assertEquals(PairingEntryStatus.Ready, model.state.status)
        assertNull(model.takeScannedInvitation())
    }

    @Test fun staleTimeoutAndResultCannotRevokeOrReplaceNewStagedInvitation() {
        val model = model()
        val first = requireNotNull(model.beginScan())
        model.scanCancelled(first)
        val second = requireNotNull(model.beginScan())
        assertTrue(model.completeScan(second, true, qr(codes().last())))
        model.expireScan(first)
        assertFalse(model.completeScan(first, true, qr(codes().first())))
        model.scanCancelled(first)
        assertTrue(model.state.canConfirmScan)
        assertEquals(codes().last(), requireNotNull(model.takeScannedInvitation()).exportedCode())
    }

    @Test fun manualPairActionRetiresScannedAndPendingScanAdmission() {
        val model = model()
        val scannedAttempt = requireNotNull(model.beginScan())
        assertTrue(model.completeScan(scannedAttempt, true, qr(codes().first())))
        model.changeManualInput(codes().last())
        assertEquals(codes().last(), requireNotNull(model.takeManualInvitation()).exportedCode())
        assertNull(model.takeScannedInvitation())
        val pending = requireNotNull(model.beginScan())
        model.changeManualInput(codes().first())
        assertEquals(codes().first(), requireNotNull(model.takeManualInvitation()).exportedCode())
        assertFalse(model.completeScan(pending, true, qr(codes().last())))
        assertFalse(model.state.canConfirmScan)
    }

    @Test fun stagedStateDescriptionsExposeOnlyConfirmationAvailability() {
        val model = model()
        val code = codes().first()
        assertTrue(model.completeScan(requireNotNull(model.beginScan()), true, qr(code)))
        assertEquals("", model.state.manualInput)
        assertTrue(model.state.canConfirmScan)
        assertFalse(model.state.toString().contains(code))
        assertFalse(model.toString().contains(code))
        assertFalse(PairingEntryState::class.java.declaredFields.any {
            it.type == com.elamin.beluga.protocol.PairingInvitation::class.java
        })
    }
}
