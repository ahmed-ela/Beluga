import BelugaCore

/// Copied source-choice policy only. Native snapshots, object identity and effects stay native.
enum BelugaRustSupportedPlayerArbitrationBoundary {
    typealias Input = beluga_core_supported_player_arbitration_input_t
    typealias Output = beluga_core_supported_player_arbitration_output_t

    enum Decision: Sendable {
        case retry
        case publish(primary: Int?)
    }

    struct Projection {
        let input: Input
        let available: [Int: MacNowPlayingRuntimeSnapshot]
    }

    /// Called only after the existing native fetch-generation guard under its lock.
    /// No metadata validation or snapshot capacity rule is added by this projection.
    static func project(results: [Int: MacNowPlayingRuntimeSnapshotResult],
                        selected: Int?) -> Projection? {
        guard layoutIsExact, results.count == 2,
              let browser = results[0], let music = results[1] else { return nil }
        let selectedSource: UInt32
        switch selected {
        case nil: selectedSource = 0
        case 0?: selectedSource = 1
        case 1?: selectedSource = 2
        default: return nil
        }

        var available: [Int: MacNowPlayingRuntimeSnapshot] = [:]
        func observation(_ result: MacNowPlayingRuntimeSnapshotResult, source: Int) -> UInt32 {
            switch result {
            case .noActiveMedia: return 0
            case .snapshot(let snapshot):
                available[source] = snapshot
                // Preserve the original comparison, including NaN/negative/+infinity behavior.
                return snapshot.metadata.playbackRate > 0 ? 2 : 1
            case .retry: return 3
            }
        }

        var input = Input()
        input.abi_version = 1
        input.selected_source = selectedSource
        input.browser_observation = observation(browser, source: 0)
        input.music_observation = observation(music, source: 1)
        input.reserved = 0
        return Projection(input: input, available: available)
    }

    /// Rejection-only copied-output custody, not a second source chooser.
    /// Structurally possible but wrong priority belongs to independent parity/mutation tests.
    static func decision(input: Input, output: Output) -> Decision? {
        guard layoutIsExact, input.abi_version == 1, input.reserved == 0,
              input.selected_source <= 2, input.browser_observation <= 3,
              input.music_observation <= 3,
              output.abi_version == 1, output.reserved == 0,
              output.primary_or_hold <= 2 else { return nil }
        let retry = input.browser_observation == 3 || input.music_observation == 3
        switch output.action {
        case 1:
            guard retry, output.primary_or_hold == input.selected_source else { return nil }
            return .retry
        case 2:
            guard !retry else { return nil }
            switch output.primary_or_hold {
            case 0:
                guard input.browser_observation == 0, input.music_observation == 0 else { return nil }
                return .publish(primary: nil)
            case 1:
                guard input.browser_observation == 1 || input.browser_observation == 2 else { return nil }
                return .publish(primary: 0)
            case 2:
                guard input.music_observation == 1 || input.music_observation == 2 else { return nil }
                return .publish(primary: 1)
            default: return nil
            }
        default: return nil
        }
    }

    private static var layoutIsExact: Bool {
        MemoryLayout<Input>.size == 20 && MemoryLayout<Input>.stride == 20
            && MemoryLayout<Input>.alignment == 4
            && MemoryLayout<Output>.size == 16 && MemoryLayout<Output>.stride == 16
            && MemoryLayout<Output>.alignment == 4
    }
}

/// Immutable per-instance copied-result seam. Production makes one actual C call.
struct BelugaRustSupportedPlayerArbitrationProducer: Sendable {
    typealias Input = BelugaRustSupportedPlayerArbitrationBoundary.Input
    typealias Output = BelugaRustSupportedPlayerArbitrationBoundary.Output
    let arbitrate: @Sendable (Input) -> Output

    static let actual = Self(arbitrate: { beluga_core_supported_player_arbitrate($0) })
}
