package com.elamin.beluga.preview

import com.elamin.beluga.protocol.PairingInvitation

internal enum class PairingEntryStatus {
    Ready, Editing, Scanning, FormatValidNotPaired, InvalidInvitation,
    ScannerUnavailable, ScanCancelled, ScanExpired, Closed
}

internal class PairingEntryState(
    val manualInput: String,
    val status: PairingEntryStatus,
    val scannerPending: Boolean,
    val acceptsScanResult: Boolean,
    val canScan: Boolean,
    val canConfirmScan: Boolean,
) {
    override fun toString() = "PairingEntryState(status=$status, input=<redacted>)"
}

/** One main-thread owner; only a bounded, unconsumed parsed scan is retained privately. */
internal class PairingEntryModel(private val elapsedMilliseconds: () -> Long) {
    internal class ScanAttempt internal constructor(
        internal val startedAt: Long,
        internal val deadline: Long,
    )

    private class ScannedInvitation(
        val invitation: PairingInvitation,
        val attempt: ScanAttempt,
    ) {
        override fun toString() = "<redacted scanned Beluga invitation>"
    }

    private var manualInput = ""
    private var status = PairingEntryStatus.Ready
    private var pending: ScanAttempt? = null
    private var scanned: ScannedInvitation? = null
    private var latestScanObservation = 0L
    private var accepting = false
    private var closed = false

    val state: PairingEntryState
        get() {
            pending?.let { if (accepting) stillAdmitted(it) }
            expireStagedIfNeeded()
            return PairingEntryState(
                manualInput, status, pending != null, accepting,
                !closed && pending == null, !closed && scanned != null,
            )
        }

    fun changeManualInput(input: String) {
        if (closed) return
        accepting = false
        scanned = null
        if (input.length > PairingInvitation.MAXIMUM_MANUAL_CHARACTERS) {
            manualInput = ""
            status = PairingEntryStatus.InvalidInvitation
            return
        }
        manualInput = input
        status = if (input.isEmpty()) PairingEntryStatus.Ready else PairingEntryStatus.Editing
    }

    fun validateManual() {
        takeManualInvitation()
    }

    /** Explicit foreground action; callers own this transient invitation after return. */
    fun takeManualInvitation(): PairingInvitation? {
        if (closed) return null
        accepting = false
        scanned = null
        val entered = manualInput
        manualInput = ""
        return try {
            PairingInvitation.parseManual(entered).also {
                status = PairingEntryStatus.FormatValidNotPaired
            }
        } catch (_: IllegalArgumentException) {
            status = PairingEntryStatus.InvalidInvitation
            null
        }
    }

    /** A scanner callback cannot connect; only an explicit foreground click consumes this. */
    fun takeScannedInvitation(): PairingInvitation? {
        if (closed) return null
        expireStagedIfNeeded()
        val admitted = scanned ?: return null
        scanned = null
        return admitted.invitation
    }

    fun beginScan(): ScanAttempt? {
        if (closed || pending != null) return null
        scanned = null
        val now = elapsedMilliseconds()
        if (now < 0 || now > Long.MAX_VALUE - SCAN_WINDOW_MILLISECONDS) {
            manualInput = ""
            status = PairingEntryStatus.ScannerUnavailable
            return null
        }
        val attempt = ScanAttempt(now, now + SCAN_WINDOW_MILLISECONDS)
        latestScanObservation = now
        manualInput = ""
        pending = attempt
        accepting = true
        status = PairingEntryStatus.Scanning
        return attempt
    }

    fun completeScan(attempt: ScanAttempt, isQRCode: Boolean, payload: String?): Boolean {
        if (closed || pending !== attempt) return false
        val permitted = stillAdmitted(attempt)
        pending = null
        accepting = false
        if (!permitted) return false
        scanned = null
        if (!isQRCode) status = PairingEntryStatus.InvalidInvitation
        else try {
            scanned = ScannedInvitation(PairingInvitation.parseQRCode(payload), attempt)
            status = PairingEntryStatus.FormatValidNotPaired
        } catch (_: IllegalArgumentException) {
            status = PairingEntryStatus.InvalidInvitation
        }
        return true
    }

    fun scanUnavailable(attempt: ScanAttempt) {
        finishWithoutPayload(attempt, PairingEntryStatus.ScannerUnavailable)
    }

    fun scanCancelled(attempt: ScanAttempt) {
        finishWithoutPayload(attempt, PairingEntryStatus.ScanCancelled)
    }

    fun expireScan(attempt: ScanAttempt) {
        if (!closed && pending === attempt && accepting) stillAdmitted(attempt)
        if (!closed && scanned?.attempt === attempt) expireStagedIfNeeded()
    }

    fun clear() {
        if (closed) return
        manualInput = ""
        accepting = false
        scanned = null
        status = PairingEntryStatus.Ready
        // Retain ownership until the SDK task ends; do not launch overlapping scanners.
    }

    fun forgetManualInput() {
        forgetSensitiveInput()
    }

    /** Backgrounding clears entry/staging; the separately owned scanner SDK may still return. */
    fun forgetSensitiveInput() {
        manualInput = ""
        val hadScanned = scanned != null
        scanned = null
        if (!closed && (hadScanned || status == PairingEntryStatus.Editing)) status = PairingEntryStatus.Ready
    }

    fun dispose() {
        manualInput = ""
        pending = null
        scanned = null
        accepting = false
        closed = true
        status = PairingEntryStatus.Closed
    }

    private fun stillAdmitted(attempt: ScanAttempt): Boolean {
        if (!accepting) return false
        if (!timeAdmitted(attempt)) {
            accepting = false
            status = PairingEntryStatus.ScanExpired
            return false
        }
        return true
    }

    private fun expireStagedIfNeeded() {
        val staged = scanned ?: return
        if (!timeAdmitted(staged.attempt)) {
            scanned = null
            status = PairingEntryStatus.ScanExpired
        }
    }

    private fun timeAdmitted(attempt: ScanAttempt): Boolean {
        val now = elapsedMilliseconds()
        if (now < latestScanObservation || now > attempt.deadline) return false
        latestScanObservation = now
        return true
    }

    private fun finishWithoutPayload(attempt: ScanAttempt, result: PairingEntryStatus) {
        if (closed || pending !== attempt) return
        val permitted = stillAdmitted(attempt)
        pending = null
        accepting = false
        if (permitted) status = result
    }

    override fun toString() = "<redacted Beluga pairing-entry model>"

    companion object {
        const val SCAN_WINDOW_MILLISECONDS = 120_000L
    }
}
