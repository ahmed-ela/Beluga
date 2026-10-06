import BelugaCore

func expectedReason(_ flags: UInt32) -> UInt32 {
    if flags > 127 { return 9 }
    if flags & 2 != 0 { return 1 }
    if flags & 1 == 0 { return 2 }
    if flags & 4 != 0 { return 3 }
    if flags & 8 != 0 { return 4 }
    if flags & 16 == 0 { return 5 }
    if flags & 32 == 0 { return 6 }
    if flags & 64 == 0 { return 7 }
    return 0
}

precondition(beluga_core_abi_version() == 1)
precondition(MemoryLayout<beluga_core_handoff_menu_policy_t>.size == 16)
precondition(MemoryLayout<beluga_core_handoff_menu_policy_t>.alignment == 4)
for flags: UInt32 in 0..<4096 {
    let policy = beluga_core_handoff_menu_policy(1, flags)
    precondition(policy.abi_version == 1)
    precondition(policy.visible == flags & 1)
    precondition(policy.reason == expectedReason(flags))
    precondition(policy.enabled == (policy.reason == 0 ? 1 : 0))
    let unknown = beluga_core_handoff_menu_policy(2, flags)
    precondition(unknown.abi_version == 1 && unknown.reason == 8 && unknown.enabled == 0)
    precondition(unknown.visible == flags & 1)
}
print("BelugaCore Swift import/link PASS: 4096 flags and unknown ABI")
precondition(MemoryLayout<beluga_core_host_lifecycle_state_t>.size == 24)
precondition(MemoryLayout<beluga_core_host_lifecycle_state_t>.alignment == 8)
precondition(MemoryLayout<beluga_core_host_lifecycle_event_t>.size == 24)
precondition(MemoryLayout<beluga_core_host_lifecycle_result_t>.size == 32)
var state = beluga_core_host_lifecycle_initial()
precondition(state.abi_version == 1 && state.run_state == 0 && state.active_token == 0 && state.media_token == 0)
let events: [(UInt32, UInt32, UInt64, UInt64)] = [
    (0, 1, 0, 0), (2, 0, 1, 64), (3, 0, 1, 999), (4, 0, 1, 999), (2, 0, 2, 64)
]
for (opcode, argument, token, length) in events {
    var event = beluga_core_host_lifecycle_event_t()
    event.opcode = opcode; event.argument = argument
    event.exchange_token = token; event.original_utf8_length = length
    let result = beluga_core_host_lifecycle_step(1, state, event)
    precondition(result.status == 0); state = result.state
}
precondition(state.run_state == 2 && state.active_token == 2 && state.media_token == 1)
var stale = beluga_core_host_lifecycle_event_t()
stale.opcode = 4; stale.exchange_token = 1
let unchanged = beluga_core_host_lifecycle_step(1, state, stale)
precondition(unchanged.status == 2 && unchanged.state.active_token == 2 && unchanged.state.media_token == 1)
let invalid = beluga_core_host_lifecycle_step(2, state, stale)
precondition(invalid.status == 3 && invalid.state.run_state == 3)
precondition(invalid.state.active_token == 0 && invalid.state.media_token == 0)
print("BelugaCore Swift lifecycle import/link PASS: reconnect ownership and invalid ABI")
precondition(MemoryLayout<beluga_core_handoff_transactions_state_t>.size == 48)
precondition(MemoryLayout<beluga_core_handoff_transactions_state_t>.alignment == 8)
precondition(MemoryLayout<beluga_core_handoff_transactions_state_t>.offset(of: \.host_receipt) == 8)
precondition(MemoryLayout<beluga_core_handoff_transactions_state_t>.offset(of: \.viewer_envelope) == 32)
precondition(MemoryLayout<beluga_core_handoff_transactions_event_t>.size == 40)
precondition(MemoryLayout<beluga_core_handoff_transactions_event_t>.alignment == 8)
precondition(MemoryLayout<beluga_core_handoff_transactions_event_t>.offset(of: \.result) == 32)
precondition(MemoryLayout<beluga_core_handoff_transactions_result_t>.size == 80)
precondition(MemoryLayout<beluga_core_handoff_transactions_result_t>.alignment == 8)
precondition(MemoryLayout<beluga_core_handoff_transactions_result_t>.offset(of: \.status) == 48)
precondition(MemoryLayout<beluga_core_handoff_transactions_result_t>.offset(of: \.effects) == 52)
precondition(MemoryLayout<beluga_core_handoff_transactions_result_t>.offset(of: \.revoked_receipt) == 56)
precondition(MemoryLayout<beluga_core_handoff_transactions_result_t>.offset(of: \.completed_offer) == 64)
precondition(MemoryLayout<beluga_core_handoff_transactions_result_t>.offset(of: \.completed_result) == 72)
precondition(MemoryLayout<beluga_core_handoff_transactions_result_t>.offset(of: \.reserved) == 76)
func transactionEvent(_ opcode: UInt32, _ receipt: UInt64 = 0, _ envelope: UInt64 = 0,
                      _ offer: UInt64 = 0, _ result: UInt32 = 0) -> beluga_core_handoff_transactions_event_t {
    var event = beluga_core_handoff_transactions_event_t()
    event.opcode = opcode; event.argument = opcode == 2 ? 1 : 0
    event.receipt_token = receipt; event.envelope_token = envelope; event.offer_token = offer; event.result = result
    return event
}
var transaction = beluga_core_handoff_transactions_initial()
precondition(transaction.abi_version == 1 && transaction.host_phase == 0 && transaction.viewer_offer == 0)
var outcome = beluga_core_handoff_transactions_step(1, transaction, transactionEvent(0, 11, 12))
precondition(outcome.status == 0 && outcome.effects == 0 && outcome.state.host_receipt == 11)
transaction = outcome.state
outcome = beluga_core_handoff_transactions_step(1, transaction, transactionEvent(0, 21, 22))
precondition(outcome.status == 1 && outcome.effects == 0 && outcome.state.host_receipt == 11)
outcome = beluga_core_handoff_transactions_step(1, transaction, transactionEvent(2, 0, 31, 32))
precondition(outcome.status == 0 && outcome.state.viewer_offer == 32); transaction = outcome.state
outcome = beluga_core_handoff_transactions_step(1, transaction, transactionEvent(1, 11, 99, 0, 1))
precondition(outcome.status == 1 && outcome.effects == 0 && outcome.state.host_phase == 1)
outcome = beluga_core_handoff_transactions_step(1, transaction, transactionEvent(1, 11, 12, 0, 1))
precondition(outcome.status == 0 && outcome.effects == 3 && outcome.revoked_receipt == 11 && outcome.state.host_result == 1)
transaction = outcome.state
outcome = beluga_core_handoff_transactions_step(1, transaction, transactionEvent(1, 11, 12, 0, 1))
precondition(outcome.status == 2 && outcome.effects == 2 && outcome.revoked_receipt == 0)
outcome = beluga_core_handoff_transactions_step(1, transaction, transactionEvent(1, 11, 12, 0, 2))
precondition(outcome.status == 1 && outcome.effects == 0 && outcome.state.host_result == 1)
outcome = beluga_core_handoff_transactions_step(1, transaction, transactionEvent(4, 0, 0, 32))
precondition(outcome.status == 0 && outcome.effects == 4 && outcome.completed_offer == 32 && outcome.completed_result == 3)
outcome = beluga_core_handoff_transactions_step(2, transaction, transactionEvent(5))
precondition(outcome.status == 3 && outcome.effects == 5 && outcome.revoked_receipt == 11 && outcome.completed_offer == 32 && outcome.completed_result == 3)
precondition(outcome.state.host_phase == 0 && outcome.state.viewer_offer == 0 && outcome.reserved == 0)
print("BelugaCore Swift transaction import/link PASS: exact identity, cached reply, revocation and unknown outcome")
