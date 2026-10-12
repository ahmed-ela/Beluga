import BelugaCore

/// Copied abort decision only; no native identity, mutation or observation authority.
package enum BelugaRustUpdateAbort {
    package typealias Request = beluga_core_update_abort_request_t
    package typealias Result = beluga_core_update_abort_result_t
    package typealias ResultMutation = @Sendable (Request, Result) -> Result

    package enum Action: UInt32, Sendable {
        case markAbort = 1, preserve, poison
    }

    package static var layoutIsExact: Bool {
        MemoryLayout<Request>.size == 8 && MemoryLayout<Request>.stride == 8
            && MemoryLayout<Request>.alignment == 4
            && MemoryLayout<Request>.offset(of: \Request.abi_version) == 0
            && MemoryLayout<Request>.offset(of: \Request.flags) == 4
            && MemoryLayout<Result>.size == 12 && MemoryLayout<Result>.stride == 12
            && MemoryLayout<Result>.alignment == 4
            && MemoryLayout<Result>.offset(of: \Result.abi_version) == 0
            && MemoryLayout<Result>.offset(of: \Result.status) == 4
            && MemoryLayout<Result>.offset(of: \Result.action) == 8
    }

    package static func classify(
        failurePresent: Bool, cleanUnarmedCycle: Bool, acknowledged: Bool,
        observedAbort: Bool, sameFailureError: Bool, sameNoUpdateError: Bool
    ) -> Action? {
        var flags: UInt32 = 0
        if failurePresent { flags |= 1 << 0 }
        if cleanUnarmedCycle { flags |= 1 << 1 }
        if acknowledged { flags |= 1 << 2 }
        if observedAbort { flags |= 1 << 3 }
        if sameFailureError { flags |= 1 << 4 }
        if sameNoUpdateError { flags |= 1 << 5 }
        return evaluate(Request(abi_version: 1, flags: flags))
    }

    // Direct bridge-test seam only; the actual session uses the fixed C producer.
    package static func evaluate(_ request: Request,
                                 resultMutation: ResultMutation? = nil) -> Action? {
        guard layoutIsExact else { return nil }
        let actual = beluga_core_update_abort_decide(request)
        let result = resultMutation?(request, actual) ?? actual
        guard beluga_core_update_abort_result_is_valid(request, result) == 1,
              result.abi_version == 1, result.status == 0,
              let action = Action(rawValue: result.action) else { return nil }
        return action
    }
}
