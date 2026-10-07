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


private typealias PhoneRequest = beluga_core_youtube_handoff_operation_request_t
private typealias PhoneEvidence = beluga_core_youtube_handoff_operation_evidence_t
private typealias PhoneState = beluga_core_youtube_handoff_operation_state_t
private typealias PhoneEvent = beluga_core_youtube_handoff_operation_event_t
private typealias PhoneOutput = beluga_core_youtube_handoff_operation_result_t
private func phoneLayout<T>(_ type: T.Type, _ size: Int, _ offsets: [(PartialKeyPath<T>, Int)]) {
    precondition(MemoryLayout<T>.size == size && MemoryLayout<T>.alignment == 8)
    for (field, offset) in offsets { precondition(MemoryLayout<T>.offset(of: field) == offset) }
}
phoneLayout(PhoneRequest.self, 40, [
    (\.position, 0), (\.duration, 8), (\.rate, 16), (\.deadline, 24), (\.position_observed_at, 32)
])
phoneLayout(PhoneEvidence.self, 32, [(\.token, 0), (\.position, 8), (\.rate, 16), (\.observed_at, 24)])
phoneLayout(PhoneState.self, 152, [
    (\.abi, 0), (\.phase, 4), (\.failure, 8), (\.mac_pause, 12), (\.flags, 16),
    (\.presence, 20), (\.sequence, 24), (\.reserved, 28), (\.request, 32),
    (\.last_now, 72), (\.first_position, 80), (\.first_at, 88), (\.latest_playing_at, 96),
    (\.latest_state, 104), (\.latest_state_reserved, 108), (\.evidence, 112), (\.reply_deadline, 144)
])
phoneLayout(PhoneEvent.self, 80, [
    (\.opcode, 0), (\.flags, 4), (\.presence, 8), (\.sequence, 12), (\.kind, 16),
    (\.sample_state, 20), (\.completion, 24), (\.failure, 28), (\.now, 32),
    (\.proof_token, 40), (\.candidate_token, 48), (\.sample_position, 56),
    (\.sample_duration, 64), (\.sample_rate, 72)
])
phoneLayout(PhoneOutput.self, 168, [(\.state, 0), (\.status, 152), (\.event, 156), (\.accepted, 160), (\.failure, 164)])
private func phoneBits(_ value: Double) -> UInt64 { value.bitPattern }
private func phoneRequest() -> PhoneRequest {
    var request = PhoneRequest()
    request.position = phoneBits(20); request.duration = phoneBits(200); request.rate = phoneBits(1)
    request.deadline = phoneBits(40); request.position_observed_at = phoneBits(10); return request
}
private func phoneStateWords(_ state: PhoneState) -> [UInt64] {
    [UInt64(state.abi), UInt64(state.phase), UInt64(state.failure), UInt64(state.mac_pause),
     UInt64(state.flags), UInt64(state.presence), UInt64(state.sequence), UInt64(state.reserved),
     state.request.position, state.request.duration, state.request.rate, state.request.deadline,
     state.request.position_observed_at, state.last_now, state.first_position, state.first_at,
     state.latest_playing_at, UInt64(UInt32(bitPattern: state.latest_state)), UInt64(state.latest_state_reserved),
     state.evidence.token, state.evidence.position, state.evidence.rate, state.evidence.observed_at, state.reply_deadline]
}
private func phoneEvent(_ opcode: UInt32, _ now: Double) -> PhoneEvent {
    var event = PhoneEvent(); event.opcode = opcode; event.now = phoneBits(now); return event
}
private func phoneMessage(_ sequence: UInt32, _ kind: UInt32, _ position: Double, _ now: Double) -> PhoneEvent {
    var event = phoneEvent(2, now)
    event.flags = 14; event.sequence = sequence; event.kind = kind; event.candidate_token = 91
    if kind == 2 {
        event.presence = 15; event.sample_state = 1; event.sample_position = phoneBits(position)
        event.sample_duration = phoneBits(200); event.sample_rate = phoneBits(1)
    }
    return event
}
@discardableResult private func phoneApply(_ state: inout PhoneState, _ event: PhoneEvent) -> PhoneOutput {
    let result = beluga_core_youtube_handoff_operation_step(1, state, event)
    precondition(result.status == 0); state = result.state; return result
}
private func phoneProof(_ opcode: UInt32, _ now: Double, _ token: UInt64) -> PhoneEvent {
    var event = phoneEvent(opcode, now); event.flags = 16; event.proof_token = token; return event
}
private func phoneCompletion(_ outcome: UInt32, _ now: Double) -> PhoneEvent {
    var event = phoneEvent(5, now); event.flags = 32; event.completion = outcome; return event
}
private func phoneConfirm(_ token: UInt64) -> PhoneState {
    var state = beluga_core_youtube_handoff_operation_initial(phoneRequest(), phoneBits(10))
    precondition(state.abi == 1 && state.phase == 0 && state.flags == 0 && state.presence == 0)
    var event = phoneEvent(0, 10); event.flags = 1; phoneApply(&state, event)
    phoneApply(&state, phoneMessage(1, 0, 20, 10)); phoneApply(&state, phoneMessage(2, 2, 20, 10.1))
    event = phoneMessage(3, 2, 20.3, 10.4); event.candidate_token = token
    let result = phoneApply(&state, event)
    precondition(result.event == 2 && result.accepted == 0 && result.failure == 0)
    precondition(state.phase == 4 && state.mac_pause == 0 && state.evidence.token == token)
    precondition(state.evidence.position == phoneBits(20.3) && state.evidence.observed_at == phoneBits(10.4))
    return state
}
private func phonePending() -> PhoneState {
    var state = phoneConfirm(91); let result = phoneApply(&state, phoneProof(4, 10.5, 91))
    precondition(result.accepted == 1 && result.event == 0 && state.mac_pause == 1 && state.phase == 5)
    precondition(state.reply_deadline == phoneBits(13.5)); return state
}
private func phoneUnchanged(_ result: PhoneOutput, _ before: PhoneState, _ status: UInt32) {
    precondition(result.status == status && result.event == 0 && result.accepted == 0 && result.failure == 0)
    precondition(phoneStateWords(result.state) == phoneStateWords(before))
}
private func phoneOperationSmoke() {
    let infinityBits: UInt64 = 0x7ff0000000000000
    let negativeInfinityBits: UInt64 = 0xfff0000000000000
    let nanBits: UInt64 = 0x7ff8000000001234
    var state = beluga_core_youtube_handoff_operation_initial(phoneRequest(), nanBits)
    precondition(state.phase == 0 && state.last_now == nanBits)
    var event = phoneMessage(1, 0, 0, 0); event.flags = 0; event.now = infinityBits
    phoneUnchanged(beluga_core_youtube_handoff_operation_step(1, state, event), state, 0)
    var result = phoneApply(&state, phoneEvent(1, 10))
    precondition(result.event == 4 && result.failure == 9 && state.last_now == nanBits)

    state = phoneConfirm(91); var before = state
    event = phoneMessage(99, 3, 0, 0); event.flags = 10; event.now = infinityBits
    phoneUnchanged(beluga_core_youtube_handoff_operation_step(1, state, event), before, 0)
    result = phoneApply(&state, phoneMessage(1, 0, 0, 40))
    precondition(result.event == 4 && result.failure == 2 && state.sequence == before.sequence)

    state = phoneConfirm(91); result = phoneApply(&state, phoneProof(4, 10.5, 92))
    precondition(result.accepted == 0 && state.mac_pause == 0)
    result = phoneApply(&state, phoneEvent(4, 10.5))
    precondition(result.accepted == 0 && state.evidence.token == 91)
    state = phonePending(); before = state
    event = phoneProof(4, 0, 91); event.now = nanBits
    phoneUnchanged(beluga_core_youtube_handoff_operation_step(1, state, event), before, 0)
    event = phoneCompletion(1, 0); event.flags = 0; event.now = infinityBits
    phoneUnchanged(beluga_core_youtube_handoff_operation_step(1, state, event), before, 0)
    phoneApply(&state, phoneMessage(4, 2, 21.3, 11.4)); result = phoneApply(&state, phoneProof(3, 11.4, 91))
    precondition(result.accepted == 0 && state.evidence.observed_at == phoneBits(10.4))
    result = phoneApply(&state, phoneCompletion(1, 11.5))
    precondition(result.event == 3 && state.phase == 6 && state.mac_pause == 2 && state.evidence.token == 0)
    event = phoneMessage(5, 2, 80, 60); event.sample_state = 2; event.sample_rate = phoneBits(2)
    result = phoneApply(&state, event); precondition(result.event == 0 && state.phase == 6 && state.mac_pause == 2)
    result = phoneApply(&state, phoneProof(3, 60, 91)); precondition(result.accepted == 0)

    state = phonePending(); result = phoneApply(&state, phoneCompletion(1, 11.5))
    precondition(result.event == 4 && result.failure == 12 && state.mac_pause == 2 && state.evidence.token == 91)
    precondition(state.phase == 7 && state.flags & 8 == 8)
    state = phonePending(); event = PhoneEvent(); event.opcode = 6; event.failure = 4
    result = phoneApply(&state, event)
    precondition(result.event == 4 && result.failure == 4 && state.mac_pause == 4 && state.evidence.token == 91)
    before = state
    phoneUnchanged(beluga_core_youtube_handoff_operation_step(1, state, phoneCompletion(1, 10.6)), before, 0)

    state = beluga_core_youtube_handoff_operation_initial(phoneRequest(), phoneBits(10))
    event = phoneEvent(0, 10); event.flags = 1; phoneApply(&state, event)
    event = phoneMessage(1, 0, 0, 10); event.candidate_token = 0; phoneApply(&state, event)
    event = phoneMessage(2, 2, 20, 10.1); event.candidate_token = 0; phoneApply(&state, event)
    precondition(state.phase == 3 && state.evidence.token == 0)
    event = phoneMessage(3, 2, 20.3, 10.4); event.candidate_token = 0; result = phoneApply(&state, event)
    precondition(result.event == 4 && result.failure == 8 && state.phase == 7)
    precondition(state.sequence == 3 && state.last_now == phoneBits(10.4) && state.evidence.token == 0)
    state = phoneConfirm(UInt64.max); event = phoneMessage(4, 2, 20.5, 10.6); event.candidate_token = 0
    phoneApply(&state, event); precondition(state.evidence.token == UInt64.max && state.phase == 4)

    before = state; event = phoneEvent(7, 10.6)
    phoneUnchanged(beluga_core_youtube_handoff_operation_step(1, state, event), before, 3)
    phoneUnchanged(beluga_core_youtube_handoff_operation_step(2, state, phoneEvent(1, 10.6)), before, 3)
    state.reserved = 1; before = state
    phoneUnchanged(beluga_core_youtube_handoff_operation_step(1, state, phoneEvent(1, 10.6)), before, 3)

    state = beluga_core_youtube_handoff_operation_initial(phoneRequest(), negativeInfinityBits)
    event = phoneEvent(0, -20); event.flags = 1; phoneApply(&state, event)
    phoneApply(&state, phoneMessage(1, 0, 0, -20)); phoneApply(&state, phoneMessage(2, 2, 20, -19.9))
    result = phoneApply(&state, phoneMessage(3, 2, 20.3, -19.6)); precondition(result.event == 2)
    result = phoneApply(&state, phoneProof(4, -19.5, 91)); precondition(result.accepted == 1)
    precondition(state.evidence.observed_at == phoneBits(-19.6) && state.reply_deadline == phoneBits(-16.5))
    result = phoneApply(&state, phoneCompletion(1, -19.4)); precondition(result.event == 3)
    state = beluga_core_youtube_handoff_operation_initial(phoneRequest(), phoneBits(-0.0))
    precondition(state.last_now == 0x8000000000000000)
    phoneApply(&state, phoneEvent(1, 0)); precondition(state.last_now == 0)
    phoneApply(&state, phoneEvent(1, -0.0)); precondition(state.last_now == 0x8000000000000000)
    print("BelugaCore Swift phone operation import/link PASS: exact layouts, original ordering, immutable proof and honest pause outcomes")
}
phoneOperationSmoke()

private typealias InvitationState = beluga_core_invitation_acceptance_state_t
private typealias InvitationEvent = beluga_core_invitation_acceptance_event_t
private typealias InvitationOutput = beluga_core_invitation_acceptance_result_t

private func invitationAcceptanceSmoke() {
    precondition(MemoryLayout<InvitationState>.size == 8 && MemoryLayout<InvitationState>.alignment == 4)
    precondition(MemoryLayout<InvitationState>.offset(of: \.abi_version) == 0)
    precondition(MemoryLayout<InvitationState>.offset(of: \.flags) == 4)
    precondition(MemoryLayout<InvitationEvent>.size == 32 && MemoryLayout<InvitationEvent>.alignment == 4)
    precondition(MemoryLayout<InvitationEvent>.offset(of: \.opcode) == 0)
    precondition(MemoryLayout<InvitationEvent>.offset(of: \.generation_matches) == 4)
    precondition(MemoryLayout<InvitationEvent>.offset(of: \.phase) == 8)
    precondition(MemoryLayout<InvitationEvent>.offset(of: \.admission_callback_present) == 12)
    precondition(MemoryLayout<InvitationEvent>.offset(of: \.prepared_kind) == 16)
    precondition(MemoryLayout<InvitationEvent>.offset(of: \.prepared_flags) == 20)
    precondition(MemoryLayout<InvitationEvent>.offset(of: \.owner_matches) == 24)
    precondition(MemoryLayout<InvitationEvent>.offset(of: \.callback_outcome) == 28)
    precondition(MemoryLayout<InvitationOutput>.size == 32 && MemoryLayout<InvitationOutput>.alignment == 4)
    precondition(MemoryLayout<InvitationOutput>.offset(of: \.state) == 0)
    precondition(MemoryLayout<InvitationOutput>.offset(of: \.callback_success_state) == 8)
    precondition(MemoryLayout<InvitationOutput>.offset(of: \.status) == 16)
    precondition(MemoryLayout<InvitationOutput>.offset(of: \.completion_succeeded) == 20)
    precondition(MemoryLayout<InvitationOutput>.offset(of: \.callback_kind) == 24)
    precondition(MemoryLayout<InvitationOutput>.offset(of: \.prepared_flags) == 28)

    var state = beluga_core_invitation_acceptance_initial()
    precondition(state.abi_version == 1 && state.flags == 0)
    var event = InvitationEvent()
    event.opcode = 0; event.admission_callback_present = 1
    var result = beluga_core_invitation_acceptance_step(1, state, event)
    precondition(result.status == 0 && result.state.flags == 7 && result.callback_kind == 0)
    state = result.state

    event = InvitationEvent()
    event.opcode = 1; event.phase = UInt32.max
    result = beluga_core_invitation_acceptance_step(1, state, event)
    precondition(result.status == 1 && result.state.flags == 7 && result.callback_kind == 0)
    event.generation_matches = 1; event.phase = 1
    result = beluga_core_invitation_acceptance_step(1, state, event)
    precondition(result.status == 2 && result.state.flags == 7)
    precondition(result.callback_success_state.flags == 15 && result.callback_kind == 1)
    precondition(result.prepared_flags == 7 && result.completion_succeeded == 0)
    let admission = result

    event = InvitationEvent()
    event.opcode = 3; event.prepared_kind = admission.callback_kind
    event.prepared_flags = admission.prepared_flags; event.owner_matches = 1; event.callback_outcome = 2
    result = beluga_core_invitation_acceptance_step(1, state, event)
    precondition(result.status == 5 && result.state.flags == 7 && result.completion_succeeded == 0)
    event.callback_outcome = 1
    result = beluga_core_invitation_acceptance_step(1, state, event)
    precondition(result.status == 0 && result.state.flags == 15)
    state = result.state

    event = InvitationEvent()
    event.opcode = 1; event.generation_matches = 1; event.phase = UInt32.max
    result = beluga_core_invitation_acceptance_step(1, state, event)
    precondition(result.status == 1 && result.state.flags == 15)
    event = InvitationEvent()
    event.opcode = 2; event.generation_matches = 1; event.phase = 2
    result = beluga_core_invitation_acceptance_step(1, state, event)
    precondition(result.status == 2 && result.state.flags == 15 && result.callback_success_state.flags == 0)
    precondition(result.callback_kind == 2 && result.completion_succeeded == 0)
    let completion = result

    event = InvitationEvent()
    event.opcode = 3; event.prepared_kind = completion.callback_kind
    event.prepared_flags = completion.prepared_flags; event.callback_outcome = 1
    result = beluga_core_invitation_acceptance_step(1, state, event)
    precondition(result.status == 6 && result.state.flags == 15)
    event.owner_matches = 1
    result = beluga_core_invitation_acceptance_step(1, state, event)
    precondition(result.status == 0 && result.state.flags == 0 && result.completion_succeeded == 1)
    state = result.state

    event = InvitationEvent(); event.opcode = 0
    state = beluga_core_invitation_acceptance_step(1, state, event).state
    precondition(state.flags == 5)
    event = InvitationEvent(); event.opcode = 1; event.generation_matches = 1; event.phase = 1
    result = beluga_core_invitation_acceptance_step(1, state, event)
    precondition(result.status == 0 && result.state.flags == 13 && result.callback_kind == 0)
    state = result.state
    event = InvitationEvent(); event.opcode = 4; event.generation_matches = 1
    result = beluga_core_invitation_acceptance_step(2, state, event)
    precondition(result.status == 7 && result.state.flags == 13 && result.callback_kind == 0)
    event.opcode = UInt32.max
    result = beluga_core_invitation_acceptance_step(1, state, event)
    precondition(result.status == 7 && result.state.flags == 13 && result.callback_kind == 0)
    print("BelugaCore Swift invitation acceptance import/link PASS: exact layouts, original guard order and one-use callback outcomes")
}
invitationAcceptanceSmoke()
// Additive seventh smoke; prior six contracts and their markers remain unchanged.
private func signalingReplaySmoke() {
    typealias ReplayState = beluga_core_signaling_replay_state_t
    typealias ReplayResult = beluga_core_signaling_replay_result_t
    precondition(MemoryLayout<ReplayState>.size == 24 && MemoryLayout<ReplayState>.alignment == 8)
    precondition(MemoryLayout<ReplayState>.offset(of: \.abi_version) == 0)
    precondition(MemoryLayout<ReplayState>.offset(of: \.has_highest) == 4)
    precondition(MemoryLayout<ReplayState>.offset(of: \.highest) == 8)
    precondition(MemoryLayout<ReplayState>.offset(of: \.bitmap) == 16)
    precondition(MemoryLayout<ReplayResult>.size == 32 && MemoryLayout<ReplayResult>.alignment == 8)
    precondition(MemoryLayout<ReplayResult>.offset(of: \.state) == 0)
    precondition(MemoryLayout<ReplayResult>.offset(of: \.decision) == 24)
    precondition(MemoryLayout<ReplayResult>.offset(of: \.reserved) == 28)
    func same(_ left: ReplayState, _ right: ReplayState) {
        precondition(left.abi_version == right.abi_version && left.has_highest == right.has_highest &&
                     left.highest == right.highest && left.bitmap == right.bitmap)
    }
    let empty = beluga_core_signaling_replay_initial()
    precondition(empty.abi_version == 1 && empty.has_highest == 0 && empty.highest == 0 && empty.bitmap == 0)
    var result = beluga_core_signaling_replay_step(1, empty, 0)
    precondition(result.decision == 0 && result.reserved == 0 && result.state.abi_version == 1 &&
                 result.state.has_highest == 1 && result.state.highest == 0 && result.state.bitmap == 1)
    let zero = result.state
    result = beluga_core_signaling_replay_step(1, zero, 0)
    precondition(result.decision == 1 && result.reserved == 0); same(result.state, zero)
    result = beluga_core_signaling_replay_step(1, zero, 63)
    precondition(result.decision == 0 && result.state.highest == 63 &&
                 result.state.bitmap == (UInt64(1) << 63) | 1)
    result = beluga_core_signaling_replay_step(1, zero, 64)
    precondition(result.decision == 0 && result.state.highest == 64 && result.state.bitmap == 1)
    let sixtyFour = result.state
    result = beluga_core_signaling_replay_step(1, sixtyFour, 1)
    precondition(result.decision == 0 && result.state.highest == 64 &&
                 result.state.bitmap == (UInt64(1) << 63) | 1)
    let reordered = result.state
    result = beluga_core_signaling_replay_step(1, reordered, 0)
    precondition(result.decision == 2 && result.reserved == 0); same(result.state, reordered)
    result = beluga_core_signaling_replay_step(1, reordered, 2)
    precondition(result.decision == 0 && result.state.bitmap == (UInt64(1) << 63) | (UInt64(1) << 62) | 1)
    precondition(sixtyFour.bitmap == 1 && reordered.bitmap == (UInt64(1) << 63) | 1)
    result = beluga_core_signaling_replay_step(1, empty, UInt64.max)
    precondition(result.decision == 0 && result.state.highest == UInt64.max && result.state.bitmap == 1)
    let maximum = result.state
    result = beluga_core_signaling_replay_step(1, maximum, UInt64.max - 63)
    precondition(result.decision == 0 && result.state.bitmap == (UInt64(1) << 63) | 1)
    result = beluga_core_signaling_replay_step(1, maximum, UInt64.max - 64)
    precondition(result.decision == 2 && result.reserved == 0); same(result.state, maximum)
    result = beluga_core_signaling_replay_step(1, maximum, UInt64.max)
    precondition(result.decision == 1 && result.reserved == 0); same(result.state, maximum)
    result = beluga_core_signaling_replay_step(2, maximum, UInt64.max)
    precondition(result.decision == 3 && result.reserved == 0); same(result.state, maximum)
    let malformed: [(UInt32, UInt32, UInt64, UInt64)] = [
        (0, 0, 0, 0), (1, 2, 0, 0), (1, 0, 1, 0), (1, 0, 0, 1),
        (1, 1, 10, 0), (1, 1, 10, 2), (1, 1, 0, 3)
    ]
    for (abi, present, highest, bitmap) in malformed {
        var before = ReplayState()
        before.abi_version = abi; before.has_highest = present
        before.highest = highest; before.bitmap = bitmap
        result = beluga_core_signaling_replay_step(1, before, 7)
        precondition(result.decision == 3 && result.reserved == 0); same(result.state, before)
    }
    print("BelugaCore Swift signaling replay import/link PASS: exact layouts, zero/MAX, 63/64 window and unchanged rejection")
}
signalingReplaySmoke()
