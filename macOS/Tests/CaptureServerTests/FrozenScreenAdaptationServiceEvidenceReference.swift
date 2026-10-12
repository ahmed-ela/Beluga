import WebRTCTransport

// Test-only freeze of WorldwideScreenService.swift (3d117d542141a34fb86a0692abb56dec11221e4dbcec20a85cea44a55217eb9a),
// lines 439–463 and 2914–2931. This is not a native identity/admission implementation.
struct FrozenScreenAdaptationFreshnessFence: Equatable {
    private(set) var minimumCollectionSequence: UInt64?

    mutating func beginPostResumeEpoch(minimumCollectionSequence: UInt64) {
        self.minimumCollectionSequence = self.minimumCollectionSequence.map {
            max($0, minimumCollectionSequence)
        } ?? minimumCollectionSequence
    }

    mutating func reset() { minimumCollectionSequence = nil }

    func admits(sequence: UInt64?) -> Bool {
        guard let minimumCollectionSequence else { return true }
        guard let sequence else { return false }
        return sequence >= minimumCollectionSequence
    }
}

struct FrozenScreenAdaptationEvidenceLaneReference: Equatable {
    enum Lane: Equatable { case fastSender, ordinaryFallback }
    private(set) var lane: Lane?
    private(set) var lastEvidenceTime: ContinuousClock.Instant?
    private(set) var revision: UInt64
    private(set) var resetCount = 0

    init(revision: UInt64 = 0) { self.revision = revision }

    mutating func prepare(from lane: Lane, at now: ContinuousClock.Instant) -> UInt64 {
        let exceededMaximumGap = lastEvidenceTime.map {
            $0.duration(to: now) > .seconds(2)
        } ?? false
        if let previousLane = self.lane,
           previousLane != lane || exceededMaximumGap {
            resetCount += 1
            revision &+= 1
        }
        self.lane = lane
        lastEvidenceTime = now
        return revision
    }
}
