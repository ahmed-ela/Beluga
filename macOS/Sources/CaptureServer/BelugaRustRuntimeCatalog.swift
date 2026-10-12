import BelugaCore

/// Copied authority only. UUIDs, full records, native tasks and clients never enter this ABI.
struct BelugaRustRuntimeCatalog: Sendable {
    typealias State = beluga_core_runtime_catalog_state_t
    typealias Event = beluga_core_runtime_catalog_event_t
    typealias Result = beluga_core_runtime_catalog_result_t
    typealias ResultMutation = @Sendable (State, Event, Result) -> Result

    enum Stage: UInt32, CaseIterable, Sendable {
        case startupGuard = 0, startupInstalled, preflight, quietStructural, owner, authorization
        case catalogPresence, catalogFresh, begin, retirementEnter, retirementDrained
        case retirementFinish, revalidate, end, recoveryStructural, recoveryOwner
        case recoveryPresence, recoveryFresh, resumeBeforeOwner, resumeOwner, pairIdentity
        case installIntent, clearIntent, takeIntent, bootstrapStartBeforeOwner, bootstrapStartAfterOwner
        case commitBeforeOwner, commitAfterOwner, commitStoppedBeforeOwner, commitStoppedAfterOwner
        case recordReadback, activationAuthority, activationIntent, bootstrapEndBeforeOwner
        case bootstrapEndAfterOwner, bootstrapEndStoppedBeforeOwner, bootstrapEndStoppedAfterOwner
        case availabilityStartBeforeOwner, availabilityStartAfterOwner, generationBeforeOwner
        case generationAfterOwner, currentClientPresence, currentClientExact, persistSelected
        case mediaTargetBeforeOwner, mediaTargetAfterOwner, preparedBeforeOwner, preparedAfterOwner
        case revoke, pairCatchBeforeOwner, pairCatchAfterOwner, invitationChanged
        case availabilityEnded, availabilityEndedTerminal, mediaMove, preparedRetire
        case preparedLifecyclePrefix, mediaMovePrefix
    }

    enum Operation: UInt32, Sendable { case none = 0, select, forget, pair }

    private(set) var state: State
    private(set) var isPoisoned = false
    private let resultMutation: ResultMutation?

    init(resultMutation: ResultMutation? = nil) {
        var initial = State()
        initial.abi_version = 1
        state = initial
        self.resultMutation = resultMutation
    }

    static func flags(_ facts: [Bool]) -> UInt32 {
        precondition(facts.count <= 32)
        return facts.enumerated().reduce(0) { $0 | ($1.element ? UInt32(1) << $1.offset : 0) }
    }

    mutating func decide(_ stage: Stage, _ facts: [Bool] = [], operation: Operation = .none) throws -> Result {
        var event = Event()
        event.opcode = stage.rawValue
        event.operation = operation.rawValue
        event.facts = Self.flags(facts)
        return try checked(event)
    }

    /// A rejected proposal cannot install even a success-looking state or erase native custody.
    mutating func checked(_ event: Event) throws -> Result {
        guard !isPoisoned, Self.layoutIsExact else {
            isPoisoned = true
            throw WorldwidePhoneCatalogRuntimeError.invalidRuntimeCatalogBridge
        }
        let actual = beluga_core_runtime_catalog_step(state, event)
        let result = resultMutation?(state, event, actual) ?? actual
        guard beluga_core_runtime_catalog_result_is_valid(state, event, result) == 1 else {
            isPoisoned = true
            throw WorldwidePhoneCatalogRuntimeError.invalidRuntimeCatalogBridge
        }
        state = result.state
        return result
    }

    @discardableResult
    mutating func require(_ stage: Stage, _ facts: [Bool] = [], operation: Operation = .none) throws -> Result {
        let result = try decide(stage, facts, operation: operation)
        switch result.decision {
        case 0: return result
        case 2: throw WorldwideHostCoordinatorError.invalidLifecycle
        case 3: throw WorldwidePairedPhoneCatalogError.unknownPhone
        case 4: throw WorldwidePairedPhoneCatalogError.capacityReached
        case 5: throw WorldwidePhoneCatalogRuntimeError.notQuiet
        case 6: throw WorldwidePhoneCatalogRuntimeError.ownerNotAuthorized
        case 7: throw WorldwidePhoneCatalogRuntimeError.staleSelection
        case 8: throw CancellationError()
        case 9: throw WorldwidePhoneCatalogRuntimeError.staleAttempt
        default: throw WorldwidePhoneCatalogRuntimeError.invalidRuntimeCatalogBridge
        }
    }

    mutating func permits(_ stage: Stage, _ facts: [Bool] = []) -> Bool {
        (try? decide(stage, facts).decision) == 0
    }

    func requireHealthy() throws {
        guard !isPoisoned else { throw WorldwidePhoneCatalogRuntimeError.invalidRuntimeCatalogBridge }
    }

    /// Native shutdown proceeds whether or not the copied bridge is trustworthy.
    /// On corruption, keep the last verified state and sticky denial, never manufacture revoke proof.
    mutating func revoke() { _ = try? decide(.revoke) }

    static var layoutIsExact: Bool {
        MemoryLayout<State>.size == 24 && MemoryLayout<State>.stride == 24 &&
        MemoryLayout<State>.alignment == 4 &&
        MemoryLayout<State>.offset(of: \.abi_version) == 0 &&
        MemoryLayout<State>.offset(of: \.phase) == 4 &&
        MemoryLayout<State>.offset(of: \.operation) == 8 &&
        MemoryLayout<State>.offset(of: \.eligible) == 12 &&
        MemoryLayout<State>.offset(of: \.intent) == 16 &&
        MemoryLayout<State>.offset(of: \.first_grant) == 20 &&
        MemoryLayout<Event>.size == 16 && MemoryLayout<Event>.stride == 16 &&
        MemoryLayout<Event>.alignment == 4 &&
        MemoryLayout<Event>.offset(of: \.opcode) == 0 &&
        MemoryLayout<Event>.offset(of: \.operation) == 4 &&
        MemoryLayout<Event>.offset(of: \.facts) == 8 &&
        MemoryLayout<Event>.offset(of: \.reserved) == 12 &&
        MemoryLayout<Result>.size == 40 && MemoryLayout<Result>.stride == 40 &&
        MemoryLayout<Result>.alignment == 4 &&
        MemoryLayout<Result>.offset(of: \.state) == 0 &&
        MemoryLayout<Result>.offset(of: \.status) == 24 &&
        MemoryLayout<Result>.offset(of: \.decision) == 28 &&
        MemoryLayout<Result>.offset(of: \.effect) == 32 &&
        MemoryLayout<Result>.offset(of: \.value) == 36
    }
}
