package com.elamin.beluga.preview

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.elamin.beluga.protocol.ViewerLibraryController
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import java.lang.ref.WeakReference

class MainActivity : ComponentActivity() {
    private val model = PairingEntryModel(SystemClock::elapsedRealtime)
    private val timeouts = Handler(Looper.getMainLooper())
    private var screen by mutableStateOf(model.state)
    private lateinit var library: ViewerLibraryController
    private var libraryState by mutableStateOf<ViewerLibraryController.State?>(null)
    private var resumed by mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        library = ViewerLibraryController.create(applicationContext)
        libraryState = library.state()
        setContent {
            MaterialTheme {
                PairingScreen(
                    screen,
                    onInput = { if (resumed) { model.changeManualInput(it); refresh() } },
                    onPairManual = ::pairManual,
                    onPairScan = ::pairScanned,
                    onScan = ::startExplicitScan,
                    onClear = { model.clear(); refresh() },
                    foreground = resumed,
                    libraryState = libraryState,
                    onCancelPairing = { library.cancelPairing() },
                    onInitialize = { if (resumed) library.initialize(it) },
                    onLibraryRefresh = { if (resumed) library.refresh() },
                    onSelect = { mac, expected -> if (resumed) library.select(mac.deviceID, expected) },
                    onForget = { mac, expected -> if (resumed) library.forget(mac.deviceID, expected) },
                    onAbandon = { row, expected -> if (resumed) library.abandon(row.slot, expected) },
                )
            }
        }
    }

    override fun onStart() {
        super.onStart()
        library.start { libraryState = it }
    }

    override fun onResume() {
        super.onResume()
        resumed = true
        refresh() // Rechecks the original monotonic scan deadline after sleep/backgrounding.
    }

    override fun onPause() {
        resumed = false
        library.cancelPairing()
        model.forgetSensitiveInput()
        refresh()
        super.onPause()
    }

    override fun onStop() {
        library.stop()
        libraryState = library.state()
        model.forgetSensitiveInput()
        refresh()
        super.onStop()
    }

    override fun onDestroy() {
        library.close()
        libraryState = library.state()
        timeouts.removeCallbacksAndMessages(null)
        model.dispose()
        refresh()
        super.onDestroy()
    }

    private fun refresh() {
        screen = model.state
    }

    private fun pairManual() {
        val expected = library.state()
        if (!resumed || !expected.canPair()) return
        val invitation = model.takeManualInvitation()
        refresh()
        if (invitation != null) library.pair(expected, invitation)
    }

    private fun pairScanned() {
        val expected = library.state()
        if (!resumed || !expected.canPair()) return
        val invitation = model.takeScannedInvitation()
        refresh()
        if (invitation != null) library.pair(expected, invitation)
    }

    private fun startExplicitScan() {
        if (!resumed || !library.state().canPair()) return
        val attempt = model.beginScan() ?: return
        refresh()
        val owner = WeakReference(this)
        timeouts.postAtTime({
            owner.get()?.let {
                it.model.expireScan(attempt)
                it.refresh()
            }
        }, attempt, SystemClock.uptimeMillis() + PairingEntryModel.SCAN_WINDOW_MILLISECONDS + 1)

        val options = GmsBarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
            .build()
        try {
            GmsBarcodeScanning.getClient(this, options).startScan()
                .addOnSuccessListener { result ->
                    owner.get()?.let {
                        // Keep the original deadline for a staged, unconfirmed result.
                        it.model.completeScan(attempt, result.format == Barcode.FORMAT_QR_CODE, result.rawValue)
                        it.refresh()
                    }
                }
                .addOnCanceledListener {
                    owner.get()?.let {
                        it.timeouts.removeCallbacksAndMessages(attempt)
                        it.model.scanCancelled(attempt)
                        it.refresh()
                    }
                }
                .addOnFailureListener {
                    owner.get()?.let {
                        it.timeouts.removeCallbacksAndMessages(attempt)
                        it.model.scanUnavailable(attempt)
                        it.refresh()
                    }
                }
        } catch (_: RuntimeException) {
            timeouts.removeCallbacksAndMessages(attempt)
            model.scanUnavailable(attempt)
            refresh()
        }
    }
}

@Composable
private fun PairingScreen(
    state: PairingEntryState,
    onInput: (String) -> Unit,
    onPairManual: () -> Unit,
    onPairScan: () -> Unit,
    onScan: () -> Unit,
    onClear: () -> Unit,
    foreground: Boolean,
    libraryState: ViewerLibraryController.State?,
    onCancelPairing: () -> Unit,
    onInitialize: (ViewerLibraryController.State) -> Unit,
    onLibraryRefresh: () -> Unit,
    onSelect: (ViewerLibraryController.Mac, ViewerLibraryController.State) -> Unit,
    onForget: (ViewerLibraryController.Mac, ViewerLibraryController.State) -> Unit,
    onAbandon: (ViewerLibraryController.PendingEnrollment, ViewerLibraryController.State) -> Unit,
) {
    val canPair = foreground && libraryState?.canPair() == true
    Surface(Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier.safeDrawingPadding().imePadding()
                .verticalScroll(rememberScrollState()).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text("Beluga", style = MaterialTheme.typography.headlineLarge)
            Text("Android", style = MaterialTheme.typography.labelLarge)
            Text("Scan a Mac’s pairing QR code, or enter its one-use code manually.")
            Text("Initialize the local library below on first use, then pair a Mac. QR scans require a confirmation tap. This preview saves authenticated pairings; reconnecting and playing media are not implemented yet.")
            OutlinedTextField(
                value = state.manualInput,
                onValueChange = onInput,
                label = { Text("Pairing code") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                enabled = canPair && !state.acceptsScanResult,
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(
                    autoCorrectEnabled = false,
                    keyboardType = KeyboardType.Password,
                    imeAction = ImeAction.Done,
                ),
                keyboardActions = KeyboardActions(onDone = { onPairManual() }),
            )
            Button(
                onClick = onPairManual,
                enabled = canPair && state.manualInput.isNotEmpty() && !state.acceptsScanResult,
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Pair using code") }
            OutlinedButton(
                onClick = onScan,
                enabled = canPair && state.canScan,
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Scan Mac QR code") }
            if (state.canConfirmScan) {
                Button(onClick = onPairScan, enabled = canPair, modifier = Modifier.fillMaxWidth()) {
                    Text("Pair scanned Mac")
                }
            }
            OutlinedButton(onClick = onClear, modifier = Modifier.fillMaxWidth()) {
                Text(if (state.scannerPending) "Ignore pending scan and clear" else "Clear")
            }
            Text(statusMessage(state))
            libraryState?.let {
                Text(pairingMessage(it.pairingStatus))
                if (it.canCancelPairing()) {
                    OutlinedButton(onClick = onCancelPairing, enabled = foreground) { Text("Cancel pairing") }
                }
            }
            Text("QR scanning uses Google Play services’ camera screen and requires its scanner module; first use may download it. Manual entry remains available. Beluga does not request camera or microphone access.")
            libraryState?.let { state ->
                SavedMacLibrary(state, foreground, onInitialize, onLibraryRefresh, onSelect, onForget, onAbandon)
            }
        }
    }
}

@Composable
private fun SavedMacLibrary(
    state: ViewerLibraryController.State,
    foreground: Boolean,
    onInitialize: (ViewerLibraryController.State) -> Unit,
    onRefresh: () -> Unit,
    onSelect: (ViewerLibraryController.Mac, ViewerLibraryController.State) -> Unit,
    onForget: (ViewerLibraryController.Mac, ViewerLibraryController.State) -> Unit,
    onAbandon: (ViewerLibraryController.PendingEnrollment, ViewerLibraryController.State) -> Unit,
) {
    Text("Saved Macs", style = MaterialTheme.typography.headlineSmall)
    when (state.status) {
        ViewerLibraryController.Status.INACTIVE -> Text("Library is inactive while this screen is backgrounded.")
        ViewerLibraryController.Status.UNSUPPORTED -> Text("Pairing requires Android 8.1 (API 27) or later.")
        ViewerLibraryController.Status.LOADING -> Text("Reading the saved library…")
        ViewerLibraryController.Status.WORKING -> Text("Updating the saved library…")
        ViewerLibraryController.Status.UNAVAILABLE -> {
            if (state.pairingStatus == ViewerLibraryController.PairingStatus.CLEANUP_UNPROVEN) {
                Text("Library actions are blocked because pairing cleanup could not be verified. Nothing is reset automatically.")
            } else if (state.pairingStatus == ViewerLibraryController.PairingStatus.BLOCKED) {
                Text("Another pairing attempt still owns this process. Reload after it finishes; do not initialize a new library.")
                OutlinedButton(onClick = onRefresh, enabled = foreground) { Text("Check availability") }
            } else {
                Text("The library is unavailable or not initialized. Initialize only on first use. Existing, partial or unsafe storage is refused, never reset or repaired automatically.")
                Button(onClick = { onInitialize(state) }, enabled = foreground && state.canInitialize()) {
                    Text("Initialize first-use library")
                }
                OutlinedButton(onClick = onRefresh, enabled = foreground) { Text("Reload library") }
            }
        }
        ViewerLibraryController.Status.READY -> {
            if (state.macs.isEmpty()) Text("No Macs saved. Pair a Mac using its one-use code or QR above.")
            state.macs.forEach { mac ->
                Text(mac.displayName ?: "Saved Mac")
                Text(when (mac.phase) {
                    ViewerLibraryController.Phase.PENDING -> "Pairing incomplete; not connected."
                    ViewerLibraryController.Phase.ACCEPTED_ISSUED -> "Pairing completion pending; not connected."
                    ViewerLibraryController.Phase.ACTIVE -> "Saved pairing; not connected."
                })
                Text(if (mac.deviceID == state.selectedMacID) "Selected Mac" else "Not selected")
                OutlinedButton(
                    onClick = { onSelect(mac, state) },
                    enabled = foreground && state.canChangeLibrary() && mac.deviceID != state.selectedMacID,
                ) { Text("Select this Mac") }
                OutlinedButton(onClick = { onForget(mac, state) }, enabled = foreground && state.canChangeLibrary()) {
                    Text("Forget this Mac locally")
                }
            }
            state.pendingEnrollments.forEachIndexed { index, row ->
                Text("Unfinished enrollment ${index + 1}: no authenticated Mac binding.")
                OutlinedButton(onClick = { onAbandon(row, state) }, enabled = foreground && state.canChangeLibrary()) {
                    Text("Remove this unfinished enrollment")
                }
            }
            Text("Selection does not connect. Forgetting removes only the local saved binding; it does not contact the Mac.")
            OutlinedButton(onClick = onRefresh, enabled = foreground) { Text("Reload library") }
        }
        ViewerLibraryController.Status.CLOSED -> Text("Library is closed.")
    }
}

private fun statusMessage(state: PairingEntryState): String = when (state.status) {
    PairingEntryStatus.Ready -> "No invitation entered."
    PairingEntryStatus.Editing -> "The code stays only in this screen until submitted, cleared or backgrounded."
    PairingEntryStatus.Scanning -> "Scanning. No pairing or connection is being attempted."
    PairingEntryStatus.FormatValidNotPaired -> if (state.canConfirmScan)
        "QR format valid. Tap Pair scanned Mac to authenticate before the scan window expires."
        else "Code consumed. Check pairing status below; valid format alone is not a pairing."
    PairingEntryStatus.InvalidInvitation -> "Not a valid Beluga invitation. No pairing attempted."
    PairingEntryStatus.ScannerUnavailable -> "QR scanning unavailable. Google Play services and its scanner module are required. Enter the code manually."
    PairingEntryStatus.ScanCancelled -> "Scan cancelled. Not paired."
    PairingEntryStatus.ScanExpired -> "Scan timed out; any late result will be ignored. Close the scanner and use manual entry."
    PairingEntryStatus.Closed -> "Entry closed."
}

private fun pairingMessage(status: ViewerLibraryController.PairingStatus): String = when (status) {
    ViewerLibraryController.PairingStatus.IDLE -> "No pairing in progress."
    ViewerLibraryController.PairingStatus.PAIRING -> "Authenticating and saving this Mac… Keep this screen open."
    ViewerLibraryController.PairingStatus.CANCELLING -> "Cancelling pairing and waiting for cleanup…"
    ViewerLibraryController.PairingStatus.PAIRED -> "Pairing completed and cleaned up. Saved Macs are reloaded below; media is not connected."
    ViewerLibraryController.PairingStatus.CANCELLED -> "Pairing cancelled. The library is reloaded to show any unfinished enrollment."
    ViewerLibraryController.PairingStatus.FAILED -> "Pairing did not complete. Check the library; request a fresh Mac code before another attempt."
    ViewerLibraryController.PairingStatus.CLEANUP_UNPROVEN -> "Cleanup is unverified. Further pairing and library changes are blocked."
    ViewerLibraryController.PairingStatus.BLOCKED -> "An earlier pairing attempt is still held. No new pairing will start."
}
