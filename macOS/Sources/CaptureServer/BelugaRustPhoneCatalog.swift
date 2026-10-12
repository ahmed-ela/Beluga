import BelugaCore
import RemoteSessionCore

/// Operation-local copied policy. Native records, cryptographic checks and storage stay outside Rust.
struct BelugaRustPhoneCatalog: Sendable {
    typealias Input = beluga_core_phone_catalog_input_t
    typealias Result = beluga_core_phone_catalog_result_t
    typealias ResultMutation = @Sendable (Input, Result) -> Result

    private let resultMutation: ResultMutation?

    init(resultMutation: ResultMutation? = nil) {
        self.resultMutation = resultMutation
    }

    static func input(_ stage: UInt32, operation: UInt32 = 0) -> Input {
        var input = Input()
        input.abi_version = 1
        input.stage = stage
        input.operation = operation
        return input
    }

    func checked(_ input: Input) throws -> Result {
        guard Self.layoutIsExact else { throw WorldwidePairedPhoneCatalogError.invalidCatalog }
        let actual = beluga_core_phone_catalog_decide(input)
        let result = resultMutation?(input, actual) ?? actual
        guard beluga_core_phone_catalog_result_is_valid(input, result) == 1 else {
            throw WorldwidePairedPhoneCatalogError.invalidCatalog
        }
        switch result.error {
        case 0: return result
        case 1: throw WorldwidePairedPhoneCatalogError.invalidCatalog
        case 2: throw WorldwidePairedPhoneCatalogError.identityMismatch
        case 3: throw WorldwidePairedPhoneCatalogError.duplicatePhone
        case 4: throw WorldwidePairedPhoneCatalogError.unknownPhone
        case 5: throw WorldwidePairedPhoneCatalogError.capacityReached
        case 6: throw WorldwidePairedPhoneCatalogError.staleCatalog
        case 7: throw WorldwidePairedPhoneCatalogError.staleRecord
        case 8: throw WorldwidePairedPhoneCatalogError.bindingConflict
        case 9: throw WorldwidePairedPhoneCatalogError.revisionExhausted
        case 10: throw RemoteSessionCoreError.invalidPairingCommitBridge
        default: throw WorldwidePairedPhoneCatalogError.invalidCatalog
        }
    }

    static func slots(_ result: Result) -> [UInt32] {
        [result.slot0, result.slot1, result.slot2, result.slot3,
         result.slot4, result.slot5, result.slot6, result.slot7]
    }

    static var layoutIsExact: Bool {
        UInt16(littleEndian: 1) == 1
            && MemoryLayout<Input>.size == 104 && MemoryLayout<Input>.stride == 104
            && MemoryLayout<Input>.alignment == 8
            && MemoryLayout<Result>.size == 72 && MemoryLayout<Result>.stride == 72
            && MemoryLayout<Result>.alignment == 8
            && MemoryLayout<Input>.offset(of: \Input.abi_version) == 0
            && MemoryLayout<Input>.offset(of: \Input.stage) == 4
            && MemoryLayout<Input>.offset(of: \Input.operation) == 8
            && MemoryLayout<Input>.offset(of: \Input.flags) == 12
            && MemoryLayout<Input>.offset(of: \Input.count) == 16
            && MemoryLayout<Input>.offset(of: \Input.selected_slot) == 20
            && MemoryLayout<Input>.offset(of: \Input.target_slot) == 24
            && MemoryLayout<Input>.offset(of: \Input.duplicate_axes) == 28
            && MemoryLayout<Input>.offset(of: \Input.previous_phase) == 32
            && MemoryLayout<Input>.offset(of: \Input.candidate_phase) == 36
            && MemoryLayout<Input>.offset(of: \Input.previous_recovery) == 40
            && MemoryLayout<Input>.offset(of: \Input.candidate_recovery) == 44
            && MemoryLayout<Input>.offset(of: \Input.reserved0) == 48
            && MemoryLayout<Input>.offset(of: \Input.reserved1) == 52
            && MemoryLayout<Input>.offset(of: \Input.revision) == 56
            && MemoryLayout<Input>.offset(of: \Input.previous_outbound) == 64
            && MemoryLayout<Input>.offset(of: \Input.candidate_outbound) == 72
            && MemoryLayout<Input>.offset(of: \Input.previous_accepted) == 80
            && MemoryLayout<Input>.offset(of: \Input.candidate_accepted) == 88
            && MemoryLayout<Input>.offset(of: \Input.reserved2) == 96
            && MemoryLayout<Result>.offset(of: \Result.abi_version) == 0
            && MemoryLayout<Result>.offset(of: \Result.status) == 4
            && MemoryLayout<Result>.offset(of: \Result.error) == 8
            && MemoryLayout<Result>.offset(of: \Result.action) == 12
            && MemoryLayout<Result>.offset(of: \Result.count) == 16
            && MemoryLayout<Result>.offset(of: \Result.selected_slot) == 20
            && MemoryLayout<Result>.offset(of: \Result.target_slot) == 24
            && MemoryLayout<Result>.offset(of: \Result.reserved) == 28
            && MemoryLayout<Result>.offset(of: \Result.slot0) == 32
            && MemoryLayout<Result>.offset(of: \Result.slot1) == 36
            && MemoryLayout<Result>.offset(of: \Result.slot2) == 40
            && MemoryLayout<Result>.offset(of: \Result.slot3) == 44
            && MemoryLayout<Result>.offset(of: \Result.slot4) == 48
            && MemoryLayout<Result>.offset(of: \Result.slot5) == 52
            && MemoryLayout<Result>.offset(of: \Result.slot6) == 56
            && MemoryLayout<Result>.offset(of: \Result.slot7) == 60
            && MemoryLayout<Result>.offset(of: \Result.revision) == 64
    }
}
