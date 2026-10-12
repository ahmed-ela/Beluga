import BelugaCore
import Foundation
@testable import WebRTCTransport
import XCTest

private final class ScreenLivenessRawRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [([UInt64], [UInt64])] = []
    func append(_ before: beluga_core_screen_liveness_state_t, _ sample: beluga_core_screen_liveness_sample_t) {
        lock.withLock { records.append((BelugaRustScreenLivenessBoundary.stateWords(before),
                                        BelugaRustScreenLivenessBoundary.sampleWords(sample))) }
    }
    var recorded: [([UInt64], [UInt64])] { lock.withLock { records } }
}

final class BelugaRustScreenLivenessTests: XCTestCase {
    private func sample(
        generation: UInt64 = 1, now: UInt64, counters: [UInt64] = [10,10,10,10,10,5],
        presentedAt: UInt64? = nil, track: Bool = true,
        cover: WorldwideScreenLivenessCoverState = .none
    ) -> WorldwideScreenLivenessSample {
        .init(generation: generation, observedAtUptimeNanoseconds: now,
              hasRemoteVideoTrack: track, coverState: cover,
              inboundVideo: .init(bytes: counters[0], packets: counters[1],
                                  framesPerSecond: 30, frameWidth: 1_280, frameHeight: 832,
                                  framesEncodedOrDecoded: counters[2]),
              renderObservation: .init(presentedFrames: counters[3], contentSamples: counters[4],
                  contentChanges: counters[5], presentedAtUptimeNanoseconds: presentedAt ?? now,
                  frameWidth: 1_280, frameHeight: 832))
    }

    private func compare(_ samples: [WorldwideScreenLivenessSample]) throws
        -> [WorldwideScreenLivenessDiagnosticSnapshot] {
        var actual = WorldwideScreenLivenessClassifier()
        var original = FrozenWorldwideScreenLivenessClassifier()
        return try samples.map { input in
            // The production adapter calls actual C before invoking the frozen original.
            let output = try actual.observe(input)
            let reference = original.observe(input)
            XCTAssertEqual(output, reference)
            return output
        }
    }

    func testFractionalPresentationAndExactContentFreshnessHaveLiteralDifferentEdges() throws {
        let anchors: [(UInt64,UInt64,WorldwideScreenLivenessState)] = [
            (2_499_999_999,2_499,.presentingLive),
            (2_500_000_000,2_500,.presentingLive),
            (2_500_000_001,2_500,.presentingUnchanged),
            (2_500_999_999,2_500,.presentingUnchanged),
            (2_501_000_000,2_501,.inboundRTPStalled),
        ]
        let inputs = [sample(now:0,presentedAt:0),
            sample(now:0,counters:[10,10,10,10,10,6],presentedAt:0)]
            + anchors.map { sample(now:$0.0,counters:[10,10,10,10,10,6],presentedAt:0) }
        let outputs = try compare(inputs)
        XCTAssertEqual(outputs[1].state,.presentingLive)
        for (index,anchor) in anchors.enumerated() {
            XCTAssertEqual(outputs[index+2].state,anchor.2)
            XCTAssertEqual(outputs[index+2].lastPresentationAgeMilliseconds,anchor.1)
            XCTAssertEqual(outputs[index+2].resetReason,.none)
        }
    }

    func testAllCoversPrecedeAbsentTrackAndEveryResetReason() throws {
        for cover in [WorldwideScreenLivenessCoverState.intentionalBandwidthPause,.privacy,.resuming,.screenHidden] {
            let out = try compare([sample(now:0,track:false,cover:cover),
                sample(generation:2,now:1,counters:[0,0,0,0,0,0],track:false,cover:cover)])
            XCTAssertEqual(out[0].state,cover == .intentionalBandwidthPause ? .intentionallyCovered : .covered)
            XCTAssertEqual(out[1].state,out[0].state)
            XCTAssertEqual(out[1].resetReason,.generationChanged)
            XCTAssertEqual(out[1].statusText,cover.statusText)
        }
    }

    func testCoveredAndMissingTrackObservationsStillAdvanceBothHistorySlots() throws {
        for coverAndTrack in [(WorldwideScreenLivenessCoverState.privacy,true),(.none,false)] {
            let out = try compare([sample(now:0),sample(now:1,counters:[11,11,11,11,11,6],
                track:coverAndTrack.1,cover:coverAndTrack.0),
                sample(now:2,counters:[11,11,11,11,11,6],presentedAt:1)])
            XCTAssertEqual(out[2].state,.presentingLive)
            XCTAssertEqual(out[2].inboundByteDelta,0)
            XCTAssertEqual(out[2].presentedFrameDelta,0)
            XCTAssertEqual(out[2].contentChangeDelta,0)
        }
    }

    func testEachSingleRegressionClearsAllDeltasAndGenerationWinsPrecedence() throws {
        for index in 0..<6 {
            var counters: [UInt64] = [12,12,12,12,12,7]
            counters[index] = 0
            let out = try compare([sample(now:0),
                sample(now:1,counters:[11,11,11,11,11,6]),sample(now:2,counters:counters)])
            XCTAssertEqual(out[2].resetReason,.counterRegression)
            XCTAssertEqual(out[2].state,.awaitingEvidence)
            XCTAssertNil(out[2].inboundByteDelta); XCTAssertNil(out[2].inboundPacketDelta)
            XCTAssertNil(out[2].decodedFrameDelta); XCTAssertNil(out[2].presentedFrameDelta)
            XCTAssertNil(out[2].contentSampleDelta); XCTAssertNil(out[2].contentChangeDelta)
        }
        let out = try compare([sample(generation:.max,now:0,counters:[.max,.max,.max,.max,.max,.max]),
            sample(generation:0,now:1,counters:[0,0,0,0,0,0])])
        XCTAssertEqual(out[1].resetReason,.generationChanged)
    }

    func testOptionalCounterHolesAndMetadataOnlyInboundAreNotZero() throws {
        let first = sample(now:0,counters:[100,100,100,100,100,100])
        let hole = WorldwideScreenLivenessSample(generation:1,observedAtUptimeNanoseconds:1,
            hasRemoteVideoTrack:true,coverState:.none,
            inboundVideo:.init(packets:101,framesEncodedOrDecoded:101),
            renderObservation:first.renderObservation)
        let low = WorldwideScreenLivenessSample(generation:1,observedAtUptimeNanoseconds:2,
            hasRemoteVideoTrack:true,coverState:.none,
            inboundVideo:.init(bytes:1,packets:102,framesEncodedOrDecoded:102),
            renderObservation:first.renderObservation)
        let out = try compare([first,hole,low])
        XCTAssertNil(out[2].inboundByteDelta)
        XCTAssertEqual(out[2].inboundPacketDelta,1)
        XCTAssertEqual(out[2].resetReason,.none)
        let metadata = WorldwideScreenLivenessSample(generation:0,observedAtUptimeNanoseconds:.max,
            hasRemoteVideoTrack:true,coverState:.none,
            inboundVideo:.init(framesPerSecond:24,frameWidth:1_920,frameHeight:1_080),
            renderObservation:nil)
        let m = try compare([metadata,metadata])
        XCTAssertEqual(m[1].state,.awaitingEvidence)
        XCTAssertNil(m[1].inboundByteDelta)
        XCTAssertEqual(m[1].frameWidth,1_920); XCTAssertEqual(m[1].framesPerSecond,24)
    }

    func testDimensionFallbackIsPerAxisAndFPSRawNaNPayloadDoesNotBecomeAConstraint() throws {
        let input = WorldwideScreenLivenessSample(generation:0,observedAtUptimeNanoseconds:0,
            hasRemoteVideoTrack:true,coverState:.none,
            inboundVideo:.init(framesPerSecond:Double(bitPattern:0xfff8_0000_0000_0011),
                frameWidth:1_920,frameHeight:1_080),
            renderObservation:.init(presentedFrames:0,contentSamples:0,contentChanges:0,
                presentedAtUptimeNanoseconds:0,frameWidth:-1,frameHeight:832))
        let out = try compare([input])
        XCTAssertEqual(out[0].frameWidth,1_920); XCTAssertEqual(out[0].frameHeight,832)
        XCTAssertNil(out[0].framesPerSecond)
    }

    func testFuturePresentationClockReversalAndFullWidthAgePreserveOriginalSemantics() throws {
        let out = try compare([sample(now:10),sample(now:20,counters:[11,11,11,11,11,6]),
            sample(now:15,counters:[11,11,11,11,11,6],presentedAt:20)])
        XCTAssertEqual(out[2].state,.presentingUnchanged)
        XCTAssertEqual(out[2].lastPresentationAgeMilliseconds,0)
        XCTAssertEqual(out[2].resetReason,.none)
        let age = try compare([sample(generation:.max,now:.max,presentedAt:0)])
        XCTAssertEqual(age[0].lastPresentationAgeMilliseconds,86_400_000)
    }

    func testFullWidthCountersAndValueCopiesPreserveExactDeltas() throws {
        for n in [UInt64(UInt32.max),UInt64(1)<<53,UInt64(Int64.max),UInt64.max-1] {
            let out = try compare([sample(generation:.max,now:0,counters:[n,n,n,n,n,n]),
                sample(generation:.max,now:1,counters:[n+1,n+1,n+1,n+1,n+1,n+1])])
            XCTAssertEqual(out[1].inboundByteDelta,1); XCTAssertEqual(out[1].contentChangeDelta,1)
        }
        var base = WorldwideScreenLivenessClassifier()
        _ = try base.observe(sample(now:0,counters:[0,0,0,0,0,0]))
        var a = base, b = base
        XCTAssertEqual(try a.observe(sample(now:1,counters:[.max,.max,.max,.max,.max,.max])).inboundByteDelta,.max)
        XCTAssertEqual(try b.observe(sample(now:2,counters:[1,1,1,1,1,1])).inboundByteDelta,1)
        base.reset()
        XCTAssertEqual(try base.observe(sample(now:3)).resetReason,.initialSample)
    }

    func testTypedProjectionCallsActualCFirstAndPreservesEveryInputAndBothStateSlots() throws {
        let recorder = ScreenLivenessRawRecorder()
        let producer = BelugaRustScreenLivenessProducer(observe: { abi,before,input in
            let actual = beluga_core_screen_liveness_observe(abi,before,input)
            recorder.append(before,input)
            return actual
        })
        var classifier = WorldwideScreenLivenessClassifier(producer:producer)
        let input = WorldwideScreenLivenessSample(generation:0xffff_ffff_ffff_ffe0,observedAtUptimeNanoseconds:.max,
            hasRemoteVideoTrack:true,coverState:.resuming,
            inboundVideo:.init(bytes:0xffff_ffff_ffff_fffe,packets:0x8000_0000_0000_0001,
                framesPerSecond:Double(bitPattern:0xfff8_0000_0000_0042),
                frameWidth:Int.min+3,frameHeight:Int.max-5,framesEncodedOrDecoded:0x0020_0000_0000_0002),
            renderObservation:.init(presentedFrames:0xffff_ffff_ffff_fff3,
                contentSamples:0x8000_0000_0000_0004,contentChanges:0x0020_0000_0000_0005,
                presentedAtUptimeNanoseconds:.max-7,frameWidth:Int.max-7,frameHeight:Int.min+11))
        _ = try classifier.observe(input)
        let expected: [UInt64] = [0xffff_ffff_ffff_ffe0,.max,1,3,1,
            1,0xffff_ffff_ffff_fffe,1,0x8000_0000_0000_0001,1,0x0020_0000_0000_0002,
            1,0x8000_0000_0000_0003,1,0x7fff_ffff_ffff_fffa,1,0xfff8_0000_0000_0042,
            1,0xffff_ffff_ffff_fff3,0x8000_0000_0000_0004,0x0020_0000_0000_0005,
            .max-7,0x7fff_ffff_ffff_fff8,0x8000_0000_0000_000b]
        XCTAssertEqual(recorder.recorded.count,1)
        XCTAssertEqual(recorder.recorded[0].0,[UInt64](repeating:0,count:27))
        XCTAssertEqual(recorder.recorded[0].1,expected)
        _ = try classifier.observe(input)
        XCTAssertEqual(recorder.recorded.count,2)
        XCTAssertEqual(recorder.recorded[1].0,[1,0,0]+expected)
        // Establish a real positive-change clock, then verify its separate optional slot.
        var live = WorldwideScreenLivenessClassifier(producer:producer)
        _ = try live.observe(sample(now:0))
        _ = try live.observe(sample(now:7,counters:[11,11,11,11,11,6]))
        _ = try live.observe(sample(now:8,counters:[11,11,11,11,11,6],presentedAt:7))
        XCTAssertEqual(Array(recorder.recorded.last!.0.prefix(3)),[1,1,7])
    }

    func testTypedProjectionPreservesAbsentMetadataPresenceAllCoversAndSignedZeroFPS() throws {
        let recorder=ScreenLivenessRawRecorder()
        let producer=BelugaRustScreenLivenessProducer(observe:{abi,before,input in
            let actual=beluga_core_screen_liveness_observe(abi,before,input)
            recorder.append(before,input); return actual
        })
        for (index,cover) in [WorldwideScreenLivenessCoverState.none,.intentionalBandwidthPause,.privacy,.resuming,.screenHidden].enumerated() {
            var classifier=WorldwideScreenLivenessClassifier(producer:producer)
            _ = try classifier.observe(.init(generation:0,observedAtUptimeNanoseconds:0,
                hasRemoteVideoTrack:false,coverState:cover,inboundVideo:nil,renderObservation:nil))
            let expected:[UInt64]=[0,0,0,UInt64(index)]+[UInt64](repeating:0,count:20)
            XCTAssertEqual(recorder.recorded.last!.1,expected)
        }
        var classifier=WorldwideScreenLivenessClassifier(producer:producer)
        let metadata=WorldwideScreenLivenessSample(generation:0,observedAtUptimeNanoseconds:0,
            hasRemoteVideoTrack:true,coverState:.none,
            inboundVideo:.init(framesPerSecond:-0.0,frameHeight:32768),renderObservation:nil)
        let output=try classifier.observe(metadata)
        XCTAssertEqual(recorder.recorded.last!.1,
            [0,0,1,0,1,0,0,0,0,0,0,0,0,1,32768,1,0x8000_0000_0000_0000,0,0,0,0,0,0,0])
        XCTAssertEqual(output.framesPerSecond?.bitPattern,0x8000_0000_0000_0000)
    }

    func testCopiedResultCorruptionThrowsAndCannotAdvanceEitherHistorySlot() throws {
        typealias Result=beluga_core_screen_liveness_result_t
        let corruptions: [@Sendable (inout Result)->Void] = [
            {$0.abi_version=2},{$0.status=3},{$0.reserved=1},
            {$0.state.previous_present=0},{$0.state.previous.generation ^= 1},
            {$0.state.last_change_at.present=2},{$0.snapshot.liveness=9},
            {$0.snapshot.reset_reason=4},{$0.snapshot.track_attached=2},
            {$0.snapshot.cover=5},{$0.snapshot.generation ^= 1},
            {$0.snapshot.inbound_bytes.value ^= 1},{$0.snapshot.inbound_byte_delta.present=2},
            {$0.snapshot.inbound_byte_delta.value = .max},
            {$0.snapshot.presentation_age_ms.value=86_400_001},
            {$0.snapshot.frame_width.value=32_769},
            {$0.snapshot.frames_per_second_bits.value=Double.infinity.bitPattern},
            {$0.snapshot.inbound_byte_delta.present=0;$0.snapshot.inbound_byte_delta.value=0},
            {$0.state.last_change_at.present=0;$0.state.last_change_at.value=0},
            {$0.snapshot.presentation_age_ms.value=1},
            {$0.snapshot.frame_width.present=0;$0.snapshot.frame_width.value=0},
            {$0.snapshot.frames_per_second_bits.present=0;$0.snapshot.frames_per_second_bits.value=0},
        ]
        for corrupt in corruptions {
            let producer=BelugaRustScreenLivenessProducer(observe:{abi,before,input in
                var actual=beluga_core_screen_liveness_observe(abi,before,input)
                if input.observed_at == 2 { corrupt(&actual) }
                return actual
            })
            var classifier=WorldwideScreenLivenessClassifier(producer:producer)
            _ = try classifier.observe(sample(now:0))
            _ = try classifier.observe(sample(now:1,counters:[11,11,11,11,11,6]))
            let before=BelugaRustScreenLivenessBoundary.stateWords(classifier.rawStateForTests)
            XCTAssertThrowsError(try classifier.observe(sample(now:2,counters:[12,12,12,12,12,7]))) {
                XCTAssertEqual($0 as? WorldwideScreenLivenessBridgeError,.invalidBridge)
            }
            XCTAssertEqual(BelugaRustScreenLivenessBoundary.stateWords(classifier.rawStateForTests),before)
            var resumed: WorldwideScreenLivenessDiagnosticSnapshot?
            XCTAssertNoThrow(resumed = try classifier.observe(sample(now:3,counters:[13,13,13,13,13,8])))
            XCTAssertEqual(resumed?.inboundByteDelta,2)
            XCTAssertEqual(resumed?.contentChangeDelta,2)
        }
    }

    func testTypedProjectionOptionalFieldsAndTrackInboundRenderPresenceRemainIndependent() throws {
        let recorder=ScreenLivenessRawRecorder()
        let producer=BelugaRustScreenLivenessProducer(observe:{abi,before,input in
            let actual=beluga_core_screen_liveness_observe(abi,before,input)
            recorder.append(before,input);return actual
        })
        let records: [(WebRTCVideoStatistics?,WorldwideScreenLivenessRenderObservation?,Bool,[UInt64])] = [
            (.init(bytes:41),nil,false,[0,0,0,0,1,1,41,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]),
            (.init(packets:43),nil,true,[0,0,1,0,1,0,0,1,43,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]),
            (.init(framesEncodedOrDecoded:47),nil,false,[0,0,0,0,1,0,0,0,0,1,47,0,0,0,0,0,0,0,0,0,0,0,0,0]),
            (.init(frameWidth:53),nil,true,[0,0,1,0,1,0,0,0,0,0,0,1,53,0,0,0,0,0,0,0,0,0,0,0]),
            (.init(frameHeight:59),nil,false,[0,0,0,0,1,0,0,0,0,0,0,0,0,1,59,0,0,0,0,0,0,0,0,0]),
            (.init(),nil,false,[0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]),
            (nil,.init(presentedFrames:61,contentSamples:67,contentChanges:71,
                presentedAtUptimeNanoseconds:73,frameWidth:79,frameHeight:83),true,
                [0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,61,67,71,73,79,83]),
        ]
        for (inbound,render,track,expected) in records {
            var classifier=WorldwideScreenLivenessClassifier(producer:producer)
            _ = try classifier.observe(.init(generation:0,observedAtUptimeNanoseconds:0,
                hasRemoteVideoTrack:track,coverState:.none,inboundVideo:inbound,renderObservation:render))
            XCTAssertEqual(recorder.recorded.last!.1,expected)
        }
        for bits in [UInt64(0x7ff8_0000_0000_0011),0xfff8_0000_0000_0022,
            0x7ff0_0000_0000_0000,0xfff0_0000_0000_0000,0,0x8000_0000_0000_0000] {
            var classifier=WorldwideScreenLivenessClassifier(producer:producer)
            _ = try classifier.observe(.init(generation:0,observedAtUptimeNanoseconds:0,
                hasRemoteVideoTrack:true,coverState:.none,
                inboundVideo:.init(framesPerSecond:Double(bitPattern:bits)),renderObservation:nil))
            XCTAssertEqual(recorder.recorded.last!.1,
                [0,0,1,0,1,0,0,0,0,0,0,0,0,0,0,1,bits,0,0,0,0,0,0,0])
        }
    }
}
