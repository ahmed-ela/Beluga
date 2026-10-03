import SwiftUI
import WebKit

/// The coordinator correlates this provider with an exact transport offer. Displaying the
/// sheet alone never authorizes a Mac pause; native advancing playback is required first.
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
                Text(player.statusText)
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
