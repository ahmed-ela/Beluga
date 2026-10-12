import SwiftUI

/// The production menu's existing content, without app/status-item or updater ownership.
/// The Bool comes from the outer menu's observed updater; native dispatch stays in the model.
struct BelugaMediaHandoffControlsView: View {
    @ObservedObject var model: BelugaMenuBarModel
    let isUpdateInProgress: Bool

    var body: some View {
        let state = model.mediaHandoffControl
        let target = model.presentation.connectedMediaTarget
        return VStack(alignment: .leading, spacing: 8) {
            if state.visible {
                Button("Move media to phone") {
                    if let target { model.moveMedia(to: target) }
                }
                .disabled(!state.enabled || isUpdateInProgress)
                .accessibilityIdentifier("beluga.move-media-to-phone")
                if let reason = state.reason.message {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("beluga.media-handoff-disabled-reason")
                }
                if let message = model.mediaHandoffMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("beluga.media-handoff-message")
                }
            }
        }
    }
}
