import BelugaCore
import Foundation

public enum WorldwideScreenLivenessBridgeError: Error, Equatable, Sendable {
    case invalidBridge
}

internal struct BelugaRustScreenLivenessProducer: Sendable {
    typealias State = beluga_core_screen_liveness_state_t
    typealias Sample = beluga_core_screen_liveness_sample_t
    typealias Result = beluga_core_screen_liveness_result_t
    typealias Observe = @Sendable (UInt64, State, Sample) -> Result
    let observe: Observe
    static let actual = Self(observe: { beluga_core_screen_liveness_observe($0, $1, $2) })
}

/// Copied-result custody only. No classification fallback or platform effects.
internal enum BelugaRustScreenLivenessBoundary {
    typealias OptionalWord = beluga_core_screen_liveness_optional_t
    typealias State = beluga_core_screen_liveness_state_t
    typealias Sample = beluga_core_screen_liveness_sample_t
    typealias Snapshot = beluga_core_screen_liveness_snapshot_t
    typealias Result = beluga_core_screen_liveness_result_t

    static func optional(_ value: UInt64?) -> OptionalWord {
        var raw = OptionalWord()
        raw.present = value == nil ? 0 : 1
        raw.value = value ?? 0
        return raw
    }
    static func word(_ value: OptionalWord) -> UInt64? {
        value.present == 1 ? value.value : nil
    }
    static func same(_ lhs: OptionalWord, _ rhs: OptionalWord) -> Bool {
        lhs.present == rhs.present && lhs.value == rhs.value
    }
    static func valid(_ raw: OptionalWord) -> Bool {
        raw.present <= 1 && (raw.present == 1 || raw.value == 0)
    }
    static func cover(_ value: WorldwideScreenLivenessCoverState) -> UInt64 {
        switch value {
        case .none: 0
        case .intentionalBandwidthPause: 1
        case .privacy: 2
        case .resuming: 3
        case .screenHidden: 4
        }
    }
    static func sample(_ input: WorldwideScreenLivenessSample) -> Sample {
        var raw = Sample()
        raw.generation = input.generation
        raw.observed_at = input.observedAtUptimeNanoseconds
        raw.track_attached = input.hasRemoteVideoTrack ? 1 : 0
        raw.cover = cover(input.coverState)
        raw.inbound_present = input.inboundVideo == nil ? 0 : 1
        raw.inbound_bytes = optional(input.inboundVideo?.bytes)
        raw.inbound_packets = optional(input.inboundVideo?.packets)
        raw.decoded_frames = optional(input.inboundVideo?.framesEncodedOrDecoded)
        raw.inbound_width = optional(input.inboundVideo?.frameWidth.map { UInt64(bitPattern: Int64($0)) })
        raw.inbound_height = optional(input.inboundVideo?.frameHeight.map { UInt64(bitPattern: Int64($0)) })
        raw.frames_per_second_bits = optional(input.inboundVideo?.framesPerSecond.map(\.bitPattern))
        if let render = input.renderObservation {
            raw.render_present = 1
            raw.presented_frames = render.presentedFrames
            raw.content_samples = render.contentSamples
            raw.content_changes = render.contentChanges
            raw.presented_at = render.presentedAtUptimeNanoseconds
            raw.render_width_bits = UInt64(bitPattern: Int64(render.frameWidth))
            raw.render_height_bits = UInt64(bitPattern: Int64(render.frameHeight))
        }
        return raw
    }
    static func sampleWords(_ raw: Sample) -> [UInt64] {
        [raw.generation, raw.observed_at, raw.track_attached, raw.cover, raw.inbound_present,
         raw.inbound_bytes.present, raw.inbound_bytes.value,
         raw.inbound_packets.present, raw.inbound_packets.value,
         raw.decoded_frames.present, raw.decoded_frames.value,
         raw.inbound_width.present, raw.inbound_width.value,
         raw.inbound_height.present, raw.inbound_height.value,
         raw.frames_per_second_bits.present, raw.frames_per_second_bits.value,
         raw.render_present, raw.presented_frames, raw.content_samples, raw.content_changes,
         raw.presented_at, raw.render_width_bits, raw.render_height_bits]
    }
    static func stateWords(_ raw: State) -> [UInt64] {
        [raw.previous_present, raw.last_change_at.present, raw.last_change_at.value]
            + sampleWords(raw.previous)
    }
    static func valid(_ raw: Sample) -> Bool {
        let inbound = [raw.inbound_bytes, raw.inbound_packets, raw.decoded_frames,
                       raw.inbound_width, raw.inbound_height, raw.frames_per_second_bits]
        return raw.track_attached <= 1 && raw.cover <= 4
            && raw.inbound_present <= 1 && raw.render_present <= 1
            && inbound.allSatisfy(valid)
            && (raw.inbound_present == 1 || inbound.allSatisfy { $0.present == 0 && $0.value == 0 })
            && (raw.render_present == 1 || [raw.presented_frames, raw.content_samples,
                raw.content_changes, raw.presented_at, raw.render_width_bits,
                raw.render_height_bits].allSatisfy { $0 == 0 })
    }
    static func valid(_ raw: State) -> Bool {
        raw.previous_present <= 1 && valid(raw.last_change_at) && valid(raw.previous)
            && (raw.previous_present == 1
                || (sampleWords(raw.previous).allSatisfy { $0 == 0 }
                    && raw.last_change_at.present == 0 && raw.last_change_at.value == 0))
    }
    private static func counters(_ sample: Sample) -> [OptionalWord] {
        [sample.inbound_bytes, sample.inbound_packets, sample.decoded_frames,
         optional(sample.render_present == 1 ? sample.presented_frames : nil),
         optional(sample.render_present == 1 ? sample.content_samples : nil),
         optional(sample.render_present == 1 ? sample.content_changes : nil)]
    }
    private static func delta(_ current: OptionalWord, _ previous: OptionalWord) -> OptionalWord {
        guard current.present == 1, previous.present == 1,
              current.value >= previous.value else { return optional(nil) }
        return optional(current.value - previous.value)
    }
    private static func dimension(_ raw: OptionalWord) -> OptionalWord {
        raw.present == 1 && (1...32_768).contains(raw.value) ? raw : optional(nil)
    }
    static func accepts(before: State, sample: Sample, output: Result) -> Bool {
        let after = output.state, snapshot = output.snapshot
        guard valid(before), valid(sample), output.abi_version == 1, output.status == 0,
              output.reserved == 0, valid(after), after.previous_present == 1,
              sampleWords(after.previous) == sampleWords(sample),
              snapshot.liveness <= 8, snapshot.reset_reason <= 3,
              snapshot.generation == sample.generation,
              snapshot.track_attached == sample.track_attached,
              snapshot.cover == sample.cover else { return false }
        // Rejection-only numeric custody checks; never synthesize a policy result.
        let current = counters(sample), previous = counters(before.previous)
        let expectedReset: UInt64 = before.previous_present == 0 ? 1
            : before.previous.generation != sample.generation ? 2
            : zip(current, previous).contains(where: {
                $0.0.present == 1 && $0.1.present == 1 && $0.0.value < $0.1.value
            }) ? 3 : 0
        guard snapshot.reset_reason == expectedReset else { return false }
        let expectedDeltas = zip(current, previous).map {
            expectedReset == 0 ? delta($0.0, $0.1) : optional(nil)
        }
        let expectedChange = expectedReset != 0 ? optional(nil)
            : expectedDeltas[5].present == 1 && expectedDeltas[5].value > 0
                ? optional(sample.observed_at) : before.last_change_at
        guard same(after.last_change_at, expectedChange) else { return false }
        if snapshot.reset_reason != 0 {
            guard after.last_change_at.present == 0 else { return false }
        } else if !same(after.last_change_at, before.last_change_at) {
            guard after.last_change_at.present == 1,
                  after.last_change_at.value == sample.observed_at else { return false }
        }
        let totals = [snapshot.inbound_bytes, snapshot.inbound_packets, snapshot.decoded_frames,
                      snapshot.presented_frames, snapshot.content_samples, snapshot.content_changes]
        let expectedTotals = [sample.inbound_bytes, sample.inbound_packets, sample.decoded_frames,
            optional(sample.render_present == 1 ? sample.presented_frames : nil),
            optional(sample.render_present == 1 ? sample.content_samples : nil),
            optional(sample.render_present == 1 ? sample.content_changes : nil)]
        let deltas = [snapshot.inbound_byte_delta, snapshot.inbound_packet_delta,
                      snapshot.decoded_frame_delta, snapshot.presented_frame_delta,
                      snapshot.content_sample_delta, snapshot.content_change_delta]
        guard zip(totals, expectedTotals).allSatisfy({ same($0.0, $0.1) }),
              zip(deltas, expectedDeltas).allSatisfy({ same($0.0, $0.1) }),
              deltas.allSatisfy(valid),
              zip(totals, deltas).allSatisfy({ total, delta in
                  delta.present == 0 || (total.present == 1 && delta.value <= total.value)
              }),
              snapshot.reset_reason == 0 || deltas.allSatisfy({ $0.present == 0 }),
              valid(snapshot.presentation_age_ms),
              (snapshot.presentation_age_ms.present == 1) == (sample.render_present == 1),
              snapshot.presentation_age_ms.value <= WorldwideScreenLivenessDiagnosticSnapshot.maximumPresentationAgeMilliseconds,
              valid(snapshot.frame_width), valid(snapshot.frame_height),
              [snapshot.frame_width, snapshot.frame_height].allSatisfy({
                  $0.present == 0 || (1...32_768).contains($0.value)
              }),
              valid(snapshot.frames_per_second_bits) else { return false }
        let age: UInt64? = sample.render_present == 0 ? nil : min(
            (sample.observed_at >= sample.presented_at
                ? sample.observed_at - sample.presented_at : 0) / 1_000_000,
            WorldwideScreenLivenessDiagnosticSnapshot.maximumPresentationAgeMilliseconds
        )
        let width = dimension(optional(sample.render_present == 1 ? sample.render_width_bits : nil))
        let height = dimension(optional(sample.render_present == 1 ? sample.render_height_bits : nil))
        let expectedWidth = width.present == 1 ? width : dimension(sample.inbound_width)
        let expectedHeight = height.present == 1 ? height : dimension(sample.inbound_height)
        let rawFPS = word(sample.frames_per_second_bits).map(Double.init(bitPattern:))
        let expectedFPS = rawFPS.map({ $0.isFinite && (0...1_000).contains($0) }) == true
            ? sample.frames_per_second_bits : optional(nil)
        guard same(snapshot.presentation_age_ms, optional(age)),
              same(snapshot.frame_width, expectedWidth), same(snapshot.frame_height, expectedHeight),
              same(snapshot.frames_per_second_bits, expectedFPS) else { return false }
        if let bits = word(snapshot.frames_per_second_bits) {
            let value = Double(bitPattern: bits)
            guard value.isFinite, (0...1_000).contains(value),
                  same(snapshot.frames_per_second_bits, sample.frames_per_second_bits) else { return false }
        }
        // These are consistency fences, not a second evidence classifier.
        if sample.cover == 1 { return snapshot.liveness == 0 }
        if sample.cover != 0 { return snapshot.liveness == 1 }
        if sample.track_attached == 0 { return snapshot.liveness == 2 }
        if snapshot.reset_reason != 0 { return snapshot.liveness == 3 }
        return snapshot.liveness >= 3
    }

    static func snapshot(_ raw: Snapshot) throws -> WorldwideScreenLivenessDiagnosticSnapshot {
        let states: [WorldwideScreenLivenessState] = [.intentionallyCovered, .covered, .trackMissing,
            .awaitingEvidence, .inboundRTPStalled, .decodeStalled, .presentationStalled,
            .presentingUnchanged, .presentingLive]
        let resets: [WorldwideScreenLivenessResetReason] = [.none, .initialSample, .generationChanged, .counterRegression]
        let covers: [WorldwideScreenLivenessCoverState] = [.none, .intentionalBandwidthPause, .privacy, .resuming, .screenHidden]
        guard raw.liveness < UInt64(states.count), raw.reset_reason < UInt64(resets.count), raw.cover < UInt64(covers.count) else {
            throw WorldwideScreenLivenessBridgeError.invalidBridge
        }
        return WorldwideScreenLivenessDiagnosticSnapshot(
            state: states[Int(raw.liveness)], resetReason: resets[Int(raw.reset_reason)],
            generation: raw.generation, trackAttached: raw.track_attached == 1,
            coverState: covers[Int(raw.cover)],
            inboundBytes: word(raw.inbound_bytes), inboundByteDelta: word(raw.inbound_byte_delta),
            inboundPackets: word(raw.inbound_packets), inboundPacketDelta: word(raw.inbound_packet_delta),
            decodedFrames: word(raw.decoded_frames), decodedFrameDelta: word(raw.decoded_frame_delta),
            presentedFrames: word(raw.presented_frames), presentedFrameDelta: word(raw.presented_frame_delta),
            contentSamples: word(raw.content_samples), contentSampleDelta: word(raw.content_sample_delta),
            contentChanges: word(raw.content_changes), contentChangeDelta: word(raw.content_change_delta),
            lastPresentationAgeMilliseconds: word(raw.presentation_age_ms),
            frameWidth: word(raw.frame_width).map(Int.init),
            frameHeight: word(raw.frame_height).map(Int.init),
            framesPerSecond: word(raw.frames_per_second_bits).map(Double.init(bitPattern:))
        )
    }
}
