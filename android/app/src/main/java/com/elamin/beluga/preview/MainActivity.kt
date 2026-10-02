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
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import java.lang.ref.WeakReference

class MainActivity : ComponentActivity() {
    private val model = PairingEntryModel(SystemClock::elapsedRealtime)
    private val timeouts = Handler(Looper.getMainLooper())
    private var screen by mutableStateOf(model.state)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        setContent {
            MaterialTheme {
                PairingScreen(
                    screen,
                    onInput = { model.changeManualInput(it); refresh() },
                    onValidate = { model.validateManual(); refresh() },
                    onScan = ::startExplicitScan,
                    onClear = { model.clear(); refresh() },
                )
            }
        }
    }

    override fun onStop() {
        model.forgetManualInput()
        refresh()
        super.onStop()
    }

    override fun onDestroy() {
        timeouts.removeCallbacksAndMessages(null)
        model.dispose()
        refresh()
        super.onDestroy()
    }

    private fun refresh() {
        screen = model.state
    }

    private fun startExplicitScan() {
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
                        it.timeouts.removeCallbacksAndMessages(attempt)
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
    onValidate: () -> Unit,
    onScan: () -> Unit,
    onClear: () -> Unit,
) {
    Surface(Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier.safeDrawingPadding().imePadding()
                .verticalScroll(rememberScrollState()).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text("Beluga", style = MaterialTheme.typography.headlineLarge)
            Text("Android preview", style = MaterialTheme.typography.labelLarge)
            Text("Scan a Mac’s pairing QR code, or enter its one-use code manually.")
            Text("This preview checks the code format only. Pairing, saved Macs, connection and media are not implemented.")
            OutlinedTextField(
                value = state.manualInput,
                onValueChange = onInput,
                label = { Text("Pairing code") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                enabled = !state.acceptsScanResult,
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(
                    autoCorrectEnabled = false,
                    keyboardType = KeyboardType.Password,
                    imeAction = ImeAction.Done,
                ),
                keyboardActions = KeyboardActions(onDone = { onValidate() }),
            )
            Button(
                onClick = onValidate,
                enabled = state.manualInput.isNotEmpty() && !state.acceptsScanResult,
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Check code format") }
            OutlinedButton(
                onClick = onScan,
                enabled = state.canScan,
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Scan Mac QR code") }
            OutlinedButton(onClick = onClear, modifier = Modifier.fillMaxWidth()) {
                Text(if (state.scannerPending) "Ignore pending scan and clear" else "Clear")
            }
            Text(statusMessage(state.status))
            Text("QR scanning uses Google Play services’ camera screen and requires its scanner module; first use may download it. Manual entry remains available. Beluga does not request camera or microphone access.")
        }
    }
}

private fun statusMessage(status: PairingEntryStatus): String = when (status) {
    PairingEntryStatus.Ready -> "Not paired."
    PairingEntryStatus.Editing -> "The code stays only in this screen until checked, cleared or backgrounded."
    PairingEntryStatus.Scanning -> "Scanning. No pairing or connection is being attempted."
    PairingEntryStatus.FormatValidNotPaired -> "Code format valid. Not paired: authenticated transport is not implemented, so expiry and one-use availability are not checked. The code was discarded."
    PairingEntryStatus.InvalidInvitation -> "Not a valid Beluga invitation. No pairing attempted."
    PairingEntryStatus.ScannerUnavailable -> "QR scanning unavailable. Google Play services and its scanner module are required. Enter the code manually."
    PairingEntryStatus.ScanCancelled -> "Scan cancelled. Not paired."
    PairingEntryStatus.ScanExpired -> "Scan timed out; any late result will be ignored. Close the scanner and use manual entry."
    PairingEntryStatus.Closed -> "Not paired."
}
