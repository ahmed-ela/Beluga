@preconcurrency import LiveKitWebRTC

/// The same once-only process bootstrap precedes both ordinary and sharing factories.
/// This is the existing initializer unchanged; sharing must not create a competing first factory.
enum WebRTCRuntime {
    static let isInitialized: Bool = {
        guard LKRTCInitializeSSL() else { return false }
        #if os(macOS)
        // Tiny screencast packets must not leave an already-budgeted probe waiting for 200 bytes.
        LKRTCPeerConnectionFactory.configureFieldTrials(
            "WebRTC-Bwe-ProbingBehavior/min_packet_size:0/"
        )
        WebRTCNativeProbeDiagnostics.start()
        #endif
        return true
    }()
}
