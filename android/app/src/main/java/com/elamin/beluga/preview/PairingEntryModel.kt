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
) {
    override fun toString() = "PairingEntryState(status=$status, input=<redacted>)"
}

/** One main-thread owner; never stores a parsed invitation or a scanner payload. */
internal class PairingEntryModel(private val elapsedMilliseconds: () -> Long) {
    internal class ScanAttempt internal constructor(
        internal val startedAt: Long,
        internal val deadline: Long,
    )

    private var manualInput = ""
    private var status = PairingEntryStatus.Ready
    private var pending: ScanAttempt? = null
    private var accepting = false
    private var closed = false

    val state: PairingEntryState
        get() = PairingEntryState(
            manualInput, status, pending != null, accepting,
            !closed && pending == null,
        )

    fun changeManualInput(input: String) {
        if (closed) return
        accepting = false
        if (input.length > PairingInvitation.MAXIMUM_MANUAL_CHARACTERS) {
            manualInput = ""
            status = PairingEntryStatus.InvalidInvitation
            return
        }
        manualInput = input
        status = if (input.isEmpty()) PairingEntryStatus.Ready else PairingEntryStatus.Editing
    }

    fun validateManual() {
        if (closed) return
        accepting = false
        val entered = manualInput
        manualInput = ""
        status = try {
            PairingInvitation.parseManual(entered)
            PairingEntryStatus.FormatValidNotPaired
        } catch (_: IllegalArgumentException) {
            PairingEntryStatus.InvalidInvitation
        }
    }

    fun beginScan(): ScanAttempt? {
        if (closed || pending != null) return null
        val now = elapsedMilliseconds()
        if (now < 0 || now > Long.MAX_VALUE - SCAN_WINDOW_MILLISECONDS) {
            manualInput = ""
            status = PairingEntryStatus.ScannerUnavailable
            return null
        }
        val attempt = ScanAttempt(now, now + SCAN_WINDOW_MILLISECONDS)
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
        status = if (!isQRCode) {
            PairingEntryStatus.InvalidInvitation
        } else {
            try {
                PairingInvitation.parseQRCode(payload)
                PairingEntryStatus.FormatValidNotPaired
            } catch (_: IllegalArgumentException) {
                PairingEntryStatus.InvalidInvitation
            }
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
    }

    fun clear() {
        if (closed) return
        manualInput = ""
        accepting = false
        status = PairingEntryStatus.Ready
        // Retain ownership until the SDK task ends; do not launch overlapping scanners.
    }

    fun forgetManualInput() {
        manualInput = ""
        if (status == PairingEntryStatus.Editing) status = PairingEntryStatus.Ready
    }

    fun dispose() {
        manualInput = ""
        pending = null
        accepting = false
        closed = true
        status = PairingEntryStatus.Closed
    }

    private fun stillAdmitted(attempt: ScanAttempt): Boolean {
        if (!accepting) return false
        val now = elapsedMilliseconds()
        if (now < attempt.startedAt || now > attempt.deadline) {
            accepting = false
            status = PairingEntryStatus.ScanExpired
            return false
        }
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
