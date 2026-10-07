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

private func pairingCatalogCheckpointSmoke() {
    typealias State = beluga_core_pairing_catalog_checkpoint_state_t
    typealias Event = beluga_core_pairing_catalog_checkpoint_event_t
    typealias Output = beluga_core_pairing_catalog_checkpoint_result_t
    precondition(MemoryLayout<State>.size == 8 && MemoryLayout<State>.alignment == 4)
    precondition(MemoryLayout<State>.offset(of: \.abi_version) == 0)
    precondition(MemoryLayout<State>.offset(of: \.flags) == 4)
    precondition(MemoryLayout<Event>.size == 16 && MemoryLayout<Event>.alignment == 4)
    precondition(MemoryLayout<Event>.offset(of: \.opcode) == 0)
    precondition(MemoryLayout<Event>.offset(of: \.owner_valid) == 4)
    precondition(MemoryLayout<Event>.offset(of: \.binding_matches) == 8)
    precondition(MemoryLayout<Event>.offset(of: \.snapshot_matches) == 12)
    precondition(MemoryLayout<Output>.size == 12 && MemoryLayout<Output>.alignment == 4)
    precondition(MemoryLayout<Output>.offset(of: \.candidate_state) == 0)
    precondition(MemoryLayout<Output>.offset(of: \.decision) == 8)
    var state = beluga_core_pairing_catalog_checkpoint_initial()
    precondition(state.abi_version == 1 && state.flags == 0)
    var event = Event(); event.owner_valid = 1
    var output = beluga_core_pairing_catalog_checkpoint_step(1, state, event)
    precondition(output.decision == 0 && output.candidate_state.flags == 1 && state.flags == 0)
    state = output.candidate_state
    output = beluga_core_pairing_catalog_checkpoint_step(1, state, event)
    precondition(output.decision == 1 && output.candidate_state.flags == 1)
    event.opcode = 1; event.binding_matches = 1
    output = beluga_core_pairing_catalog_checkpoint_step(1, state, event)
    precondition(output.decision == 0 && output.candidate_state.flags == 1)
    event.binding_matches = 0
    output = beluga_core_pairing_catalog_checkpoint_step(1, state, event)
    precondition(output.decision == 1 && output.candidate_state.flags == 1)
    event = Event(); event.opcode = 2
    output = beluga_core_pairing_catalog_checkpoint_step(1, state, event)
    precondition(output.decision == 0 && output.candidate_state.flags == 3)
    state = output.candidate_state
    event = Event(); event.owner_valid = 1
    output = beluga_core_pairing_catalog_checkpoint_step(1, state, event)
    precondition(output.decision == 1 && output.candidate_state.flags == 3)
    event = Event(); event.opcode = 3; event.snapshot_matches = 1
    output = beluga_core_pairing_catalog_checkpoint_step(1, state, event)
    precondition(output.decision == 0 && output.candidate_state.flags == 3)
    event.snapshot_matches = 0
    output = beluga_core_pairing_catalog_checkpoint_step(1, state, event)
    precondition(output.decision == 1 && output.candidate_state.flags == 3)
    for invalid: UInt32 in [2, UInt32.max] {
        event.opcode = 2
        output = beluga_core_pairing_catalog_checkpoint_step(invalid, state, event)
        precondition(output.decision == 3 && output.candidate_state.abi_version == 1 && output.candidate_state.flags == 3)
        event.opcode = UInt32.max
        output = beluga_core_pairing_catalog_checkpoint_step(1, state, event)
        precondition(output.decision == 3 && output.candidate_state.flags == 3)
    }
    print("BelugaCore Swift catalog checkpoint import/link PASS: exact layouts, candidate custody, terminal revoke and full readback")
}
pairingCatalogCheckpointSmoke()

private func reconnectCountersSmoke() {
    typealias State = beluga_core_reconnect_counters_state_t
    typealias Event = beluga_core_reconnect_counters_event_t
    typealias Output = beluga_core_reconnect_counters_result_t
    precondition(MemoryLayout<State>.size == 24 && MemoryLayout<State>.alignment == 8)
    precondition(MemoryLayout<State>.offset(of: \.abi_version) == 0)
    precondition(MemoryLayout<State>.offset(of: \.reserved) == 4)
    precondition(MemoryLayout<State>.offset(of: \.next_outbound) == 8)
    precondition(MemoryLayout<State>.offset(of: \.highest_accepted) == 16)
    precondition(MemoryLayout<Event>.size == 16 && MemoryLayout<Event>.alignment == 8)
    precondition(MemoryLayout<Event>.offset(of: \.opcode) == 0)
    precondition(MemoryLayout<Event>.offset(of: \.reserved) == 4)
    precondition(MemoryLayout<Event>.offset(of: \.request_sequence) == 8)
    precondition(MemoryLayout<Output>.size == 32 && MemoryLayout<Output>.alignment == 8)
    precondition(MemoryLayout<Output>.offset(of: \.candidate_state) == 0)
    precondition(MemoryLayout<Output>.offset(of: \.decision) == 24)
    precondition(MemoryLayout<Output>.offset(of: \.reserved) == 28)
    func same(_ a: State, _ b: State) {
        precondition(a.abi_version == b.abi_version && a.reserved == b.reserved &&
                     a.next_outbound == b.next_outbound && a.highest_accepted == b.highest_accepted)
    }
    let values: [UInt64] = [0, 1, 2, (UInt64(1) << 53) + 1, UInt64.max - 1, UInt64.max]
    for next in values {
        for highest in values {
            var before = State(); before.abi_version = 1
            before.next_outbound = next; before.highest_accepted = highest
            var event = Event()
            var output = beluga_core_reconnect_counters_step(1, before, event)
            precondition(output.decision == (next < UInt64.max ? 0 : 1) && output.reserved == 0)
            precondition(output.candidate_state.abi_version == 1 && output.candidate_state.reserved == 0)
            precondition(output.candidate_state.next_outbound == (next < UInt64.max ? next + 1 : next))
            precondition(output.candidate_state.highest_accepted == highest)
            for sequence in values {
                event = Event(); event.opcode = 1; event.request_sequence = sequence
                output = beluga_core_reconnect_counters_step(1, before, event)
                precondition(output.decision == (sequence > highest ? 0 : 2) && output.reserved == 0)
                precondition(output.candidate_state.next_outbound == next)
                precondition(output.candidate_state.highest_accepted == (sequence > highest ? sequence : highest))
            }
        }
    }
    var before = State(); before.abi_version = 1
    before.next_outbound = 23; before.highest_accepted = 47
    let reserve = Event()
    let output = beluga_core_reconnect_counters_step(1, before, reserve)
    precondition(output.decision == 0 && output.candidate_state.next_outbound == 24)
    precondition(before.next_outbound == 23 && before.highest_accepted == 47)
    for invalid: UInt32 in [0, 2, UInt32.max] {
        var result = beluga_core_reconnect_counters_step(invalid, before, reserve)
        precondition(result.decision == 3 && result.reserved == 0); same(result.candidate_state, before)
        var malformed = before; malformed.abi_version = invalid
        result = beluga_core_reconnect_counters_step(1, malformed, reserve)
        precondition(result.decision == 3 && result.reserved == 0); same(result.candidate_state, malformed)
    }
    for invalid: UInt32 in [1, 2, UInt32.max] {
        var malformed = before; malformed.reserved = invalid
        var result = beluga_core_reconnect_counters_step(1, malformed, reserve)
        precondition(result.decision == 3 && result.reserved == 0); same(result.candidate_state, malformed)
        var event = reserve; event.reserved = invalid
        result = beluga_core_reconnect_counters_step(1, before, event)
        precondition(result.decision == 3 && result.reserved == 0); same(result.candidate_state, before)
    }
    for opcode: UInt32 in [2, UInt32.max] {
        var event = reserve; event.opcode = opcode
        let result = beluga_core_reconnect_counters_step(1, before, event)
        precondition(result.decision == 3 && result.reserved == 0); same(result.candidate_state, before)
    }
    for sequence: UInt64 in [1, (UInt64(1) << 53) + 1, UInt64.max] {
        var event = reserve; event.request_sequence = sequence
        let result = beluga_core_reconnect_counters_step(1, before, event)
        precondition(result.decision == 3 && result.reserved == 0); same(result.candidate_state, before)
    }
    print("BelugaCore Swift reconnect counters import/link PASS: exact layouts, zero/MAX, strict admission and unchanged refusal")
}
reconnectCountersSmoke()

// Actual linked copied-value contract; not native authentication or storage proof.
private func pairingCommitSmoke() {
    typealias State = beluga_core_pairing_commit_state_t
    typealias Event = beluga_core_pairing_commit_event_t
    typealias Output = beluga_core_pairing_commit_result_t
    precondition(MemoryLayout<State>.size == 24 && MemoryLayout<State>.alignment == 4)
    precondition(MemoryLayout<State>.offset(of: \.abi_version) == 0)
    precondition(MemoryLayout<State>.offset(of: \.reserved) == 4)
    precondition(MemoryLayout<State>.offset(of: \.local_role) == 8)
    precondition(MemoryLayout<State>.offset(of: \.pairing_state) == 12)
    precondition(MemoryLayout<State>.offset(of: \.recovery_phase) == 16)
    precondition(MemoryLayout<State>.offset(of: \.reserved_tail) == 20)
    precondition(MemoryLayout<Event>.size == 16 && MemoryLayout<Event>.alignment == 4)
    precondition(MemoryLayout<Event>.offset(of: \.opcode) == 0)
    precondition(MemoryLayout<Event>.offset(of: \.reserved) == 4)
    precondition(MemoryLayout<Event>.offset(of: \.commit_id_matches) == 8)
    precondition(MemoryLayout<Event>.offset(of: \.reserved_tail) == 12)
    precondition(MemoryLayout<Output>.size == 40 && MemoryLayout<Output>.alignment == 4)
    precondition(MemoryLayout<Output>.offset(of: \.candidate_state) == 0)
    precondition(MemoryLayout<Output>.offset(of: \.decision) == 24)
    precondition(MemoryLayout<Output>.offset(of: \.action) == 28)
    precondition(MemoryLayout<Output>.offset(of: \.auth_phase) == 32)
    precondition(MemoryLayout<Output>.offset(of: \.reserved) == 36)
    func state(_ role: UInt32, _ phase: UInt32, _ cache: UInt32) -> State {
        var value = State(); value.abi_version = 1; value.local_role = role
        value.pairing_state = phase; value.recovery_phase = cache; return value
    }
    func event(_ opcode: UInt32, _ exact: UInt32 = 0) -> Event {
        var value = Event(); value.opcode = opcode; value.commit_id_matches = exact; return value
    }
    func same(_ a: State, _ b: State) {
        precondition(a.abi_version == b.abi_version && a.reserved == b.reserved &&
            a.local_role == b.local_role && a.pairing_state == b.pairing_state &&
            a.recovery_phase == b.recovery_phase && a.reserved_tail == b.reserved_tail)
    }
    // role, phase, cache, opcode, UUID match, next phase, next cache, decision, action, auth.
    let literals: [[UInt32]] = [
        [0,0,0,0,0,0,0,0,2,0], [1,0,0,0,0,0,0,0,1,0], [0,1,0,0,0,1,0,0,1,0],
        [1,2,0,0,0,2,0,0,4,0], [1,3,0,0,0,3,0,0,0,0], [0,1,4,0,0,1,4,0,3,0],
        [0,0,0,1,0,0,1,0,5,0], [0,0,1,1,0,0,1,0,3,0], [0,0,4,1,0,0,4,1,0,0],
        [1,0,4,2,0,1,2,0,6,1], [1,1,4,2,0,1,4,0,3,1], [1,2,4,2,0,2,4,1,0,0],
        [0,0,3,3,0,2,0,0,0,2], [0,2,3,3,0,2,3,0,0,2], [0,3,4,3,0,3,4,0,0,2],
        [0,2,0,4,0,2,3,0,7,0], [0,2,3,4,0,2,3,0,3,0], [0,3,0,4,0,3,0,0,7,0],
        [0,3,3,4,0,3,3,1,0,0], [0,2,3,5,1,2,3,0,0,0], [0,2,3,5,0,2,3,1,0,0],
        [0,3,0,5,1,3,0,0,0,0], [1,3,4,6,0,3,4,0,3,3], [1,3,0,6,0,3,0,2,0,3],
        [1,3,3,6,0,3,3,2,0,3], [1,1,2,6,0,3,4,0,8,3], [1,0,0,6,0,0,0,1,0,0],
        [0,2,3,7,0,3,0,0,0,4], [0,3,4,7,0,3,0,0,0,4], [1,1,2,8,0,1,2,0,9,0],
        [0,3,3,8,0,3,3,3,0,0], [1,0,0,8,0,0,0,0,0,0]
    ]
    for literal in literals {
        let before = state(literal[0], literal[1], literal[2])
        let output = beluga_core_pairing_commit_step(1, before, event(literal[3], literal[4]))
        same(output.candidate_state, state(literal[0], literal[5], literal[6]))
        precondition(output.decision == literal[7] && output.action == literal[8] &&
            output.auth_phase == literal[9] && output.reserved == 0)
        same(before, state(literal[0], literal[1], literal[2]))
    }
    func invalid(_ abi: UInt32, _ before: State, _ input: Event) {
        let output = beluga_core_pairing_commit_step(abi, before, input)
        precondition(output.decision == 4 && output.action == 0 && output.auth_phase == 0 && output.reserved == 0)
        same(output.candidate_state, before)
    }
    let before = state(1, 3, 4)
    let input = event(6)
    for bad: UInt32 in [0, 2, UInt32.max] {
        invalid(bad, before, input)
        var raw = before; raw.abi_version = bad; invalid(1, raw, input)
    }
    for bit in 0..<32 {
        let bad = UInt32(1) << bit
        var raw = before; raw.reserved = bad; invalid(1, raw, input)
        raw = before; raw.reserved_tail = bad; invalid(1, raw, input)
        var malformed = input; malformed.reserved = bad; invalid(1, before, malformed)
        malformed = input; malformed.reserved_tail = bad; invalid(1, before, malformed)
    }
    var raw = before; raw.local_role = 2; invalid(1, raw, input)
    raw = before; raw.pairing_state = 4; invalid(1, raw, input)
    raw = before; raw.recovery_phase = 5; invalid(1, raw, input)
    invalid(1, before, event(9)); invalid(1, before, event(5, 2)); invalid(1, before, event(6, 1))
    print("BelugaCore Swift pairing commit import/link PASS: exact layouts, phase plans, auth ordering and unchanged refusal")
}
pairingCommitSmoke()

func supportedPlayerArbitrationSmoke() {
    typealias Input = beluga_core_supported_player_arbitration_input_t
    typealias Output = beluga_core_supported_player_arbitration_output_t
    precondition(MemoryLayout<Input>.size == 20 && MemoryLayout<Input>.stride == 20)
    precondition(MemoryLayout<Input>.alignment == 4)
    precondition(MemoryLayout<Input>.offset(of: \.abi_version) == 0)
    precondition(MemoryLayout<Input>.offset(of: \.selected_source) == 4)
    precondition(MemoryLayout<Input>.offset(of: \.browser_observation) == 8)
    precondition(MemoryLayout<Input>.offset(of: \.music_observation) == 12)
    precondition(MemoryLayout<Input>.offset(of: \.reserved) == 16)
    precondition(MemoryLayout<Output>.size == 16 && MemoryLayout<Output>.stride == 16)
    precondition(MemoryLayout<Output>.alignment == 4)
    precondition(MemoryLayout<Output>.offset(of: \.abi_version) == 0)
    precondition(MemoryLayout<Output>.offset(of: \.action) == 4)
    precondition(MemoryLayout<Output>.offset(of: \.primary_or_hold) == 8)
    precondition(MemoryLayout<Output>.offset(of: \.reserved) == 12)
    // Frozen native-reference rows; expected choices never call a Swift chooser.
    let literals: [[UInt32]] = [
        [0,0,0,2,0], [0,0,1,2,2], [0,0,2,2,2], [0,0,3,1,0],
        [0,1,0,2,1], [0,1,1,2,1], [0,1,2,2,2], [0,1,3,1,0],
        [0,2,0,2,1], [0,2,1,2,1], [0,2,2,2,1], [0,2,3,1,0],
        [0,3,0,1,0], [0,3,1,1,0], [0,3,2,1,0], [0,3,3,1,0],
        [1,0,0,2,0], [1,0,1,2,2], [1,0,2,2,2], [1,0,3,1,1],
        [1,1,0,2,1], [1,1,1,2,1], [1,1,2,2,2], [1,1,3,1,1],
        [1,2,0,2,1], [1,2,1,2,1], [1,2,2,2,1], [1,2,3,1,1],
        [1,3,0,1,1], [1,3,1,1,1], [1,3,2,1,1], [1,3,3,1,1],
        [2,0,0,2,0], [2,0,1,2,2], [2,0,2,2,2], [2,0,3,1,2],
        [2,1,0,2,1], [2,1,1,2,2], [2,1,2,2,2], [2,1,3,1,2],
        [2,2,0,2,1], [2,2,1,2,1], [2,2,2,2,2], [2,2,3,1,2],
        [2,3,0,1,2], [2,3,1,1,2], [2,3,2,1,2], [2,3,3,1,2]
    ]
    let invalids: [[UInt32]] = [[0,2,UInt32.max], [3,4,UInt32.max],
        [4,5,UInt32.max], [4,5,UInt32.max], [1,2,UInt32.max]]
    precondition(literals.count == 48)
    var invalidAttempts = 0
    for literal in literals {
        precondition(literal.count == 5)
        var input = Input()
        input.abi_version = 1; input.selected_source = literal[0]
        input.browser_observation = literal[1]; input.music_observation = literal[2]
        let output = beluga_core_supported_player_arbitrate(input)
        precondition(output.abi_version == 1 && output.action == literal[3])
        precondition(output.primary_or_hold == literal[4] && output.reserved == 0)
        for field in 0..<5 {
            for bad in invalids[field] {
                var raw = input
                switch field {
                case 0: raw.abi_version = bad
                case 1: raw.selected_source = bad
                case 2: raw.browser_observation = bad
                case 3: raw.music_observation = bad
                case 4: raw.reserved = bad
                default: preconditionFailure("unknown smoke field")
                }
                let refused = beluga_core_supported_player_arbitrate(raw)
                precondition(refused.abi_version == 1 && refused.action == 0)
                precondition(refused.primary_or_hold == 0 && refused.reserved == 0)
                invalidAttempts += 1
            }
        }
        precondition(input.abi_version == 1 && input.selected_source == literal[0])
        precondition(input.browser_observation == literal[1] && input.music_observation == literal[2])
        precondition(input.reserved == 0)
    }
    precondition(invalidAttempts == 720)
    print("BelugaCore Swift supported player arbitration import/link PASS: exact layouts, 48 literal choices and 720 closed-field refusals")
}
supportedPlayerArbitrationSmoke()

func availabilityRetrySmoke() {
    typealias State = beluga_core_availability_retry_state_t
    typealias Event = beluga_core_availability_retry_event_t
    typealias Output = beluga_core_availability_retry_result_t
    precondition(MemoryLayout<State>.size == 16 && MemoryLayout<State>.stride == 16)
    precondition(MemoryLayout<State>.alignment == 4)
    precondition(MemoryLayout<State>.offset(of: \.abi_version) == 0)
    precondition(MemoryLayout<State>.offset(of: \.next_delay_seconds) == 4)
    precondition(MemoryLayout<State>.offset(of: \.has_validated_connection) == 8)
    precondition(MemoryLayout<State>.offset(of: \.reserved) == 12)
    precondition(MemoryLayout<Event>.size == 8 && MemoryLayout<Event>.stride == 8)
    precondition(MemoryLayout<Event>.alignment == 4)
    precondition(MemoryLayout<Event>.offset(of: \.opcode) == 0)
    precondition(MemoryLayout<Event>.offset(of: \.reserved) == 4)
    precondition(MemoryLayout<Output>.size == 32 && MemoryLayout<Output>.stride == 32)
    precondition(MemoryLayout<Output>.alignment == 4)
    precondition(MemoryLayout<Output>.offset(of: \.candidate_state) == 0)
    precondition(MemoryLayout<Output>.offset(of: \.decision) == 16)
    precondition(MemoryLayout<Output>.offset(of: \.became_validated) == 20)
    precondition(MemoryLayout<Output>.offset(of: \.retry_delay_seconds) == 24)
    precondition(MemoryLayout<Output>.offset(of: \.reserved) == 28)

    func assertState(_ actual: State, _ expected: State) {
        precondition(actual.abi_version == expected.abi_version)
        precondition(actual.next_delay_seconds == expected.next_delay_seconds)
        precondition(actual.has_validated_connection == expected.has_validated_connection)
        precondition(actual.reserved == expected.reserved)
    }
    func assertRefused(_ abi: UInt32, _ before: State, _ event: Event) -> Int {
        let copiedState = before
        let copiedEvent = event
        let output = beluga_core_availability_retry_step(abi, before, event)
        assertState(output.candidate_state, before)
        precondition(output.decision == 2 && output.became_validated == 0)
        precondition(output.retry_delay_seconds == 0 && output.reserved == 0)
        assertState(before, copiedState)
        precondition(event.opcode == copiedEvent.opcode && event.reserved == copiedEvent.reserved)
        return 1
    }
    // Frozen original rows; expected transitions never call a Swift policy.
    let literals: [[UInt32]] = [
        [1,0,0,1,1,0,1,0], [1,0,1,2,0,1,0,1],
        [2,0,0,1,1,0,1,0], [2,0,1,4,0,1,0,2],
        [4,0,0,1,1,0,1,0], [4,0,1,8,0,1,0,4],
        [8,0,0,1,1,0,1,0], [8,0,1,16,0,1,0,8],
        [16,0,0,1,1,0,1,0], [16,0,1,30,0,1,0,16],
        [30,0,0,1,1,0,1,0], [30,0,1,30,0,1,0,30],
        [1,1,0,1,1,0,0,0], [1,1,1,2,0,1,0,1]
    ]
    let invalids: [[UInt32]] = [
        [0,2,UInt32.max], [0,2,UInt32.max], [0,3,32,UInt32.max],
        [2,UInt32.max], [1,UInt32.max], [2,UInt32.max], [1,UInt32.max]
    ]
    precondition(literals.count == 14)
    var refusedAttempts = 0
    for literal in literals {
        precondition(literal.count == 8)
        let before = State(abi_version: 1, next_delay_seconds: literal[0],
            has_validated_connection: literal[1], reserved: 0)
        let event = Event(opcode: literal[2], reserved: 0)
        let output = beluga_core_availability_retry_step(1, before, event)
        assertState(output.candidate_state, State(abi_version: 1,
            next_delay_seconds: literal[3], has_validated_connection: literal[4], reserved: 0))
        precondition(output.decision == literal[5] && output.became_validated == literal[6])
        precondition(output.retry_delay_seconds == literal[7] && output.reserved == 0)
        for field in 0..<7 {
            for bad in invalids[field] {
                var callABI: UInt32 = 1
                var rawState = before
                var rawEvent = event
                switch field {
                case 0: callABI = bad
                case 1: rawState.abi_version = bad
                case 2: rawState.next_delay_seconds = bad
                case 3: rawState.has_validated_connection = bad
                case 4: rawState.reserved = bad
                case 5: rawEvent.opcode = bad
                case 6: rawEvent.reserved = bad
                default: preconditionFailure("unknown availability smoke field")
                }
                refusedAttempts += assertRefused(callABI, rawState, rawEvent)
            }
        }
        var rawState = before
        rawState.next_delay_seconds = 2
        rawState.has_validated_connection = 1
        refusedAttempts += assertRefused(1, rawState, event)
        rawState = before
        rawState.abi_version = 9
        rawState.reserved = 17
        refusedAttempts += assertRefused(0, rawState, Event(opcode: 7, reserved: UInt32.max))
        assertState(before, State(abi_version: 1, next_delay_seconds: literal[0],
            has_validated_connection: literal[1], reserved: 0))
        precondition(event.opcode == literal[2] && event.reserved == 0)
    }
    precondition(refusedAttempts == 280)
    print("BelugaCore Swift availability retry import/link PASS: exact layouts, 14 literal transitions and 280 unchanged refusals")
}
availabilityRetrySmoke()

// PRIVATE additive actual-C smoke. Uncompiled and unexecuted.
func batchAPolicySmoke() {
    typealias Config = beluga_core_safe_output_retry_config_t
    typealias State = beluga_core_safe_output_retry_state_t
    typealias Retry = beluga_core_safe_output_retry_result_t
    typealias Start = beluga_core_system_audio_start_facts_t
    typealias StartDecision = beluga_core_system_audio_start_decision_t
    typealias Observation = beluga_core_hosted_call_observation_facts_t
    typealias Evidence = beluga_core_hosted_call_evidence_facts_t
    typealias Peer = beluga_core_hosted_call_peer_facts_t
    typealias HostedDecision = beluga_core_hosted_call_decision_t
    typealias UUIDBytes = (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                          UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8)
    precondition(MemoryLayout<Config>.size == 32 && MemoryLayout<Config>.stride == 32)
    precondition(MemoryLayout<Config>.alignment == 8)
    precondition(MemoryLayout<Config>.offset(of: \.abi_version) == 0)
    precondition(MemoryLayout<Config>.offset(of: \.reserved) == 4)
    precondition(MemoryLayout<Config>.offset(of: \.maximum_failed_attempt_count) == 8)
    precondition(MemoryLayout<Config>.offset(of: \.maximum_backoff_tick_count) == 16)
    precondition(MemoryLayout<Config>.offset(of: \.capped_cooldown_tick_count) == 24)
    precondition(MemoryLayout<State>.size == 56 && MemoryLayout<State>.stride == 56)
    precondition(MemoryLayout<State>.alignment == 8)
    precondition(MemoryLayout<State>.offset(of: \.abi_version) == 0)
    precondition(MemoryLayout<State>.offset(of: \.reserved) == 4)
    precondition(MemoryLayout<State>.offset(of: \.maximum_failed_attempt_count) == 8)
    precondition(MemoryLayout<State>.offset(of: \.maximum_backoff_tick_count) == 16)
    precondition(MemoryLayout<State>.offset(of: \.capped_cooldown_tick_count) == 24)
    precondition(MemoryLayout<State>.offset(of: \.failed_attempt_count) == 32)
    precondition(MemoryLayout<State>.offset(of: \.backoff_tick_count) == 40)
    precondition(MemoryLayout<State>.offset(of: \.cooldown_tick_count) == 48)
    precondition(MemoryLayout<Retry>.size == 64 && MemoryLayout<Retry>.stride == 64)
    precondition(MemoryLayout<Retry>.alignment == 8)
    precondition(MemoryLayout<Retry>.offset(of: \.state) == 0)
    precondition(MemoryLayout<Retry>.offset(of: \.status) == 56)
    precondition(MemoryLayout<Retry>.offset(of: \.tick_decision) == 60)
    precondition(MemoryLayout<Start>.size == 32 && MemoryLayout<Start>.stride == 32)
    precondition(MemoryLayout<Start>.alignment == 4)
    precondition(MemoryLayout<Start>.offset(of: \.abi_version) == 0)
    precondition(MemoryLayout<Start>.offset(of: \.reserved) == 4)
    precondition(MemoryLayout<Start>.offset(of: \.is_live) == 8)
    precondition(MemoryLayout<Start>.offset(of: \.is_paused_for_recovery) == 12)
    precondition(MemoryLayout<Start>.offset(of: \.has_source) == 16)
    precondition(MemoryLayout<Start>.offset(of: \.has_sink) == 20)
    precondition(MemoryLayout<Start>.offset(of: \.has_valid_authorization) == 24)
    precondition(MemoryLayout<Start>.offset(of: \.peer_generation_matches) == 28)
    precondition(MemoryLayout<StartDecision>.size == 16 && MemoryLayout<StartDecision>.stride == 16)
    precondition(MemoryLayout<StartDecision>.alignment == 4)
    precondition(MemoryLayout<StartDecision>.offset(of: \.abi_version) == 0)
    precondition(MemoryLayout<StartDecision>.offset(of: \.status) == 4)
    precondition(MemoryLayout<StartDecision>.offset(of: \.mode) == 8)
    precondition(MemoryLayout<StartDecision>.offset(of: \.reserved) == 12)
    precondition(MemoryLayout<Observation>.size == 120 && MemoryLayout<Observation>.stride == 120)
    precondition(MemoryLayout<Observation>.alignment == 8)
    precondition(MemoryLayout<Observation>.offset(of: \.abi_version) == 0)
    precondition(MemoryLayout<Observation>.offset(of: \.reserved) == 4)
    precondition(MemoryLayout<Observation>.offset(of: \.observation_sequence) == 8)
    precondition(MemoryLayout<Observation>.offset(of: \.highest_admitted_sequence) == 16)
    precondition(MemoryLayout<Observation>.offset(of: \.observation_challenge_present) == 24)
    precondition(MemoryLayout<Observation>.offset(of: \.current_challenge_present) == 28)
    precondition(MemoryLayout<Observation>.offset(of: \.current_protocol_version) == 32)
    precondition(MemoryLayout<Observation>.offset(of: \.observation_challenge_sequence) == 40)
    precondition(MemoryLayout<Observation>.offset(of: \.current_challenge_sequence) == 48)
    precondition(MemoryLayout<Observation>.offset(of: \.observation_nonce) == 56)
    precondition(MemoryLayout<Observation>.offset(of: \.observation_call_epoch_nonce) == 72)
    precondition(MemoryLayout<Observation>.offset(of: \.current_nonce) == 88)
    precondition(MemoryLayout<Observation>.offset(of: \.current_call_epoch_nonce) == 104)
    precondition(MemoryLayout<Evidence>.size == 16 && MemoryLayout<Evidence>.stride == 16)
    precondition(MemoryLayout<Evidence>.alignment == 4)
    precondition(MemoryLayout<Evidence>.offset(of: \.abi_version) == 0)
    precondition(MemoryLayout<Evidence>.offset(of: \.reserved) == 4)
    precondition(MemoryLayout<Evidence>.offset(of: \.active) == 8)
    precondition(MemoryLayout<Evidence>.offset(of: \.armed) == 12)
    precondition(MemoryLayout<Peer>.size == 40 && MemoryLayout<Peer>.stride == 40)
    precondition(MemoryLayout<Peer>.alignment == 8)
    precondition(MemoryLayout<Peer>.offset(of: \.abi_version) == 0)
    precondition(MemoryLayout<Peer>.offset(of: \.reserved) == 4)
    precondition(MemoryLayout<Peer>.offset(of: \.audio_present) == 8)
    precondition(MemoryLayout<Peer>.offset(of: \.challenge_present) == 12)
    precondition(MemoryLayout<Peer>.offset(of: \.audio_generation) == 16)
    precondition(MemoryLayout<Peer>.offset(of: \.challenge_generation) == 24)
    precondition(MemoryLayout<Peer>.offset(of: \.current_generation) == 32)
    precondition(MemoryLayout<HostedDecision>.size == 16 && MemoryLayout<HostedDecision>.stride == 16)
    precondition(MemoryLayout<HostedDecision>.alignment == 4)
    precondition(MemoryLayout<HostedDecision>.offset(of: \.abi_version) == 0)
    precondition(MemoryLayout<HostedDecision>.offset(of: \.status) == 4)
    precondition(MemoryLayout<HostedDecision>.offset(of: \.value) == 8)
    precondition(MemoryLayout<HostedDecision>.offset(of: \.reserved) == 12)

    func configFields(_ x: Config) -> [Int64] {
        [Int64(x.abi_version),Int64(x.reserved),x.maximum_failed_attempt_count,
         x.maximum_backoff_tick_count,x.capped_cooldown_tick_count]
    }
    func stateFields(_ x: State) -> [Int64] {
        [Int64(x.abi_version),Int64(x.reserved),x.maximum_failed_attempt_count,
         x.maximum_backoff_tick_count,x.capped_cooldown_tick_count,
         x.failed_attempt_count,x.backoff_tick_count,x.cooldown_tick_count]
    }
    func startFields(_ x: Start) -> [UInt32] {
        [x.abi_version,x.reserved,x.is_live,x.is_paused_for_recovery,x.has_source,
         x.has_sink,x.has_valid_authorization,x.peer_generation_matches]
    }
    func uuidFields(_ x: UUIDBytes) -> [UInt8] {
        [x.0,x.1,x.2,x.3,x.4,x.5,x.6,x.7,x.8,x.9,x.10,x.11,x.12,x.13,x.14,x.15]
    }
    func uuid(_ x: [UInt8]) -> UUIDBytes {
        precondition(x.count == 16)
        return (x[0],x[1],x[2],x[3],x[4],x[5],x[6],x[7],x[8],x[9],x[10],x[11],x[12],x[13],x[14],x[15])
    }
    func observationScalars(_ x: Observation) -> [UInt64] {
        [UInt64(x.abi_version),UInt64(x.reserved),x.observation_sequence,x.highest_admitted_sequence,
         UInt64(x.observation_challenge_present),UInt64(x.current_challenge_present),
         UInt64(bitPattern:x.current_protocol_version),x.observation_challenge_sequence,x.current_challenge_sequence]
    }
    func observationUUIDs(_ x: Observation) -> [[UInt8]] {
        [uuidFields(x.observation_nonce),uuidFields(x.observation_call_epoch_nonce),
         uuidFields(x.current_nonce),uuidFields(x.current_call_epoch_nonce)]
    }
    func evidenceFields(_ x: Evidence) -> [UInt32] { [x.abi_version,x.reserved,x.active,x.armed] }
    func peerFields(_ x: Peer) -> [UInt64] {
        [UInt64(x.abi_version),UInt64(x.reserved),UInt64(x.audio_present),UInt64(x.challenge_present),
         x.audio_generation,x.challenge_generation,x.current_generation]
    }
    // Exactly one actual export call per wrapper, then all caller-owned fields
    // are compared with a pre-call copy. No production output computes expected values.
    func initialize(_ input: Config) -> Retry {
        let before = input
        let output = beluga_core_safe_output_retry_initialize(input)
        precondition(configFields(input) == configFields(before))
        return output
    }
    func transition(_ input: State, _ event: UInt32) -> Retry {
        let before = input, beforeEvent = event
        let output = beluga_core_safe_output_retry_transition(input,event)
        precondition(stateFields(input) == stateFields(before) && event == beforeEvent)
        return output
    }
    func start(_ input: Start) -> StartDecision {
        let before = input
        let output = beluga_core_system_audio_start(input)
        precondition(startFields(input) == startFields(before))
        return output
    }
    func observation(_ input: Observation) -> HostedDecision {
        let before = input
        let output = beluga_core_hosted_call_observation(input)
        precondition(observationScalars(input) == observationScalars(before))
        precondition(observationUUIDs(input) == observationUUIDs(before))
        return output
    }
    func evidence(_ input: Evidence) -> HostedDecision {
        let before = input
        let output = beluga_core_hosted_call_evidence(input)
        precondition(evidenceFields(input) == evidenceFields(before))
        return output
    }
    func peer(_ input: Peer) -> HostedDecision {
        let before = input
        let output = beluga_core_hosted_call_peer_generation(input)
        precondition(peerFields(input) == peerFields(before))
        return output
    }
    func config(_ f: Int64, _ b: Int64, _ c: Int64) -> Config {
        var x = Config(); x.abi_version = 1
        x.maximum_failed_attempt_count = f; x.maximum_backoff_tick_count = b
        x.capped_cooldown_tick_count = c; return x
    }
    func counts(_ x: Retry, _ status: UInt32, _ tick: UInt32, _ f: Int64, _ b: Int64, _ c: Int64) {
        precondition(x.status == status && x.tick_decision == tick)
        precondition(x.state.failed_attempt_count == f && x.state.backoff_tick_count == b && x.state.cooldown_tick_count == c)
    }
    func preservedConfig(_ x: State, _ f: Int64, _ b: Int64, _ c: Int64) {
        precondition(x.abi_version == 1 && x.reserved == 0)
        precondition(x.maximum_failed_attempt_count == f && x.maximum_backoff_tick_count == b && x.capped_cooldown_tick_count == c)
    }
    func invalidRetry(_ raw: State) {
        for event: UInt32 in 1...3 {
            let x = transition(raw,event)
            precondition(x.status == 0 && x.tick_decision == 0 && stateFields(x.state) == stateFields(raw))
        }
    }

    let requested: [Int64] = [.min,-9,0,1,2,.max]
    let normalized: [Int64] = [1,1,1,1,2,.max]
    for f in 0..<6 { for b in 0..<6 { for c in 0..<6 {
        let x = initialize(config(requested[f],requested[b],requested[c]))
        counts(x,1,0,0,0,0); preservedConfig(x.state,normalized[f],normalized[b],normalized[c])
    } } }
    let trace: [(UInt32,Int64,Int64,Int64,UInt32)] = [
        (1,0,0,0,2),(2,1,1,0,0),(1,1,0,0,1),(1,1,0,0,2),(2,2,2,0,0),
        (1,2,1,0,1),(1,2,0,0,1),(1,2,0,0,2),(2,3,0,3,0),(2,3,0,3,0),
        (1,3,0,2,1),(1,3,0,1,1),(1,3,0,0,1),(1,0,0,0,2),(2,1,1,0,0),
        (3,0,0,0,0),(1,0,0,0,2),(3,0,0,0,0),(1,0,0,0,2)
    ]
    precondition(trace.count == 19)
    var raw = initialize(config(3,4,3)).state
    for (event,f,b,c,tick) in trace {
        let x = transition(raw,event); counts(x,1,tick,f,b,c)
        preservedConfig(x.state,3,4,3); raw = x.state
    }
    let defaultRows: [(Int64,Int64,Int64)] = [(1,1,0),(2,2,0),(3,4,0),(4,8,0),(5,16,0),(6,0,60)]
    raw = initialize(config(6,16,60)).state
    for (f,b,c) in defaultRows {
        let x = transition(raw,2); counts(x,1,0,f,b,c); preservedConfig(x.state,6,16,60); raw = x.state
    }
    for tick: Int64 in 0..<60 {
        let x = transition(raw,1); counts(x,1,1,6,0,59-tick); raw = x.state
    }
    counts(transition(raw,1),1,2,0,0,0)
    raw = initialize(config(1,.max,.max)).state
    let cap = transition(raw,2); counts(cap,1,0,1,0,.max)
    let waited = transition(cap.state,1); counts(waited,1,1,1,0,Int64.max-1)
    let retained = transition(waited.state,2)
    precondition(retained.status == 1 && retained.tick_decision == 0)
    precondition(stateFields(retained.state) == stateFields(waited.state))
    raw = initialize(config(.max,.max,.max)).state; raw.failed_attempt_count = Int64.max-1
    counts(transition(raw,2),1,0,.max,0,.max)
    let priors: [Int64] = [30,31,32,64,999,Int64.max-2]
    for prior in priors {
        raw = initialize(config(.max,.max,5)).state; raw.failed_attempt_count = prior
        counts(transition(raw,2),1,0,prior+1,1_073_741_824,0)
    }
    raw = initialize(config(1000,7,5)).state; raw.failed_attempt_count = 998
    counts(transition(raw,2),1,0,999,7,0)

    let envelopes: [(UInt32,UInt32)] = [(0,0),(2,0),(.max,0),(1,1),(1,2),(1,.max),(9,17)]
    for requested in [config(.min,-7,.max),config(3,4,3)] {
        for (version,reserved) in envelopes {
            var input = requested; input.abi_version = version; input.reserved = reserved
            var expected = State(); expected.abi_version = version; expected.reserved = reserved
            expected.maximum_failed_attempt_count = requested.maximum_failed_attempt_count
            expected.maximum_backoff_tick_count = requested.maximum_backoff_tick_count
            expected.capped_cooldown_tick_count = requested.capped_cooldown_tick_count
            let x = initialize(input)
            precondition(x.status == 0 && x.tick_decision == 0)
            precondition(stateFields(x.state) == stateFields(expected))
        }
    }
    let initial = initialize(config(3,4,3)).state
    let pending = transition(initial,2).state
    let capped = transition(transition(pending,2).state,2).state
    for base in [initial,pending,capped] {
        for event: UInt32 in [0,4,.max] {
            let x = transition(base,event)
            precondition(x.status == 0 && x.tick_decision == 0 && stateFields(x.state) == stateFields(base))
        }
        var bad = base; bad.abi_version = 0; invalidRetry(bad)
        bad = base; bad.abi_version = 2; invalidRetry(bad)
        bad = base; bad.reserved = 1; invalidRetry(bad)
        for limit: Int64 in [.min,-1,0] {
            bad = base; bad.maximum_failed_attempt_count = limit; invalidRetry(bad)
            bad = base; bad.maximum_backoff_tick_count = limit; invalidRetry(bad)
            bad = base; bad.capped_cooldown_tick_count = limit; invalidRetry(bad)
        }
        bad = base; bad.failed_attempt_count = -1; invalidRetry(bad)
        bad = base; bad.failed_attempt_count = 4; invalidRetry(bad)
        bad = base; bad.backoff_tick_count = -1; invalidRetry(bad)
        bad = base; bad.backoff_tick_count = 9; invalidRetry(bad)
        bad = base; bad.cooldown_tick_count = -1; invalidRetry(bad)
        bad = base; bad.cooldown_tick_count = 4; invalidRetry(bad)
    }
    raw = initial; raw.cooldown_tick_count = 1; invalidRetry(raw)
    raw = pending; raw.cooldown_tick_count = 1; invalidRetry(raw)
    raw = capped; raw.backoff_tick_count = 1; invalidRetry(raw)
    let reset = transition(pending,3); counts(reset,1,0,0,0,0)
    precondition(stateFields(reset.state) == stateFields(initial))
    precondition(pending.failed_attempt_count == 1 && pending.backoff_tick_count == 1)
    print("BelugaCore Swift safe output retry import/link PASS: exact layouts, frozen literal transitions and unchanged refusals")

    func startInput(_ bits: UInt32) -> Start {
        var x = Start(); x.abi_version = 1
        x.is_live = bits & 1; x.is_paused_for_recovery = (bits >> 1) & 1
        x.has_source = (bits >> 2) & 1; x.has_sink = (bits >> 3) & 1
        x.has_valid_authorization = (bits >> 4) & 1; x.peer_generation_matches = (bits >> 5) & 1
        return x
    }
    func assertStart(_ x: StartDecision, _ status: UInt32, _ mode: UInt32) {
        precondition(x.abi_version == 1 && x.status == status && x.mode == mode && x.reserved == 0)
    }
    let modes: [UInt32] = [
        3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        3,0,0,0,0,0,0,0,0,0,0,0,0,0,2,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0
    ]
    precondition(modes.count == 64)
    let malformed: [UInt32] = [2,.max]
    for bits: UInt32 in 0..<64 {
        let base = startInput(bits); assertStart(start(base),1,modes[Int(bits)])
        for field in 0..<8 { for bad in malformed {
            var x = base
            switch field {
            case 0: x.abi_version = bad
            case 1: x.reserved = bad
            case 2: x.is_live = bad
            case 3: x.is_paused_for_recovery = bad
            case 4: x.has_source = bad
            case 5: x.has_sink = bad
            case 6: x.has_valid_authorization = bad
            default: x.peer_generation_matches = bad
            }
            assertStart(start(x),0,0)
        } }
        var x = base; x.abi_version = 0; assertStart(start(x),0,0)
        x = base; x.reserved = 1; assertStart(start(x),0,0)
    }
    print("BelugaCore Swift system audio start import/link PASS: exact layouts, 64 literal choices and 1152 closed-field refusals")

    let nonce: [UInt8] = [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16]
    let epoch: [UInt8] = [16,15,14,13,12,11,10,9,8,7,6,5,4,3,2,1]
    let zeroUUID = uuid(Array(repeating:0,count:16))
    func observationInput() -> Observation {
        var x = Observation(); x.abi_version = 1
        x.observation_sequence = 11; x.highest_admitted_sequence = 10
        x.observation_challenge_present = 1; x.current_challenge_present = 1
        x.current_protocol_version = 3; x.observation_challenge_sequence = 7; x.current_challenge_sequence = 7
        x.observation_nonce = uuid(nonce); x.current_nonce = uuid(nonce)
        x.observation_call_epoch_nonce = uuid(epoch); x.current_call_epoch_nonce = uuid(epoch)
        return x
    }
    func assertHosted(_ x: HostedDecision, _ status: UInt32, _ value: UInt32) {
        precondition(x.abi_version == 1 && x.status == status && x.value == value && x.reserved == 0)
    }
    func peerInput(_ ap: UInt32, _ a: UInt64, _ cp: UInt32, _ c: UInt64, _ current: UInt64) -> Peer {
        var x = Peer(); x.abi_version = 1; x.audio_present = ap; x.challenge_present = cp
        x.audio_generation = a; x.challenge_generation = c; x.current_generation = current; return x
    }
    let watermarks: [(UInt64,UInt64,UInt32)] = [
        (0,0,0),(1,0,1),(10,10,0),(11,10,1),(10,11,0),(.max,0,1),(0,.max,0),
        (.max,UInt64.max-1,1),(.max,.max,0),(UInt64.max-1,.max,0)
    ]
    for (sequence,highest,value) in watermarks {
        var x = observationInput(); x.observation_sequence = sequence; x.highest_admitted_sequence = highest
        assertHosted(observation(x),1,value)
    }
    let versions: [(Int64,UInt32)] = [(.min,0),(-1,0),(0,0),(1,0),(2,0),(3,1),(4,0),(.max,0)]
    for (version,value) in versions {
        var x = observationInput(); x.current_protocol_version = version; assertHosted(observation(x),1,value)
    }
    for (sequence,value): (UInt64,UInt32) in [(0,0),(1,1),(.max,1)] {
        var x = observationInput(); x.observation_challenge_sequence = sequence; x.current_challenge_sequence = sequence
        assertHosted(observation(x),1,value)
    }
    for (op,cp): (UInt32,UInt32) in [(0,0),(0,1),(1,0)] {
        var x = observationInput(); x.observation_challenge_present = op; x.current_challenge_present = cp
        x.current_protocol_version = .min; x.current_challenge_sequence = .max
        assertHosted(observation(x),1,0)
    }
    var x = observationInput(); x.observation_nonce = zeroUUID; x.current_nonce = zeroUUID
    assertHosted(observation(x),1,0)
    x = observationInput(); x.observation_call_epoch_nonce = zeroUUID; x.current_call_epoch_nonce = zeroUUID
    assertHosted(observation(x),1,0)
    x = observationInput(); x.observation_call_epoch_nonce = uuid(nonce); x.current_call_epoch_nonce = uuid(nonce)
    assertHosted(observation(x),1,0)
    x = observationInput(); x.observation_challenge_sequence = 6; assertHosted(observation(x),1,0)
    for byte in 0..<16 { for field in 0..<4 {
        x = observationInput()
        var bytes = observationUUIDs(x)[field]; bytes[byte] ^= 0x80
        switch field {
        case 0: x.observation_nonce = uuid(bytes)
        case 1: x.observation_call_epoch_nonce = uuid(bytes)
        case 2: x.current_nonce = uuid(bytes)
        default: x.current_call_epoch_nonce = uuid(bytes)
        }
        assertHosted(observation(x),1,0)
    } }
    for field in 0..<4 { for bad in malformed {
        x = observationInput()
        switch field {
        case 0: x.abi_version = bad
        case 1: x.reserved = bad
        case 2: x.observation_challenge_present = bad
        default: x.current_challenge_present = bad
        }
        assertHosted(observation(x),0,0)
    } }
    x = observationInput(); x.abi_version = 0; assertHosted(observation(x),0,0)
    x = observationInput(); x.reserved = 1; assertHosted(observation(x),0,0)
    let evidenceRows: [(UInt32,UInt32,UInt32)] = [(0,0,1),(0,1,2),(1,0,3),(1,1,0)]
    for (active,armed,value) in evidenceRows {
        var e = Evidence(); e.abi_version = 1; e.active = active; e.armed = armed
        assertHosted(evidence(e),1,value)
        for field in 0..<4 { for bad in malformed {
            var input = e
            switch field {
            case 0: input.abi_version = bad
            case 1: input.reserved = bad
            case 2: input.active = bad
            default: input.armed = bad
            }
            assertHosted(evidence(input),0,0)
        } }
        var input = e; input.abi_version = 0; assertHosted(evidence(input),0,0)
        input = e; input.reserved = 1; assertHosted(evidence(input),0,0)
    }
    let peers: [(UInt32,UInt64,UInt32,UInt64,UInt64,UInt32)] = [
        (0,0,0,0,0,0),(1,0,1,0,0,0),(0,0,1,7,7,0),(1,7,0,0,7,0),
        (1,6,1,7,7,0),(1,7,1,6,7,0),(1,7,1,7,7,1),(1,1,1,1,1,1),
        (1,.max,1,.max,.max,1),(1,UInt64.max-1,1,.max,.max,0),
        (1,0,1,7,7,0),(1,7,1,0,7,0)
    ]
    for (ap,a,cp,c,current,value) in peers { assertHosted(peer(peerInput(ap,a,cp,c,current)),1,value) }
    assertHosted(peer(peerInput(0,.max,0,.max,7)),1,0)
    for base in [peerInput(1,7,1,7,7),peerInput(0,0,0,0,7),peerInput(1,0,1,0,0)] {
        for field in 0..<4 { for bad in malformed {
            var input = base
            switch field {
            case 0: input.abi_version = bad
            case 1: input.reserved = bad
            case 2: input.audio_present = bad
            default: input.challenge_present = bad
            }
            assertHosted(peer(input),0,0)
        } }
        var input = base; input.abi_version = 0; assertHosted(peer(input),0,0)
        input = base; input.reserved = 1; assertHosted(peer(input),0,0)
    }
    print("BelugaCore Swift hosted call import/link PASS: exact layouts, strict watermark and generation identity, unchanged refusals")
}
batchAPolicySmoke()
