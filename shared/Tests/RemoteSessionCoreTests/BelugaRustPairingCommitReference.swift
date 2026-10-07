/// Independent scalar specification from the frozen original Swift guards.
/// This file does not call the new Rust producer, copied boundary, enums or helpers.
internal struct OriginalPairingCommitPlan {
    let phase: UInt32
    let cache: UInt32
    let decision: UInt32
    let action: UInt32
    let auth: UInt32

    static func evaluate(
        role: UInt32, phase: UInt32, cache: UInt32, opcode: UInt32, exact: UInt32
    ) -> Self {
        func result(
            _ decision: UInt32, _ action: UInt32, _ auth: UInt32,
            phase nextPhase: UInt32? = nil, cache nextCache: UInt32? = nil
        ) -> Self {
            Self(
                phase: nextPhase ?? phase, cache: nextCache ?? cache,
                decision: decision, action: action, auth: auth
            )
        }
        guard role <= 1, phase <= 3, cache <= 4, opcode <= 8,
              exact <= 1, opcode == 5 || exact == 0 else { return result(4, 0, 0) }
        switch opcode {
        case 0:
            if cache != 0 { return result(0, 3, 0) }
            switch phase {
            case 0: return result(0, role == 0 ? 2 : 1, 0)
            case 1: return result(0, 1, 0)
            case 2: return result(0, 4, 0)
            default: return result(0, 0, 0)
            }
        case 1:
            guard role == 0, phase == 0 else { return result(1, 0, 0) }
            if cache == 1 { return result(0, 3, 0) }
            guard cache == 0 else { return result(1, 0, 0) }
            return result(0, 5, 0, cache: 1)
        case 2:
            guard role == 1, phase == 0 || phase == 1 else { return result(1, 0, 0) }
            if phase == 1, cache != 0 { return result(0, 3, 1) }
            return result(0, 6, 1, phase: 1, cache: 2)
        case 3:
            guard role == 0, phase == 0 || phase == 2 || phase == 3 else {
                return result(1, 0, 0)
            }
            if phase == 0 { return result(0, 0, 2, phase: 2, cache: 0) }
            return result(0, 0, 2)
        case 4:
            guard role == 0, phase == 2 || phase == 3 else { return result(1, 0, 0) }
            if phase == 3 {
                guard cache == 0 else { return result(1, 0, 0) }
                return result(0, 7, 0)
            }
            if cache == 3 { return result(0, 3, 0) }
            guard cache == 0 else { return result(1, 0, 0) }
            return result(0, 7, 0, cache: 3)
        case 5:
            guard role == 0, exact == 1 else { return result(1, 0, 0) }
            if phase == 2, cache == 3 { return result(0, 0, 0) }
            if phase == 3, cache == 0 { return result(0, 0, 0) }
            return result(1, 0, 0)
        case 6:
            guard role == 1 else { return result(1, 0, 0) }
            if phase == 3 {
                if cache == 4 { return result(0, 3, 3) }
                return result(2, 0, 3)
            }
            guard phase == 1 else { return result(1, 0, 0) }
            return result(0, 8, 3, phase: 3, cache: 4)
        case 7:
            guard role == 0, phase == 2 || phase == 3 else { return result(1, 0, 0) }
            return result(0, 0, 4, phase: 3, cache: 0)
        default:
            // Only stored-shape validation restricts the original eight tuples.
            switch (role, phase, cache) {
            case (0, 0, 0), (0, 0, 1), (0, 2, 0), (0, 2, 3),
                 (0, 3, 0), (1, 0, 0), (1, 1, 2), (1, 3, 4):
                return result(0, cache == 0 ? 0 : 9, 0)
            default: return result(3, 0, 0)
            }
        }
    }
}

