import BelugaCore

/// Copied callback policy only; the native session retains SDK and broker authority.
/// The two phases keep the original synchronous authority callback between them.
package enum BelugaRustSparkleAdmission {
    package typealias Request = beluga_core_update_sparkle_admission_request_t
    package typealias Result = beluga_core_update_sparkle_admission_result_t
    package typealias ResultMutation = @Sendable (Request, Result) -> Result

    package enum Action: UInt32, Sendable {
        case foreignUpdater = 1, nonManualCheck, authorityNotRetained, checkNotRequested
        case queryAuthority, consumeAndAdmit
    }

    package static var layoutIsExact: Bool {
        MemoryLayout<Request>.size == 12 && MemoryLayout<Request>.stride == 12
            && MemoryLayout<Request>.alignment == 4
            && MemoryLayout<Request>.offset(of: \Request.abi_version) == 0
            && MemoryLayout<Request>.offset(of: \Request.phase) == 4
            && MemoryLayout<Request>.offset(of: \Request.flags) == 8
            && MemoryLayout<Result>.size == 12 && MemoryLayout<Result>.stride == 12
            && MemoryLayout<Result>.alignment == 4
            && MemoryLayout<Result>.offset(of: \Result.abi_version) == 0
            && MemoryLayout<Result>.offset(of: \Result.status) == 4
            && MemoryLayout<Result>.offset(of: \Result.action) == 8
    }

    package static func prefix(exactCallback: Bool, manualCheck: Bool, running: Bool,
                               resultMutation: ResultMutation? = nil) -> Action? {
        let flags: UInt32 = (exactCallback ? 1 : 0) | (manualCheck ? 2 : 0)
            | (running ? 4 : 0)
        return evaluate(Request(abi_version: 1, phase: 1, flags: flags),
                        resultMutation: resultMutation)
    }

    package static func finish(retained: Bool, freshRequest: Bool,
                               resultMutation: ResultMutation? = nil) -> Action? {
        let flags: UInt32 = (retained ? 1 : 0) | (freshRequest ? 2 : 0)
        return evaluate(Request(abi_version: 1, phase: 2, flags: flags),
                        resultMutation: resultMutation)
    }

    // Only the copied result can be changed by tests. Verification is always the real export.
    package static func evaluate(_ request: Request,
                                 resultMutation: ResultMutation? = nil) -> Action? {
        guard layoutIsExact else { return nil }
        let actual = beluga_core_update_sparkle_admission_decide(request)
        let result = resultMutation?(request, actual) ?? actual
        guard beluga_core_update_sparkle_admission_result_is_valid(request, result) == 1,
              result.abi_version == 1, result.status == 0,
              let action = Action(rawValue: result.action) else { return nil }
        return action
    }
}
