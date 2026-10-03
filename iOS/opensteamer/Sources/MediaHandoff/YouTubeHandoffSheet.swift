import SwiftUI
import WebKit

/// Unwired provider component. Its callback must be correlated with the exact transport offer;
/// displaying this sheet alone never authorizes a Mac pause.
struct YouTubeHandoffSheet: View {
    @ObservedObject var player: YouTubeHandoffPlayer
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var isPresented = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                YouTubeHandoffWebViewContainer(player: player)
                    .frame(minWidth: 200, minHeight: 220)
                    .accessibilityLabel("YouTube video player")
                Text(statusText)
                    .font(.callout)
                    .accessibilityAddTraits(.updatesFrequently)
                    .padding(.horizontal)
                Spacer(minLength: 0)
            }
            .navigationTitle("Play on iPhone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { player.dismiss(); dismiss() }
                }
            }
        }
        .onAppear { isPresented = true; updateVisibility() }
        .onDisappear { isPresented = false; player.dismiss() }
        .onChange(of: scenePhase) { _, _ in updateVisibility() }
    }

    private func updateVisibility() {
        player.setPresentation(isPresented: isPresented, sceneIsActive: scenePhase == .active)
    }

    private var statusText: String {
        switch player.phase {
        case .preparing: "Loading YouTube…"
        case .ready: "Waiting for playback at the Mac’s position…"
        case .playRequired: "Tap Play in the YouTube player to continue."
        case .verifying: "Confirming playback on this iPhone…"
        case .confirmed: "Playback confirmed on this iPhone."
        case .failed(.timedOut): "The handoff expired. The Mac was not instructed to pause."
        case .failed(.notVisible), .failed(.dismissed), .failed(.replaced): "Handoff stopped."
        case .failed: "This video could not be confirmed. The Mac was not instructed to pause."
        }
    }
}

private struct YouTubeHandoffWebViewContainer: UIViewRepresentable {
    let player: YouTubeHandoffPlayer
    func makeCoordinator() -> YouTubeHandoffPlayer { player }
    func makeUIView(context: Context) -> WKWebView { player.makeWebView() }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    static func dismantleUIView(_ uiView: WKWebView, coordinator: YouTubeHandoffPlayer) {
        if let view = uiView as? YouTubeHandoffWebView { coordinator.dismantle(view) }
    }
}
