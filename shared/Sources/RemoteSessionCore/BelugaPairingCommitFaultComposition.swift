import Foundation

/// Internal denial-only dependency. Never encoded, retained by a record or set from runtime input.
internal enum BelugaPairingCommitDecodeSelection: Sendable {
    enum Match: Sendable {
        case any
        case exact(role: UInt32, state: UInt32, cache: UInt32)
    }

    case actual
    case invalidContext
    case corruptReservedResult(Match)

    // Deliberately repeated only by the internal opensteamer/CaptureServer decoder factories.
    // No public/SPI bridge is added just to expose a fault-testing dependency.
    static let key = CodingUserInfoKey(
        rawValue: "com.elamin.beluga.testing.pairing-commit-decode-v1"
    )!

    static func reservedResultMatching(
        role: RemotePeerRole,
        state: RemotePairingPersistenceState,
        cache: RemotePairingCommitPhase?
    ) -> UInt32 {
        let snapshot = BelugaRustPairingCommitBoundary.state(
            role: role, pairingState: state, recoveryPhase: cache
        )
        return 0x8000_0000 | (snapshot.local_role << 8)
            | (snapshot.pairing_state << 4) | snapshot.recovery_phase
    }

    /// Capture is nonthrowing; original native immutable guards still execute first.
    static func capture(from decoder: any Decoder) -> Self {
        guard let supplied = decoder.userInfo[key] else { return .actual }
        guard type(of: supplied) == UInt32.self, let raw = supplied as? UInt32 else {
            return .invalidContext
        }
        if raw == 1 { return .corruptReservedResult(.any) }
        let knownMask: UInt32 = 0x8000_0137
        guard (raw & 0x8000_0000) != 0, (raw & ~knownMask) == 0,
              (raw & 7) <= 4 else { return .invalidContext }
        return .corruptReservedResult(.exact(
            role: (raw >> 8) & 1, state: (raw >> 4) & 3, cache: raw & 7
        ))
    }

    func producer(
        role: RemotePeerRole,
        state: RemotePairingPersistenceState,
        cache: RemotePairingCommitPhase?
    ) -> BelugaRustPairingCommitProducer {
        switch self {
        case .actual: return .actual
        case .invalidContext: return Self.denialOnly
        case .corruptReservedResult(.any): return Self.denialOnly
        case .corruptReservedResult(.exact(let expectedRole, let expectedState, let expectedCache)):
            let snapshot = BelugaRustPairingCommitBoundary.state(
                role: role, pairingState: state, recoveryPhase: cache
            )
            guard snapshot.local_role == expectedRole,
                  snapshot.pairing_state == expectedState,
                  snapshot.recovery_phase == expectedCache else { return .actual }
            return Self.denialOnly
        }
    }

    /// Exactly one actual C call, followed only by copied reserved-output corruption.
    /// Wrong context uses the same actual boundary, not a synthetic thrown bridge error.
    private static var denialOnly: BelugaRustPairingCommitProducer {
        .init(step: { abi, state, event in
            var output = BelugaRustPairingCommitProducer.actual.step(abi, state, event)
            output.reserved = 1
            return output
        })
    }
}

/// Per-call phase-only throwing probe; cannot produce a commit or accepted successor.
internal struct BelugaPairingCommitConstructionProbe: Sendable {
    typealias Before = @Sendable (RemotePairingCommitPhase) throws -> Void
    let before: Before
    static let none = Self(before: { _ in })
}
