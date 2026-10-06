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
