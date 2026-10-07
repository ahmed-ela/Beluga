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
precondition(MemoryLayout<beluga_core_handoff_offers_primary_t>.size == 48)
precondition(MemoryLayout<beluga_core_handoff_offers_primary_t>.alignment == 8)
precondition(MemoryLayout<beluga_core_handoff_offers_primary_t>.offset(of: \.flags) == 0)
precondition(MemoryLayout<beluga_core_handoff_offers_primary_t>.offset(of: \.native_matches) == 8)
precondition(MemoryLayout<beluga_core_handoff_offers_primary_t>.offset(of: \.revision) == 16)
precondition(MemoryLayout<beluga_core_handoff_offers_primary_t>.offset(of: \.position) == 24)
precondition(MemoryLayout<beluga_core_handoff_offers_primary_t>.offset(of: \.duration) == 32)
precondition(MemoryLayout<beluga_core_handoff_offers_primary_t>.offset(of: \.rate) == 40)
precondition(MemoryLayout<beluga_core_handoff_offers_envelope_t>.size == 56)
precondition(MemoryLayout<beluga_core_handoff_offers_envelope_t>.alignment == 8)
precondition(MemoryLayout<beluga_core_handoff_offers_envelope_t>.offset(of: \.text_valid) == 0)
precondition(MemoryLayout<beluga_core_handoff_offers_envelope_t>.offset(of: \.reserved) == 4)
precondition(MemoryLayout<beluga_core_handoff_offers_envelope_t>.offset(of: \.sequence) == 8)
precondition(MemoryLayout<beluga_core_handoff_offers_envelope_t>.offset(of: \.revision) == 16)
precondition(MemoryLayout<beluga_core_handoff_offers_envelope_t>.offset(of: \.position) == 24)
precondition(MemoryLayout<beluga_core_handoff_offers_envelope_t>.offset(of: \.duration) == 32)
precondition(MemoryLayout<beluga_core_handoff_offers_envelope_t>.offset(of: \.rate) == 40)
precondition(MemoryLayout<beluga_core_handoff_offers_envelope_t>.offset(of: \.lifetime) == 48)
precondition(MemoryLayout<beluga_core_handoff_offers_source_t>.size == 48)
precondition(MemoryLayout<beluga_core_handoff_offers_source_t>.alignment == 8)
precondition(MemoryLayout<beluga_core_handoff_offers_source_t>.offset(of: \.present) == 0)
precondition(MemoryLayout<beluga_core_handoff_offers_source_t>.offset(of: \.video_equal) == 4)
precondition(MemoryLayout<beluga_core_handoff_offers_source_t>.offset(of: \.position) == 8)
precondition(MemoryLayout<beluga_core_handoff_offers_source_t>.offset(of: \.duration) == 16)
precondition(MemoryLayout<beluga_core_handoff_offers_source_t>.offset(of: \.rate) == 24)
precondition(MemoryLayout<beluga_core_handoff_offers_source_t>.offset(of: \.observed_at) == 32)
precondition(MemoryLayout<beluga_core_handoff_offers_source_t>.offset(of: \.deadline) == 40)
precondition(MemoryLayout<beluga_core_handoff_offers_timeline_t>.size == 88)
precondition(MemoryLayout<beluga_core_handoff_offers_timeline_t>.alignment == 8)
precondition(MemoryLayout<beluga_core_handoff_offers_timeline_t>.offset(of: \.token) == 0)
precondition(MemoryLayout<beluga_core_handoff_offers_timeline_t>.offset(of: \.sequence) == 8)
precondition(MemoryLayout<beluga_core_handoff_offers_timeline_t>.offset(of: \.revision) == 16)
precondition(MemoryLayout<beluga_core_handoff_offers_timeline_t>.offset(of: \.position) == 24)
precondition(MemoryLayout<beluga_core_handoff_offers_timeline_t>.offset(of: \.duration) == 32)
precondition(MemoryLayout<beluga_core_handoff_offers_timeline_t>.offset(of: \.rate) == 40)
precondition(MemoryLayout<beluga_core_handoff_offers_timeline_t>.offset(of: \.lifetime) == 48)
precondition(MemoryLayout<beluga_core_handoff_offers_timeline_t>.offset(of: \.origin) == 56)
precondition(MemoryLayout<beluga_core_handoff_offers_timeline_t>.offset(of: \.deadline) == 64)
precondition(MemoryLayout<beluga_core_handoff_offers_timeline_t>.offset(of: \.last_observation) == 72)
precondition(MemoryLayout<beluga_core_handoff_offers_timeline_t>.offset(of: \.last_position) == 80)
precondition(MemoryLayout<beluga_core_handoff_offers_state_t>.size == 224)
precondition(MemoryLayout<beluga_core_handoff_offers_state_t>.alignment == 8)
precondition(MemoryLayout<beluga_core_handoff_offers_state_t>.offset(of: \.abi) == 0)
precondition(MemoryLayout<beluga_core_handoff_offers_state_t>.offset(of: \.presence) == 4)
precondition(MemoryLayout<beluga_core_handoff_offers_state_t>.offset(of: \.terminal) == 8)
precondition(MemoryLayout<beluga_core_handoff_offers_state_t>.offset(of: \.reserved) == 12)
precondition(MemoryLayout<beluga_core_handoff_offers_state_t>.offset(of: \.next_sent) == 16)
precondition(MemoryLayout<beluga_core_handoff_offers_state_t>.offset(of: \.highest_received) == 24)
precondition(MemoryLayout<beluga_core_handoff_offers_state_t>.offset(of: \.sent_at) == 32)
precondition(MemoryLayout<beluga_core_handoff_offers_state_t>.offset(of: \.received_at) == 40)
precondition(MemoryLayout<beluga_core_handoff_offers_state_t>.offset(of: \.sent) == 48)
precondition(MemoryLayout<beluga_core_handoff_offers_state_t>.offset(of: \.received) == 136)
precondition(MemoryLayout<beluga_core_handoff_offers_event_t>.size == 200)
precondition(MemoryLayout<beluga_core_handoff_offers_event_t>.alignment == 8)
precondition(MemoryLayout<beluga_core_handoff_offers_event_t>.offset(of: \.opcode) == 0)
precondition(MemoryLayout<beluga_core_handoff_offers_event_t>.offset(of: \.reserved) == 4)
precondition(MemoryLayout<beluga_core_handoff_offers_event_t>.offset(of: \.token) == 8)
precondition(MemoryLayout<beluga_core_handoff_offers_event_t>.offset(of: \.native_matches) == 16)
precondition(MemoryLayout<beluga_core_handoff_offers_event_t>.offset(of: \.now) == 24)
precondition(MemoryLayout<beluga_core_handoff_offers_event_t>.offset(of: \.phone_position) == 32)
precondition(MemoryLayout<beluga_core_handoff_offers_event_t>.offset(of: \.phone_observed_at) == 40)
precondition(MemoryLayout<beluga_core_handoff_offers_event_t>.offset(of: \.primary) == 48)
precondition(MemoryLayout<beluga_core_handoff_offers_event_t>.offset(of: \.envelope) == 96)
precondition(MemoryLayout<beluga_core_handoff_offers_event_t>.offset(of: \.source) == 152)
precondition(MemoryLayout<beluga_core_handoff_offers_result_t>.size == 288)
precondition(MemoryLayout<beluga_core_handoff_offers_result_t>.alignment == 8)
precondition(MemoryLayout<beluga_core_handoff_offers_result_t>.offset(of: \.state) == 0)
precondition(MemoryLayout<beluga_core_handoff_offers_result_t>.offset(of: \.status) == 224)
precondition(MemoryLayout<beluga_core_handoff_offers_result_t>.offset(of: \.decision) == 228)
precondition(MemoryLayout<beluga_core_handoff_offers_result_t>.offset(of: \.effects) == 232)
precondition(MemoryLayout<beluga_core_handoff_offers_result_t>.offset(of: \.reserved) == 236)
precondition(MemoryLayout<beluga_core_handoff_offers_result_t>.offset(of: \.retired_sent) == 240)
precondition(MemoryLayout<beluga_core_handoff_offers_result_t>.offset(of: \.retired_received) == 248)
precondition(MemoryLayout<beluga_core_handoff_offers_result_t>.offset(of: \.minted_token) == 256)
precondition(MemoryLayout<beluga_core_handoff_offers_result_t>.offset(of: \.sequence) == 264)
precondition(MemoryLayout<beluga_core_handoff_offers_result_t>.offset(of: \.lifetime) == 272)
precondition(MemoryLayout<beluga_core_handoff_offers_result_t>.offset(of: \.deadline) == 280)

func offersEvent(_ opcode: UInt32, _ now: Double) -> beluga_core_handoff_offers_event_t {
    var event = beluga_core_handoff_offers_event_t()
    event.opcode = opcode; event.token = 100; event.native_matches = 15
    event.now = now.bitPattern; event.phone_position = Double(20).bitPattern
    event.phone_observed_at = now.bitPattern
    event.primary.flags = 511; event.primary.native_matches = 12; event.primary.revision = 1
    event.primary.position = Double(20).bitPattern; event.primary.duration = Double(200).bitPattern
    event.primary.rate = Double(1).bitPattern
    event.envelope.text_valid = 1; event.envelope.sequence = 1; event.envelope.revision = 1
    event.envelope.position = Double(20).bitPattern; event.envelope.duration = Double(200).bitPattern
    event.envelope.rate = Double(1).bitPattern; event.envelope.lifetime = Double(30).bitPattern
    return event
}
func offersPair() -> beluga_core_handoff_offers_state_t {
    var state = beluga_core_handoff_offers_initial()
    precondition(state.abi == 1 && state.presence == 0 && state.terminal == 0 && state.next_sent == 1)
    for opcode: UInt32 in [0, 1, 2, 5] {
        let result = beluga_core_handoff_offers_step(1, state, offersEvent(opcode, 10))
        precondition(result.status == 0 && result.reserved == 0)
        if opcode == 2 || opcode == 5 {
            precondition(result.decision == (opcode == 2 ? 1 : 2))
            precondition(result.minted_token == 100 && result.sequence == 1)
            precondition(result.lifetime == Double(30).bitPattern && result.deadline == Double(40).bitPattern)
        }
        state = result.state
    }
    precondition(state.presence == 15 && state.next_sent == 2 && state.highest_received == 1)
    precondition(state.sent.token == 100 && state.received.token == 100)
    return state
}
var offers = offersPair()
var offerResult = beluga_core_handoff_offers_step(1, offers, offersEvent(3, 10))
precondition(offerResult.status == 0 && offerResult.effects == 1 && offerResult.retired_sent == 100)
precondition(offerResult.state.sent.token == 0 && offerResult.state.received.token == 100)
offerResult = beluga_core_handoff_offers_step(1, offers, offersEvent(8, 10))
precondition(offerResult.effects == 2 && offerResult.retired_received == 100)
precondition(offerResult.state.sent.token == 100 && offerResult.state.received.token == 0)
var offerEvent = offersEvent(5, 12)
offerEvent.token = 101; offerEvent.envelope.sequence = 2
offerResult = beluga_core_handoff_offers_step(1, offers, offerEvent)
precondition(offerResult.status == 0 && offerResult.decision == 0 && offerResult.effects == 2)
precondition(offerResult.retired_received == 100 && offerResult.state.highest_received == 2)
precondition(offerResult.state.received.token == 0 && offerResult.state.sent.token == 100)
offers = offerResult.state
offerResult = beluga_core_handoff_offers_step(1, offers, offersEvent(1, 12))
offers = offerResult.state
offerResult = beluga_core_handoff_offers_step(1, offers, offerEvent)
precondition(offerResult.status == 0 && offerResult.decision == 0 && offerResult.effects == 0)
precondition(offerResult.state.received.token == 0 && offerResult.state.highest_received == 2)
offers = offersPair()
offerResult = beluga_core_handoff_offers_step(1, offers, offersEvent(4, 10))
precondition(offerResult.decision == 4 && offerResult.effects == 1 && offerResult.retired_sent == 100)
precondition(offerResult.deadline == Double(40).bitPattern && offerResult.state.received.token == 100)
offerEvent = offersEvent(7, 10); offerEvent.phone_observed_at = Double(9.25).bitPattern
offerResult = beluga_core_handoff_offers_step(1, offers, offerEvent)
precondition(offerResult.decision == 5 && offerResult.effects == 2 && offerResult.retired_received == 100)
precondition(offerResult.state.sent.token == 100 && offerResult.state.received.token == 0)
for opcode: UInt32 in [4, 6] {
    offers = offersPair()
    offerResult = beluga_core_handoff_offers_step(1, offers, offersEvent(opcode, 12))
    precondition(offerResult.status == 0 && offerResult.decision == 0)
    precondition(offerResult.effects == (opcode == 4 ? 1 : 2))
    offers = offerResult.state
    offerResult = beluga_core_handoff_offers_step(1, offers, offersEvent(opcode, 10.1))
    precondition(offerResult.status == 0 && offerResult.decision == 0 && offerResult.effects == 0)
}
offers = offersPair()
offerResult = beluga_core_handoff_offers_step(1, offers, offersEvent(9, 10))
precondition(offerResult.effects == 3 && offerResult.state.presence == 0)
precondition(offerResult.state.next_sent == 2 && offerResult.state.highest_received == 1)
offerResult = beluga_core_handoff_offers_step(1, offers, offersEvent(UInt32.max, 10))
precondition(offerResult.status == 3 && offerResult.effects == 0 && offerResult.decision == 0)
precondition(offerResult.state.abi == offers.abi && offerResult.state.terminal == offers.terminal)
precondition(offerResult.state.presence == offers.presence)
precondition(offerResult.state.next_sent == offers.next_sent && offerResult.state.highest_received == offers.highest_received)
precondition(offerResult.state.sent.token == offers.sent.token && offerResult.state.received.token == offers.received.token)
precondition(offerResult.state.sent_at == offers.sent_at && offerResult.state.received_at == offers.received_at)
offerResult = beluga_core_handoff_offers_step(2, offers, offersEvent(9, 10))
precondition(offerResult.status == 3 && offerResult.effects == 3 && offerResult.state.terminal == 1)
precondition(offerResult.state.presence == 0 && offerResult.state.next_sent == UInt64.max)
precondition(offerResult.retired_sent == 100 && offerResult.retired_received == 100)
print("BelugaCore Swift offers import/link PASS: independent owners, sequence burn, consuming rejection and exact layouts")
