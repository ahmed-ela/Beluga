import AVFoundation
import RemoteSessionCore
import SwiftUI
import VisionKit

/// SwiftUI owns permission, presentation and errors; VisionKit supplies only live QR capture.
struct PairingQRCodeScannerView: View {
    let onInvitation: (RemoteInvitationCode) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var cameraAllowed = false
    @State private var permissionWasChecked = false
    @State private var scannerError: String?

    var body: some View {
        NavigationStack {
            Group {
                if cameraAllowed && DataScannerViewController.isSupported
                    && DataScannerViewController.isAvailable {
                    PairingLiveQRCodeScanner(onPayload: accept, onFailure: {
                        scannerError = "The camera scanner is unavailable. Enter the one-time code instead."
                    })
                    .overlay(alignment: .bottom) {
                        Text(scannerError ?? "Scan the pairing QR shown by Beluga on your Mac.")
                            .padding()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .padding()
                    }
                } else if permissionWasChecked {
                    ContentUnavailableView(
                        "Camera unavailable", systemImage: "camera",
                        description: Text("Allow camera access in Settings, or enter the one-time code shown on the Mac.")
                    )
                } else {
                    ProgressView("Checking camera access")
                }
            }
            .navigationTitle("Pair a Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            } }
        }
        .task {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            cameraAllowed = status == .authorized
            if status == .notDetermined {
                cameraAllowed = await AVCaptureDevice.requestAccess(for: .video)
            }
            permissionWasChecked = true
        }
    }

    private func accept(_ payload: String) -> Bool {
        do {
            let qr = try RemotePairingQRCode(scannedPayload: payload)
            onInvitation(qr.invitation)
            dismiss()
            return true
        } catch {
            scannerError = "This is not a valid Beluga pairing QR. Generate a fresh one on the Mac."
            return false
        }
    }
}

private struct PairingLiveQRCodeScanner: UIViewControllerRepresentable {
    let onPayload: (String) -> Bool
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPayload: onPayload) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced, recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false, isPinchToZoomEnabled: true,
            isGuidanceEnabled: true, isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        do { try controller.startScanning() } catch {
            Task { @MainActor in onFailure() }
        }
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
        controller.delegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onPayload: (String) -> Bool
        private var accepted = false
        init(onPayload: @escaping (String) -> Bool) { self.onPayload = onPayload }

        func dataScanner(_ controller: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !accepted else { return }
            for item in addedItems {
                guard case .barcode(let barcode) = item,
                      let payload = barcode.payloadStringValue,
                      payload.utf8.count <= RemotePairingQRCode.maximumPayloadBytes else { continue }
                if onPayload(payload) {
                    accepted = true
                    controller.stopScanning()
                    return
                }
            }
        }
    }
}
