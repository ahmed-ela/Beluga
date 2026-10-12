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

// Display admission smoke: copied ABI values, no native display effects.
func displayAdmissionSmoke() {
    typealias DisplayRequirement = beluga_core_display_requirement_facts_t
    precondition(MemoryLayout<DisplayRequirement>.size == 64 && MemoryLayout<DisplayRequirement>.alignment == 8 && MemoryLayout<DisplayRequirement>.stride == 64)
    precondition(MemoryLayout<DisplayRequirement>.offset(of: \DisplayRequirement.abi_version) == 0)
    precondition(MemoryLayout<DisplayRequirement>.offset(of: \DisplayRequirement.reserved) == 4)
    precondition(MemoryLayout<DisplayRequirement>.offset(of: \DisplayRequirement.required_vendor_id) == 8)
    precondition(MemoryLayout<DisplayRequirement>.offset(of: \DisplayRequirement.required_product_id) == 12)
    precondition(MemoryLayout<DisplayRequirement>.offset(of: \DisplayRequirement.required_serial_number) == 16)
    precondition(MemoryLayout<DisplayRequirement>.offset(of: \DisplayRequirement.requires_sole_main_display) == 20)
    precondition(MemoryLayout<DisplayRequirement>.offset(of: \DisplayRequirement.display_id) == 24)
    precondition(MemoryLayout<DisplayRequirement>.offset(of: \DisplayRequirement.observed_vendor_id) == 28)
    precondition(MemoryLayout<DisplayRequirement>.offset(of: \DisplayRequirement.observed_product_id) == 32)
    precondition(MemoryLayout<DisplayRequirement>.offset(of: \DisplayRequirement.observed_serial_number) == 36)
    precondition(MemoryLayout<DisplayRequirement>.offset(of: \DisplayRequirement.is_online) == 40)
    precondition(MemoryLayout<DisplayRequirement>.offset(of: \DisplayRequirement.is_active) == 44)
    precondition(MemoryLayout<DisplayRequirement>.offset(of: \DisplayRequirement.main_display_id) == 48)
    precondition(MemoryLayout<DisplayRequirement>.offset(of: \DisplayRequirement.sole_online_display_id) == 52)
    precondition(MemoryLayout<DisplayRequirement>.offset(of: \DisplayRequirement.online_display_count) == 56)
    typealias DisplayBoolean = beluga_core_display_boolean_decision_t
    precondition(MemoryLayout<DisplayBoolean>.size == 16 && MemoryLayout<DisplayBoolean>.alignment == 4 && MemoryLayout<DisplayBoolean>.stride == 16)
    precondition(MemoryLayout<DisplayBoolean>.offset(of: \DisplayBoolean.abi_version) == 0)
    precondition(MemoryLayout<DisplayBoolean>.offset(of: \DisplayBoolean.status) == 4)
    precondition(MemoryLayout<DisplayBoolean>.offset(of: \DisplayBoolean.value) == 8)
    precondition(MemoryLayout<DisplayBoolean>.offset(of: \DisplayBoolean.reserved) == 12)
    typealias DisplayKind = beluga_core_source_dimension_kind_facts_t
    precondition(MemoryLayout<DisplayKind>.size == 16 && MemoryLayout<DisplayKind>.alignment == 4 && MemoryLayout<DisplayKind>.stride == 16)
    precondition(MemoryLayout<DisplayKind>.offset(of: \DisplayKind.abi_version) == 0)
    precondition(MemoryLayout<DisplayKind>.offset(of: \DisplayKind.reserved) == 4)
    precondition(MemoryLayout<DisplayKind>.offset(of: \DisplayKind.vendor_id) == 8)
    precondition(MemoryLayout<DisplayKind>.offset(of: \DisplayKind.product_id) == 12)
    typealias DisplayKindOutput = beluga_core_source_dimension_kind_decision_t
    precondition(MemoryLayout<DisplayKindOutput>.size == 16 && MemoryLayout<DisplayKindOutput>.alignment == 4 && MemoryLayout<DisplayKindOutput>.stride == 16)
    precondition(MemoryLayout<DisplayKindOutput>.offset(of: \DisplayKindOutput.abi_version) == 0)
    precondition(MemoryLayout<DisplayKindOutput>.offset(of: \DisplayKindOutput.status) == 4)
    precondition(MemoryLayout<DisplayKindOutput>.offset(of: \DisplayKindOutput.kind) == 8)
    precondition(MemoryLayout<DisplayKindOutput>.offset(of: \DisplayKindOutput.reserved) == 12)
    typealias DisplaySource = beluga_core_source_dimensions_facts_t
    precondition(MemoryLayout<DisplaySource>.size == 88 && MemoryLayout<DisplaySource>.alignment == 8 && MemoryLayout<DisplaySource>.stride == 88)
    precondition(MemoryLayout<DisplaySource>.offset(of: \DisplaySource.abi_version) == 0)
    precondition(MemoryLayout<DisplaySource>.offset(of: \DisplaySource.reserved) == 4)
    precondition(MemoryLayout<DisplaySource>.offset(of: \DisplaySource.vendor_id) == 8)
    precondition(MemoryLayout<DisplaySource>.offset(of: \DisplaySource.product_id) == 12)
    precondition(MemoryLayout<DisplaySource>.offset(of: \DisplaySource.logical_width) == 16)
    precondition(MemoryLayout<DisplaySource>.offset(of: \DisplaySource.logical_height) == 24)
    precondition(MemoryLayout<DisplaySource>.offset(of: \DisplaySource.core_graphics_logical_width) == 32)
    precondition(MemoryLayout<DisplaySource>.offset(of: \DisplaySource.core_graphics_logical_height) == 40)
    precondition(MemoryLayout<DisplaySource>.offset(of: \DisplaySource.core_graphics_pixel_width) == 48)
    precondition(MemoryLayout<DisplaySource>.offset(of: \DisplaySource.core_graphics_pixel_height) == 56)
    precondition(MemoryLayout<DisplaySource>.offset(of: \DisplaySource.filter_content_width) == 64)
    precondition(MemoryLayout<DisplaySource>.offset(of: \DisplaySource.filter_content_height) == 72)
    precondition(MemoryLayout<DisplaySource>.offset(of: \DisplaySource.point_pixel_scale) == 80)
    typealias DisplaySourceOutput = beluga_core_source_dimensions_decision_t
    precondition(MemoryLayout<DisplaySourceOutput>.size == 32 && MemoryLayout<DisplaySourceOutput>.alignment == 8 && MemoryLayout<DisplaySourceOutput>.stride == 32)
    precondition(MemoryLayout<DisplaySourceOutput>.offset(of: \DisplaySourceOutput.abi_version) == 0)
    precondition(MemoryLayout<DisplaySourceOutput>.offset(of: \DisplaySourceOutput.status) == 4)
    precondition(MemoryLayout<DisplaySourceOutput>.offset(of: \DisplaySourceOutput.kind) == 8)
    precondition(MemoryLayout<DisplaySourceOutput>.offset(of: \DisplaySourceOutput.has_dimensions) == 12)
    precondition(MemoryLayout<DisplaySourceOutput>.offset(of: \DisplaySourceOutput.width) == 16)
    precondition(MemoryLayout<DisplaySourceOutput>.offset(of: \DisplaySourceOutput.height) == 24)
    typealias DisplayStability = beluga_core_source_dimensions_stability_facts_t
    precondition(MemoryLayout<DisplayStability>.size == 40 && MemoryLayout<DisplayStability>.alignment == 8 && MemoryLayout<DisplayStability>.stride == 40)
    precondition(MemoryLayout<DisplayStability>.offset(of: \DisplayStability.abi_version) == 0)
    precondition(MemoryLayout<DisplayStability>.offset(of: \DisplayStability.reserved) == 4)
    precondition(MemoryLayout<DisplayStability>.offset(of: \DisplayStability.before_width) == 8)
    precondition(MemoryLayout<DisplayStability>.offset(of: \DisplayStability.before_height) == 16)
    precondition(MemoryLayout<DisplayStability>.offset(of: \DisplayStability.after_width) == 24)
    precondition(MemoryLayout<DisplayStability>.offset(of: \DisplayStability.after_height) == 32)
    func requirementInput() -> DisplayRequirement {
        var x = DisplayRequirement()
        x.abi_version = 1
        x.reserved = 0
        x.required_vendor_id = 0x6f73
        x.required_product_id = 0x1717
        x.required_serial_number = 7
        x.requires_sole_main_display = 1
        x.display_id = 42
        x.observed_vendor_id = 0x6f73
        x.observed_product_id = 0x1717
        x.observed_serial_number = 7
        x.is_online = 1
        x.is_active = 1
        x.main_display_id = 42
        x.sole_online_display_id = 42
        x.online_display_count = 1
        return x
    }
    func sourceInput() -> DisplaySource {
        var x = DisplaySource()
        x.abi_version = 1
        x.reserved = 0
        x.vendor_id = 0x6f73
        x.product_id = 0x1717
        x.logical_width = 390
        x.logical_height = 844
        x.core_graphics_logical_width = 390
        x.core_graphics_logical_height = 844
        x.core_graphics_pixel_width = 1170
        x.core_graphics_pixel_height = 2532
        x.filter_content_width = 390.0
        x.filter_content_height = 844.0
        x.point_pixel_scale = 3.0
        return x
    }
    func requirementWords(_ x: DisplayRequirement) -> [UInt64] {
        [UInt64(x.abi_version), UInt64(x.reserved), UInt64(x.required_vendor_id), UInt64(x.required_product_id), UInt64(x.required_serial_number), UInt64(x.requires_sole_main_display), UInt64(x.display_id), UInt64(x.observed_vendor_id), UInt64(x.observed_product_id), UInt64(x.observed_serial_number), UInt64(x.is_online), UInt64(x.is_active), UInt64(x.main_display_id), UInt64(x.sole_online_display_id), UInt64(x.online_display_count)]
    }
    func kindWords(_ x: DisplayKind) -> [UInt64] {
        [UInt64(x.abi_version), UInt64(x.reserved), UInt64(x.vendor_id), UInt64(x.product_id)]
    }
    func sourceWords(_ x: DisplaySource) -> [UInt64] {
        [UInt64(x.abi_version), UInt64(x.reserved), UInt64(x.vendor_id), UInt64(x.product_id), UInt64(bitPattern: x.logical_width), UInt64(bitPattern: x.logical_height), UInt64(bitPattern: x.core_graphics_logical_width), UInt64(bitPattern: x.core_graphics_logical_height), UInt64(bitPattern: x.core_graphics_pixel_width), UInt64(bitPattern: x.core_graphics_pixel_height), x.filter_content_width.bitPattern, x.filter_content_height.bitPattern, x.point_pixel_scale.bitPattern]
    }
    func stabilityWords(_ x: DisplayStability) -> [UInt64] {
        [UInt64(x.abi_version), UInt64(x.reserved), UInt64(bitPattern: x.before_width), UInt64(bitPattern: x.before_height), UInt64(bitPattern: x.after_width), UInt64(bitPattern: x.after_height)]
    }
    func expectRequirement(_ input: DisplayRequirement, _ status: UInt32, _ value: UInt32) {
        let before = requirementWords(input)
        let output = beluga_core_display_requirement_admission(input)
        precondition(requirementWords(input) == before)
        precondition(output.abi_version == 1 && output.status == status && output.value == value && output.reserved == 0)
    }
    func expectKind(_ input: DisplayKind, _ status: UInt32, _ kind: UInt32) {
        let before = kindWords(input)
        let output = beluga_core_source_dimension_kind(input)
        precondition(kindWords(input) == before)
        precondition(output.abi_version == 1 && output.status == status && output.kind == kind && output.reserved == 0)
    }
    func expectSource(_ input: DisplaySource, _ status: UInt32, _ kind: UInt32, _ present: UInt32, _ width: Int64, _ height: Int64) {
        let before = sourceWords(input)
        let output = beluga_core_source_dimensions(input)
        precondition(sourceWords(input) == before)
        precondition(output.abi_version == 1 && output.status == status && output.kind == kind &&
                     output.has_dimensions == present && output.width == width && output.height == height)
    }
    func expectStable(_ input: DisplayStability, _ status: UInt32, _ value: UInt32) {
        let before = stabilityWords(input)
        let output = beluga_core_source_dimensions_stable(input)
        precondition(stabilityWords(input) == before)
        precondition(output.abi_version == 1 && output.status == status && output.value == value && output.reserved == 0)
    }
    // exact sole main identity
    do { var input = requirementInput()

        expectRequirement(input, 1, 1)
    }
    // required_vendor_id independent mismatch
    do { var input = requirementInput()
        input.required_vendor_id = 0x00016f73
        expectRequirement(input, 1, 0)
    }
    // observed_vendor_id independent mismatch
    do { var input = requirementInput()
        input.observed_vendor_id = 0x00016f73
        expectRequirement(input, 1, 0)
    }
    // required_product_id independent mismatch
    do { var input = requirementInput()
        input.required_product_id = 0x00011717
        expectRequirement(input, 1, 0)
    }
    // observed_product_id independent mismatch
    do { var input = requirementInput()
        input.observed_product_id = 0x00011717
        expectRequirement(input, 1, 0)
    }
    // required_serial_number independent mismatch
    do { var input = requirementInput()
        input.required_serial_number = 0x00010007
        expectRequirement(input, 1, 0)
    }
    // observed_serial_number independent mismatch
    do { var input = requirementInput()
        input.observed_serial_number = 0x00010007
        expectRequirement(input, 1, 0)
    }
    // is_online independent mismatch
    do { var input = requirementInput()
        input.is_online = 0
        expectRequirement(input, 1, 0)
    }
    // is_active independent mismatch
    do { var input = requirementInput()
        input.is_active = 0
        expectRequirement(input, 1, 0)
    }
    // main_display_id independent mismatch
    do { var input = requirementInput()
        input.main_display_id = 0x0001002a
        expectRequirement(input, 1, 0)
    }
    // sole_online_display_id independent mismatch
    do { var input = requirementInput()
        input.sole_online_display_id = 0x0001002a
        expectRequirement(input, 1, 0)
    }
    // display_id independent mismatch
    do { var input = requirementInput()
        input.display_id = 0x0001002a
        expectRequirement(input, 1, 0)
    }
    // exact topology count 0
    do { var input = requirementInput()
        input.online_display_count = 0
        expectRequirement(input, 1, 0)
    }
    // exact topology count 2
    do { var input = requirementInput()
        input.online_display_count = 2
        expectRequirement(input, 1, 0)
    }
    // exact topology count UINT64_MAX
    do { var input = requirementInput()
        input.online_display_count = UInt64.max
        expectRequirement(input, 1, 0)
    }
    // exact topology count 0x0000000100000001
    do { var input = requirementInput()
        input.online_display_count = 0x0000000100000001
        expectRequirement(input, 1, 0)
    }
    // optional ignores absent and arbitrary topology
    do { var input = requirementInput()
        input.requires_sole_main_display = 0;         input.main_display_id = 0;         input.sole_online_display_id = UInt32.max;         input.online_display_count = UInt64.max
        expectRequirement(input, 1, 1)
    }
    // full high-bit identity remains valid
    do { var input = requirementInput()
        input.required_vendor_id = 0x00016f73;         input.observed_vendor_id = 0x00016f73;         input.required_product_id = 0x00011717;         input.observed_product_id = 0x00011717;         input.required_serial_number = 0x00010007;         input.observed_serial_number = 0x00010007;         input.display_id = 0x0001002a;         input.main_display_id = 0x0001002a;         input.sole_online_display_id = 0x0001002a
        expectRequirement(input, 1, 1)
    }
    // exact unrestricted identity 0
    do { var input = requirementInput()
        input.required_vendor_id = 0;         input.observed_vendor_id = 0;         input.required_product_id = 0;         input.observed_product_id = 0;         input.required_serial_number = 0;         input.observed_serial_number = 0;         input.display_id = 0;         input.main_display_id = 0;         input.sole_online_display_id = 0
        expectRequirement(input, 1, 1)
    }
    // exact unrestricted identity UINT32_MAX
    do { var input = requirementInput()
        input.required_vendor_id = UInt32.max;         input.observed_vendor_id = UInt32.max;         input.required_product_id = UInt32.max;         input.observed_product_id = UInt32.max;         input.required_serial_number = UInt32.max;         input.observed_serial_number = UInt32.max;         input.display_id = UInt32.max;         input.main_display_id = UInt32.max;         input.sole_online_display_id = UInt32.max
        expectRequirement(input, 1, 1)
    }
    // closed requires_sole_main_display=2
    do { var input = requirementInput()
        input.requires_sole_main_display = 2
        expectRequirement(input, 0, 0)
    }
    // closed requires_sole_main_display=UINT32_MAX
    do { var input = requirementInput()
        input.requires_sole_main_display = UInt32.max
        expectRequirement(input, 0, 0)
    }
    // closed is_online=2
    do { var input = requirementInput()
        input.requires_sole_main_display = 0;         input.is_online = 2
        expectRequirement(input, 0, 0)
    }
    // closed is_online=UINT32_MAX
    do { var input = requirementInput()
        input.requires_sole_main_display = 0;         input.is_online = UInt32.max
        expectRequirement(input, 0, 0)
    }
    // closed is_active=2
    do { var input = requirementInput()
        input.requires_sole_main_display = 0;         input.is_active = 2
        expectRequirement(input, 0, 0)
    }
    // closed is_active=UINT32_MAX
    do { var input = requirementInput()
        input.requires_sole_main_display = 0;         input.is_active = UInt32.max
        expectRequirement(input, 0, 0)
    }
    // literal vendor=0x6f73 product=0x1717
    do { var input = DisplayKind(); input.abi_version = 1; input.vendor_id = 0x6f73; input.product_id = 0x1717
        input.vendor_id = 0x6f73;         input.product_id = 0x1717
        expectKind(input, 1, 1)
    }
    // literal vendor=0x6f73 product=0x1718
    do { var input = DisplayKind(); input.abi_version = 1; input.vendor_id = 0x6f73; input.product_id = 0x1717
        input.vendor_id = 0x6f73;         input.product_id = 0x1718
        expectKind(input, 1, 1)
    }
    // literal vendor=0 product=0x1717
    do { var input = DisplayKind(); input.abi_version = 1; input.vendor_id = 0x6f73; input.product_id = 0x1717
        input.vendor_id = 0;         input.product_id = 0x1717
        expectKind(input, 1, 0)
    }
    // literal vendor=0x6f73 product=0x1719
    do { var input = DisplayKind(); input.abi_version = 1; input.vendor_id = 0x6f73; input.product_id = 0x1717
        input.vendor_id = 0x6f73;         input.product_id = 0x1719
        expectKind(input, 1, 0)
    }
    // literal vendor=0x00016f73 product=0x1717
    do { var input = DisplayKind(); input.abi_version = 1; input.vendor_id = 0x6f73; input.product_id = 0x1717
        input.vendor_id = 0x00016f73;         input.product_id = 0x1717
        expectKind(input, 1, 0)
    }
    // literal vendor=0x00016f73 product=0x1718
    do { var input = DisplayKind(); input.abi_version = 1; input.vendor_id = 0x6f73; input.product_id = 0x1717
        input.vendor_id = 0x00016f73;         input.product_id = 0x1718
        expectKind(input, 1, 0)
    }
    // literal vendor=0x6f73 product=0x00011717
    do { var input = DisplayKind(); input.abi_version = 1; input.vendor_id = 0x6f73; input.product_id = 0x1717
        input.vendor_id = 0x6f73;         input.product_id = 0x00011717
        expectKind(input, 1, 0)
    }
    // literal vendor=0x6f73 product=0x00011718
    do { var input = DisplayKind(); input.abi_version = 1; input.vendor_id = 0x6f73; input.product_id = 0x1717
        input.vendor_id = 0x6f73;         input.product_id = 0x00011718
        expectKind(input, 1, 0)
    }
    // literal vendor=0x00016f73 product=0x00011717
    do { var input = DisplayKind(); input.abi_version = 1; input.vendor_id = 0x6f73; input.product_id = 0x1717
        input.vendor_id = 0x00016f73;         input.product_id = 0x00011717
        expectKind(input, 1, 0)
    }
    // literal vendor=UINT32_MAX product=UINT32_MAX
    do { var input = DisplayKind(); input.abi_version = 1; input.vendor_id = 0x6f73; input.product_id = 0x1717
        input.vendor_id = UInt32.max;         input.product_id = UInt32.max
        expectKind(input, 1, 0)
    }
    // ordinary signed endpoints INT64_MIN/INT64_MAX
    do { var input = sourceInput()
        input.core_graphics_logical_width = Int64.min;         input.core_graphics_logical_height = Int64.max;         input.core_graphics_pixel_width = Int64.min;         input.core_graphics_pixel_height = Int64.max;         input.filter_content_width = Double(bitPattern: 0x7ff80000000000a5);         input.filter_content_height = Double(bitPattern: 0x7ff0000000000000);         input.point_pixel_scale = Double(bitPattern: 0x8000000000000000);         input.vendor_id = 0;         input.logical_width = Int64.min;         input.logical_height = Int64.max
        expectSource(input, 1, 0, 1, Int64.min, Int64.max)
    }
    // ordinary signed endpoints INT64_MAX/INT64_MIN
    do { var input = sourceInput()
        input.core_graphics_logical_width = Int64.min;         input.core_graphics_logical_height = Int64.max;         input.core_graphics_pixel_width = Int64.min;         input.core_graphics_pixel_height = Int64.max;         input.filter_content_width = Double(bitPattern: 0x7ff80000000000a5);         input.filter_content_height = Double(bitPattern: 0x7ff0000000000000);         input.point_pixel_scale = Double(bitPattern: 0x8000000000000000);         input.vendor_id = 0;         input.logical_width = Int64.max;         input.logical_height = Int64.min
        expectSource(input, 1, 0, 1, Int64.max, Int64.min)
    }
    // ordinary signed endpoints -1/0
    do { var input = sourceInput()
        input.core_graphics_logical_width = Int64.min;         input.core_graphics_logical_height = Int64.max;         input.core_graphics_pixel_width = Int64.min;         input.core_graphics_pixel_height = Int64.max;         input.filter_content_width = Double(bitPattern: 0x7ff80000000000a5);         input.filter_content_height = Double(bitPattern: 0x7ff0000000000000);         input.point_pixel_scale = Double(bitPattern: 0x8000000000000000);         input.vendor_id = 0;         input.logical_width = -1;         input.logical_height = 0
        expectSource(input, 1, 0, 1, -1, 0)
    }
    // ordinary signed endpoints 0/1
    do { var input = sourceInput()
        input.core_graphics_logical_width = Int64.min;         input.core_graphics_logical_height = Int64.max;         input.core_graphics_pixel_width = Int64.min;         input.core_graphics_pixel_height = Int64.max;         input.filter_content_width = Double(bitPattern: 0x7ff80000000000a5);         input.filter_content_height = Double(bitPattern: 0x7ff0000000000000);         input.point_pixel_scale = Double(bitPattern: 0x8000000000000000);         input.vendor_id = 0;         input.logical_width = 0;         input.logical_height = 1
        expectSource(input, 1, 0, 1, 0, 1)
    }
    // ordinary signed endpoints 32769/-32769
    do { var input = sourceInput()
        input.core_graphics_logical_width = Int64.min;         input.core_graphics_logical_height = Int64.max;         input.core_graphics_pixel_width = Int64.min;         input.core_graphics_pixel_height = Int64.max;         input.filter_content_width = Double(bitPattern: 0x7ff80000000000a5);         input.filter_content_height = Double(bitPattern: 0x7ff0000000000000);         input.point_pixel_scale = Double(bitPattern: 0x8000000000000000);         input.vendor_id = 0;         input.logical_width = 32769;         input.logical_height = -32769
        expectSource(input, 1, 0, 1, 32769, -32769)
    }
    // ordinary alias/source early return 0/0x1717
    do { var input = sourceInput()
        input.core_graphics_logical_width = Int64.min;         input.core_graphics_logical_height = Int64.max;         input.core_graphics_pixel_width = Int64.min;         input.core_graphics_pixel_height = Int64.max;         input.filter_content_width = Double(bitPattern: 0x7ff80000000000a5);         input.filter_content_height = Double(bitPattern: 0x7ff0000000000000);         input.point_pixel_scale = Double(bitPattern: 0x8000000000000000);         input.vendor_id = 0;         input.product_id = 0x1717;         input.logical_width = Int64.min;         input.logical_height = Int64.max
        expectSource(input, 1, 0, 1, Int64.min, Int64.max)
    }
    // ordinary alias/source early return 0x6f73/0x1719
    do { var input = sourceInput()
        input.core_graphics_logical_width = Int64.min;         input.core_graphics_logical_height = Int64.max;         input.core_graphics_pixel_width = Int64.min;         input.core_graphics_pixel_height = Int64.max;         input.filter_content_width = Double(bitPattern: 0x7ff80000000000a5);         input.filter_content_height = Double(bitPattern: 0x7ff0000000000000);         input.point_pixel_scale = Double(bitPattern: 0x8000000000000000);         input.vendor_id = 0x6f73;         input.product_id = 0x1719;         input.logical_width = Int64.min;         input.logical_height = Int64.max
        expectSource(input, 1, 0, 1, Int64.min, Int64.max)
    }
    // ordinary alias/source early return 0x00016f73/0x1717
    do { var input = sourceInput()
        input.core_graphics_logical_width = Int64.min;         input.core_graphics_logical_height = Int64.max;         input.core_graphics_pixel_width = Int64.min;         input.core_graphics_pixel_height = Int64.max;         input.filter_content_width = Double(bitPattern: 0x7ff80000000000a5);         input.filter_content_height = Double(bitPattern: 0x7ff0000000000000);         input.point_pixel_scale = Double(bitPattern: 0x8000000000000000);         input.vendor_id = 0x00016f73;         input.product_id = 0x1717;         input.logical_width = Int64.min;         input.logical_height = Int64.max
        expectSource(input, 1, 0, 1, Int64.min, Int64.max)
    }
    // ordinary alias/source early return 0x00016f73/0x1718
    do { var input = sourceInput()
        input.core_graphics_logical_width = Int64.min;         input.core_graphics_logical_height = Int64.max;         input.core_graphics_pixel_width = Int64.min;         input.core_graphics_pixel_height = Int64.max;         input.filter_content_width = Double(bitPattern: 0x7ff80000000000a5);         input.filter_content_height = Double(bitPattern: 0x7ff0000000000000);         input.point_pixel_scale = Double(bitPattern: 0x8000000000000000);         input.vendor_id = 0x00016f73;         input.product_id = 0x1718;         input.logical_width = Int64.min;         input.logical_height = Int64.max
        expectSource(input, 1, 0, 1, Int64.min, Int64.max)
    }
    // ordinary alias/source early return 0x6f73/0x00011717
    do { var input = sourceInput()
        input.core_graphics_logical_width = Int64.min;         input.core_graphics_logical_height = Int64.max;         input.core_graphics_pixel_width = Int64.min;         input.core_graphics_pixel_height = Int64.max;         input.filter_content_width = Double(bitPattern: 0x7ff80000000000a5);         input.filter_content_height = Double(bitPattern: 0x7ff0000000000000);         input.point_pixel_scale = Double(bitPattern: 0x8000000000000000);         input.vendor_id = 0x6f73;         input.product_id = 0x00011717;         input.logical_width = Int64.min;         input.logical_height = Int64.max
        expectSource(input, 1, 0, 1, Int64.min, Int64.max)
    }
    // ordinary alias/source early return 0x6f73/0x00011718
    do { var input = sourceInput()
        input.core_graphics_logical_width = Int64.min;         input.core_graphics_logical_height = Int64.max;         input.core_graphics_pixel_width = Int64.min;         input.core_graphics_pixel_height = Int64.max;         input.filter_content_width = Double(bitPattern: 0x7ff80000000000a5);         input.filter_content_height = Double(bitPattern: 0x7ff0000000000000);         input.point_pixel_scale = Double(bitPattern: 0x8000000000000000);         input.vendor_id = 0x6f73;         input.product_id = 0x00011718;         input.logical_width = Int64.min;         input.logical_height = Int64.max
        expectSource(input, 1, 0, 1, Int64.min, Int64.max)
    }
    // ordinary alias/source early return 0x00016f73/0x00011717
    do { var input = sourceInput()
        input.core_graphics_logical_width = Int64.min;         input.core_graphics_logical_height = Int64.max;         input.core_graphics_pixel_width = Int64.min;         input.core_graphics_pixel_height = Int64.max;         input.filter_content_width = Double(bitPattern: 0x7ff80000000000a5);         input.filter_content_height = Double(bitPattern: 0x7ff0000000000000);         input.point_pixel_scale = Double(bitPattern: 0x8000000000000000);         input.vendor_id = 0x00016f73;         input.product_id = 0x00011717;         input.logical_width = Int64.min;         input.logical_height = Int64.max
        expectSource(input, 1, 0, 1, Int64.min, Int64.max)
    }
    // ordinary alias/source early return UINT32_MAX/UINT32_MAX
    do { var input = sourceInput()
        input.core_graphics_logical_width = Int64.min;         input.core_graphics_logical_height = Int64.max;         input.core_graphics_pixel_width = Int64.min;         input.core_graphics_pixel_height = Int64.max;         input.filter_content_width = Double(bitPattern: 0x7ff80000000000a5);         input.filter_content_height = Double(bitPattern: 0x7ff0000000000000);         input.point_pixel_scale = Double(bitPattern: 0x8000000000000000);         input.vendor_id = UInt32.max;         input.product_id = UInt32.max;         input.logical_width = Int64.min;         input.logical_height = Int64.max
        expectSource(input, 1, 0, 1, Int64.min, Int64.max)
    }
    // owned exact current framebuffer
    do { var input = sourceInput()

        expectSource(input, 1, 1, 1, 1170, 2532)
    }
    // second owned product exact current framebuffer
    do { var input = sourceInput()
        input.product_id = 0x1718
        expectSource(input, 1, 1, 1, 1170, 2532)
    }
    // owned minimum inclusive
    do { var input = sourceInput()
        input.logical_width = 2;         input.logical_height = 2;         input.core_graphics_logical_width = 2;         input.core_graphics_logical_height = 2;         input.core_graphics_pixel_width = 2;         input.core_graphics_pixel_height = 2;         input.filter_content_width = 2.0;         input.filter_content_height = 2.0;         input.point_pixel_scale = 1.0
        expectSource(input, 1, 1, 1, 2, 2)
    }
    // owned maximum inclusive
    do { var input = sourceInput()
        input.logical_width = 32768;         input.logical_height = 32768;         input.core_graphics_logical_width = 32768;         input.core_graphics_logical_height = 32768;         input.core_graphics_pixel_width = 32768;         input.core_graphics_pixel_height = 32768;         input.filter_content_width = 32768.0;         input.filter_content_height = 32768.0;         input.point_pixel_scale = 4.0
        expectSource(input, 1, 1, 1, 32768, 32768)
    }
    // owned odd framebuffer has no chroma/output rounding
    do { var input = sourceInput()
        input.logical_width = 2;         input.logical_height = 2;         input.core_graphics_logical_width = 2;         input.core_graphics_logical_height = 2;         input.core_graphics_pixel_width = 3;         input.core_graphics_pixel_height = 5;         input.filter_content_width = 2.0;         input.filter_content_height = 2.0;         input.point_pixel_scale = 4.0
        expectSource(input, 1, 1, 1, 3, 5)
    }
    // owned refuses logical_width=1
    do { var input = sourceInput()
        input.logical_width = 1
        expectSource(input, 1, 1, 0, 0, 0)
    }
    // owned refuses logical_width=32769
    do { var input = sourceInput()
        input.logical_width = 32769
        expectSource(input, 1, 1, 0, 0, 0)
    }
    // owned refuses logical_height=1
    do { var input = sourceInput()
        input.logical_height = 1
        expectSource(input, 1, 1, 0, 0, 0)
    }
    // owned refuses logical_height=32769
    do { var input = sourceInput()
        input.logical_height = 32769
        expectSource(input, 1, 1, 0, 0, 0)
    }
    // owned refuses core_graphics_logical_width=1
    do { var input = sourceInput()
        input.core_graphics_logical_width = 1
        expectSource(input, 1, 1, 0, 0, 0)
    }
    // owned refuses core_graphics_logical_width=32769
    do { var input = sourceInput()
        input.core_graphics_logical_width = 32769
        expectSource(input, 1, 1, 0, 0, 0)
    }
    // owned refuses core_graphics_logical_height=1
    do { var input = sourceInput()
        input.core_graphics_logical_height = 1
        expectSource(input, 1, 1, 0, 0, 0)
    }
    // owned refuses core_graphics_logical_height=32769
    do { var input = sourceInput()
        input.core_graphics_logical_height = 32769
        expectSource(input, 1, 1, 0, 0, 0)
    }
    // owned refuses core_graphics_pixel_width=1
    do { var input = sourceInput()
        input.core_graphics_pixel_width = 1
        expectSource(input, 1, 1, 0, 0, 0)
    }
    // owned refuses core_graphics_pixel_width=32769
    do { var input = sourceInput()
        input.core_graphics_pixel_width = 32769
        expectSource(input, 1, 1, 0, 0, 0)
    }
    // owned refuses core_graphics_pixel_height=1
    do { var input = sourceInput()
        input.core_graphics_pixel_height = 1
        expectSource(input, 1, 1, 0, 0, 0)
    }
    // owned refuses core_graphics_pixel_height=32769
    do { var input = sourceInput()
        input.core_graphics_pixel_height = 32769
        expectSource(input, 1, 1, 0, 0, 0)
    }
    // owned refuses nonfinite filter_content_width 0x7ff80000000000a5
    do { var input = sourceInput()
        input.filter_content_width = Double(bitPattern: 0x7ff80000000000a5)
        expectSource(input, 1, 1, 0, 0, 0)
    }
    // owned refuses nonfinite filter_content_width 0x7ff0000000000000
    do { var input = sourceInput()
        input.filter_content_width = Double(bitPattern: 0x7ff0000000000000)
        expectSource(input, 1, 1, 0, 0, 0)
    }
    // owned refuses nonfinite filter_content_width 0xfff0000000000000
    do { var input = sourceInput()
        input.filter_content_width = Double(bitPattern: 0xfff0000000000000)
        expectSource(input, 1, 1, 0, 0, 0)
    }
    // owned refuses nonfinite filter_content_height 0x7ff80000000000a5
    do { var input = sourceInput()
        input.filter_content_height = Double(bitPattern: 0x7ff80000000000a5)
        expectSource(input, 1, 1, 0, 0, 0)
    }
    // owned refuses nonfinite filter_content_height 0x7ff0000000000000
    do { var input = sourceInput()
        input.filter_content_height = Double(bitPattern: 0x7ff0000000000000)
        expectSource(input, 1, 1, 0, 0, 0)
    }
    // owned refuses nonfinite filter_content_height 0xfff0000000000000
    do { var input = sourceInput()
        input.filter_content_height = Double(bitPattern: 0xfff0000000000000)
        expectSource(input, 1, 1, 0, 0, 0)
    }
    // owned refuses nonfinite point_pixel_scale 0x7ff80000000000a5
    do { var input = sourceInput()
        input.point_pixel_scale = Double(bitPattern: 0x7ff80000000000a5)
        expectSource(input, 1, 1, 0, 0, 0)
    }
    // owned refuses nonfinite point_pixel_scale 0x7ff0000000000000
    do { var input = sourceInput()
        input.point_pixel_scale = Double(bitPattern: 0x7ff0000000000000)
        expectSource(input, 1, 1, 0, 0, 0)
    }
    // owned refuses nonfinite point_pixel_scale 0xfff0000000000000
    do { var input = sourceInput()
        input.point_pixel_scale = Double(bitPattern: 0xfff0000000000000)
        expectSource(input, 1, 1, 0, 0, 0)
    }
    // owned scale literal {"bits":"0x3fefffffffffffff"}
    do { var input = sourceInput()
        input.point_pixel_scale = Double(bitPattern: 0x3fefffffffffffff)
        expectSource(input, 1, 1, 0, 0, 0)
    }
    // owned scale literal "1.0"
    do { var input = sourceInput()
        input.point_pixel_scale = 1.0
        expectSource(input, 1, 1, 1, 1170, 2532)
    }
    // owned scale literal "4.0"
    do { var input = sourceInput()
        input.point_pixel_scale = 4.0
        expectSource(input, 1, 1, 1, 1170, 2532)
    }
    // owned scale literal {"bits":"0x4010000000000001"}
    do { var input = sourceInput()
        input.point_pixel_scale = Double(bitPattern: 0x4010000000000001)
        expectSource(input, 1, 1, 0, 0, 0)
    }
    // owned half-pixel literal filter_content_width 0x4078580000000000
    do { var input = sourceInput()
        input.filter_content_width = Double(bitPattern: 0x4078580000000000)
        expectSource(input, 1, 1, 1, 1170, 2532)
    }
    // owned half-pixel literal filter_content_width 0x407857ffffffffff
    do { var input = sourceInput()
        input.filter_content_width = Double(bitPattern: 0x407857ffffffffff)
        expectSource(input, 1, 1, 0, 0, 0)
    }
    // owned half-pixel literal filter_content_width 0x4078680000000000
    do { var input = sourceInput()
        input.filter_content_width = Double(bitPattern: 0x4078680000000000)
        expectSource(input, 1, 1, 1, 1170, 2532)
    }
    // owned half-pixel literal filter_content_width 0x4078680000000001
    do { var input = sourceInput()
        input.filter_content_width = Double(bitPattern: 0x4078680000000001)
        expectSource(input, 1, 1, 0, 0, 0)
    }
    // owned half-pixel literal filter_content_height 0x408a5c0000000000
    do { var input = sourceInput()
        input.filter_content_height = Double(bitPattern: 0x408a5c0000000000)
        expectSource(input, 1, 1, 1, 1170, 2532)
    }
    // owned half-pixel literal filter_content_height 0x408a5bffffffffff
    do { var input = sourceInput()
        input.filter_content_height = Double(bitPattern: 0x408a5bffffffffff)
        expectSource(input, 1, 1, 0, 0, 0)
    }
    // owned half-pixel literal filter_content_height 0x408a640000000000
    do { var input = sourceInput()
        input.filter_content_height = Double(bitPattern: 0x408a640000000000)
        expectSource(input, 1, 1, 1, 1170, 2532)
    }
    // owned half-pixel literal filter_content_height 0x408a640000000001
    do { var input = sourceInput()
        input.filter_content_height = Double(bitPattern: 0x408a640000000001)
        expectSource(input, 1, 1, 0, 0, 0)
    }
    // signed exact stability
    do { var input = DisplayStability(); input.abi_version = 1; input.before_width = Int64.min; input.before_height = Int64.max; input.after_width = Int64.min; input.after_height = Int64.max
        input.before_width = Int64.min;         input.before_height = Int64.max;         input.after_width = Int64.min;         input.after_height = Int64.max
        expectStable(input, 1, 1)
    }
    // signed exact stability
    do { var input = DisplayStability(); input.abi_version = 1; input.before_width = Int64.min; input.before_height = Int64.max; input.after_width = Int64.min; input.after_height = Int64.max
        input.before_width = Int64.min;         input.before_height = Int64.max;         input.after_width = Int64.min;         input.after_height = 0
        expectStable(input, 1, 0)
    }
    // signed exact stability
    do { var input = DisplayStability(); input.abi_version = 1; input.before_width = Int64.min; input.before_height = Int64.max; input.after_width = Int64.min; input.after_height = Int64.max
        input.before_width = Int64.min;         input.before_height = Int64.max;         input.after_width = 0;         input.after_height = Int64.max
        expectStable(input, 1, 0)
    }
    // signed exact stability
    do { var input = DisplayStability(); input.abi_version = 1; input.before_width = Int64.min; input.before_height = Int64.max; input.after_width = Int64.min; input.after_height = Int64.max
        input.before_width = 0;         input.before_height = 0;         input.after_width = 0;         input.after_height = 0
        expectStable(input, 1, 1)
    }
    // signed exact stability
    do { var input = DisplayStability(); input.abi_version = 1; input.before_width = Int64.min; input.before_height = Int64.max; input.after_width = Int64.min; input.after_height = Int64.max
        input.before_width = -1;         input.before_height = 1;         input.after_width = -1;         input.after_height = 1
        expectStable(input, 1, 1)
    }
    // signed exact stability
    do { var input = DisplayStability(); input.abi_version = 1; input.before_width = Int64.min; input.before_height = Int64.max; input.after_width = Int64.min; input.after_height = Int64.max
        input.before_width = 32769;         input.before_height = -32769;         input.after_width = 32769;         input.after_height = -32769
        expectStable(input, 1, 1)
    }
    // independent envelope abi_version=0
    do { var input = requirementInput()
        input.abi_version = 0
        expectRequirement(input, 0, 0)
    }
    // independent envelope abi_version=2
    do { var input = requirementInput()
        input.abi_version = 2
        expectRequirement(input, 0, 0)
    }
    // independent envelope abi_version=UINT32_MAX
    do { var input = requirementInput()
        input.abi_version = UInt32.max
        expectRequirement(input, 0, 0)
    }
    // independent envelope reserved=1
    do { var input = requirementInput()
        input.reserved = 1
        expectRequirement(input, 0, 0)
    }
    // independent envelope reserved=2
    do { var input = requirementInput()
        input.reserved = 2
        expectRequirement(input, 0, 0)
    }
    // independent envelope reserved=UINT32_MAX
    do { var input = requirementInput()
        input.reserved = UInt32.max
        expectRequirement(input, 0, 0)
    }
    // independent envelope abi_version=0
    do { var input = DisplayKind(); input.abi_version = 1; input.vendor_id = 0x6f73; input.product_id = 0x1717
        input.abi_version = 0
        expectKind(input, 0, 0)
    }
    // independent envelope abi_version=2
    do { var input = DisplayKind(); input.abi_version = 1; input.vendor_id = 0x6f73; input.product_id = 0x1717
        input.abi_version = 2
        expectKind(input, 0, 0)
    }
    // independent envelope abi_version=UINT32_MAX
    do { var input = DisplayKind(); input.abi_version = 1; input.vendor_id = 0x6f73; input.product_id = 0x1717
        input.abi_version = UInt32.max
        expectKind(input, 0, 0)
    }
    // independent envelope reserved=1
    do { var input = DisplayKind(); input.abi_version = 1; input.vendor_id = 0x6f73; input.product_id = 0x1717
        input.reserved = 1
        expectKind(input, 0, 0)
    }
    // independent envelope reserved=2
    do { var input = DisplayKind(); input.abi_version = 1; input.vendor_id = 0x6f73; input.product_id = 0x1717
        input.reserved = 2
        expectKind(input, 0, 0)
    }
    // independent envelope reserved=UINT32_MAX
    do { var input = DisplayKind(); input.abi_version = 1; input.vendor_id = 0x6f73; input.product_id = 0x1717
        input.reserved = UInt32.max
        expectKind(input, 0, 0)
    }
    // independent envelope abi_version=0
    do { var input = sourceInput()
        input.abi_version = 0
        expectSource(input, 0, 0, 0, 0, 0)
    }
    // independent envelope abi_version=2
    do { var input = sourceInput()
        input.abi_version = 2
        expectSource(input, 0, 0, 0, 0, 0)
    }
    // independent envelope abi_version=UINT32_MAX
    do { var input = sourceInput()
        input.abi_version = UInt32.max
        expectSource(input, 0, 0, 0, 0, 0)
    }
    // independent envelope reserved=1
    do { var input = sourceInput()
        input.reserved = 1
        expectSource(input, 0, 0, 0, 0, 0)
    }
    // independent envelope reserved=2
    do { var input = sourceInput()
        input.reserved = 2
        expectSource(input, 0, 0, 0, 0, 0)
    }
    // independent envelope reserved=UINT32_MAX
    do { var input = sourceInput()
        input.reserved = UInt32.max
        expectSource(input, 0, 0, 0, 0, 0)
    }
    // independent envelope abi_version=0
    do { var input = DisplayStability(); input.abi_version = 1; input.before_width = Int64.min; input.before_height = Int64.max; input.after_width = Int64.min; input.after_height = Int64.max
        input.abi_version = 0
        expectStable(input, 0, 0)
    }
    // independent envelope abi_version=2
    do { var input = DisplayStability(); input.abi_version = 1; input.before_width = Int64.min; input.before_height = Int64.max; input.after_width = Int64.min; input.after_height = Int64.max
        input.abi_version = 2
        expectStable(input, 0, 0)
    }
    // independent envelope abi_version=UINT32_MAX
    do { var input = DisplayStability(); input.abi_version = 1; input.before_width = Int64.min; input.before_height = Int64.max; input.after_width = Int64.min; input.after_height = Int64.max
        input.abi_version = UInt32.max
        expectStable(input, 0, 0)
    }
    // independent envelope reserved=1
    do { var input = DisplayStability(); input.abi_version = 1; input.before_width = Int64.min; input.before_height = Int64.max; input.after_width = Int64.min; input.after_height = Int64.max
        input.reserved = 1
        expectStable(input, 0, 0)
    }
    // independent envelope reserved=2
    do { var input = DisplayStability(); input.abi_version = 1; input.before_width = Int64.min; input.before_height = Int64.max; input.after_width = Int64.min; input.after_height = Int64.max
        input.reserved = 2
        expectStable(input, 0, 0)
    }
    // independent envelope reserved=UINT32_MAX
    do { var input = DisplayStability(); input.abi_version = 1; input.before_width = Int64.min; input.before_height = Int64.max; input.after_width = Int64.min; input.after_height = Int64.max
        input.reserved = UInt32.max
        expectStable(input, 0, 0)
    }
    // envelope precedes ordinary branch abi_version
    do { var input = sourceInput()
        input.vendor_id = 0;         input.core_graphics_logical_width = Int64.min;         input.core_graphics_logical_height = Int64.max;         input.core_graphics_pixel_width = Int64.min;         input.core_graphics_pixel_height = Int64.max;         input.filter_content_width = Double(bitPattern: 0x7ff80000000000a5);         input.filter_content_height = Double(bitPattern: 0x7ff0000000000000);         input.point_pixel_scale = Double(bitPattern: 0x8000000000000000);         input.logical_width = Int64.min;         input.logical_height = Int64.max;         input.abi_version = 0
        expectSource(input, 0, 0, 0, 0, 0)
    }
    // envelope precedes ordinary branch reserved
    do { var input = sourceInput()
        input.vendor_id = 0;         input.core_graphics_logical_width = Int64.min;         input.core_graphics_logical_height = Int64.max;         input.core_graphics_pixel_width = Int64.min;         input.core_graphics_pixel_height = Int64.max;         input.filter_content_width = Double(bitPattern: 0x7ff80000000000a5);         input.filter_content_height = Double(bitPattern: 0x7ff0000000000000);         input.point_pixel_scale = Double(bitPattern: 0x8000000000000000);         input.logical_width = Int64.min;         input.logical_height = Int64.max;         input.reserved = 1
        expectSource(input, 0, 0, 0, 0, 0)
    }
    // envelope precedes legitimate owned absence abi_version
    do { var input = sourceInput()
        input.logical_width = 1;         input.abi_version = 0
        expectSource(input, 0, 0, 0, 0, 0)
    }
    // envelope precedes legitimate owned absence reserved
    do { var input = sourceInput()
        input.logical_width = 1;         input.reserved = 1
        expectSource(input, 0, 0, 0, 0, 0)
    }
    // ordinary ignores three distinct NaN payloads
    do { var input = sourceInput()
        input.vendor_id = 0;         input.logical_width = Int64.max;         input.logical_height = Int64.min;         input.filter_content_width = Double(bitPattern: 0x7ff80000000000a5);         input.filter_content_height = Double(bitPattern: 0xfff800000000005a);         input.point_pixel_scale = Double(bitPattern: 0x7ff8000000000001)
        expectSource(input, 1, 0, 1, Int64.max, Int64.min)
    }
    // ordinary ignores positive and negative signed zero
    do { var input = sourceInput()
        input.vendor_id = 0;         input.logical_width = -1;         input.logical_height = 1;         input.filter_content_width = Double(bitPattern: 0x8000000000000000);         input.filter_content_height = Double(bitPattern: 0x0000000000000000);         input.point_pixel_scale = Double(bitPattern: 0x8000000000000000)
        expectSource(input, 1, 0, 1, -1, 1)
    }
    print("BelugaCore Swift display admission import/link PASS: exact layouts, native branch order, signed endpoints and unchanged refusals")
}
displayAdmissionSmoke()

// Output dimensions: actual imported copied ABI only, no native capture effects.
func outputDimensionsSmoke() {
    typealias OutputFacts = beluga_core_output_dimensions_facts_t
    typealias OutputDecision = beluga_core_output_dimensions_decision_t
    precondition(MemoryLayout<OutputFacts>.size == 32 && MemoryLayout<OutputFacts>.stride == 32 && MemoryLayout<OutputFacts>.alignment == 8)
    precondition(MemoryLayout<OutputFacts>.offset(of: \OutputFacts.abi_version) == 0)
    precondition(MemoryLayout<OutputFacts>.offset(of: \OutputFacts.reserved) == 4)
    precondition(MemoryLayout<OutputFacts>.offset(of: \OutputFacts.source_width) == 8)
    precondition(MemoryLayout<OutputFacts>.offset(of: \OutputFacts.source_height) == 16)
    precondition(MemoryLayout<OutputFacts>.offset(of: \OutputFacts.maximum_width) == 24)
    precondition(MemoryLayout<OutputDecision>.size == 40 && MemoryLayout<OutputDecision>.stride == 40 && MemoryLayout<OutputDecision>.alignment == 8)
    precondition(MemoryLayout<OutputDecision>.offset(of: \OutputDecision.abi_version) == 0)
    precondition(MemoryLayout<OutputDecision>.offset(of: \OutputDecision.status) == 4)
    precondition(MemoryLayout<OutputDecision>.offset(of: \OutputDecision.decision) == 8)
    precondition(MemoryLayout<OutputDecision>.offset(of: \OutputDecision.reserved) == 12)
    precondition(MemoryLayout<OutputDecision>.offset(of: \OutputDecision.width) == 16)
    precondition(MemoryLayout<OutputDecision>.offset(of: \OutputDecision.height) == 24)
    precondition(MemoryLayout<OutputDecision>.offset(of: \OutputDecision.rounded_height_bits) == 32)
    func copiedWords(_ input: OutputFacts) -> [UInt64] {
        [UInt64(input.abi_version), UInt64(input.reserved),
         UInt64(bitPattern: input.source_width), UInt64(bitPattern: input.source_height),
         UInt64(bitPattern: input.maximum_width)]
    }
    func expect(_ version: UInt32, _ reserved: UInt32, _ sourceWidth: Int64,
                _ sourceHeight: Int64, _ maximumWidth: Int64, _ status: UInt32,
                _ decision: UInt32, _ width: Int64, _ height: Int64, _ roundedBits: UInt64) {
        var input = OutputFacts()
        input.abi_version = version; input.reserved = reserved
        input.source_width = sourceWidth; input.source_height = sourceHeight; input.maximum_width = maximumWidth
        let before = copiedWords(input)
        let actual = beluga_core_output_dimensions(input)
        precondition(copiedWords(input) == before)
        precondition(actual.abi_version == 1 && actual.status == status && actual.decision == decision)
        precondition(actual.reserved == 0 && actual.width == width && actual.height == height)
        precondition(actual.rounded_height_bits == roundedBits)
    }
    // phone-retina
    expect(1, 0, 1206, 2622, 1920,
           1, 1, 1206, 2622, 0x40a47c0000000000)
    // landscape
    expect(1, 0, 3840, 2160, 1920,
           1, 1, 1920, 1080, 0x4090e00000000000)
    // odd-full-frame
    expect(1, 0, 1205, 2621, 1920,
           1, 1, 1204, 2618, 0x40a4760000000000)
    // half-scale
    expect(1, 0, 603, 1312, 1920,
           1, 1, 602, 1310, 0x4094780000000000)
    // odd-cap
    expect(1, 0, 7, 11, 5,
           1, 1, 4, 6, 0x4018000000000000)
    // positive-half-up
    expect(1, 0, 4, 7, 2,
           1, 1, 2, 4, 0x4010000000000000)
    // positive-half-chroma
    expect(1, 0, 4, 5, 2,
           1, 1, 2, 2, 0x4008000000000000)
    // nearest-upper
    expect(1, 0, 100, 99, 20,
           1, 1, 20, 20, 0x4034000000000000)
    // nearest-lower
    expect(1, 0, 100, 91, 20,
           1, 1, 20, 18, 0x4032000000000000)
    // nearest-chroma
    expect(1, 0, 100, 96, 20,
           1, 1, 20, 18, 0x4033000000000000)
    // floor-zero
    expect(1, 0, 100, 11, 2,
           1, 1, 2, 2, 0x0000000000000000)
    // floor-one
    expect(1, 0, 100, 26, 2,
           1, 1, 2, 2, 0x3ff0000000000000)
    // cap-small
    expect(1, 0, 4, 6, 2,
           1, 1, 2, 2, 0x4008000000000000)
    // cap-exact
    expect(1, 0, 4, 6, 4,
           1, 1, 4, 6, 0x4018000000000000)
    // cap-no-upscale
    expect(1, 0, 4, 6, 100,
           1, 1, 4, 6, 0x4018000000000000)
    // width-chroma-before-scale
    expect(1, 0, 7, 14, 5,
           1, 1, 4, 8, 0x4020000000000000)
    // source-chroma-before-scale
    expect(1, 0, 5, 10, 20,
           1, 1, 4, 8, 0x4020000000000000)
    // third-width
    expect(1, 0, 3, 9, 3,
           1, 1, 2, 6, 0x4018000000000000)
    // larger-half-up
    expect(1, 0, 400, 699, 200,
           1, 1, 200, 350, 0x4075e00000000000)
    // larger-half-even-chroma
    expect(1, 0, 400, 698, 200,
           1, 1, 200, 348, 0x4075d00000000000)
    // integer-ratio-is-not-policy
    expect(1, 0, 5, 9, 4,
           1, 1, 4, 6, 0x401c000000000000)
    // wide-signed-min-height
    expect(1, 0, 9223372036854775807, 2, 2,
           1, 1, 2, 2, 0x0000000000000000)
    // wide-signed-no-arbitrary-cap
    expect(1, 0, 9223372036854775807, 2, 9223372036854775807,
           1, 1, 9223372036854775806, 2, 0x4000000000000000)
    // source-width-high-u16
    expect(1, 0, 65538, 6, 2,
           1, 1, 2, 2, 0x0000000000000000)
    // source-width-high-u32
    expect(1, 0, 4294967298, 6, 2,
           1, 1, 2, 2, 0x0000000000000000)
    // source-height-high-u32
    expect(1, 0, 2, 4294967297, 2,
           1, 1, 2, 4294967296, 0x41f0000000100000)
    // cap-high-u16
    expect(1, 0, 8, 16, 65538,
           1, 1, 8, 16, 0x4030000000000000)
    // cap-high-u32
    expect(1, 0, 8, 16, 4294967298,
           1, 1, 8, 16, 0x4030000000000000)
    // height-2pow53-plus1
    expect(1, 0, 2, 9007199254740993, 2,
           1, 1, 2, 9007199254740992, 0x4340000000000000)
    // height-2pow53-plus3
    expect(1, 0, 2, 9007199254740995, 2,
           1, 1, 2, 9007199254740996, 0x4340000000000002)
    // upper-minus1024
    expect(1, 0, 2, 9223372036854774783, 2,
           1, 1, 2, 9223372036854774784, 0x43dfffffffffffff)
    // upper-representable-adjacent
    expect(1, 0, 2, 9223372036854775295, 2,
           1, 1, 2, 9223372036854774784, 0x43dfffffffffffff)
    // upper-minus1023
    expect(1, 0, 2, 9223372036854774784, 2,
           1, 1, 2, 9223372036854774784, 0x43dfffffffffffff)
    // height-maximum-width-three
    expect(1, 0, 3, 9223372036854775807, 2,
           1, 1, 2, 6148914691236516864, 0x43d5555555555555)
    // upper-distinct-refusal
    expect(1, 0, 2, 9223372036854775807, 2,
           1, 2, 2, 0, 0x43e0000000000000)
    // upper-midpoint-distinct-refusal
    expect(1, 0, 2, 9223372036854775296, 2,
           1, 2, 2, 0, 0x43e0000000000000)
    // maximum-triple-distinct-refusal
    expect(1, 0, 9223372036854775807, 9223372036854775807, 9223372036854775807,
           1, 2, 9223372036854775806, 0, 0x43e0000000000000)
    // invalid-slot-0--9223372036854775808
    expect(1, 0, Int64.min, 2, 2,
           1, 0, 0, 0, 0x0000000000000000)
    // invalid-slot-1--9223372036854775808
    expect(1, 0, 2, Int64.min, 2,
           1, 0, 0, 0, 0x0000000000000000)
    // invalid-slot-2--9223372036854775808
    expect(1, 0, 2, 2, Int64.min,
           1, 0, 0, 0, 0x0000000000000000)
    // invalid-slot-0--4294967296
    expect(1, 0, -4294967296, 2, 2,
           1, 0, 0, 0, 0x0000000000000000)
    // invalid-slot-1--4294967296
    expect(1, 0, 2, -4294967296, 2,
           1, 0, 0, 0, 0x0000000000000000)
    // invalid-slot-2--4294967296
    expect(1, 0, 2, 2, -4294967296,
           1, 0, 0, 0, 0x0000000000000000)
    // invalid-slot-0--1
    expect(1, 0, -1, 2, 2,
           1, 0, 0, 0, 0x0000000000000000)
    // invalid-slot-1--1
    expect(1, 0, 2, -1, 2,
           1, 0, 0, 0, 0x0000000000000000)
    // invalid-slot-2--1
    expect(1, 0, 2, 2, -1,
           1, 0, 0, 0, 0x0000000000000000)
    // invalid-slot-0-0
    expect(1, 0, 0, 2, 2,
           1, 0, 0, 0, 0x0000000000000000)
    // invalid-slot-1-0
    expect(1, 0, 2, 0, 2,
           1, 0, 0, 0, 0x0000000000000000)
    // invalid-slot-2-0
    expect(1, 0, 2, 2, 0,
           1, 0, 0, 0, 0x0000000000000000)
    // invalid-slot-0-1
    expect(1, 0, 1, 2, 2,
           1, 0, 0, 0, 0x0000000000000000)
    // invalid-slot-1-1
    expect(1, 0, 2, 1, 2,
           1, 0, 0, 0, 0x0000000000000000)
    // invalid-slot-2-1
    expect(1, 0, 2, 2, 1,
           1, 0, 0, 0, 0x0000000000000000)
    // unknown-abi-0
    expect(0, 0, 2, 2, 2,
           0, 0, 0, 0, 0x0000000000000000)
    // unknown-abi-2
    expect(2, 0, 2, 2, 2,
           0, 0, 0, 0, 0x0000000000000000)
    // unknown-abi-2147483649
    expect(2147483649, 0, 2, 2, 2,
           0, 0, 0, 0, 0x0000000000000000)
    // unknown-abi-4294967295
    expect(4294967295, 0, 2, 2, 2,
           0, 0, 0, 0, 0x0000000000000000)
    // nonzero-reserved-1
    expect(1, 1, 2, 2, 2,
           0, 0, 0, 0, 0x0000000000000000)
    // nonzero-reserved-2
    expect(1, 2, 2, 2, 2,
           0, 0, 0, 0, 0x0000000000000000)
    // nonzero-reserved-2147483648
    expect(1, 2147483648, 2, 2, 2,
           0, 0, 0, 0, 0x0000000000000000)
    // nonzero-reserved-4294967295
    expect(1, 4294967295, 2, 2, 2,
           0, 0, 0, 0, 0x0000000000000000)
    // unknown-envelope-before-invalid-dimensions
    expect(0, 0, Int64.min, 9223372036854775807, -1,
           0, 0, 0, 0, 0x0000000000000000)
    // reserved-before-former-trap
    expect(1, 1, 2, 9223372036854775807, 2,
           0, 0, 0, 0, 0x0000000000000000)
    print("BelugaCore Swift output dimensions import/link PASS: two layouts, twelve offsets, signed projection and distinct conversion refusal")
}
outputDimensionsSmoke()

// Private append body. Preserve all old Swift bytes and append one call before old footer.
func iceRecoverySmoke() {
    typealias S = beluga_core_ice_recovery_state_t
    typealias E = beluga_core_ice_recovery_event_t
    func state(_ v: [UInt64]) -> S {
        .init(abi_version: UInt32(v[0]), phase: UInt32(v[1]), epoch: v[2],
              attempts: Int64(bitPattern: v[3]), maximum_attempts: Int64(bitPattern: v[4]),
              exhaustion_delivered: UInt32(v[5]), grace_positive: UInt32(v[6]), cursor: UInt32(v[7]), reserved: UInt32(v[8]))
    }
    func stateWords(_ v: S) -> [UInt64] {
        [UInt64(v.abi_version), UInt64(v.phase), v.epoch, UInt64(bitPattern: v.attempts), UInt64(bitPattern: v.maximum_attempts),
         UInt64(v.exhaustion_delivered), UInt64(v.grace_positive), UInt64(v.cursor), UInt64(v.reserved)]
    }
    func event(_ v: [UInt64]) -> E {
        .init(abi_version: UInt32(v[0]), opcode: UInt32(v[1]), workflow_epoch: v[2], task_cancelled: UInt32(v[3]),
              succeeded: UInt32(v[4]), wait_kind: UInt32(v[5]), reserved: UInt32(v[6]))
    }
    func eventWords(_ v: E) -> [UInt64] {
        [UInt64(v.abi_version), UInt64(v.opcode), v.workflow_epoch, UInt64(v.task_cancelled),
         UInt64(v.succeeded), UInt64(v.wait_kind), UInt64(v.reserved)]
    }
    precondition(MemoryLayout<beluga_core_ice_recovery_config_t>.size == 16 && MemoryLayout<beluga_core_ice_recovery_config_t>.stride == 16 && MemoryLayout<beluga_core_ice_recovery_config_t>.alignment == 8)
    precondition(MemoryLayout<beluga_core_ice_recovery_config_t>.offset(of: \.maximum_attempts) == 0)
    precondition(MemoryLayout<beluga_core_ice_recovery_config_t>.offset(of: \.grace_positive) == 8)
    precondition(MemoryLayout<beluga_core_ice_recovery_config_t>.offset(of: \.reserved) == 12)
    precondition(MemoryLayout<beluga_core_ice_recovery_state_t>.size == 48 && MemoryLayout<beluga_core_ice_recovery_state_t>.stride == 48 && MemoryLayout<beluga_core_ice_recovery_state_t>.alignment == 8)
    precondition(MemoryLayout<beluga_core_ice_recovery_state_t>.offset(of: \.abi_version) == 0)
    precondition(MemoryLayout<beluga_core_ice_recovery_state_t>.offset(of: \.phase) == 4)
    precondition(MemoryLayout<beluga_core_ice_recovery_state_t>.offset(of: \.epoch) == 8)
    precondition(MemoryLayout<beluga_core_ice_recovery_state_t>.offset(of: \.attempts) == 16)
    precondition(MemoryLayout<beluga_core_ice_recovery_state_t>.offset(of: \.maximum_attempts) == 24)
    precondition(MemoryLayout<beluga_core_ice_recovery_state_t>.offset(of: \.exhaustion_delivered) == 32)
    precondition(MemoryLayout<beluga_core_ice_recovery_state_t>.offset(of: \.grace_positive) == 36)
    precondition(MemoryLayout<beluga_core_ice_recovery_state_t>.offset(of: \.cursor) == 40)
    precondition(MemoryLayout<beluga_core_ice_recovery_state_t>.offset(of: \.reserved) == 44)
    precondition(MemoryLayout<beluga_core_ice_recovery_event_t>.size == 32 && MemoryLayout<beluga_core_ice_recovery_event_t>.stride == 32 && MemoryLayout<beluga_core_ice_recovery_event_t>.alignment == 8)
    precondition(MemoryLayout<beluga_core_ice_recovery_event_t>.offset(of: \.abi_version) == 0)
    precondition(MemoryLayout<beluga_core_ice_recovery_event_t>.offset(of: \.opcode) == 4)
    precondition(MemoryLayout<beluga_core_ice_recovery_event_t>.offset(of: \.workflow_epoch) == 8)
    precondition(MemoryLayout<beluga_core_ice_recovery_event_t>.offset(of: \.task_cancelled) == 16)
    precondition(MemoryLayout<beluga_core_ice_recovery_event_t>.offset(of: \.succeeded) == 20)
    precondition(MemoryLayout<beluga_core_ice_recovery_event_t>.offset(of: \.wait_kind) == 24)
    precondition(MemoryLayout<beluga_core_ice_recovery_event_t>.offset(of: \.reserved) == 28)
    precondition(MemoryLayout<beluga_core_ice_recovery_init_result_t>.size == 72 && MemoryLayout<beluga_core_ice_recovery_init_result_t>.stride == 72 && MemoryLayout<beluga_core_ice_recovery_init_result_t>.alignment == 8)
    precondition(MemoryLayout<beluga_core_ice_recovery_init_result_t>.offset(of: \.status) == 0)
    precondition(MemoryLayout<beluga_core_ice_recovery_init_result_t>.offset(of: \.reserved) == 4)
    precondition(MemoryLayout<beluga_core_ice_recovery_init_result_t>.offset(of: \.copied_config) == 8)
    precondition(MemoryLayout<beluga_core_ice_recovery_init_result_t>.offset(of: \.candidate_state) == 24)
    precondition(MemoryLayout<beluga_core_ice_recovery_result_t>.size == 152 && MemoryLayout<beluga_core_ice_recovery_result_t>.stride == 152 && MemoryLayout<beluga_core_ice_recovery_result_t>.alignment == 8)
    precondition(MemoryLayout<beluga_core_ice_recovery_result_t>.offset(of: \.abi_version) == 0)
    precondition(MemoryLayout<beluga_core_ice_recovery_result_t>.offset(of: \.status) == 4)
    precondition(MemoryLayout<beluga_core_ice_recovery_result_t>.offset(of: \.copied_before) == 8)
    precondition(MemoryLayout<beluga_core_ice_recovery_result_t>.offset(of: \.copied_event) == 56)
    precondition(MemoryLayout<beluga_core_ice_recovery_result_t>.offset(of: \.candidate_state) == 88)
    precondition(MemoryLayout<beluga_core_ice_recovery_result_t>.offset(of: \.effect) == 136)
    precondition(MemoryLayout<beluga_core_ice_recovery_result_t>.offset(of: \.flags) == 140)
    precondition(MemoryLayout<beluga_core_ice_recovery_result_t>.offset(of: \.reserved) == 144)
    let config = beluga_core_ice_recovery_config_t(maximum_attempts: Int64.max, grace_positive: 1, reserved: 0)
    let initial = beluga_core_ice_recovery_initialize(1, config)
    precondition(initial.status == 0 && initial.reserved == 0)
    precondition(initial.copied_config.maximum_attempts == Int64.max && initial.copied_config.grace_positive == 1 && initial.copied_config.reserved == 0)
    precondition(stateWords(initial.candidate_state) == [1,0,0,0,9223372036854775807,0,1,0,0])
    let denied = beluga_core_ice_recovery_initialize(0x10001, config)
    precondition(denied.status == 1 && denied.reserved == 0)
    precondition(denied.copied_config.maximum_attempts == Int64.max && denied.copied_config.grace_positive == 1 && denied.copied_config.reserved == 0)
    precondition(stateWords(denied.candidate_state) == [0,0,0,0,0,0,0,0,0])
    func row(_ abi: UInt32, _ b: [UInt64], _ e: [UInt64], _ status: UInt32, _ a: [UInt64], _ effect: UInt32, _ flags: UInt32) {
        let out = beluga_core_ice_recovery_step(abi, state(b), event(e))
        precondition(out.abi_version == 1 && out.status == status && out.effect == effect && out.flags == flags && out.reserved == 0)
        precondition(stateWords(out.copied_before) == b && eventWords(out.copied_event) == e && stateWords(out.candidate_state) == a)
    }
    row(1, [1,0,18446744073709551615,0,9223372036854775807,0,1,0,0], [1,8,0,0,0,0,0], 0, [1,2,0,0,9223372036854775807,0,1,1,0], 1, 1)
    row(1, [1,2,0,0,9223372036854775807,0,1,1,0], [1,10,0,0,0,0,0], 0, [1,2,0,0,9223372036854775807,0,1,2,0], 2, 0)
    row(1, [1,2,0,0,9223372036854775807,0,1,2,0], [1,11,0,0,0,0,0], 0, [1,2,0,1,9223372036854775807,0,1,3,0], 3, 0)
    row(1, [1,2,0,1,9223372036854775807,0,1,3,0], [1,12,0,0,0,0,0], 0, [1,2,0,1,9223372036854775807,0,1,6,0], 10, 0)
    row(1, [1,2,0,9223372036854775807,9223372036854775807,0,1,6,0], [1,15,0,0,0,0,0], 0, [1,2,0,9223372036854775807,9223372036854775807,0,1,7,0], 11, 0)
    row(1, [1,2,0,9223372036854775807,9223372036854775807,0,1,7,0], [1,16,0,0,0,0,0], 0, [1,5,0,9223372036854775807,9223372036854775807,1,1,8,0], 12, 0)
    row(1, [1,5,0,9223372036854775807,9223372036854775807,1,1,8,0], [1,17,0,1,0,0,0], 0, [1,5,0,9223372036854775807,9223372036854775807,1,1,0,0], 14, 0)
    row(1, [1,2,0,0,9223372036854775807,0,1,1,0], [1,10,0,2,0,0,0], 3, [1,2,0,0,9223372036854775807,0,1,1,0], 0, 0)
    row(65537, [1,2,0,0,9223372036854775807,0,1,1,0], [1,10,0,0,0,0,0], 1, [1,2,0,0,9223372036854775807,0,1,1,0], 0, 0)
    row(1, [1,0,18446744073709551615,9223372036854775808,9223372036854775807,0,1,0,0], [1,8,0,0,0,0,0], 2, [1,0,18446744073709551615,9223372036854775808,9223372036854775807,0,1,0,0], 0, 0)
    print("BelugaCore Swift ICE recovery import/link PASS: five layouts, thirty-one offsets and full-width transactional transitions")
}

iceRecoverySmoke()

// Authored-only architecture smoke addition; not executed/cross-linked here.
import BelugaCore

func screenLivenessSmoke() {
    precondition(MemoryLayout<beluga_core_screen_liveness_optional_t>.size == 16)
    precondition(MemoryLayout<beluga_core_screen_liveness_optional_t>.stride == 16)
    precondition(MemoryLayout<beluga_core_screen_liveness_optional_t>.alignment == 8)
    precondition(MemoryLayout<beluga_core_screen_liveness_optional_t>.offset(of: \.present) == 0)
    precondition(MemoryLayout<beluga_core_screen_liveness_optional_t>.offset(of: \.value) == 8)
    precondition(MemoryLayout<beluga_core_screen_liveness_sample_t>.size == 192)
    precondition(MemoryLayout<beluga_core_screen_liveness_sample_t>.stride == 192)
    precondition(MemoryLayout<beluga_core_screen_liveness_sample_t>.alignment == 8)
    precondition(MemoryLayout<beluga_core_screen_liveness_sample_t>.offset(of: \.generation) == 0)
    precondition(MemoryLayout<beluga_core_screen_liveness_sample_t>.offset(of: \.observed_at) == 8)
    precondition(MemoryLayout<beluga_core_screen_liveness_sample_t>.offset(of: \.track_attached) == 16)
    precondition(MemoryLayout<beluga_core_screen_liveness_sample_t>.offset(of: \.cover) == 24)
    precondition(MemoryLayout<beluga_core_screen_liveness_sample_t>.offset(of: \.inbound_present) == 32)
    precondition(MemoryLayout<beluga_core_screen_liveness_sample_t>.offset(of: \.inbound_bytes) == 40)
    precondition(MemoryLayout<beluga_core_screen_liveness_sample_t>.offset(of: \.inbound_packets) == 56)
    precondition(MemoryLayout<beluga_core_screen_liveness_sample_t>.offset(of: \.decoded_frames) == 72)
    precondition(MemoryLayout<beluga_core_screen_liveness_sample_t>.offset(of: \.inbound_width) == 88)
    precondition(MemoryLayout<beluga_core_screen_liveness_sample_t>.offset(of: \.inbound_height) == 104)
    precondition(MemoryLayout<beluga_core_screen_liveness_sample_t>.offset(of: \.frames_per_second_bits) == 120)
    precondition(MemoryLayout<beluga_core_screen_liveness_sample_t>.offset(of: \.render_present) == 136)
    precondition(MemoryLayout<beluga_core_screen_liveness_sample_t>.offset(of: \.presented_frames) == 144)
    precondition(MemoryLayout<beluga_core_screen_liveness_sample_t>.offset(of: \.content_samples) == 152)
    precondition(MemoryLayout<beluga_core_screen_liveness_sample_t>.offset(of: \.content_changes) == 160)
    precondition(MemoryLayout<beluga_core_screen_liveness_sample_t>.offset(of: \.presented_at) == 168)
    precondition(MemoryLayout<beluga_core_screen_liveness_sample_t>.offset(of: \.render_width_bits) == 176)
    precondition(MemoryLayout<beluga_core_screen_liveness_sample_t>.offset(of: \.render_height_bits) == 184)
    precondition(MemoryLayout<beluga_core_screen_liveness_state_t>.size == 216)
    precondition(MemoryLayout<beluga_core_screen_liveness_state_t>.stride == 216)
    precondition(MemoryLayout<beluga_core_screen_liveness_state_t>.alignment == 8)
    precondition(MemoryLayout<beluga_core_screen_liveness_state_t>.offset(of: \.previous_present) == 0)
    precondition(MemoryLayout<beluga_core_screen_liveness_state_t>.offset(of: \.last_change_at) == 8)
    precondition(MemoryLayout<beluga_core_screen_liveness_state_t>.offset(of: \.previous) == 24)
    precondition(MemoryLayout<beluga_core_screen_liveness_snapshot_t>.size == 296)
    precondition(MemoryLayout<beluga_core_screen_liveness_snapshot_t>.stride == 296)
    precondition(MemoryLayout<beluga_core_screen_liveness_snapshot_t>.alignment == 8)
    precondition(MemoryLayout<beluga_core_screen_liveness_snapshot_t>.offset(of: \.liveness) == 0)
    precondition(MemoryLayout<beluga_core_screen_liveness_snapshot_t>.offset(of: \.reset_reason) == 8)
    precondition(MemoryLayout<beluga_core_screen_liveness_snapshot_t>.offset(of: \.generation) == 16)
    precondition(MemoryLayout<beluga_core_screen_liveness_snapshot_t>.offset(of: \.track_attached) == 24)
    precondition(MemoryLayout<beluga_core_screen_liveness_snapshot_t>.offset(of: \.cover) == 32)
    precondition(MemoryLayout<beluga_core_screen_liveness_snapshot_t>.offset(of: \.inbound_bytes) == 40)
    precondition(MemoryLayout<beluga_core_screen_liveness_snapshot_t>.offset(of: \.inbound_byte_delta) == 56)
    precondition(MemoryLayout<beluga_core_screen_liveness_snapshot_t>.offset(of: \.inbound_packets) == 72)
    precondition(MemoryLayout<beluga_core_screen_liveness_snapshot_t>.offset(of: \.inbound_packet_delta) == 88)
    precondition(MemoryLayout<beluga_core_screen_liveness_snapshot_t>.offset(of: \.decoded_frames) == 104)
    precondition(MemoryLayout<beluga_core_screen_liveness_snapshot_t>.offset(of: \.decoded_frame_delta) == 120)
    precondition(MemoryLayout<beluga_core_screen_liveness_snapshot_t>.offset(of: \.presented_frames) == 136)
    precondition(MemoryLayout<beluga_core_screen_liveness_snapshot_t>.offset(of: \.presented_frame_delta) == 152)
    precondition(MemoryLayout<beluga_core_screen_liveness_snapshot_t>.offset(of: \.content_samples) == 168)
    precondition(MemoryLayout<beluga_core_screen_liveness_snapshot_t>.offset(of: \.content_sample_delta) == 184)
    precondition(MemoryLayout<beluga_core_screen_liveness_snapshot_t>.offset(of: \.content_changes) == 200)
    precondition(MemoryLayout<beluga_core_screen_liveness_snapshot_t>.offset(of: \.content_change_delta) == 216)
    precondition(MemoryLayout<beluga_core_screen_liveness_snapshot_t>.offset(of: \.presentation_age_ms) == 232)
    precondition(MemoryLayout<beluga_core_screen_liveness_snapshot_t>.offset(of: \.frame_width) == 248)
    precondition(MemoryLayout<beluga_core_screen_liveness_snapshot_t>.offset(of: \.frame_height) == 264)
    precondition(MemoryLayout<beluga_core_screen_liveness_snapshot_t>.offset(of: \.frames_per_second_bits) == 280)
    precondition(MemoryLayout<beluga_core_screen_liveness_result_t>.size == 536)
    precondition(MemoryLayout<beluga_core_screen_liveness_result_t>.stride == 536)
    precondition(MemoryLayout<beluga_core_screen_liveness_result_t>.alignment == 8)
    precondition(MemoryLayout<beluga_core_screen_liveness_result_t>.offset(of: \.abi_version) == 0)
    precondition(MemoryLayout<beluga_core_screen_liveness_result_t>.offset(of: \.status) == 8)
    precondition(MemoryLayout<beluga_core_screen_liveness_result_t>.offset(of: \.reserved) == 16)
    precondition(MemoryLayout<beluga_core_screen_liveness_result_t>.offset(of: \.state) == 24)
    precondition(MemoryLayout<beluga_core_screen_liveness_result_t>.offset(of: \.snapshot) == 240)
    var state=beluga_core_screen_liveness_state_t()
    var sample=beluga_core_screen_liveness_sample_t()
    sample.generation=UInt64.max
    let out=beluga_core_screen_liveness_observe(1,state,sample)
    precondition(out.status==0 && out.snapshot.liveness==2)
    precondition(out.snapshot.generation==UInt64.max && out.snapshot.reset_reason==1)
    state=out.state
    let next=beluga_core_screen_liveness_observe(1,state,sample)
    precondition(next.status==0 && next.snapshot.reset_reason==0)
}


// Additive architecture behavior corpus; source-only, uncompiled and unexecuted.
// Literal tables are expected values, not a successful native classifier.
// Each named-field projection preserves raw bits, options and full UInt64 words.
// 0: zero
private let livenessSwiftSamples0: [UInt64] = [
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 1: A_covered_high
private let livenessSwiftSamples1: [UInt64] = [
    0xffffffffffffffe0, 0xfffffffffffffffe, 0x1, 0x3, 0x1, 0x1,
    0xfefdfcfbfaf9f8f7, 0x1, 0x8000000000000021, 0x1, 0x20000000000023, 0x1,
    0x8000000000000003, 0x1, 0x8000, 0x1, 0xfff8000000000042, 0x1,
    0xffffffffffffffe1, 0x8000000000000037, 0x20000000000041, 0xfffffffffffffffd, 0x780, 0x7ffffffffffffffa
]

// 2: B_progress
private let livenessSwiftSamples2: [UInt64] = [
    0xffffffffffffffe0, 0xffffffffffffffff, 0x1, 0x0, 0x1, 0x1,
    0xfefdfcfbfaf9f8f8, 0x1, 0x8000000000000023, 0x1, 0x20000000000026, 0x1,
    0x8000000000000003, 0x1, 0x8000, 0x1, 0x8000000000000000, 0x1,
    0xffffffffffffffe5, 0x800000000000003c, 0x20000000000047, 0xfffffffffffffff8, 0x1, 0x340
]

// 3: C_clock_reversal
private let livenessSwiftSamples3: [UInt64] = [
    0xffffffffffffffe0, 0x0, 0x1, 0x0, 0x1, 0x1,
    0xfefdfcfbfaf9f8f8, 0x1, 0x8000000000000023, 0x1, 0x20000000000026, 0x1,
    0x8000000000000003, 0x1, 0x8000, 0x1, 0x8000000000000000, 0x1,
    0xffffffffffffffe5, 0x800000000000003c, 0x20000000000047, 0xfffffffffffffff8, 0x1, 0x340
]

// 4: timing_before
private let livenessSwiftSamples4: [UInt64] = [
    0xffffffffffffffe0, 0x0, 0x1, 0x0, 0x1, 0x1,
    0xfefdfcfbfaf9f8f8, 0x1, 0x8000000000000023, 0x1, 0x20000000000026, 0x1,
    0x8000000000000003, 0x1, 0x8000, 0x1, 0x8000000000000000, 0x1,
    0xffffffffffffffe5, 0x800000000000003c, 0x20000000000047, 0x0, 0x1, 0x340
]

// 5: timing_exact
private let livenessSwiftSamples5: [UInt64] = [
    0xffffffffffffffe0, 0x9502f900, 0x1, 0x0, 0x1, 0x1,
    0xfefdfcfbfaf9f8f8, 0x1, 0x8000000000000023, 0x1, 0x20000000000026, 0x1,
    0x8000000000000003, 0x1, 0x8000, 0x1, 0x8000000000000000, 0x1,
    0xffffffffffffffe5, 0x800000000000003c, 0x20000000000047, 0x0, 0x1, 0x340
]

// 6: timing_ns_after
private let livenessSwiftSamples6: [UInt64] = [
    0xffffffffffffffe0, 0x9502f901, 0x1, 0x0, 0x1, 0x1,
    0xfefdfcfbfaf9f8f8, 0x1, 0x8000000000000023, 0x1, 0x20000000000026, 0x1,
    0x8000000000000003, 0x1, 0x8000, 0x1, 0x8000000000000000, 0x1,
    0xffffffffffffffe5, 0x800000000000003c, 0x20000000000047, 0x0, 0x1, 0x340
]

// 7: timing_ms_last
private let livenessSwiftSamples7: [UInt64] = [
    0xffffffffffffffe0, 0x95123b3f, 0x1, 0x0, 0x1, 0x1,
    0xfefdfcfbfaf9f8f8, 0x1, 0x8000000000000023, 0x1, 0x20000000000026, 0x1,
    0x8000000000000003, 0x1, 0x8000, 0x1, 0x8000000000000000, 0x1,
    0xffffffffffffffe5, 0x800000000000003c, 0x20000000000047, 0x0, 0x1, 0x340
]

// 8: timing_ms_after
private let livenessSwiftSamples8: [UInt64] = [
    0xffffffffffffffe0, 0x95123b40, 0x1, 0x0, 0x1, 0x1,
    0xfefdfcfbfaf9f8f8, 0x1, 0x8000000000000023, 0x1, 0x20000000000026, 0x1,
    0x8000000000000003, 0x1, 0x8000, 0x1, 0x8000000000000000, 0x1,
    0xffffffffffffffe5, 0x800000000000003c, 0x20000000000047, 0x0, 0x1, 0x340
]

// 9: H_decode_stalled
private let livenessSwiftSamples9: [UInt64] = [
    0xffffffffffffffe0, 0xb2d05e00, 0x1, 0x0, 0x1, 0x1,
    0xfefdfcfbfaf9f8f9, 0x0, 0x0, 0x1, 0x20000000000026, 0x1,
    0x438, 0x1, 0x924, 0x1, 0x408f400000000000, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 10: I_presentation_stalled
private let livenessSwiftSamples10: [UInt64] = [
    0xffffffffffffffe0, 0xb2d05e01, 0x1, 0x0, 0x1, 0x1,
    0xfefdfcfbfaf9f8fa, 0x0, 0x0, 0x1, 0x20000000000027, 0x1,
    0x8000000000000000, 0x1, 0x7fffffffffffffff, 0x1, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 11: J_metadata_only
private let livenessSwiftSamples11: [UInt64] = [
    0xffffffffffffffe0, 0xb2d05e02, 0x1, 0x0, 0x1, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x1,
    0x0, 0x1, 0x8001, 0x1, 0x7ff0000000000000, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 12: K_missing_track
private let livenessSwiftSamples12: [UInt64] = [
    0x0, 0xffffffffffffffff, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 13: L_intentional
private let livenessSwiftSamples13: [UInt64] = [
    0xffffffffffffffff, 0x0, 0x0, 0x1, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 14: M_privacy
private let livenessSwiftSamples14: [UInt64] = [
    0xffffffffffffffff, 0x1, 0x0, 0x2, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 15: N_hidden
private let livenessSwiftSamples15: [UInt64] = [
    0xffffffffffffffff, 0x2, 0x0, 0x4, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 16: O_regression
private let livenessSwiftSamples16: [UInt64] = [
    0xffffffffffffffe0, 0x1, 0x1, 0x0, 0x1, 0x1,
    0x0, 0x1, 0x8000000000000023, 0x1, 0x20000000000026, 0x1,
    0x8000000000000003, 0x1, 0x8000, 0x1, 0x8000000000000000, 0x1,
    0xffffffffffffffe5, 0x800000000000003c, 0x20000000000047, 0x1, 0x1, 0x340
]

// 17: P_generation_zero
private let livenessSwiftSamples17: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x1, 0x1,
    0x0, 0x1, 0x0, 0x1, 0x0, 0x1,
    0x8000000000000003, 0x1, 0x8000, 0x1, 0x7ff8000000000011, 0x1,
    0x0, 0x0, 0x0, 0x0, 0x8000, 0x1
]

// 18: Q_before
private let livenessSwiftSamples18: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x1, 0x1,
    0x7, 0x1, 0xb, 0x1, 0xd, 0x1,
    0x8000000000000003, 0x1, 0x8000, 0x1, 0x4038000000000000, 0x1,
    0x11, 0x13, 0x16, 0x0, 0x780, 0x438
]

// 19: Q_change_zero
private let livenessSwiftSamples19: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x1, 0x1,
    0x7, 0x1, 0xb, 0x1, 0xd, 0x1,
    0x8000000000000003, 0x1, 0x8000, 0x1, 0x4038000000000000, 0x1,
    0x11, 0x13, 0x17, 0x0, 0x780, 0x438
]

// 20: R_no_objects
private let livenessSwiftSamples20: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 21: S_empty_inbound
private let livenessSwiftSamples21: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x1, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 22: T_before
private let livenessSwiftSamples22: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x1, 0x1,
    0x0, 0x1, 0x0, 0x1, 0x0, 0x1,
    0x8000000000000003, 0x1, 0x8000, 0x1, 0x408f400000000000, 0x1,
    0x0, 0x0, 0x0, 0x0, 0x8000, 0x1
]

// 23: T_max
private let livenessSwiftSamples23: [UInt64] = [
    0x0, 0xffffffffffffffff, 0x1, 0x0, 0x1, 0x1,
    0xffffffffffffffff, 0x1, 0xffffffffffffffff, 0x1, 0xffffffffffffffff, 0x1,
    0x8000000000000003, 0x1, 0x8000, 0x1, 0x408f400000000000, 0x1,
    0xffffffffffffffff, 0xffffffffffffffff, 0xffffffffffffffff, 0x0, 0x8000, 0x1
]

// 24: fps_above_upper
private let livenessSwiftSamples24: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x1, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x1, 0x408f480000000000, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 25: fps_negative
private let livenessSwiftSamples25: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x1, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x1, 0xbff0000000000000, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 26: fps_negative_inf
private let livenessSwiftSamples26: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x1, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x1, 0xfff0000000000000, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 27: hidden_generation
private let livenessSwiftSamples27: [UInt64] = [
    0x1, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 28: absent_inbound_payload_0
private let livenessSwiftSamples28: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x0, 0x1,
    0xffffffffffffffff, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 29: inbound_optional_0_presence_2
private let livenessSwiftSamples29: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x1, 0x2,
    0x11, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 30: inbound_optional_0_absent_payload
private let livenessSwiftSamples30: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x1, 0x0,
    0x1, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 31: absent_inbound_payload_1
private let livenessSwiftSamples31: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x0, 0x0,
    0x0, 0x1, 0x8000000000000021, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 32: inbound_optional_1_presence_2
private let livenessSwiftSamples32: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x1, 0x0,
    0x0, 0x2, 0x11, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 33: inbound_optional_1_absent_payload
private let livenessSwiftSamples33: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x1, 0x0,
    0x0, 0x0, 0x1, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 34: absent_inbound_payload_2
private let livenessSwiftSamples34: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x1, 0x20000000000023, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 35: inbound_optional_2_presence_2
private let livenessSwiftSamples35: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x1, 0x0,
    0x0, 0x0, 0x0, 0x2, 0x11, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 36: inbound_optional_2_absent_payload
private let livenessSwiftSamples36: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x1, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x1, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 37: absent_inbound_payload_3
private let livenessSwiftSamples37: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x1,
    0x8000000000000000, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 38: inbound_optional_3_presence_2
private let livenessSwiftSamples38: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x1, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x2,
    0x11, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 39: inbound_optional_3_absent_payload
private let livenessSwiftSamples39: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x1, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x1, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 40: absent_inbound_payload_4
private let livenessSwiftSamples40: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x1, 0x7fffffffffffffff, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 41: inbound_optional_4_presence_2
private let livenessSwiftSamples41: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x1, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x2, 0x11, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 42: inbound_optional_4_absent_payload
private let livenessSwiftSamples42: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x1, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x1, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 43: absent_inbound_payload_5
private let livenessSwiftSamples43: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x1, 0xfff8000000000042, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 44: inbound_optional_5_presence_2
private let livenessSwiftSamples44: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x1, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x2, 0x11, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 45: inbound_optional_5_absent_payload
private let livenessSwiftSamples45: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x1, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x1, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 46: bad_track
private let livenessSwiftSamples46: [UInt64] = [
    0x0, 0x0, 0x2, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 47: bad_cover
private let livenessSwiftSamples47: [UInt64] = [
    0x0, 0x0, 0x1, 0x5, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 48: bad_inbound_presence
private let livenessSwiftSamples48: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x2, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 49: bad_render_presence
private let livenessSwiftSamples49: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x2,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 50: absent_render_payload_0
private let livenessSwiftSamples50: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0xffffffffffffffff, 0x0, 0x0, 0x0, 0x0, 0x0
]

// 51: absent_render_payload_1
private let livenessSwiftSamples51: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x8000000000000037, 0x0, 0x0, 0x0, 0x0
]

// 52: absent_render_payload_2
private let livenessSwiftSamples52: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x20000000000041, 0x0, 0x0, 0x0
]

// 53: absent_render_payload_3
private let livenessSwiftSamples53: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0xffffffffffffffff, 0x0, 0x0
]

// 54: absent_render_payload_4
private let livenessSwiftSamples54: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x8000000000000000, 0x0
]

// 55: absent_render_payload_5
private let livenessSwiftSamples55: [UInt64] = [
    0x0, 0x0, 0x1, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x7fffffffffffffff
]

// 56: bad_previous_track
private let livenessSwiftSamples56: [UInt64] = [
    0xffffffffffffffe0, 0xffffffffffffffff, 0x2, 0x0, 0x1, 0x1,
    0xfefdfcfbfaf9f8f8, 0x1, 0x8000000000000023, 0x1, 0x20000000000026, 0x1,
    0x8000000000000003, 0x1, 0x8000, 0x1, 0x8000000000000000, 0x1,
    0xffffffffffffffe5, 0x800000000000003c, 0x20000000000047, 0xfffffffffffffff8, 0x1, 0x340
]

private let livenessSwiftSamples: [[UInt64]] = [
    livenessSwiftSamples0,
    livenessSwiftSamples1,
    livenessSwiftSamples2,
    livenessSwiftSamples3,
    livenessSwiftSamples4,
    livenessSwiftSamples5,
    livenessSwiftSamples6,
    livenessSwiftSamples7,
    livenessSwiftSamples8,
    livenessSwiftSamples9,
    livenessSwiftSamples10,
    livenessSwiftSamples11,
    livenessSwiftSamples12,
    livenessSwiftSamples13,
    livenessSwiftSamples14,
    livenessSwiftSamples15,
    livenessSwiftSamples16,
    livenessSwiftSamples17,
    livenessSwiftSamples18,
    livenessSwiftSamples19,
    livenessSwiftSamples20,
    livenessSwiftSamples21,
    livenessSwiftSamples22,
    livenessSwiftSamples23,
    livenessSwiftSamples24,
    livenessSwiftSamples25,
    livenessSwiftSamples26,
    livenessSwiftSamples27,
    livenessSwiftSamples28,
    livenessSwiftSamples29,
    livenessSwiftSamples30,
    livenessSwiftSamples31,
    livenessSwiftSamples32,
    livenessSwiftSamples33,
    livenessSwiftSamples34,
    livenessSwiftSamples35,
    livenessSwiftSamples36,
    livenessSwiftSamples37,
    livenessSwiftSamples38,
    livenessSwiftSamples39,
    livenessSwiftSamples40,
    livenessSwiftSamples41,
    livenessSwiftSamples42,
    livenessSwiftSamples43,
    livenessSwiftSamples44,
    livenessSwiftSamples45,
    livenessSwiftSamples46,
    livenessSwiftSamples47,
    livenessSwiftSamples48,
    livenessSwiftSamples49,
    livenessSwiftSamples50,
    livenessSwiftSamples51,
    livenessSwiftSamples52,
    livenessSwiftSamples53,
    livenessSwiftSamples54,
    livenessSwiftSamples55,
    livenessSwiftSamples56
]
// 0: empty
private let livenessSwiftStates0: [UInt64] = [
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0
]

// 1: after_A
private let livenessSwiftStates1: [UInt64] = [
    0x1, 0x0, 0x0, 0xffffffffffffffe0, 0xfffffffffffffffe, 0x1,
    0x3, 0x1, 0x1, 0xfefdfcfbfaf9f8f7, 0x1, 0x8000000000000021,
    0x1, 0x20000000000023, 0x1, 0x8000000000000003, 0x1, 0x8000,
    0x1, 0xfff8000000000042, 0x1, 0xffffffffffffffe1, 0x8000000000000037, 0x20000000000041,
    0xfffffffffffffffd, 0x780, 0x7ffffffffffffffa
]

// 2: after_B
private let livenessSwiftStates2: [UInt64] = [
    0x1, 0x1, 0xffffffffffffffff, 0xffffffffffffffe0, 0xffffffffffffffff, 0x1,
    0x0, 0x1, 0x1, 0xfefdfcfbfaf9f8f8, 0x1, 0x8000000000000023,
    0x1, 0x20000000000026, 0x1, 0x8000000000000003, 0x1, 0x8000,
    0x1, 0x8000000000000000, 0x1, 0xffffffffffffffe5, 0x800000000000003c, 0x20000000000047,
    0xfffffffffffffff8, 0x1, 0x340
]

// 3: after_C
private let livenessSwiftStates3: [UInt64] = [
    0x1, 0x1, 0xffffffffffffffff, 0xffffffffffffffe0, 0x0, 0x1,
    0x0, 0x1, 0x1, 0xfefdfcfbfaf9f8f8, 0x1, 0x8000000000000023,
    0x1, 0x20000000000026, 0x1, 0x8000000000000003, 0x1, 0x8000,
    0x1, 0x8000000000000000, 0x1, 0xffffffffffffffe5, 0x800000000000003c, 0x20000000000047,
    0xfffffffffffffff8, 0x1, 0x340
]

// 4: timing_zero_change
private let livenessSwiftStates4: [UInt64] = [
    0x1, 0x1, 0x0, 0xffffffffffffffe0, 0x0, 0x1,
    0x0, 0x1, 0x1, 0xfefdfcfbfaf9f8f8, 0x1, 0x8000000000000023,
    0x1, 0x20000000000026, 0x1, 0x8000000000000003, 0x1, 0x8000,
    0x1, 0x8000000000000000, 0x1, 0xffffffffffffffe5, 0x800000000000003c, 0x20000000000047,
    0x0, 0x1, 0x340
]

// 5: after_timing_exact
private let livenessSwiftStates5: [UInt64] = [
    0x1, 0x1, 0x0, 0xffffffffffffffe0, 0x9502f900, 0x1,
    0x0, 0x1, 0x1, 0xfefdfcfbfaf9f8f8, 0x1, 0x8000000000000023,
    0x1, 0x20000000000026, 0x1, 0x8000000000000003, 0x1, 0x8000,
    0x1, 0x8000000000000000, 0x1, 0xffffffffffffffe5, 0x800000000000003c, 0x20000000000047,
    0x0, 0x1, 0x340
]

// 6: after_timing_ns_after
private let livenessSwiftStates6: [UInt64] = [
    0x1, 0x1, 0x0, 0xffffffffffffffe0, 0x9502f901, 0x1,
    0x0, 0x1, 0x1, 0xfefdfcfbfaf9f8f8, 0x1, 0x8000000000000023,
    0x1, 0x20000000000026, 0x1, 0x8000000000000003, 0x1, 0x8000,
    0x1, 0x8000000000000000, 0x1, 0xffffffffffffffe5, 0x800000000000003c, 0x20000000000047,
    0x0, 0x1, 0x340
]

// 7: after_timing_ms_last
private let livenessSwiftStates7: [UInt64] = [
    0x1, 0x1, 0x0, 0xffffffffffffffe0, 0x95123b3f, 0x1,
    0x0, 0x1, 0x1, 0xfefdfcfbfaf9f8f8, 0x1, 0x8000000000000023,
    0x1, 0x20000000000026, 0x1, 0x8000000000000003, 0x1, 0x8000,
    0x1, 0x8000000000000000, 0x1, 0xffffffffffffffe5, 0x800000000000003c, 0x20000000000047,
    0x0, 0x1, 0x340
]

// 8: after_timing_ms_after
private let livenessSwiftStates8: [UInt64] = [
    0x1, 0x1, 0x0, 0xffffffffffffffe0, 0x95123b40, 0x1,
    0x0, 0x1, 0x1, 0xfefdfcfbfaf9f8f8, 0x1, 0x8000000000000023,
    0x1, 0x20000000000026, 0x1, 0x8000000000000003, 0x1, 0x8000,
    0x1, 0x8000000000000000, 0x1, 0xffffffffffffffe5, 0x800000000000003c, 0x20000000000047,
    0x0, 0x1, 0x340
]

// 9: after_H
private let livenessSwiftStates9: [UInt64] = [
    0x1, 0x1, 0xffffffffffffffff, 0xffffffffffffffe0, 0xb2d05e00, 0x1,
    0x0, 0x1, 0x1, 0xfefdfcfbfaf9f8f9, 0x0, 0x0,
    0x1, 0x20000000000026, 0x1, 0x438, 0x1, 0x924,
    0x1, 0x408f400000000000, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0
]

// 10: after_I
private let livenessSwiftStates10: [UInt64] = [
    0x1, 0x1, 0xffffffffffffffff, 0xffffffffffffffe0, 0xb2d05e01, 0x1,
    0x0, 0x1, 0x1, 0xfefdfcfbfaf9f8fa, 0x0, 0x0,
    0x1, 0x20000000000027, 0x1, 0x8000000000000000, 0x1, 0x7fffffffffffffff,
    0x1, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0
]

// 11: after_J
private let livenessSwiftStates11: [UInt64] = [
    0x1, 0x1, 0xffffffffffffffff, 0xffffffffffffffe0, 0xb2d05e02, 0x1,
    0x0, 0x1, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x1, 0x0, 0x1, 0x8001,
    0x1, 0x7ff0000000000000, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0
]

// 12: after_K
private let livenessSwiftStates12: [UInt64] = [
    0x1, 0x0, 0x0, 0x0, 0xffffffffffffffff, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0
]

// 13: after_L
private let livenessSwiftStates13: [UInt64] = [
    0x1, 0x0, 0x0, 0xffffffffffffffff, 0x0, 0x0,
    0x1, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0
]

// 14: after_M
private let livenessSwiftStates14: [UInt64] = [
    0x1, 0x0, 0x0, 0xffffffffffffffff, 0x1, 0x0,
    0x2, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0
]

// 15: after_N
private let livenessSwiftStates15: [UInt64] = [
    0x1, 0x0, 0x0, 0xffffffffffffffff, 0x2, 0x0,
    0x4, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0
]

// 16: after_O
private let livenessSwiftStates16: [UInt64] = [
    0x1, 0x0, 0x0, 0xffffffffffffffe0, 0x1, 0x1,
    0x0, 0x1, 0x1, 0x0, 0x1, 0x8000000000000023,
    0x1, 0x20000000000026, 0x1, 0x8000000000000003, 0x1, 0x8000,
    0x1, 0x8000000000000000, 0x1, 0xffffffffffffffe5, 0x800000000000003c, 0x20000000000047,
    0x1, 0x1, 0x340
]

// 17: after_P
private let livenessSwiftStates17: [UInt64] = [
    0x1, 0x0, 0x0, 0x0, 0x0, 0x1,
    0x0, 0x1, 0x1, 0x0, 0x1, 0x0,
    0x1, 0x0, 0x1, 0x8000000000000003, 0x1, 0x8000,
    0x1, 0x7ff8000000000011, 0x1, 0x0, 0x0, 0x0,
    0x0, 0x8000, 0x1
]

// 18: before_Q
private let livenessSwiftStates18: [UInt64] = [
    0x1, 0x0, 0x0, 0x0, 0x0, 0x1,
    0x0, 0x1, 0x1, 0x7, 0x1, 0xb,
    0x1, 0xd, 0x1, 0x8000000000000003, 0x1, 0x8000,
    0x1, 0x4038000000000000, 0x1, 0x11, 0x13, 0x16,
    0x0, 0x780, 0x438
]

// 19: after_Q
private let livenessSwiftStates19: [UInt64] = [
    0x1, 0x1, 0x0, 0x0, 0x0, 0x1,
    0x0, 0x1, 0x1, 0x7, 0x1, 0xb,
    0x1, 0xd, 0x1, 0x8000000000000003, 0x1, 0x8000,
    0x1, 0x4038000000000000, 0x1, 0x11, 0x13, 0x17,
    0x0, 0x780, 0x438
]

// 20: after_R
private let livenessSwiftStates20: [UInt64] = [
    0x1, 0x0, 0x0, 0x0, 0x0, 0x1,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0
]

// 21: after_S
private let livenessSwiftStates21: [UInt64] = [
    0x1, 0x0, 0x0, 0x0, 0x0, 0x1,
    0x0, 0x1, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0
]

// 22: before_T
private let livenessSwiftStates22: [UInt64] = [
    0x1, 0x0, 0x0, 0x0, 0x0, 0x1,
    0x0, 0x1, 0x1, 0x0, 0x1, 0x0,
    0x1, 0x0, 0x1, 0x8000000000000003, 0x1, 0x8000,
    0x1, 0x408f400000000000, 0x1, 0x0, 0x0, 0x0,
    0x0, 0x8000, 0x1
]

// 23: after_T
private let livenessSwiftStates23: [UInt64] = [
    0x1, 0x1, 0xffffffffffffffff, 0x0, 0xffffffffffffffff, 0x1,
    0x0, 0x1, 0x1, 0xffffffffffffffff, 0x1, 0xffffffffffffffff,
    0x1, 0xffffffffffffffff, 0x1, 0x8000000000000003, 0x1, 0x8000,
    0x1, 0x408f400000000000, 0x1, 0xffffffffffffffff, 0xffffffffffffffff, 0xffffffffffffffff,
    0x0, 0x8000, 0x1
]

// 24: after_fps_above_upper
private let livenessSwiftStates24: [UInt64] = [
    0x1, 0x0, 0x0, 0x0, 0x0, 0x1,
    0x0, 0x1, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x1, 0x408f480000000000, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0
]

// 25: after_fps_negative
private let livenessSwiftStates25: [UInt64] = [
    0x1, 0x0, 0x0, 0x0, 0x0, 0x1,
    0x0, 0x1, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x1, 0xbff0000000000000, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0
]

// 26: after_fps_negative_inf
private let livenessSwiftStates26: [UInt64] = [
    0x1, 0x0, 0x0, 0x0, 0x0, 0x1,
    0x0, 0x1, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x1, 0xfff0000000000000, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0
]

// 27: bad_before_presence_2
private let livenessSwiftStates27: [UInt64] = [
    0x2, 0x1, 0xffffffffffffffff, 0xffffffffffffffe0, 0xffffffffffffffff, 0x1,
    0x0, 0x1, 0x1, 0xfefdfcfbfaf9f8f8, 0x1, 0x8000000000000023,
    0x1, 0x20000000000026, 0x1, 0x8000000000000003, 0x1, 0x8000,
    0x1, 0x8000000000000000, 0x1, 0xffffffffffffffe5, 0x800000000000003c, 0x20000000000047,
    0xfffffffffffffff8, 0x1, 0x340
]

// 28: bad_clock_presence_2
private let livenessSwiftStates28: [UInt64] = [
    0x1, 0x2, 0x11, 0xffffffffffffffe0, 0xffffffffffffffff, 0x1,
    0x0, 0x1, 0x1, 0xfefdfcfbfaf9f8f8, 0x1, 0x8000000000000023,
    0x1, 0x20000000000026, 0x1, 0x8000000000000003, 0x1, 0x8000,
    0x1, 0x8000000000000000, 0x1, 0xffffffffffffffe5, 0x800000000000003c, 0x20000000000047,
    0xfffffffffffffff8, 0x1, 0x340
]

// 29: bad_clock_presence_max
private let livenessSwiftStates29: [UInt64] = [
    0x1, 0xffffffffffffffff, 0xffffffffffffffff, 0xffffffffffffffe0, 0xffffffffffffffff, 0x1,
    0x0, 0x1, 0x1, 0xfefdfcfbfaf9f8f8, 0x1, 0x8000000000000023,
    0x1, 0x20000000000026, 0x1, 0x8000000000000003, 0x1, 0x8000,
    0x1, 0x8000000000000000, 0x1, 0xffffffffffffffe5, 0x800000000000003c, 0x20000000000047,
    0xfffffffffffffff8, 0x1, 0x340
]

// 30: bad_clock_absent_payload
private let livenessSwiftStates30: [UInt64] = [
    0x1, 0x0, 0x1, 0xffffffffffffffe0, 0xffffffffffffffff, 0x1,
    0x0, 0x1, 0x1, 0xfefdfcfbfaf9f8f8, 0x1, 0x8000000000000023,
    0x1, 0x20000000000026, 0x1, 0x8000000000000003, 0x1, 0x8000,
    0x1, 0x8000000000000000, 0x1, 0xffffffffffffffe5, 0x800000000000003c, 0x20000000000047,
    0xfffffffffffffff8, 0x1, 0x340
]

// 31: bad_absent_before_generation
private let livenessSwiftStates31: [UInt64] = [
    0x0, 0x0, 0x0, 0x1, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0
]

// 32: bad_absent_before_full
private let livenessSwiftStates32: [UInt64] = [
    0x0, 0x0, 0x0, 0xffffffffffffffe0, 0xffffffffffffffff, 0x1,
    0x0, 0x1, 0x1, 0xfefdfcfbfaf9f8f8, 0x1, 0x8000000000000023,
    0x1, 0x20000000000026, 0x1, 0x8000000000000003, 0x1, 0x8000,
    0x1, 0x8000000000000000, 0x1, 0xffffffffffffffe5, 0x800000000000003c, 0x20000000000047,
    0xfffffffffffffff8, 0x1, 0x340
]

// 33: bad_absent_before_clock_0
private let livenessSwiftStates33: [UInt64] = [
    0x0, 0x1, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0
]

// 34: bad_absent_before_clock_18446744073709551615
private let livenessSwiftStates34: [UInt64] = [
    0x0, 0x1, 0xffffffffffffffff, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0
]

// 35: bad_nested_previous
private let livenessSwiftStates35: [UInt64] = [
    0x1, 0x1, 0xffffffffffffffff, 0xffffffffffffffe0, 0xffffffffffffffff, 0x2,
    0x0, 0x1, 0x1, 0xfefdfcfbfaf9f8f8, 0x1, 0x8000000000000023,
    0x1, 0x20000000000026, 0x1, 0x8000000000000003, 0x1, 0x8000,
    0x1, 0x8000000000000000, 0x1, 0xffffffffffffffe5, 0x800000000000003c, 0x20000000000047,
    0xfffffffffffffff8, 0x1, 0x340
]

private let livenessSwiftStates: [[UInt64]] = [
    livenessSwiftStates0,
    livenessSwiftStates1,
    livenessSwiftStates2,
    livenessSwiftStates3,
    livenessSwiftStates4,
    livenessSwiftStates5,
    livenessSwiftStates6,
    livenessSwiftStates7,
    livenessSwiftStates8,
    livenessSwiftStates9,
    livenessSwiftStates10,
    livenessSwiftStates11,
    livenessSwiftStates12,
    livenessSwiftStates13,
    livenessSwiftStates14,
    livenessSwiftStates15,
    livenessSwiftStates16,
    livenessSwiftStates17,
    livenessSwiftStates18,
    livenessSwiftStates19,
    livenessSwiftStates20,
    livenessSwiftStates21,
    livenessSwiftStates22,
    livenessSwiftStates23,
    livenessSwiftStates24,
    livenessSwiftStates25,
    livenessSwiftStates26,
    livenessSwiftStates27,
    livenessSwiftStates28,
    livenessSwiftStates29,
    livenessSwiftStates30,
    livenessSwiftStates31,
    livenessSwiftStates32,
    livenessSwiftStates33,
    livenessSwiftStates34,
    livenessSwiftStates35
]
// 0: A_initial
private let livenessSwiftSnapshots0: [UInt64] = [
    0x1, 0x1, 0xffffffffffffffe0, 0x1, 0x3, 0x1,
    0xfefdfcfbfaf9f8f7, 0x0, 0x0, 0x1, 0x8000000000000021, 0x0,
    0x0, 0x1, 0x20000000000023, 0x0, 0x0, 0x1,
    0xffffffffffffffe1, 0x0, 0x0, 0x1, 0x8000000000000037, 0x0,
    0x0, 0x1, 0x20000000000041, 0x0, 0x0, 0x1,
    0x0, 0x1, 0x780, 0x1, 0x8000, 0x0,
    0x0
]

// 1: A_plateau
private let livenessSwiftSnapshots1: [UInt64] = [
    0x1, 0x0, 0xffffffffffffffe0, 0x1, 0x3, 0x1,
    0xfefdfcfbfaf9f8f7, 0x1, 0x0, 0x1, 0x8000000000000021, 0x1,
    0x0, 0x1, 0x20000000000023, 0x1, 0x0, 0x1,
    0xffffffffffffffe1, 0x1, 0x0, 0x1, 0x8000000000000037, 0x1,
    0x0, 0x1, 0x20000000000041, 0x1, 0x0, 0x1,
    0x0, 0x1, 0x780, 0x1, 0x8000, 0x0,
    0x0
]

// 2: B_progress
private let livenessSwiftSnapshots2: [UInt64] = [
    0x8, 0x0, 0xffffffffffffffe0, 0x1, 0x0, 0x1,
    0xfefdfcfbfaf9f8f8, 0x1, 0x1, 0x1, 0x8000000000000023, 0x1,
    0x2, 0x1, 0x20000000000026, 0x1, 0x3, 0x1,
    0xffffffffffffffe5, 0x1, 0x4, 0x1, 0x800000000000003c, 0x1,
    0x5, 0x1, 0x20000000000047, 0x1, 0x6, 0x1,
    0x0, 0x1, 0x1, 0x1, 0x340, 0x1,
    0x8000000000000000
]

// 3: C_reversal
private let livenessSwiftSnapshots3: [UInt64] = [
    0x7, 0x0, 0xffffffffffffffe0, 0x1, 0x0, 0x1,
    0xfefdfcfbfaf9f8f8, 0x1, 0x0, 0x1, 0x8000000000000023, 0x1,
    0x0, 0x1, 0x20000000000026, 0x1, 0x0, 0x1,
    0xffffffffffffffe5, 0x1, 0x0, 0x1, 0x800000000000003c, 0x1,
    0x0, 0x1, 0x20000000000047, 0x1, 0x0, 0x1,
    0x0, 0x1, 0x1, 0x1, 0x340, 0x1,
    0x8000000000000000
]

// 4: timing_exact
private let livenessSwiftSnapshots4: [UInt64] = [
    0x8, 0x0, 0xffffffffffffffe0, 0x1, 0x0, 0x1,
    0xfefdfcfbfaf9f8f8, 0x1, 0x0, 0x1, 0x8000000000000023, 0x1,
    0x0, 0x1, 0x20000000000026, 0x1, 0x0, 0x1,
    0xffffffffffffffe5, 0x1, 0x0, 0x1, 0x800000000000003c, 0x1,
    0x0, 0x1, 0x20000000000047, 0x1, 0x0, 0x1,
    0x9c4, 0x1, 0x1, 0x1, 0x340, 0x1,
    0x8000000000000000
]

// 5: timing_ns_after
private let livenessSwiftSnapshots5: [UInt64] = [
    0x7, 0x0, 0xffffffffffffffe0, 0x1, 0x0, 0x1,
    0xfefdfcfbfaf9f8f8, 0x1, 0x0, 0x1, 0x8000000000000023, 0x1,
    0x0, 0x1, 0x20000000000026, 0x1, 0x0, 0x1,
    0xffffffffffffffe5, 0x1, 0x0, 0x1, 0x800000000000003c, 0x1,
    0x0, 0x1, 0x20000000000047, 0x1, 0x0, 0x1,
    0x9c4, 0x1, 0x1, 0x1, 0x340, 0x1,
    0x8000000000000000
]

// 6: timing_ms_last
private let livenessSwiftSnapshots6: [UInt64] = [
    0x7, 0x0, 0xffffffffffffffe0, 0x1, 0x0, 0x1,
    0xfefdfcfbfaf9f8f8, 0x1, 0x0, 0x1, 0x8000000000000023, 0x1,
    0x0, 0x1, 0x20000000000026, 0x1, 0x0, 0x1,
    0xffffffffffffffe5, 0x1, 0x0, 0x1, 0x800000000000003c, 0x1,
    0x0, 0x1, 0x20000000000047, 0x1, 0x0, 0x1,
    0x9c4, 0x1, 0x1, 0x1, 0x340, 0x1,
    0x8000000000000000
]

// 7: timing_ms_after
private let livenessSwiftSnapshots7: [UInt64] = [
    0x4, 0x0, 0xffffffffffffffe0, 0x1, 0x0, 0x1,
    0xfefdfcfbfaf9f8f8, 0x1, 0x0, 0x1, 0x8000000000000023, 0x1,
    0x0, 0x1, 0x20000000000026, 0x1, 0x0, 0x1,
    0xffffffffffffffe5, 0x1, 0x0, 0x1, 0x800000000000003c, 0x1,
    0x0, 0x1, 0x20000000000047, 0x1, 0x0, 0x1,
    0x9c5, 0x1, 0x1, 0x1, 0x340, 0x1,
    0x8000000000000000
]

// 8: H_decode_stalled
private let livenessSwiftSnapshots8: [UInt64] = [
    0x5, 0x0, 0xffffffffffffffe0, 0x1, 0x0, 0x1,
    0xfefdfcfbfaf9f8f9, 0x1, 0x1, 0x0, 0x0, 0x0,
    0x0, 0x1, 0x20000000000026, 0x1, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x1, 0x438, 0x1, 0x924, 0x1,
    0x408f400000000000
]

// 9: I_presentation_stalled
private let livenessSwiftSnapshots9: [UInt64] = [
    0x6, 0x0, 0xffffffffffffffe0, 0x1, 0x0, 0x1,
    0xfefdfcfbfaf9f8fa, 0x1, 0x1, 0x0, 0x0, 0x0,
    0x0, 0x1, 0x20000000000027, 0x1, 0x1, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x1,
    0x0
]

// 10: J_metadata_only
private let livenessSwiftSnapshots10: [UInt64] = [
    0x3, 0x0, 0xffffffffffffffe0, 0x1, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0
]

// 11: K_missing_track
private let livenessSwiftSnapshots11: [UInt64] = [
    0x2, 0x2, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0
]

// 12: L_intentional
private let livenessSwiftSnapshots12: [UInt64] = [
    0x0, 0x2, 0xffffffffffffffff, 0x0, 0x1, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0
]

// 13: M_privacy
private let livenessSwiftSnapshots13: [UInt64] = [
    0x1, 0x0, 0xffffffffffffffff, 0x0, 0x2, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0
]

// 14: N_hidden
private let livenessSwiftSnapshots14: [UInt64] = [
    0x1, 0x0, 0xffffffffffffffff, 0x0, 0x4, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0
]

// 15: O_regression
private let livenessSwiftSnapshots15: [UInt64] = [
    0x3, 0x3, 0xffffffffffffffe0, 0x1, 0x0, 0x1,
    0x0, 0x0, 0x0, 0x1, 0x8000000000000023, 0x0,
    0x0, 0x1, 0x20000000000026, 0x0, 0x0, 0x1,
    0xffffffffffffffe5, 0x0, 0x0, 0x1, 0x800000000000003c, 0x0,
    0x0, 0x1, 0x20000000000047, 0x0, 0x0, 0x1,
    0x0, 0x1, 0x1, 0x1, 0x340, 0x1,
    0x8000000000000000
]

// 16: P_generation_zero
private let livenessSwiftSnapshots16: [UInt64] = [
    0x3, 0x2, 0x0, 0x1, 0x0, 0x1,
    0x0, 0x0, 0x0, 0x1, 0x0, 0x0,
    0x0, 0x1, 0x0, 0x0, 0x0, 0x1,
    0x0, 0x0, 0x0, 0x1, 0x0, 0x0,
    0x0, 0x1, 0x0, 0x0, 0x0, 0x1,
    0x0, 0x1, 0x8000, 0x1, 0x1, 0x0,
    0x0
]

// 17: Q_change_zero
private let livenessSwiftSnapshots17: [UInt64] = [
    0x8, 0x0, 0x0, 0x1, 0x0, 0x1,
    0x7, 0x1, 0x0, 0x1, 0xb, 0x1,
    0x0, 0x1, 0xd, 0x1, 0x0, 0x1,
    0x11, 0x1, 0x0, 0x1, 0x13, 0x1,
    0x0, 0x1, 0x17, 0x1, 0x1, 0x1,
    0x0, 0x1, 0x780, 0x1, 0x438, 0x1,
    0x4038000000000000
]

// 18: R_no_objects
private let livenessSwiftSnapshots18: [UInt64] = [
    0x3, 0x1, 0x0, 0x1, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0
]

// 19: T_max
private let livenessSwiftSnapshots19: [UInt64] = [
    0x8, 0x0, 0x0, 0x1, 0x0, 0x1,
    0xffffffffffffffff, 0x1, 0xffffffffffffffff, 0x1, 0xffffffffffffffff, 0x1,
    0xffffffffffffffff, 0x1, 0xffffffffffffffff, 0x1, 0xffffffffffffffff, 0x1,
    0xffffffffffffffff, 0x1, 0xffffffffffffffff, 0x1, 0xffffffffffffffff, 0x1,
    0xffffffffffffffff, 0x1, 0xffffffffffffffff, 0x1, 0xffffffffffffffff, 0x1,
    0x5265c00, 0x1, 0x8000, 0x1, 0x1, 0x1,
    0x408f400000000000
]

// 20: refusal_zero
private let livenessSwiftSnapshots20: [UInt64] = [
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
    0x0
]

private let livenessSwiftSnapshots: [[UInt64]] = [
    livenessSwiftSnapshots0,
    livenessSwiftSnapshots1,
    livenessSwiftSnapshots2,
    livenessSwiftSnapshots3,
    livenessSwiftSnapshots4,
    livenessSwiftSnapshots5,
    livenessSwiftSnapshots6,
    livenessSwiftSnapshots7,
    livenessSwiftSnapshots8,
    livenessSwiftSnapshots9,
    livenessSwiftSnapshots10,
    livenessSwiftSnapshots11,
    livenessSwiftSnapshots12,
    livenessSwiftSnapshots13,
    livenessSwiftSnapshots14,
    livenessSwiftSnapshots15,
    livenessSwiftSnapshots16,
    livenessSwiftSnapshots17,
    livenessSwiftSnapshots18,
    livenessSwiftSnapshots19,
    livenessSwiftSnapshots20
]

private struct LivenessSwiftLiteralCase {
    let name: String
    let abi: UInt64
    let beforeIndex: Int
    let sampleIndex: Int
    let status: UInt64
    let afterIndex: Int
    let snapshotIndex: Int
}
private let livenessSwiftCases: [LivenessSwiftLiteralCase] = [
    .init(name: "covered_initial_full_width", abi: 0x1, beforeIndex: 0, sampleIndex: 1, status: 0x0, afterIndex: 1, snapshotIndex: 0),
    .init(name: "covered_plateau_full_width", abi: 0x1, beforeIndex: 1, sampleIndex: 1, status: 0x0, afterIndex: 1, snapshotIndex: 1),
    .init(name: "all_six_distinct_deltas_negative_zero", abi: 0x1, beforeIndex: 1, sampleIndex: 2, status: 0x0, afterIndex: 2, snapshotIndex: 2),
    .init(name: "clock_reversal_retains_full_width_recent_change", abi: 0x1, beforeIndex: 2, sampleIndex: 3, status: 0x0, afterIndex: 3, snapshotIndex: 3),
    .init(name: "timing_exact", abi: 0x1, beforeIndex: 4, sampleIndex: 5, status: 0x0, afterIndex: 5, snapshotIndex: 4),
    .init(name: "timing_ns_after", abi: 0x1, beforeIndex: 4, sampleIndex: 6, status: 0x0, afterIndex: 6, snapshotIndex: 5),
    .init(name: "timing_ms_last", abi: 0x1, beforeIndex: 4, sampleIndex: 7, status: 0x0, afterIndex: 7, snapshotIndex: 6),
    .init(name: "timing_ms_after", abi: 0x1, beforeIndex: 4, sampleIndex: 8, status: 0x0, afterIndex: 8, snapshotIndex: 7),
    .init(name: "decode_stalled_inbound_only", abi: 0x1, beforeIndex: 2, sampleIndex: 9, status: 0x0, afterIndex: 9, snapshotIndex: 8),
    .init(name: "presentation_stalled_signed_dimension_bounds_positive_zero", abi: 0x1, beforeIndex: 9, sampleIndex: 10, status: 0x0, afterIndex: 10, snapshotIndex: 9),
    .init(name: "metadata_only_empty_counters_inf_and_invalid_dimensions", abi: 0x1, beforeIndex: 10, sampleIndex: 11, status: 0x0, afterIndex: 11, snapshotIndex: 10),
    .init(name: "track_missing_generation_change", abi: 0x1, beforeIndex: 11, sampleIndex: 12, status: 0x0, afterIndex: 12, snapshotIndex: 11),
    .init(name: "intentional_cover_precedes_track_and_reset", abi: 0x1, beforeIndex: 12, sampleIndex: 13, status: 0x0, afterIndex: 13, snapshotIndex: 12),
    .init(name: "privacy_cover", abi: 0x1, beforeIndex: 13, sampleIndex: 14, status: 0x0, afterIndex: 14, snapshotIndex: 13),
    .init(name: "hidden_cover", abi: 0x1, beforeIndex: 14, sampleIndex: 15, status: 0x0, afterIndex: 15, snapshotIndex: 14),
    .init(name: "counter_regression_resets_all_deltas_and_recent_change", abi: 0x1, beforeIndex: 2, sampleIndex: 16, status: 0x0, afterIndex: 16, snapshotIndex: 15),
    .init(name: "generation_change_precedes_regression_nan_raw_history", abi: 0x1, beforeIndex: 2, sampleIndex: 17, status: 0x0, afterIndex: 17, snapshotIndex: 16),
    .init(name: "present_zero_change_clock_is_not_absent", abi: 0x1, beforeIndex: 18, sampleIndex: 19, status: 0x0, afterIndex: 19, snapshotIndex: 17),
    .init(name: "no_objects_is_not_empty_inbound", abi: 0x1, beforeIndex: 0, sampleIndex: 20, status: 0x0, afterIndex: 20, snapshotIndex: 18),
    .init(name: "empty_inbound_is_not_absent_object", abi: 0x1, beforeIndex: 0, sampleIndex: 21, status: 0x0, afterIndex: 21, snapshotIndex: 18),
    .init(name: "maximum_deltas_age_clamp_recent_clock", abi: 0x1, beforeIndex: 22, sampleIndex: 23, status: 0x0, afterIndex: 23, snapshotIndex: 19),
    .init(name: "fps_above_upper", abi: 0x1, beforeIndex: 0, sampleIndex: 24, status: 0x0, afterIndex: 24, snapshotIndex: 18),
    .init(name: "fps_negative", abi: 0x1, beforeIndex: 0, sampleIndex: 25, status: 0x0, afterIndex: 25, snapshotIndex: 18),
    .init(name: "fps_negative_inf", abi: 0x1, beforeIndex: 0, sampleIndex: 26, status: 0x0, afterIndex: 26, snapshotIndex: 18),
    .init(name: "abi_0", abi: 0x0, beforeIndex: 2, sampleIndex: 2, status: 0x3, afterIndex: 2, snapshotIndex: 20),
    .init(name: "abi_2", abi: 0x2, beforeIndex: 2, sampleIndex: 2, status: 0x3, afterIndex: 2, snapshotIndex: 20),
    .init(name: "abi_18446744073709551615", abi: 0xffffffffffffffff, beforeIndex: 2, sampleIndex: 2, status: 0x3, afterIndex: 2, snapshotIndex: 20),
    .init(name: "bad_before_presence_2", abi: 0x1, beforeIndex: 27, sampleIndex: 2, status: 0x3, afterIndex: 27, snapshotIndex: 20),
    .init(name: "bad_clock_presence_2", abi: 0x1, beforeIndex: 28, sampleIndex: 2, status: 0x3, afterIndex: 28, snapshotIndex: 20),
    .init(name: "bad_clock_presence_max", abi: 0x1, beforeIndex: 29, sampleIndex: 2, status: 0x3, afterIndex: 29, snapshotIndex: 20),
    .init(name: "bad_clock_absent_payload", abi: 0x1, beforeIndex: 30, sampleIndex: 2, status: 0x3, afterIndex: 30, snapshotIndex: 20),
    .init(name: "bad_absent_before_generation", abi: 0x1, beforeIndex: 31, sampleIndex: 2, status: 0x3, afterIndex: 31, snapshotIndex: 20),
    .init(name: "bad_absent_before_full", abi: 0x1, beforeIndex: 32, sampleIndex: 2, status: 0x3, afterIndex: 32, snapshotIndex: 20),
    .init(name: "bad_absent_before_clock_0", abi: 0x1, beforeIndex: 33, sampleIndex: 2, status: 0x3, afterIndex: 33, snapshotIndex: 20),
    .init(name: "bad_absent_before_clock_18446744073709551615", abi: 0x1, beforeIndex: 34, sampleIndex: 2, status: 0x3, afterIndex: 34, snapshotIndex: 20),
    .init(name: "absent_inbound_payload_0", abi: 0x1, beforeIndex: 2, sampleIndex: 28, status: 0x3, afterIndex: 2, snapshotIndex: 20),
    .init(name: "inbound_optional_0_presence_2", abi: 0x1, beforeIndex: 2, sampleIndex: 29, status: 0x3, afterIndex: 2, snapshotIndex: 20),
    .init(name: "inbound_optional_0_absent_payload", abi: 0x1, beforeIndex: 2, sampleIndex: 30, status: 0x3, afterIndex: 2, snapshotIndex: 20),
    .init(name: "absent_inbound_payload_1", abi: 0x1, beforeIndex: 2, sampleIndex: 31, status: 0x3, afterIndex: 2, snapshotIndex: 20),
    .init(name: "inbound_optional_1_presence_2", abi: 0x1, beforeIndex: 2, sampleIndex: 32, status: 0x3, afterIndex: 2, snapshotIndex: 20),
    .init(name: "inbound_optional_1_absent_payload", abi: 0x1, beforeIndex: 2, sampleIndex: 33, status: 0x3, afterIndex: 2, snapshotIndex: 20),
    .init(name: "absent_inbound_payload_2", abi: 0x1, beforeIndex: 2, sampleIndex: 34, status: 0x3, afterIndex: 2, snapshotIndex: 20),
    .init(name: "inbound_optional_2_presence_2", abi: 0x1, beforeIndex: 2, sampleIndex: 35, status: 0x3, afterIndex: 2, snapshotIndex: 20),
    .init(name: "inbound_optional_2_absent_payload", abi: 0x1, beforeIndex: 2, sampleIndex: 36, status: 0x3, afterIndex: 2, snapshotIndex: 20),
    .init(name: "absent_inbound_payload_3", abi: 0x1, beforeIndex: 2, sampleIndex: 37, status: 0x3, afterIndex: 2, snapshotIndex: 20),
    .init(name: "inbound_optional_3_presence_2", abi: 0x1, beforeIndex: 2, sampleIndex: 38, status: 0x3, afterIndex: 2, snapshotIndex: 20),
    .init(name: "inbound_optional_3_absent_payload", abi: 0x1, beforeIndex: 2, sampleIndex: 39, status: 0x3, afterIndex: 2, snapshotIndex: 20),
    .init(name: "absent_inbound_payload_4", abi: 0x1, beforeIndex: 2, sampleIndex: 40, status: 0x3, afterIndex: 2, snapshotIndex: 20),
    .init(name: "inbound_optional_4_presence_2", abi: 0x1, beforeIndex: 2, sampleIndex: 41, status: 0x3, afterIndex: 2, snapshotIndex: 20),
    .init(name: "inbound_optional_4_absent_payload", abi: 0x1, beforeIndex: 2, sampleIndex: 42, status: 0x3, afterIndex: 2, snapshotIndex: 20),
    .init(name: "absent_inbound_payload_5", abi: 0x1, beforeIndex: 2, sampleIndex: 43, status: 0x3, afterIndex: 2, snapshotIndex: 20),
    .init(name: "inbound_optional_5_presence_2", abi: 0x1, beforeIndex: 2, sampleIndex: 44, status: 0x3, afterIndex: 2, snapshotIndex: 20),
    .init(name: "inbound_optional_5_absent_payload", abi: 0x1, beforeIndex: 2, sampleIndex: 45, status: 0x3, afterIndex: 2, snapshotIndex: 20),
    .init(name: "bad_track", abi: 0x1, beforeIndex: 2, sampleIndex: 46, status: 0x3, afterIndex: 2, snapshotIndex: 20),
    .init(name: "bad_cover", abi: 0x1, beforeIndex: 2, sampleIndex: 47, status: 0x3, afterIndex: 2, snapshotIndex: 20),
    .init(name: "bad_inbound_presence", abi: 0x1, beforeIndex: 2, sampleIndex: 48, status: 0x3, afterIndex: 2, snapshotIndex: 20),
    .init(name: "bad_render_presence", abi: 0x1, beforeIndex: 2, sampleIndex: 49, status: 0x3, afterIndex: 2, snapshotIndex: 20),
    .init(name: "absent_render_payload_0", abi: 0x1, beforeIndex: 2, sampleIndex: 50, status: 0x3, afterIndex: 2, snapshotIndex: 20),
    .init(name: "absent_render_payload_1", abi: 0x1, beforeIndex: 2, sampleIndex: 51, status: 0x3, afterIndex: 2, snapshotIndex: 20),
    .init(name: "absent_render_payload_2", abi: 0x1, beforeIndex: 2, sampleIndex: 52, status: 0x3, afterIndex: 2, snapshotIndex: 20),
    .init(name: "absent_render_payload_3", abi: 0x1, beforeIndex: 2, sampleIndex: 53, status: 0x3, afterIndex: 2, snapshotIndex: 20),
    .init(name: "absent_render_payload_4", abi: 0x1, beforeIndex: 2, sampleIndex: 54, status: 0x3, afterIndex: 2, snapshotIndex: 20),
    .init(name: "absent_render_payload_5", abi: 0x1, beforeIndex: 2, sampleIndex: 55, status: 0x3, afterIndex: 2, snapshotIndex: 20),
    .init(name: "bad_nested_previous", abi: 0x1, beforeIndex: 35, sampleIndex: 2, status: 0x3, afterIndex: 35, snapshotIndex: 20)
]

private func livenessSwiftSampleFromWords(_ words: [UInt64]) -> beluga_core_screen_liveness_sample_t {
    precondition(words.count == 24)
    var out = beluga_core_screen_liveness_sample_t()
    out.generation = words[0]
    out.observed_at = words[1]
    out.track_attached = words[2]
    out.cover = words[3]
    out.inbound_present = words[4]
    out.inbound_bytes.present = words[5]
    out.inbound_bytes.value = words[6]
    out.inbound_packets.present = words[7]
    out.inbound_packets.value = words[8]
    out.decoded_frames.present = words[9]
    out.decoded_frames.value = words[10]
    out.inbound_width.present = words[11]
    out.inbound_width.value = words[12]
    out.inbound_height.present = words[13]
    out.inbound_height.value = words[14]
    out.frames_per_second_bits.present = words[15]
    out.frames_per_second_bits.value = words[16]
    out.render_present = words[17]
    out.presented_frames = words[18]
    out.content_samples = words[19]
    out.content_changes = words[20]
    out.presented_at = words[21]
    out.render_width_bits = words[22]
    out.render_height_bits = words[23]
    return out
}
private func livenessSwiftSampleWords(_ sample: beluga_core_screen_liveness_sample_t) -> [UInt64] {
    var out = [UInt64](repeating: 0, count: 24)
    out[0] = sample.generation
    out[1] = sample.observed_at
    out[2] = sample.track_attached
    out[3] = sample.cover
    out[4] = sample.inbound_present
    out[5] = sample.inbound_bytes.present
    out[6] = sample.inbound_bytes.value
    out[7] = sample.inbound_packets.present
    out[8] = sample.inbound_packets.value
    out[9] = sample.decoded_frames.present
    out[10] = sample.decoded_frames.value
    out[11] = sample.inbound_width.present
    out[12] = sample.inbound_width.value
    out[13] = sample.inbound_height.present
    out[14] = sample.inbound_height.value
    out[15] = sample.frames_per_second_bits.present
    out[16] = sample.frames_per_second_bits.value
    out[17] = sample.render_present
    out[18] = sample.presented_frames
    out[19] = sample.content_samples
    out[20] = sample.content_changes
    out[21] = sample.presented_at
    out[22] = sample.render_width_bits
    out[23] = sample.render_height_bits
    return out
}
private func livenessSwiftStateFromWords(_ words: [UInt64]) -> beluga_core_screen_liveness_state_t {
    precondition(words.count == 27)
    var out = beluga_core_screen_liveness_state_t()
    out.previous_present = words[0]
    out.last_change_at.present = words[1]
    out.last_change_at.value = words[2]
    out.previous = livenessSwiftSampleFromWords(Array(words[3..<27]))
    return out
}
private func livenessSwiftStateWords(_ state: beluga_core_screen_liveness_state_t) -> [UInt64] {
    [state.previous_present, state.last_change_at.present, state.last_change_at.value]
        + livenessSwiftSampleWords(state.previous)
}
private func livenessSwiftSnapshotWords(_ snapshot: beluga_core_screen_liveness_snapshot_t) -> [UInt64] {
    var out = [UInt64](repeating: 0, count: 37)
    out[0] = snapshot.liveness
    out[1] = snapshot.reset_reason
    out[2] = snapshot.generation
    out[3] = snapshot.track_attached
    out[4] = snapshot.cover
    out[5] = snapshot.inbound_bytes.present
    out[6] = snapshot.inbound_bytes.value
    out[7] = snapshot.inbound_byte_delta.present
    out[8] = snapshot.inbound_byte_delta.value
    out[9] = snapshot.inbound_packets.present
    out[10] = snapshot.inbound_packets.value
    out[11] = snapshot.inbound_packet_delta.present
    out[12] = snapshot.inbound_packet_delta.value
    out[13] = snapshot.decoded_frames.present
    out[14] = snapshot.decoded_frames.value
    out[15] = snapshot.decoded_frame_delta.present
    out[16] = snapshot.decoded_frame_delta.value
    out[17] = snapshot.presented_frames.present
    out[18] = snapshot.presented_frames.value
    out[19] = snapshot.presented_frame_delta.present
    out[20] = snapshot.presented_frame_delta.value
    out[21] = snapshot.content_samples.present
    out[22] = snapshot.content_samples.value
    out[23] = snapshot.content_sample_delta.present
    out[24] = snapshot.content_sample_delta.value
    out[25] = snapshot.content_changes.present
    out[26] = snapshot.content_changes.value
    out[27] = snapshot.content_change_delta.present
    out[28] = snapshot.content_change_delta.value
    out[29] = snapshot.presentation_age_ms.present
    out[30] = snapshot.presentation_age_ms.value
    out[31] = snapshot.frame_width.present
    out[32] = snapshot.frame_width.value
    out[33] = snapshot.frame_height.present
    out[34] = snapshot.frame_height.value
    out[35] = snapshot.frames_per_second_bits.present
    out[36] = snapshot.frames_per_second_bits.value
    return out
}
private func livenessSwiftResultWords(_ result: beluga_core_screen_liveness_result_t) -> [UInt64] {
    [result.abi_version, result.status, result.reserved]
        + livenessSwiftStateWords(result.state)
        + livenessSwiftSnapshotWords(result.snapshot)
}

func screenLivenessFullCustodySmoke() {
    // Retain the frozen original layout/stride/offset and behavior prefix.
    screenLivenessSmoke()
    for row in livenessSwiftCases {
        precondition(livenessSwiftStates.indices.contains(row.beforeIndex))
        precondition(livenessSwiftStates.indices.contains(row.afterIndex))
        precondition(livenessSwiftSamples.indices.contains(row.sampleIndex))
        precondition(livenessSwiftSnapshots.indices.contains(row.snapshotIndex))
        let before = livenessSwiftStateFromWords(livenessSwiftStates[row.beforeIndex])
        let sample = livenessSwiftSampleFromWords(livenessSwiftSamples[row.sampleIndex])

        // Actual export first: no fallback, callback, corruption, or policy helper.
        let result = beluga_core_screen_liveness_observe(row.abi, before, sample)
        let actual = livenessSwiftResultWords(result)
        let expected: [UInt64] = [1, row.status, 0]
            + livenessSwiftStates[row.afterIndex]
            + livenessSwiftSnapshots[row.snapshotIndex]
        precondition(actual.count == 67 && expected.count == 67)
        for word in 0..<67 {
            precondition(actual[word] == expected[word], "\(row.name): result word \(word)")
        }
        precondition(livenessSwiftStateWords(before) == livenessSwiftStates[row.beforeIndex],
                     "\(row.name): all 27 before-state words unchanged")
        precondition(livenessSwiftSampleWords(sample) == livenessSwiftSamples[row.sampleIndex],
                     "\(row.name): all 24 sample words unchanged")
    }
    // No PASS marker here; root must emit it only after this entrypoint returns.
}

screenLivenessFullCustodySmoke()
print("BelugaCore Swift screen liveness import/link PASS: exact copied layouts, full-width values and unchanged refusal")

// Private unexecuted addition: append after the existing Swift marker sequence.
// Uses its existing import BelugaCore. All exported values are copied scalars.
private func updateOperationSmoke() {
    typealias State = BelugaUpdateOperationState
    typealias Event = BelugaUpdateOperationEvent
    typealias Output = BelugaUpdateOperationResult
    precondition(MemoryLayout<State>.size == 40 && MemoryLayout<State>.stride == 40 && MemoryLayout<State>.alignment == 4)
    precondition(MemoryLayout<Event>.size == 40 && MemoryLayout<Event>.stride == 40 && MemoryLayout<Event>.alignment == 4)
    precondition(MemoryLayout<Output>.size == 56 && MemoryLayout<Output>.stride == 56 && MemoryLayout<Output>.alignment == 4)
    let stateFields: [WritableKeyPath<State, UInt32>] = [
        \.abi_version, \.reserved, \.stage, \.broker_present, \.candidate_present,
        \.recorded_readiness_present, \.installed_fresh, \.readiness_fresh,
        \.challenge_present, \.reserved_tail
    ]
    let eventFields: [WritableKeyPath<Event, UInt32>] = [
        \.opcode, \.reserved, \.fact0, \.fact1, \.fact2, \.fact3,
        \.fact4, \.fact5, \.fact6, \.reserved_tail
    ]
    for field in 0..<10 {
        precondition(MemoryLayout<State>.offset(of: stateFields[field]) == field * 4)
        precondition(MemoryLayout<Event>.offset(of: eventFields[field]) == field * 4)
    }
    precondition(MemoryLayout<Output>.offset(of: \.candidate_state) == 0)
    precondition(MemoryLayout<Output>.offset(of: \.decision) == 40)
    precondition(MemoryLayout<Output>.offset(of: \.action) == 44)
    precondition(MemoryLayout<Output>.offset(of: \.predicate) == 48)
    precondition(MemoryLayout<Output>.offset(of: \.reserved) == 52)
    func state(_ stage: UInt32, _ broker: UInt32, _ candidate: UInt32,
               _ recorded: UInt32, _ installed: UInt32,
               _ readiness: UInt32, _ challenge: UInt32) -> State {
        var value = State()
        value.abi_version = 1; value.stage = stage; value.broker_present = broker
        value.candidate_present = candidate; value.recorded_readiness_present = recorded
        value.installed_fresh = installed; value.readiness_fresh = readiness
        value.challenge_present = challenge
        return value
    }
    func event(_ opcode: UInt32, _ f0: UInt32 = 0, _ f1: UInt32 = 0,
               _ f2: UInt32 = 0, _ f3: UInt32 = 0, _ f4: UInt32 = 0,
               _ f5: UInt32 = 0, _ f6: UInt32 = 0) -> Event {
        var value = Event(); value.opcode = opcode
        value.fact0 = f0; value.fact1 = f1; value.fact2 = f2; value.fact3 = f3
        value.fact4 = f4; value.fact5 = f5; value.fact6 = f6
        return value
    }
    func stateWords(_ value: State) -> [UInt32] { stateFields.map { value[keyPath: $0] } }
    func eventWords(_ value: Event) -> [UInt32] { eventFields.map { value[keyPath: $0] } }
    func check(_ abi: UInt32, _ before: State, _ input: Event, _ expected: State,
               _ decision: UInt32, _ action: UInt32, _ predicate: UInt32) {
        let saved = stateWords(before); let savedInput = eventWords(input)
        let actual = beluga_core_update_operation_step(abi, before, input)
        precondition(stateWords(actual.candidate_state) == stateWords(expected))
        precondition(actual.decision == decision && actual.action == action &&
            actual.predicate == predicate && actual.reserved == 0)
        precondition(stateWords(before) == saved && eventWords(input) == savedInput)
    }
    func invalid(_ abi: UInt32, _ before: State, _ input: Event) {
        check(abi, before, input, before, 2, 0, 0)
    }
    func fact(_ input: Event, _ slot: Int, _ value: UInt32) -> Event {
        precondition((0..<7).contains(slot))
        var result = input; result[keyPath: eventFields[slot + 2]] = value
        return result
    }
    // Literal expected plans; constructors only create DTOs, not an oracle.
    let prepared = state(0, 0, 0, 0, 0, 0, 0)
    let broker = state(0, 1, 0, 0, 0, 0, 0)
    let armed = state(1, 1, 0, 0, 0, 0, 0)
    let candidate = state(1, 1, 1, 0, 0, 0, 0)
    let installed = state(2, 1, 1, 0, 1, 0, 0)
    let challenged = state(2, 1, 1, 0, 1, 0, 1)
    let ready = state(3, 1, 1, 1, 1, 1, 0)
    let restored = state(3, 1, 1, 1, 0, 0, 0)
    let bindBroker = event(0, 1, 1, 1, 1)
    let bindCandidate = event(1, 1, 1, 1, 1)
    let completion = event(3, 1, 1)
    let challenge = event(4, 1, 1, 1, 1, 1, 1)
    let preflight = event(5, 1, 1, 1, 1, 1, 1)
    let commit = event(6, 1, 1, 1, 1, 1, 1, 1)
    check(1, prepared, bindBroker, broker, 0, 1, 0)
    check(1, broker, bindBroker, broker, 1, 0, 0)
    check(1, broker, event(2, 1), armed, 0, 3, 0)
    check(1, armed, bindCandidate, candidate, 0, 2, 0)
    check(1, candidate, fact(completion, 1, 0), candidate, 1, 0, 0)
    check(1, candidate, completion, installed, 0, 4, 0)
    check(1, installed, challenge, challenged, 0, 5, 0)
    check(1, challenged, preflight, challenged, 0, 6, 0)
    check(1, challenged, fact(preflight, 5, 0), challenged, 1, 0, 0)
    check(1, challenged, fact(commit, 6, 0), challenged, 1, 0, 0)
    check(1, challenged, commit, ready, 0, 7, 0)
    check(1, ready, commit, ready, 1, 0, 0) // one-use challenge
    check(1, ready, event(7), ready, 0, 0, 0)
    check(1, ready, event(8), ready, 0, 0, 0)
    for opcode: UInt32 in [9, 10] {
        check(1, ready, event(opcode), restored, 0, 8, 0)
        check(1, challenged, event(opcode), state(2, 1, 1, 0, 0, 0, 0), 0, 8, 0)
    }
    check(1, prepared, event(11), prepared, 0, 0, 0)
    check(1, ready, event(11), ready, 0, 0, 1)
    check(1, ready, event(12), ready, 0, 0, 1)
    check(1, restored, event(12), restored, 0, 0, 0)
    check(1, ready, event(13), ready, 0, 0, 0)
    check(1, restored, completion, state(3, 1, 1, 1, 1, 0, 0), 0, 4, 0)
    // Closed projections intentionally do not invent a native whole-record invariant.
    check(1, state(3, 1, 0, 0, 1, 1, 0), event(12), state(3, 1, 0, 0, 1, 1, 0), 0, 0, 1)

    for bad: UInt32 in [0, 2, UInt32.max] {
        invalid(bad, challenged, commit)
        var raw = challenged; raw.abi_version = bad; invalid(1, raw, commit)
    }
    for bad: UInt32 in [4, UInt32.max] {
        var raw = challenged; raw.stage = bad; invalid(1, raw, commit)
    }
    for field in 3...8 {
        for bad: UInt32 in [2, UInt32.max] {
            var raw = challenged; raw[keyPath: stateFields[field]] = bad
            invalid(1, raw, commit)
        }
    }
    for bit in 0..<32 {
        let bad = UInt32(1) << bit
        for field in [1, 9] {
            var raw = challenged; raw[keyPath: stateFields[field]] = bad
            invalid(1, raw, commit)
            var input = commit; input[keyPath: eventFields[field]] = bad
            invalid(1, challenged, input)
        }
    }
    for slot in 0..<7 {
        invalid(1, challenged, fact(commit, slot, 2))
        invalid(1, challenged, fact(commit, slot, UInt32.max))
    }
    for bad: UInt32 in [14, UInt32.max] {
        var input = commit; input.opcode = bad; invalid(1, challenged, input)
    }
    let used = [4, 4, 1, 2, 6, 6, 7, 0, 0, 0, 0, 0, 0, 0]
    for opcode in 0..<14 {
        for slot in used[opcode]..<7 {
            invalid(1, challenged, fact(event(UInt32(opcode)), slot, 1))
        }
    }
}

updateOperationSmoke()
print("BelugaCore Swift update operation import/link PASS: three copied layouts, exact phase plans and unchanged refusal")
precondition(MemoryLayout<beluga_core_packet_send_queue_state_t>.size == 48)
precondition(MemoryLayout<beluga_core_packet_send_queue_event_t>.size == 64)
precondition(MemoryLayout<beluga_core_packet_send_queue_result_t>.size == 96)
precondition(MemoryLayout<beluga_core_packet_send_queue_state_t>.offset(of: \.packets) == 24)
precondition(MemoryLayout<beluga_core_packet_send_queue_event_t>.offset(of: \.low_age_seconds) == 32)
precondition(MemoryLayout<beluga_core_packet_send_queue_result_t>.offset(of: \.state) == 48)
var packetQueueState = beluga_core_packet_send_queue_state_t()
packetQueueState.abi_version = 1
var packetQueueEvent = beluga_core_packet_send_queue_event_t()
packetQueueEvent.packets_present = 1; packetQueueEvent.delay_present = 1
packetQueueEvent.packets = UInt64.max - 1
var packetQueueResult = beluga_core_packet_send_queue_step(packetQueueState, packetQueueEvent)
precondition(packetQueueResult.status == 1 && packetQueueResult.observation == 0)
packetQueueState = packetQueueResult.state
packetQueueEvent.packets = UInt64.max; packetQueueEvent.delay_bits = 0.020.bitPattern
packetQueueResult = beluga_core_packet_send_queue_step(packetQueueState, packetQueueEvent)
precondition(packetQueueResult.status == 1 && packetQueueResult.observation == 2 && packetQueueResult.upgrade == 1)
precondition(packetQueueResult.measured_delay_bits == 0.020.bitPattern && packetQueueResult.low_action == 2)
packetQueueState = packetQueueResult.state
packetQueueEvent.low_age_seconds = 1; packetQueueEvent.low_age_attoseconds = 500_000_000_000_000_000
packetQueueResult = beluga_core_packet_send_queue_step(packetQueueState, packetQueueEvent)
precondition(packetQueueResult.observation == 1 && packetQueueResult.upgrade == 1 && packetQueueResult.low_action == 0)
packetQueueEvent.low_age_attoseconds += 1
packetQueueResult = beluga_core_packet_send_queue_step(packetQueueState, packetQueueEvent)
precondition(packetQueueResult.observation == 1 && packetQueueResult.upgrade == 0 && packetQueueResult.low_action == 1)
packetQueueState.reserved = 1
packetQueueResult = beluga_core_packet_send_queue_step(packetQueueState, packetQueueEvent)
precondition(packetQueueResult.status == 0 && packetQueueResult.upgrade == 0 && packetQueueResult.capacity_growth == 0)
print("BelugaCore Swift packet queue import/link PASS: exact layouts, full-width counters and bounded evidence leases")
precondition(MemoryLayout<beluga_core_rtt_evidence_measurement_t>.size == 80)
precondition(MemoryLayout<beluga_core_rtt_evidence_state_t>.size == 296)
precondition(MemoryLayout<beluga_core_rtt_evidence_event_t>.size == 128)
precondition(MemoryLayout<beluga_core_rtt_evidence_result_t>.size == 336)
precondition(MemoryLayout<beluga_core_rtt_evidence_state_t>.offset(of: \.watermark) == 128)
precondition(MemoryLayout<beluga_core_rtt_evidence_event_t>.offset(of: \.age_seconds) == 112)
precondition(MemoryLayout<beluga_core_rtt_evidence_result_t>.offset(of: \.state) == 40)
var rttState = beluga_core_rtt_evidence_state_t()
rttState.abi_version = 1; rttState.disposition = 6; rttState.permits_initial = 1
var rttEvent = beluga_core_rtt_evidence_event_t()
rttEvent.observation_kind = 2; rttEvent.fingerprint_length = 64
rttEvent.current_present = 1; rttEvent.current_bits = Double(0.1).bitPattern
let rttFingerprint: UInt64 = 0x6161616161616161
rttEvent.measurement.fingerprint_words = (rttFingerprint,rttFingerprint,rttFingerprint,rttFingerprint,rttFingerprint,rttFingerprint,rttFingerprint,rttFingerprint)
rttEvent.measurement.total_bits = Double(0.2).bitPattern; rttEvent.measurement.responses = UInt64.max
var rttResult = beluga_core_rtt_evidence_step(rttState, rttEvent)
precondition(rttResult.status == 1 && rttResult.allows_upgrade == 1 && rttResult.clock_action == 2)
precondition(rttResult.state.watermark.responses == UInt64.max)
precondition(beluga_core_rtt_evidence_result_is_valid(rttState, rttEvent, rttResult) == 1)
rttState = rttResult.state; rttEvent.age_seconds = 4
rttResult = beluga_core_rtt_evidence_step(rttState, rttEvent)
precondition(rttResult.allows_upgrade == 1 && rttResult.clock_action == 0 && rttResult.state.disposition == 4)
rttEvent.age_attoseconds = 1
rttResult = beluga_core_rtt_evidence_step(rttState, rttEvent)
precondition(rttResult.allows_upgrade == 0 && rttResult.state.disposition == 7)
rttResult.allows_upgrade = 1
precondition(beluga_core_rtt_evidence_result_is_valid(rttState, rttEvent, rttResult) == 0)
print("BelugaCore Swift RTT evidence import/link PASS: exact copied layouts, identity and nonrenewable freshness")
// Append after the existing RTT runtime marker; do not alter predecessor smoke bodies.
precondition(MemoryLayout<beluga_core_tier_demand_facts_t>.size == 24)
precondition(MemoryLayout<beluga_core_tier_demand_facts_t>.alignment == 8)
precondition(MemoryLayout<beluga_core_tier_demand_projection_t>.size == 80)
precondition(MemoryLayout<beluga_core_tier_demand_projection_t>.alignment == 8)
precondition(MemoryLayout<beluga_core_tier_demand_facts_t>.offset(of: \.abi_version) == 0)
precondition(MemoryLayout<beluga_core_tier_demand_facts_t>.offset(of: \.configured_cap) == 4)
precondition(MemoryLayout<beluga_core_tier_demand_facts_t>.offset(of: \.current_tier) == 8)
precondition(MemoryLayout<beluga_core_tier_demand_facts_t>.offset(of: \.bandwidth_present) == 12)
precondition(MemoryLayout<beluga_core_tier_demand_facts_t>.offset(of: \.bandwidth_bits) == 16)
precondition(MemoryLayout<beluga_core_tier_demand_projection_t>.offset(of: \.abi_version) == 0)
precondition(MemoryLayout<beluga_core_tier_demand_projection_t>.offset(of: \.status) == 4)
precondition(MemoryLayout<beluga_core_tier_demand_projection_t>.offset(of: \.current_tier) == 8)
precondition(MemoryLayout<beluga_core_tier_demand_projection_t>.offset(of: \.reserved) == 12)
precondition(MemoryLayout<beluga_core_tier_demand_projection_t>.offset(of: \.basis_points) == 16)
precondition(MemoryLayout<beluga_core_tier_demand_projection_t>.offset(of: \.baseline_video) == 20)
precondition(MemoryLayout<beluga_core_tier_demand_projection_t>.offset(of: \.maximum_tier_video) == 24)
precondition(MemoryLayout<beluga_core_tier_demand_projection_t>.offset(of: \.maximum_video) == 28)
precondition(MemoryLayout<beluga_core_tier_demand_projection_t>.offset(of: \.maximum_total_rtp) == 32)
precondition(MemoryLayout<beluga_core_tier_demand_projection_t>.offset(of: \.minimum_sustainable) == 36)
precondition(MemoryLayout<beluga_core_tier_demand_projection_t>.offset(of: \.initial_tier) == 40)
precondition(MemoryLayout<beluga_core_tier_demand_projection_t>.offset(of: \.sustainable_tier) == 44)
precondition(MemoryLayout<beluga_core_tier_demand_projection_t>.offset(of: \.upgrade_present) == 48)
precondition(MemoryLayout<beluga_core_tier_demand_projection_t>.offset(of: \.upgrade_tier) == 52)
precondition(MemoryLayout<beluga_core_tier_demand_projection_t>.offset(of: \.direct_threshold_present) == 56)
precondition(MemoryLayout<beluga_core_tier_demand_projection_t>.offset(of: \.direct_threshold_minimum) == 60)
precondition(MemoryLayout<beluga_core_tier_demand_projection_t>.offset(of: \.required_bitrate_bits) == 64)
precondition(MemoryLayout<beluga_core_tier_demand_projection_t>.offset(of: \.direct_threshold_bits) == 72)
var tierDemandFacts = beluga_core_tier_demand_facts_t()
tierDemandFacts.abi_version = 1; tierDemandFacts.configured_cap = 50_000_000
tierDemandFacts.current_tier = 0; tierDemandFacts.bandwidth_present = 1
tierDemandFacts.bandwidth_bits = Double(15_000_000).bitPattern
var tierDemandProjection = beluga_core_tier_demand_project(tierDemandFacts)
precondition(tierDemandProjection.status == 1 && tierDemandProjection.basis_points == 10_000)
precondition(tierDemandProjection.maximum_tier_video == 39_744_000 && tierDemandProjection.maximum_video == 39_744_000)
precondition(tierDemandProjection.maximum_total_rtp == 16_200_001 && tierDemandProjection.minimum_sustainable == 12_000_000)
precondition(tierDemandProjection.initial_tier == 5 && tierDemandProjection.sustainable_tier == 0)
precondition(tierDemandProjection.upgrade_present == 0 && tierDemandProjection.direct_threshold_present == 0)
precondition(tierDemandProjection.required_bitrate_bits == Double(12_000_000).bitPattern)
precondition(beluga_core_tier_demand_projection_is_valid(tierDemandFacts, tierDemandProjection) == 1)
tierDemandFacts.current_tier = 7
tierDemandProjection = beluga_core_tier_demand_project(tierDemandFacts)
precondition(tierDemandProjection.upgrade_present == 1 && tierDemandProjection.upgrade_tier == 0)
precondition(tierDemandProjection.direct_threshold_minimum == 546_000 && tierDemandProjection.direct_threshold_bits == Double(546_000).bitPattern)
tierDemandProjection.reserved = 1
precondition(beluga_core_tier_demand_projection_is_valid(tierDemandFacts, tierDemandProjection) == 0)
tierDemandFacts.configured_cap = UInt32.max; tierDemandFacts.current_tier = 1
tierDemandProjection = beluga_core_tier_demand_project(tierDemandFacts)
precondition(tierDemandProjection.maximum_tier_video == 3_435_717_836 && tierDemandProjection.maximum_video == 2_301_930_950)
tierDemandFacts.configured_cap = 0
tierDemandProjection = beluga_core_tier_demand_project(tierDemandFacts)
precondition(tierDemandProjection.abi_version == 1 && tierDemandProjection.status == 0)
precondition(tierDemandProjection.current_tier == 0 && tierDemandProjection.reserved == 0)
precondition(tierDemandProjection.basis_points == 0 && tierDemandProjection.baseline_video == 0)
precondition(tierDemandProjection.maximum_tier_video == 0 && tierDemandProjection.maximum_video == 0)
precondition(tierDemandProjection.maximum_total_rtp == 0 && tierDemandProjection.minimum_sustainable == 0)
precondition(tierDemandProjection.initial_tier == 0 && tierDemandProjection.sustainable_tier == 0)
precondition(tierDemandProjection.upgrade_present == 0 && tierDemandProjection.upgrade_tier == 0)
precondition(tierDemandProjection.direct_threshold_present == 0 && tierDemandProjection.direct_threshold_minimum == 0)
precondition(tierDemandProjection.required_bitrate_bits == 0 && tierDemandProjection.direct_threshold_bits == 0)
precondition(beluga_core_tier_demand_projection_is_valid(tierDemandFacts, tierDemandProjection) == 0)
print("BelugaCore Swift tier demand import/link PASS: exact copied layouts, calibrated budgets and checked projections")
// Append after the final existing tier-demand marker. Preserve its entire predecessor prefix.
func mediaCommandGateSmoke() {
    typealias State = beluga_core_media_command_gate_state_t
    typealias Event = beluga_core_media_command_gate_event_t
    typealias Result = beluga_core_media_command_gate_result_t
    precondition(MemoryLayout<State>.size == 24 && MemoryLayout<State>.stride == 24 && MemoryLayout<State>.alignment == 8)
    precondition(MemoryLayout<Event>.size == 32 && MemoryLayout<Event>.stride == 32 && MemoryLayout<Event>.alignment == 8)
    precondition(MemoryLayout<Result>.size == 40 && MemoryLayout<Result>.stride == 40 && MemoryLayout<Result>.alignment == 8)
    precondition(MemoryLayout<State>.offset(of: \.abi_version) == 0)
    precondition(MemoryLayout<State>.offset(of: \.is_open) == 4)
    precondition(MemoryLayout<State>.offset(of: \.lifecycle) == 8)
    precondition(MemoryLayout<State>.offset(of: \.command_epoch) == 16)
    precondition(MemoryLayout<Event>.offset(of: \.opcode) == 0)
    precondition(MemoryLayout<Event>.offset(of: \.context_is_current) == 4)
    precondition(MemoryLayout<Event>.offset(of: \.reserved0) == 8)
    precondition(MemoryLayout<Event>.offset(of: \.reserved1) == 12)
    precondition(MemoryLayout<Event>.offset(of: \.candidate_lifecycle) == 16)
    precondition(MemoryLayout<Event>.offset(of: \.candidate_command_epoch) == 24)
    precondition(MemoryLayout<Result>.offset(of: \.abi_version) == 0)
    precondition(MemoryLayout<Result>.offset(of: \.status) == 4)
    precondition(MemoryLayout<Result>.offset(of: \.allowed) == 8)
    precondition(MemoryLayout<Result>.offset(of: \.reserved) == 12)
    precondition(MemoryLayout<Result>.offset(of: \.state) == 16)
    func state(_ open: UInt32, _ life: UInt64, _ epoch: UInt64) -> State {
        var value = State(); value.abi_version = 1; value.is_open = open
        value.lifecycle = life; value.command_epoch = epoch; return value
    }
    func event(_ opcode: UInt32, _ member: UInt32 = 0, _ life: UInt64 = 0, _ epoch: UInt64 = 0) -> Event {
        var value = Event(); value.opcode = opcode; value.context_is_current = member
        value.candidate_lifecycle = life; value.candidate_command_epoch = epoch; return value
    }
    func equal(_ actual: State, _ expected: State) {
        precondition(actual.abi_version == expected.abi_version && actual.is_open == expected.is_open)
        precondition(actual.lifecycle == expected.lifecycle && actual.command_epoch == expected.command_epoch)
    }
    let initial = state(0, 0, 0), maximum = state(0, UInt64.max, UInt64.max)
    let open = event(0), capture = event(4, 1), lifecycleZero = event(3), admitZero = event(5, 1)
    var result = beluga_core_media_command_gate_step(initial, capture)
    precondition(result.abi_version == 1 && result.status == 1 && result.allowed == 0 && result.reserved == 0)
    equal(result.state, initial)
    precondition(beluga_core_media_command_gate_result_is_valid(initial, capture, result) == 1)
    result = beluga_core_media_command_gate_step(maximum, open)
    let wrapped = state(1, 0, 0)
    precondition(result.abi_version == 1 && result.status == 1 && result.allowed == 0 && result.reserved == 0)
    equal(result.state, wrapped)
    precondition(beluga_core_media_command_gate_result_is_valid(maximum, open, result) == 1)
    result = beluga_core_media_command_gate_step(wrapped, lifecycleZero)
    precondition(result.status == 1 && result.allowed == 1 && result.reserved == 0)
    equal(result.state, wrapped)
    precondition(beluga_core_media_command_gate_result_is_valid(wrapped, lifecycleZero, result) == 1)
    result.state.command_epoch = 1
    precondition(beluga_core_media_command_gate_result_is_valid(wrapped, lifecycleZero, result) == 0)
    result = beluga_core_media_command_gate_step(wrapped, admitZero)
    precondition(result.status == 1 && result.allowed == 1)
    precondition(beluga_core_media_command_gate_result_is_valid(wrapped, admitZero, result) == 1)
    result = beluga_core_media_command_gate_step(wrapped, event(2))
    let invalidated = state(1, 0, 1)
    precondition(result.status == 1 && result.allowed == 0)
    equal(result.state, invalidated)
    result = beluga_core_media_command_gate_step(invalidated, lifecycleZero)
    precondition(result.status == 1 && result.allowed == 1)
    result = beluga_core_media_command_gate_step(invalidated, admitZero)
    precondition(result.status == 1 && result.allowed == 0)
    result = beluga_core_media_command_gate_step(invalidated, event(5, 1, 0, 1))
    precondition(result.status == 1 && result.allowed == 1)
    result = beluga_core_media_command_gate_step(invalidated, event(1))
    precondition(result.status == 1 && result.allowed == 0)
    equal(result.state, state(0, 1, 2))
    for bad in [event(4, 2), event(0, 0, 1)] {
        result = beluga_core_media_command_gate_step(wrapped, bad)
        precondition(result.abi_version == 1 && result.status == 0 && result.allowed == 0 && result.reserved == 0)
        equal(result.state, initial)
        precondition(beluga_core_media_command_gate_result_is_valid(wrapped, bad, result) == 0)
    }
}
mediaCommandGateSmoke()
print("BelugaCore Swift media command gate import/link PASS: exact copied layouts, wrapping epochs and checked admission")

// Private additive smoke: append only after prior media-command marker.
func screenSuspensionSmoke() {
    typealias State = beluga_core_screen_suspension_state_t
    typealias Event = beluga_core_screen_suspension_event_t
    typealias Result = beluga_core_screen_suspension_result_t
    precondition(MemoryLayout<State>.size == 88 && MemoryLayout<State>.stride == 88 && MemoryLayout<State>.alignment == 8)
    precondition(MemoryLayout<State>.offset(of: \.abi_version) == 0)
    precondition(MemoryLayout<State>.offset(of: \.phase) == 4)
    precondition(MemoryLayout<State>.offset(of: \.next_generation) == 8)
    precondition(MemoryLayout<State>.offset(of: \.screen_request_id) == 16)
    precondition(MemoryLayout<State>.offset(of: \.suspension_generation) == 24)
    precondition(MemoryLayout<State>.offset(of: \.peer_generation) == 32)
    precondition(MemoryLayout<State>.offset(of: \.visibility_epoch) == 40)
    precondition(MemoryLayout<State>.offset(of: \.recovery_epoch) == 48)
    precondition(MemoryLayout<State>.offset(of: \.prior_screen_request_id) == 56)
    precondition(MemoryLayout<State>.offset(of: \.prior_suspension_generation) == 64)
    precondition(MemoryLayout<State>.offset(of: \.cover_confirmed) == 72)
    precondition(MemoryLayout<State>.offset(of: \.inactive_confirmed) == 76)
    precondition(MemoryLayout<State>.offset(of: \.custody_mask) == 80)
    precondition(MemoryLayout<State>.offset(of: \.reserved) == 84)
    precondition(MemoryLayout<Event>.size == 64 && MemoryLayout<Event>.stride == 64 && MemoryLayout<Event>.alignment == 8)
    precondition(MemoryLayout<Event>.offset(of: \.opcode) == 0)
    precondition(MemoryLayout<Event>.offset(of: \.flags) == 4)
    precondition(MemoryLayout<Event>.offset(of: \.native_facts) == 8)
    precondition(MemoryLayout<Event>.offset(of: \.reserved) == 12)
    precondition(MemoryLayout<Event>.offset(of: \.screen_request_id) == 16)
    precondition(MemoryLayout<Event>.offset(of: \.peer_generation) == 24)
    precondition(MemoryLayout<Event>.offset(of: \.visibility_epoch) == 32)
    precondition(MemoryLayout<Event>.offset(of: \.recovery_epoch) == 40)
    precondition(MemoryLayout<Event>.offset(of: \.notice_screen_request_id) == 48)
    precondition(MemoryLayout<Event>.offset(of: \.notice_generation) == 56)
    precondition(MemoryLayout<Result>.size == 128 && MemoryLayout<Result>.stride == 128 && MemoryLayout<Result>.alignment == 8)
    precondition(MemoryLayout<Result>.offset(of: \.abi_version) == 0)
    precondition(MemoryLayout<Result>.offset(of: \.status) == 4)
    precondition(MemoryLayout<Result>.offset(of: \.accepted) == 8)
    precondition(MemoryLayout<Result>.offset(of: \.custody_action) == 12)
    precondition(MemoryLayout<Result>.offset(of: \.state) == 16)
    precondition(MemoryLayout<Result>.offset(of: \.query_flags) == 104)
    precondition(MemoryLayout<Result>.offset(of: \.reserved) == 108)
    precondition(MemoryLayout<Result>.offset(of: \.produced_notice_screen_request_id) == 112)
    precondition(MemoryLayout<Result>.offset(of: \.produced_notice_generation) == 120)
    func checked(_ state: State, _ event: Event) -> Result {
        let result = beluga_core_screen_suspension_step(state, event)
        precondition(result.abi_version == 1 && result.status == 1 && result.reserved == 0)
        precondition(beluga_core_screen_suspension_result_is_valid(state, event, result) == 1)
        return result
    }
    func event(_ opcode: UInt32, _ state: State, facts: UInt32 = 0, notice: Bool = false) -> Event {
        var event = Event(); event.opcode = opcode; event.native_facts = facts
        event.peer_generation = state.peer_generation; event.visibility_epoch = state.visibility_epoch
        event.recovery_epoch = state.recovery_epoch
        if notice { event.notice_screen_request_id = state.screen_request_id; event.notice_generation = state.suspension_generation }
        return event
    }
    var state = State(); state.abi_version = 1; state.next_generation = UInt64.max
    var command = Event(); command.opcode = 1; command.screen_request_id = UInt64.max
    command.peer_generation = UInt64.max; command.visibility_epoch = UInt64.max - 1
    var result = checked(state, command)
    precondition(result.accepted == 1 && result.custody_action == 1 && result.query_flags == 72)
    state = result.state; command = event(4, state); command.flags = 1
    result = checked(state, command)
    precondition(result.accepted == 1 && result.custody_action == 3 && result.state.next_generation == 1)
    precondition(result.produced_notice_generation == UInt64.max && result.query_flags == 250)
    state = result.state
    command = event(6, state, facts: 1, notice: true); command.visibility_epoch = UInt64.max
    result = checked(state, command)
    precondition(result.accepted == 1 && result.custody_action == 0 && result.state.inactive_confirmed == 1)
    precondition(result.state.visibility_epoch == UInt64.max && result.state.phase == 2)
    state = result.state
    command = event(5, state, facts: 1 << 1, notice: true); command.visibility_epoch -= 1
    result = checked(state, command)
    precondition(result.accepted == 0 && result.state.visibility_epoch == UInt64.max && result.state.cover_confirmed == 0)
    command.visibility_epoch = UInt64.max
    result = checked(state, command)
    precondition(result.accepted == 1 && result.custody_action == 5 && result.state.phase == 3 && result.query_flags == 249)
    state = result.state; command = event(7, state, facts: 1 << 2)
    result = checked(state, command); precondition(result.accepted == 1 && result.state.custody_mask == 5); state = result.state
    let facts: [UInt32] = [(1 << 3) | (1 << 4), 1 << 5, (1 << 3) | (1 << 6) | (1 << 7), (1 << 3) | (1 << 8) | (1 << 9)]
    let masks: [UInt32] = [13, 21, 37, 69]
    for index in 0..<4 {
        command = event(8 + UInt32(index), state, facts: facts[index], notice: true)
        result = checked(state, command)
        precondition(result.accepted == 1 && result.state.phase == 5 + UInt32(index))
        precondition(result.state.custody_mask == masks[index] && result.query_flags == 253)
        state = result.state
    }
    command = event(16, state, facts: (1 << 3) | (1 << 10), notice: true)
    result = checked(state, command); precondition(result.accepted == 1 && result.custody_action == 0)
    result.accepted = 0; precondition(beluga_core_screen_suspension_result_is_valid(state, command, result) == 0)
    command = event(12, state, facts: 1 << 10, notice: true)
    result = checked(state, command)
    precondition(result.accepted == 1 && result.custody_action == 11 && result.query_flags == 248)
    precondition(result.state.phase == 1 && result.state.suspension_generation == UInt64.max); state = result.state
    command = event(14, state); command.flags = 1
    result = checked(state, command)
    precondition(result.accepted == 1 && result.custody_action == 12 && result.state.phase == 3); state = result.state
    command = Event(); command.opcode = 2
    result = checked(state, command)
    precondition(result.accepted == 1 && result.custody_action == 2 && result.state.phase == 0 && result.state.next_generation == 1)
    state = result.state; command = Event(); command.opcode = UInt32.max
    result = beluga_core_screen_suspension_step(state, command)
    precondition(result.abi_version == 1 && result.status == 0 && result.accepted == 0 && result.custody_action == 0)
    precondition(result.query_flags == 0 && result.reserved == 0 && result.state.next_generation == 1)
    precondition(beluga_core_screen_suspension_result_is_valid(state, command, result) == 0)
}
screenSuspensionSmoke()
print("BelugaCore Swift screen suspension import/link PASS: exact copied layouts, ordered transcript and retained provenance")

precondition(MemoryLayout<beluga_core_phone_catalog_input_t>.size == 104)
precondition(MemoryLayout<beluga_core_phone_catalog_input_t>.alignment == 8)
precondition(MemoryLayout<beluga_core_phone_catalog_result_t>.size == 72)
precondition(MemoryLayout<beluga_core_phone_catalog_result_t>.alignment == 8)
precondition(MemoryLayout<beluga_core_phone_catalog_input_t>.offset(of: \.abi_version) == 0)
precondition(MemoryLayout<beluga_core_phone_catalog_input_t>.offset(of: \.stage) == 4)
precondition(MemoryLayout<beluga_core_phone_catalog_input_t>.offset(of: \.operation) == 8)
precondition(MemoryLayout<beluga_core_phone_catalog_input_t>.offset(of: \.flags) == 12)
precondition(MemoryLayout<beluga_core_phone_catalog_input_t>.offset(of: \.count) == 16)
precondition(MemoryLayout<beluga_core_phone_catalog_input_t>.offset(of: \.selected_slot) == 20)
precondition(MemoryLayout<beluga_core_phone_catalog_input_t>.offset(of: \.target_slot) == 24)
precondition(MemoryLayout<beluga_core_phone_catalog_input_t>.offset(of: \.duplicate_axes) == 28)
precondition(MemoryLayout<beluga_core_phone_catalog_input_t>.offset(of: \.previous_phase) == 32)
precondition(MemoryLayout<beluga_core_phone_catalog_input_t>.offset(of: \.candidate_phase) == 36)
precondition(MemoryLayout<beluga_core_phone_catalog_input_t>.offset(of: \.previous_recovery) == 40)
precondition(MemoryLayout<beluga_core_phone_catalog_input_t>.offset(of: \.candidate_recovery) == 44)
precondition(MemoryLayout<beluga_core_phone_catalog_input_t>.offset(of: \.reserved0) == 48)
precondition(MemoryLayout<beluga_core_phone_catalog_input_t>.offset(of: \.reserved1) == 52)
precondition(MemoryLayout<beluga_core_phone_catalog_input_t>.offset(of: \.revision) == 56)
precondition(MemoryLayout<beluga_core_phone_catalog_input_t>.offset(of: \.previous_outbound) == 64)
precondition(MemoryLayout<beluga_core_phone_catalog_input_t>.offset(of: \.candidate_outbound) == 72)
precondition(MemoryLayout<beluga_core_phone_catalog_input_t>.offset(of: \.previous_accepted) == 80)
precondition(MemoryLayout<beluga_core_phone_catalog_input_t>.offset(of: \.candidate_accepted) == 88)
precondition(MemoryLayout<beluga_core_phone_catalog_input_t>.offset(of: \.reserved2) == 96)
precondition(MemoryLayout<beluga_core_phone_catalog_result_t>.offset(of: \.abi_version) == 0)
precondition(MemoryLayout<beluga_core_phone_catalog_result_t>.offset(of: \.status) == 4)
precondition(MemoryLayout<beluga_core_phone_catalog_result_t>.offset(of: \.error) == 8)
precondition(MemoryLayout<beluga_core_phone_catalog_result_t>.offset(of: \.action) == 12)
precondition(MemoryLayout<beluga_core_phone_catalog_result_t>.offset(of: \.count) == 16)
precondition(MemoryLayout<beluga_core_phone_catalog_result_t>.offset(of: \.selected_slot) == 20)
precondition(MemoryLayout<beluga_core_phone_catalog_result_t>.offset(of: \.target_slot) == 24)
precondition(MemoryLayout<beluga_core_phone_catalog_result_t>.offset(of: \.reserved) == 28)
precondition(MemoryLayout<beluga_core_phone_catalog_result_t>.offset(of: \.slot0) == 32)
precondition(MemoryLayout<beluga_core_phone_catalog_result_t>.offset(of: \.slot1) == 36)
precondition(MemoryLayout<beluga_core_phone_catalog_result_t>.offset(of: \.slot2) == 40)
precondition(MemoryLayout<beluga_core_phone_catalog_result_t>.offset(of: \.slot3) == 44)
precondition(MemoryLayout<beluga_core_phone_catalog_result_t>.offset(of: \.slot4) == 48)
precondition(MemoryLayout<beluga_core_phone_catalog_result_t>.offset(of: \.slot5) == 52)
precondition(MemoryLayout<beluga_core_phone_catalog_result_t>.offset(of: \.slot6) == 56)
precondition(MemoryLayout<beluga_core_phone_catalog_result_t>.offset(of: \.slot7) == 60)
precondition(MemoryLayout<beluga_core_phone_catalog_result_t>.offset(of: \.revision) == 64)

func phoneCatalogSmokeSlots(_ result: beluga_core_phone_catalog_result_t) -> [UInt32] {
    [result.slot0,result.slot1,result.slot2,result.slot3,result.slot4,result.slot5,result.slot6,result.slot7]
}
func phoneCatalogSmokeAssert(_ result: beluga_core_phone_catalog_result_t,
                            _ action: UInt32, _ count: UInt32, _ selected: UInt32,
                            _ target: UInt32, _ map: [UInt32], _ revision: UInt64) {
    precondition(result.abi_version == 1 && result.status == 1 && result.error == 0)
    precondition(result.action == action && result.count == count && result.selected_slot == selected)
    precondition(result.target_slot == target && result.reserved == 0 && result.revision == revision)
    precondition(phoneCatalogSmokeSlots(result) == map)
}
func phoneCatalogSmokeCorrupt(_ input: beluga_core_phone_catalog_input_t,
                             _ actual: beluga_core_phone_catalog_result_t) {
    precondition(beluga_core_phone_catalog_result_is_valid(input, actual) == 1)
    for byte in 0..<72 {
        for bit in 0..<8 {
            var mutant = actual
            withUnsafeMutableBytes(of: &mutant) { bytes in bytes[byte] ^= UInt8(1 << bit) }
            precondition(beluga_core_phone_catalog_result_is_valid(input, mutant) == 0)
        }
    }
}
for operation: UInt32 in 1...4 {
    var input = beluga_core_phone_catalog_input_t()
    input.abi_version = 1; input.stage = 10; input.operation = operation
    input.count = 3; input.selected_slot = 2; input.target_slot = operation == 1 ? 8 : 0
    var actual = beluga_core_phone_catalog_decide(input)
    // Independent original append/replace/select/remove expectations AFTER actual C.
    var expected: [UInt32] = [0,1,2,9,9,9,9,9]
    var count: UInt32 = 3, selected: UInt32 = 2
    if operation == 1 { expected[3] = 8; count = 4 }
    if operation == 2 { expected[0] = 8 }
    if operation == 3 { selected = 0 }
    if operation == 4 { expected[0] = 1; expected[1] = 2; expected[2] = 9; count = 2; selected = 1 }
    phoneCatalogSmokeAssert(actual, 1, count, selected, input.target_slot, expected, 0)
    phoneCatalogSmokeCorrupt(input, actual)
    input.stage = 11; input.revision = UInt64.max - 1
    actual = beluga_core_phone_catalog_decide(input)
    phoneCatalogSmokeAssert(actual, 3, count, selected, input.target_slot, expected, UInt64.max)
    phoneCatalogSmokeCorrupt(input, actual)
    input.revision = UInt64.max
    actual = beluga_core_phone_catalog_decide(input)
    precondition(actual.abi_version == 1 && actual.status == 1 && actual.error == 9 && actual.action == 0)
    precondition(actual.count == 0 && actual.selected_slot == 0 && actual.target_slot == 0)
    precondition(actual.reserved == 0 && actual.revision == 0 && phoneCatalogSmokeSlots(actual) == Array(repeating: 0, count: 8))
    phoneCatalogSmokeCorrupt(input, actual)
}
for operation: UInt32 in 2...3 {
    var input = beluga_core_phone_catalog_input_t()
    input.abi_version = 1; input.stage = 11; input.operation = operation; input.flags = 1
    input.count = 8; input.selected_slot = 7; input.target_slot = 7; input.revision = UInt64.max
    let actual = beluga_core_phone_catalog_decide(input)
    let original: [UInt32] = [0,1,2,3,4,5,6,7]
    phoneCatalogSmokeAssert(actual, 2, 8, 7, 7, original, UInt64.max)
    phoneCatalogSmokeCorrupt(input, actual)
}
var phoneCatalogSmokeInput = beluga_core_phone_catalog_input_t()
phoneCatalogSmokeInput.abi_version = 1; phoneCatalogSmokeInput.flags = 3
let phoneCatalogContinuation = beluga_core_phone_catalog_decide(phoneCatalogSmokeInput)
precondition(phoneCatalogContinuation.abi_version == 1 && phoneCatalogContinuation.status == 1)
precondition(phoneCatalogContinuation.error == 0 && phoneCatalogContinuation.action == 0 && phoneCatalogContinuation.count == 0)
precondition(phoneCatalogContinuation.selected_slot == 0 && phoneCatalogContinuation.target_slot == 0 && phoneCatalogContinuation.reserved == 0)
precondition(phoneCatalogContinuation.revision == 0 && phoneCatalogSmokeSlots(phoneCatalogContinuation) == Array(repeating: 0, count: 8))
phoneCatalogSmokeCorrupt(phoneCatalogSmokeInput, phoneCatalogContinuation)
phoneCatalogSmokeInput.abi_version = 2
let phoneCatalogMalformed = beluga_core_phone_catalog_decide(phoneCatalogSmokeInput)
precondition(phoneCatalogMalformed.abi_version == 1 && phoneCatalogMalformed.status == 0 && phoneCatalogMalformed.error == 0)
precondition(phoneCatalogMalformed.action == 0 && phoneCatalogMalformed.count == 0 && phoneCatalogMalformed.selected_slot == 0)
precondition(phoneCatalogMalformed.target_slot == 0 && phoneCatalogMalformed.reserved == 0 && phoneCatalogMalformed.revision == 0)
precondition(phoneCatalogSmokeSlots(phoneCatalogMalformed) == Array(repeating: 0, count: 8))
precondition(beluga_core_phone_catalog_result_is_valid(phoneCatalogSmokeInput, phoneCatalogMalformed) == 0)
print("BelugaCore Swift phone catalog import/link PASS: every offset, all operations/actions, full maps, 72-byte verifier")
// Append to the existing actual-import/link smoke; preserve all previous smokes.
precondition(MemoryLayout<beluga_core_runtime_catalog_state_t>.size == 24)
precondition(MemoryLayout<beluga_core_runtime_catalog_state_t>.alignment == 4)
precondition(MemoryLayout<beluga_core_runtime_catalog_state_t>.offset(of: \.abi_version) == 0)
precondition(MemoryLayout<beluga_core_runtime_catalog_state_t>.offset(of: \.phase) == 4)
precondition(MemoryLayout<beluga_core_runtime_catalog_state_t>.offset(of: \.operation) == 8)
precondition(MemoryLayout<beluga_core_runtime_catalog_state_t>.offset(of: \.eligible) == 12)
precondition(MemoryLayout<beluga_core_runtime_catalog_state_t>.offset(of: \.intent) == 16)
precondition(MemoryLayout<beluga_core_runtime_catalog_state_t>.offset(of: \.first_grant) == 20)
precondition(MemoryLayout<beluga_core_runtime_catalog_event_t>.size == 16)
precondition(MemoryLayout<beluga_core_runtime_catalog_event_t>.alignment == 4)
precondition(MemoryLayout<beluga_core_runtime_catalog_event_t>.offset(of: \.opcode) == 0)
precondition(MemoryLayout<beluga_core_runtime_catalog_event_t>.offset(of: \.operation) == 4)
precondition(MemoryLayout<beluga_core_runtime_catalog_event_t>.offset(of: \.facts) == 8)
precondition(MemoryLayout<beluga_core_runtime_catalog_event_t>.offset(of: \.reserved) == 12)
precondition(MemoryLayout<beluga_core_runtime_catalog_result_t>.size == 40)
precondition(MemoryLayout<beluga_core_runtime_catalog_result_t>.alignment == 4)
precondition(MemoryLayout<beluga_core_runtime_catalog_result_t>.offset(of: \.state) == 0)
precondition(MemoryLayout<beluga_core_runtime_catalog_result_t>.offset(of: \.status) == 24)
precondition(MemoryLayout<beluga_core_runtime_catalog_result_t>.offset(of: \.decision) == 28)
precondition(MemoryLayout<beluga_core_runtime_catalog_result_t>.offset(of: \.effect) == 32)
precondition(MemoryLayout<beluga_core_runtime_catalog_result_t>.offset(of: \.value) == 36)

func runtimeCatalogSmokeState(_ phase: UInt32 = 0, _ operation: UInt32 = 0,
                              _ eligible: UInt32 = 0, _ intent: UInt32 = 0,
                              _ grant: UInt32 = 0) -> beluga_core_runtime_catalog_state_t {
    var s = beluga_core_runtime_catalog_state_t()
    s.abi_version = 1; s.phase = phase; s.operation = operation
    s.eligible = eligible; s.intent = intent; s.first_grant = grant
    return s
}
func runtimeCatalogSmokeEvent(_ opcode: UInt32, _ operation: UInt32,
                              _ facts: UInt32) -> beluga_core_runtime_catalog_event_t {
    var e = beluga_core_runtime_catalog_event_t()
    e.opcode = opcode; e.operation = operation; e.facts = facts; e.reserved = 0
    return e
}
func runtimeCatalogSmokeExpected(_ state: beluga_core_runtime_catalog_state_t,
                                 _ status: UInt32, _ decision: UInt32,
                                 _ effect: UInt32, _ value: UInt32)
    -> beluga_core_runtime_catalog_result_t {
    var r = beluga_core_runtime_catalog_result_t()
    r.state = state; r.status = status; r.decision = decision; r.effect = effect; r.value = value
    return r
}
func runtimeCatalogSmokeWords(_ r: beluga_core_runtime_catalog_result_t) -> [UInt32] {
    [r.state.abi_version,r.state.phase,r.state.operation,r.state.eligible,r.state.intent,
     r.state.first_grant,r.status,r.decision,r.effect,r.value]
}
func runtimeCatalogSmokeAssert(_ state: beluga_core_runtime_catalog_state_t,
                               _ event: beluga_core_runtime_catalog_event_t,
                               _ actual: beluga_core_runtime_catalog_result_t,
                               _ expected: beluga_core_runtime_catalog_result_t) {
    precondition(runtimeCatalogSmokeWords(actual) == runtimeCatalogSmokeWords(expected))
    precondition(beluga_core_runtime_catalog_result_is_valid(state,event,actual) == expected.status)
}
func runtimeCatalogSmokeCorrupt(_ state: beluga_core_runtime_catalog_state_t,
                                _ event: beluga_core_runtime_catalog_event_t,
                                _ actual: beluga_core_runtime_catalog_result_t) {
    precondition(beluga_core_runtime_catalog_result_is_valid(state,event,actual) == 1)
    for byte in 0..<40 {
        for bit in 0..<8 {
            var mutant = actual
            withUnsafeMutableBytes(of: &mutant) { bytes in bytes[byte] ^= UInt8(1 << bit) }
            precondition(beluga_core_runtime_catalog_result_is_valid(state,event,mutant) == 0)
        }
    }
}
func runtimeCatalogSmoke() {
    // Independent native setup and row facts, not a candidate-generated expectation.
    let facts: [UInt32] = [
        0,31,24,2047,1,1,3,1,3,3,1,3,127,3,7,1,3,1,1,1,1,1,0,1,7,3,1,7,3,
        3,1,3,2047,1,7,1,3,3,7,1,1023,3,1,63,3,1023,31,15,0,3,1,3,1,3,3,7,7,1
    ]
    for opcode: UInt32 in 0..<58 {
        var state = runtimeCatalogSmokeState()
        let event = runtimeCatalogSmokeEvent(opcode,(opcode == 2 || opcode == 8) ? 3 : 0,facts[Int(opcode)])
        if opcode == 8 || opcode == 48 { state.eligible = 1 }
        if opcode == 9 || opcode == 10 { state = runtimeCatalogSmokeState(1,3,0,0,1) }
        if opcode == 11 || opcode == 12 || opcode == 14 || opcode == 24 {
            state = runtimeCatalogSmokeState(2,3,0,0,0)
        }
        if opcode == 13 { state = runtimeCatalogSmokeState(2,3,0,1,0) }
        if opcode == 21 { state = runtimeCatalogSmokeState(2,3,0,0,1) }
        if opcode == 22 || opcode == 23 { state.intent = 1 }
        let actual = beluga_core_runtime_catalog_step(state,event)
        // ORIGINAL expected state/effect/value constructed AFTER the actual C call.
        var next = state
        var effect: UInt32 = 0, value: UInt32 = 0
        if opcode == 1 { next.eligible = 1; effect = 1 }
        if opcode == 8 { next.phase = 1; next.operation = 3; next.eligible = 0; next.first_grant = 1; effect = 2; value = 1 }
        if opcode == 10 { next.phase = 2; effect = 3; value = 1 }
        if opcode == 13 { next.phase = 0; next.operation = 0; next.first_grant = 0; effect = 4; value = 1 }
        if opcode == 21 { next.intent = 1; next.first_grant = 0; effect = 5; value = 1 }
        if opcode == 22 { next.intent = 0; effect = 6 }
        if opcode == 23 { next.intent = 0; effect = 7; value = 1 }
        if opcode == 48 { next = runtimeCatalogSmokeState(3); effect = 8 }
        runtimeCatalogSmokeAssert(state,event,actual,runtimeCatalogSmokeExpected(next,1,0,effect,value))
        runtimeCatalogSmokeCorrupt(state,event,actual)
    }
    for operation: UInt32 in 1...3 {
        let state = runtimeCatalogSmokeState(0,0,1)
        let event = runtimeCatalogSmokeEvent(8,operation,3)
        let actual = beluga_core_runtime_catalog_step(state,event)
        let grant: UInt32 = operation == 3 ? 1 : 0
        let next = runtimeCatalogSmokeState(1,operation,0,0,grant)
        runtimeCatalogSmokeAssert(state,event,actual,runtimeCatalogSmokeExpected(next,1,0,2,grant))
        runtimeCatalogSmokeCorrupt(state,event,actual)
    }
    var state = runtimeCatalogSmokeState()
    var event = runtimeCatalogSmokeEvent(2,1,1)
    var actual = beluga_core_runtime_catalog_step(state,event)
    runtimeCatalogSmokeAssert(state,event,actual,runtimeCatalogSmokeExpected(state,1,3,0,0))
    event = runtimeCatalogSmokeEvent(2,3,4)
    actual = beluga_core_runtime_catalog_step(state,event)
    runtimeCatalogSmokeAssert(state,event,actual,runtimeCatalogSmokeExpected(state,1,8,0,0))
    event.facts = 0
    actual = beluga_core_runtime_catalog_step(state,event)
    runtimeCatalogSmokeAssert(state,event,actual,runtimeCatalogSmokeExpected(state,1,4,0,0))
    state.intent = 1; event = runtimeCatalogSmokeEvent(8,3,0)
    actual = beluga_core_runtime_catalog_step(state,event)
    runtimeCatalogSmokeAssert(state,event,actual,runtimeCatalogSmokeExpected(state,0,0,0,0))
    state = runtimeCatalogSmokeState(3); event = runtimeCatalogSmokeEvent(9,0,3)
    actual = beluga_core_runtime_catalog_step(state,event)
    runtimeCatalogSmokeAssert(state,event,actual,runtimeCatalogSmokeExpected(state,1,0,0,0))
    event = runtimeCatalogSmokeEvent(10,0,1)
    actual = beluga_core_runtime_catalog_step(state,event)
    runtimeCatalogSmokeAssert(state,event,actual,runtimeCatalogSmokeExpected(state,1,0,0,1))
    event = runtimeCatalogSmokeEvent(55,0,7)
    actual = beluga_core_runtime_catalog_step(state,event)
    runtimeCatalogSmokeAssert(state,event,actual,runtimeCatalogSmokeExpected(state,1,0,0,0))
    event = runtimeCatalogSmokeEvent(56,0,7)
    actual = beluga_core_runtime_catalog_step(state,event)
    runtimeCatalogSmokeAssert(state,event,actual,runtimeCatalogSmokeExpected(state,1,8,0,0))
    state.abi_version = 0; event = runtimeCatalogSmokeEvent(48,0,0)
    actual = beluga_core_runtime_catalog_step(state,event)
    runtimeCatalogSmokeAssert(state,event,actual,runtimeCatalogSmokeExpected(state,0,0,0,0))
    state = runtimeCatalogSmokeState(); event.reserved = UInt32.max
    actual = beluga_core_runtime_catalog_step(state,event)
    runtimeCatalogSmokeAssert(state,event,actual,runtimeCatalogSmokeExpected(state,0,0,0,0))
}
runtimeCatalogSmoke()
print("BelugaCore Swift runtime catalog import/link PASS: 58 ordered cuts, every offset, historical grant, 40-byte verifier")

// Additive, unexecuted import/link smoke. Synthetic lossless wire inputs are
// not native telemetry, route/Instant custody or actual actor adoption.
private func owner105PODBytes<T>(_ value: T) -> [UInt8] {
    withUnsafeBytes(of: value) { Array($0) }
}
private func owner105ArrayBytes<T>(_ values: [T]) -> [UInt8] {
    values.withUnsafeBufferPointer {
        Array(UnsafeRawBufferPointer(start: $0.baseAddress,
            count: $0.count * MemoryLayout<T>.stride))
    }
}
private func owner105RawCall(_ request: beluga_core_adaptation_owner_event_request_t,
    _ current: [beluga_core_adaptation_state_atom_t], _ outputCount: UInt32 = 179
) -> (UInt32, [[UInt8]], [[UInt8]]) {
    let header = beluga_core_adaptation_state_header_t(abi: 1, domain: 2, phase: 1, count: 179)
    let inputBefore = [owner105PODBytes(request), owner105PODBytes(header), owner105ArrayBytes(current)]
    var outputHeader = beluga_core_adaptation_state_header_t(abi: 161, domain: 162, phase: 163, count: 164)
    var outputAtoms = Array(repeating: beluga_core_adaptation_state_atom_t(kind: 777, present: 778, high: -779, low: 780), count: 179)
    var metadata = beluga_core_adaptation_owner_event_metadata_t(abi: 801, operation: 802, scope: 803,
        read_count: 804, invocation: 805, revision: 806, peer: 807, peer_present: 808, bound: 809,
        route: 810, sample: 811, enabled: 812, lease: 813, queue_fault: 814, rtt_fault: 815)
    var edits = Array(repeating: beluga_core_adaptation_time_edit_t(action: 901, source: 902,
        index: 903, ordinal: 904, high: -905, low: 906), count: 13)
    var coordinates = Array(repeating: beluga_core_adaptation_time_coordinate_t(present: 1001,
        reserved: 1002, high: -1003, low: 1004), count: 13)
    var reads = Array(repeating: beluga_core_adaptation_clock_reply_t(abi: 1101, status: 1102,
        site: 1103, ordinal: 1104, invocation: 1105, high: -1106, low: 1107, reserved: 1108), count: 15)
    let before = [owner105PODBytes(outputHeader), owner105ArrayBytes(outputAtoms), owner105PODBytes(metadata),
        owner105ArrayBytes(edits), owner105ArrayBytes(coordinates), owner105ArrayBytes(reads)]
    let status = withUnsafePointer(to: request) { requestPointer in
        withUnsafePointer(to: header) { headerPointer in
            current.withUnsafeBufferPointer { atomsPointer in
                outputAtoms.withUnsafeMutableBufferPointer { outputPointer in
                    edits.withUnsafeMutableBufferPointer { editPointer in
                        coordinates.withUnsafeMutableBufferPointer { coordinatePointer in
                            reads.withUnsafeMutableBufferPointer { readPointer in
                                beluga_core_network_adaptation_owner_zero_clock_event(requestPointer,
                                    headerPointer, atomsPointer.baseAddress!, 179, &outputHeader,
                                    outputPointer.baseAddress!, outputCount, &metadata,
                                    editPointer.baseAddress!, 13, coordinatePointer.baseAddress!, 13,
                                    readPointer.baseAddress!, 15)
                            }
                        }
                    }
                }
            }
        }
    }
    assert([owner105PODBytes(request), owner105PODBytes(header), owner105ArrayBytes(current)] == inputBefore)
    return (status, [owner105PODBytes(outputHeader), owner105ArrayBytes(outputAtoms),
        owner105PODBytes(metadata), owner105ArrayBytes(edits), owner105ArrayBytes(coordinates),
        owner105ArrayBytes(reads)], before)
}
private func adaptationOwnerZeroClockSmokeV1() {
    assert(MemoryLayout<beluga_core_adaptation_owner_event_request_t>.size == 40)
    assert(MemoryLayout<beluga_core_adaptation_owner_event_request_t>.stride == 40)
    assert(MemoryLayout<beluga_core_adaptation_owner_event_request_t>.alignment == 8)
    assert(MemoryLayout<beluga_core_adaptation_owner_event_request_t>.offset(of: \beluga_core_adaptation_owner_event_request_t.abi) == 0)
    assert(MemoryLayout<beluga_core_adaptation_owner_event_request_t>.offset(of: \beluga_core_adaptation_owner_event_request_t.operation) == 4)
    assert(MemoryLayout<beluga_core_adaptation_owner_event_request_t>.offset(of: \beluga_core_adaptation_owner_event_request_t.generation) == 8)
    assert(MemoryLayout<beluga_core_adaptation_owner_event_request_t>.offset(of: \beluga_core_adaptation_owner_event_request_t.invocation) == 16)
    assert(MemoryLayout<beluga_core_adaptation_owner_event_request_t>.offset(of: \beluga_core_adaptation_owner_event_request_t.show) == 24)
    assert(MemoryLayout<beluga_core_adaptation_owner_event_request_t>.offset(of: \beluga_core_adaptation_owner_event_request_t.capture_source_present) == 32)
    assert(MemoryLayout<beluga_core_adaptation_owner_event_request_t>.offset(of: \beluga_core_adaptation_owner_event_request_t.resume_context_absent) == 36)
    assert(MemoryLayout<beluga_core_adaptation_state_header_t>.size == 16)
    assert(MemoryLayout<beluga_core_adaptation_state_header_t>.stride == 16)
    assert(MemoryLayout<beluga_core_adaptation_state_header_t>.alignment == 4)
    assert(MemoryLayout<beluga_core_adaptation_state_header_t>.offset(of: \beluga_core_adaptation_state_header_t.abi) == 0)
    assert(MemoryLayout<beluga_core_adaptation_state_header_t>.offset(of: \beluga_core_adaptation_state_header_t.domain) == 4)
    assert(MemoryLayout<beluga_core_adaptation_state_header_t>.offset(of: \beluga_core_adaptation_state_header_t.phase) == 8)
    assert(MemoryLayout<beluga_core_adaptation_state_header_t>.offset(of: \beluga_core_adaptation_state_header_t.count) == 12)
    assert(MemoryLayout<beluga_core_adaptation_state_atom_t>.size == 24)
    assert(MemoryLayout<beluga_core_adaptation_state_atom_t>.stride == 24)
    assert(MemoryLayout<beluga_core_adaptation_state_atom_t>.alignment == 8)
    assert(MemoryLayout<beluga_core_adaptation_state_atom_t>.offset(of: \beluga_core_adaptation_state_atom_t.kind) == 0)
    assert(MemoryLayout<beluga_core_adaptation_state_atom_t>.offset(of: \beluga_core_adaptation_state_atom_t.present) == 4)
    assert(MemoryLayout<beluga_core_adaptation_state_atom_t>.offset(of: \beluga_core_adaptation_state_atom_t.high) == 8)
    assert(MemoryLayout<beluga_core_adaptation_state_atom_t>.offset(of: \beluga_core_adaptation_state_atom_t.low) == 16)
    assert(MemoryLayout<beluga_core_adaptation_time_edit_t>.size == 32)
    assert(MemoryLayout<beluga_core_adaptation_time_edit_t>.stride == 32)
    assert(MemoryLayout<beluga_core_adaptation_time_edit_t>.alignment == 8)
    assert(MemoryLayout<beluga_core_adaptation_time_edit_t>.offset(of: \beluga_core_adaptation_time_edit_t.action) == 0)
    assert(MemoryLayout<beluga_core_adaptation_time_edit_t>.offset(of: \beluga_core_adaptation_time_edit_t.source) == 4)
    assert(MemoryLayout<beluga_core_adaptation_time_edit_t>.offset(of: \beluga_core_adaptation_time_edit_t.index) == 8)
    assert(MemoryLayout<beluga_core_adaptation_time_edit_t>.offset(of: \beluga_core_adaptation_time_edit_t.ordinal) == 12)
    assert(MemoryLayout<beluga_core_adaptation_time_edit_t>.offset(of: \beluga_core_adaptation_time_edit_t.high) == 16)
    assert(MemoryLayout<beluga_core_adaptation_time_edit_t>.offset(of: \beluga_core_adaptation_time_edit_t.low) == 24)
    assert(MemoryLayout<beluga_core_adaptation_time_coordinate_t>.size == 24)
    assert(MemoryLayout<beluga_core_adaptation_time_coordinate_t>.stride == 24)
    assert(MemoryLayout<beluga_core_adaptation_time_coordinate_t>.alignment == 8)
    assert(MemoryLayout<beluga_core_adaptation_time_coordinate_t>.offset(of: \beluga_core_adaptation_time_coordinate_t.present) == 0)
    assert(MemoryLayout<beluga_core_adaptation_time_coordinate_t>.offset(of: \beluga_core_adaptation_time_coordinate_t.reserved) == 4)
    assert(MemoryLayout<beluga_core_adaptation_time_coordinate_t>.offset(of: \beluga_core_adaptation_time_coordinate_t.high) == 8)
    assert(MemoryLayout<beluga_core_adaptation_time_coordinate_t>.offset(of: \beluga_core_adaptation_time_coordinate_t.low) == 16)
    assert(MemoryLayout<beluga_core_adaptation_clock_reply_t>.size == 48)
    assert(MemoryLayout<beluga_core_adaptation_clock_reply_t>.stride == 48)
    assert(MemoryLayout<beluga_core_adaptation_clock_reply_t>.alignment == 8)
    assert(MemoryLayout<beluga_core_adaptation_clock_reply_t>.offset(of: \beluga_core_adaptation_clock_reply_t.abi) == 0)
    assert(MemoryLayout<beluga_core_adaptation_clock_reply_t>.offset(of: \beluga_core_adaptation_clock_reply_t.status) == 4)
    assert(MemoryLayout<beluga_core_adaptation_clock_reply_t>.offset(of: \beluga_core_adaptation_clock_reply_t.site) == 8)
    assert(MemoryLayout<beluga_core_adaptation_clock_reply_t>.offset(of: \beluga_core_adaptation_clock_reply_t.ordinal) == 12)
    assert(MemoryLayout<beluga_core_adaptation_clock_reply_t>.offset(of: \beluga_core_adaptation_clock_reply_t.invocation) == 16)
    assert(MemoryLayout<beluga_core_adaptation_clock_reply_t>.offset(of: \beluga_core_adaptation_clock_reply_t.high) == 24)
    assert(MemoryLayout<beluga_core_adaptation_clock_reply_t>.offset(of: \beluga_core_adaptation_clock_reply_t.low) == 32)
    assert(MemoryLayout<beluga_core_adaptation_clock_reply_t>.offset(of: \beluga_core_adaptation_clock_reply_t.reserved) == 40)
    assert(MemoryLayout<beluga_core_adaptation_owner_event_metadata_t>.size == 72)
    assert(MemoryLayout<beluga_core_adaptation_owner_event_metadata_t>.stride == 72)
    assert(MemoryLayout<beluga_core_adaptation_owner_event_metadata_t>.alignment == 8)
    assert(MemoryLayout<beluga_core_adaptation_owner_event_metadata_t>.offset(of: \beluga_core_adaptation_owner_event_metadata_t.abi) == 0)
    assert(MemoryLayout<beluga_core_adaptation_owner_event_metadata_t>.offset(of: \beluga_core_adaptation_owner_event_metadata_t.operation) == 4)
    assert(MemoryLayout<beluga_core_adaptation_owner_event_metadata_t>.offset(of: \beluga_core_adaptation_owner_event_metadata_t.scope) == 8)
    assert(MemoryLayout<beluga_core_adaptation_owner_event_metadata_t>.offset(of: \beluga_core_adaptation_owner_event_metadata_t.read_count) == 12)
    assert(MemoryLayout<beluga_core_adaptation_owner_event_metadata_t>.offset(of: \beluga_core_adaptation_owner_event_metadata_t.invocation) == 16)
    assert(MemoryLayout<beluga_core_adaptation_owner_event_metadata_t>.offset(of: \beluga_core_adaptation_owner_event_metadata_t.revision) == 24)
    assert(MemoryLayout<beluga_core_adaptation_owner_event_metadata_t>.offset(of: \beluga_core_adaptation_owner_event_metadata_t.peer) == 32)
    assert(MemoryLayout<beluga_core_adaptation_owner_event_metadata_t>.offset(of: \beluga_core_adaptation_owner_event_metadata_t.peer_present) == 40)
    assert(MemoryLayout<beluga_core_adaptation_owner_event_metadata_t>.offset(of: \beluga_core_adaptation_owner_event_metadata_t.bound) == 44)
    assert(MemoryLayout<beluga_core_adaptation_owner_event_metadata_t>.offset(of: \beluga_core_adaptation_owner_event_metadata_t.route) == 48)
    assert(MemoryLayout<beluga_core_adaptation_owner_event_metadata_t>.offset(of: \beluga_core_adaptation_owner_event_metadata_t.sample) == 52)
    assert(MemoryLayout<beluga_core_adaptation_owner_event_metadata_t>.offset(of: \beluga_core_adaptation_owner_event_metadata_t.enabled) == 56)
    assert(MemoryLayout<beluga_core_adaptation_owner_event_metadata_t>.offset(of: \beluga_core_adaptation_owner_event_metadata_t.lease) == 60)
    assert(MemoryLayout<beluga_core_adaptation_owner_event_metadata_t>.offset(of: \beluga_core_adaptation_owner_event_metadata_t.queue_fault) == 64)
    assert(MemoryLayout<beluga_core_adaptation_owner_event_metadata_t>.offset(of: \beluga_core_adaptation_owner_event_metadata_t.rtt_fault) == 68)
    // Literal codec field-kind ledger; payload construction defines input only.
    let kinds: [UInt32] = [
        2,2,2,1,7,2,2,2,2,2,2,2,10,2,2,4,4,4,2,2,
        7,7,7,10,2,4,7,2,10,2,2,2,4,4,4,3,1,3,2,10,
        10,4,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,
        3,3,3,3,3,2,2,1,1,1,1,1,1,1,1,3,1,1,1,1,
        1,1,1,1,1,3,1,3,10,4,6,2,2,2,2,3,2,2,2,2,
        2,3,2,2,2,2,2,3,2,2,2,2,2,3,2,2,2,2,2,3,
        2,2,2,2,2,3,2,2,2,2,2,3,2,2,2,2,2,3,2,5,
        4,5,2,1,4,4,1,3,3,3,1,4,1,4,4,4,4,3,4,10,
        3,1,3,10,1,1,4,10,1,4,8,10,1,4,7,2,2,2,3
    ]
    assert(kinds.count == 179)
    var current = kinds.enumerated().map { index, kind -> beluga_core_adaptation_state_atom_t in
        let offset = UInt64(index)
        let low: UInt64
        switch kind {
        case 1: low = 10000 + offset
        case 2: low = 1000 + offset
        case 3: low = 0x7ff8000000000000 + offset
        case 6: low = 20000 + offset
        case 10: low = 1000000 + offset
        default: low = 0
        }
        return beluga_core_adaptation_state_atom_t(kind: kind, present: 1, high: 0, low: low)
    }
    for index in [15,16,25,33,41,140,145,151,154,156,158,169,173] { current[index].low = 1 }
    for (index, value) in [(4,5),(20,3),(21,4),(22,6),(26,1),(174,2),(139,250),(141,251),(170,1)] {
        current[index].low = UInt64(value)
    }
    current[168].low = UInt64.max
    current[171].high = -1; current[171].low = UInt64.max - 6
    current[172].low = UInt64.max
    let request = beluga_core_adaptation_owner_event_request_t(abi: 1, operation: 105,
        generation: 0, invocation: 0xfedcba9876543210, show: 0,
        capture_source_present: 0, resume_context_absent: 0)
    let actual = owner105RawCall(request, current)
    assert(actual.0 == 1)
    // Handwritten complete successor: only these five Owner fields may change.
    var expected = current
    expected[168].low = 0; expected[169].low = 0
    for index in 170...172 {
        expected[index].present = 0; expected[index].high = 0; expected[index].low = 0
    }
    let expectedHeader = beluga_core_adaptation_state_header_t(abi: 1, domain: 2, phase: 2, count: 179)
    let expectedMetadata = beluga_core_adaptation_owner_event_metadata_t(abi: 1, operation: 105,
        scope: 2, read_count: 0, invocation: 0xfedcba9876543210, revision: 0, peer: 10003,
        peer_present: 1, bound: 0, route: 0, sample: 0, enabled: 0, lease: 0, queue_fault: 1, rtt_fault: 0)
    var expectedEdits = Array(repeating: beluga_core_adaptation_time_edit_t(), count: 13)
    expectedEdits[12].action = 2
    let expectedCoordinates = Array(repeating: beluga_core_adaptation_time_coordinate_t(), count: 13)
    let expectedReads = Array(repeating: beluga_core_adaptation_clock_reply_t(), count: 15)
    assert(actual.1 == [owner105PODBytes(expectedHeader), owner105ArrayBytes(expected),
        owner105PODBytes(expectedMetadata), owner105ArrayBytes(expectedEdits),
        owner105ArrayBytes(expectedCoordinates), owner105ArrayBytes(expectedReads)])
    for mode in 0..<4 {
        var malformedRequest = request; var malformedAtoms = current
        var outputCount: UInt32 = 179
        if mode == 0 { malformedRequest.operation = 104 }
        if mode == 1 { malformedRequest.abi = 2 }
        if mode == 2 { malformedAtoms[35].kind = 99 }
        if mode == 3 { outputCount = 178 }
        let denied = owner105RawCall(malformedRequest, malformedAtoms, outputCount)
        assert(denied.0 == 2)
        assert(denied.1 == denied.2) // all six unpublished buffers retain every byte
    }
}
adaptationOwnerZeroClockSmokeV1()
print("BelugaCore Swift adaptation Owner zero-clock PASS: layouts, full179 stop, four untouched denials")

// SOURCE-ONLY additive public Swift import/link smoke. All clocks and full179
// atoms are synthetic; no actual native Instant, actor adoption or effect proof.
private struct Owner216ClockContext { var calls: UInt32 = 0; var mode: UInt32 = 0 }
private let owner216Clock: @convention(c) (UnsafeMutableRawPointer?, UInt64, UInt32,
    UInt32, UnsafeMutablePointer<beluga_core_adaptation_clock_reply_t>?) -> UInt32 = {
    context, invocation, site, ordinal, reply in
    guard let context, let reply else { return 0 }
    let clock = context.assumingMemoryBound(to: Owner216ClockContext.self)
    precondition(invocation == 0xfedcba9876543210 && site == 2 && ordinal == 0 && clock.pointee.calls == 0)
    clock.pointee.calls += 1
    if clock.pointee.mode == 1 { return 0 }
    reply.pointee = beluga_core_adaptation_clock_reply_t(abi: 1, status: 1, site: 2,
        ordinal: 0, invocation: invocation, high: 0, low: 9000000,
        reserved: clock.pointee.mode == 2 ? 1 : 0)
    return 1
}
private func owner216SmokeSeed() -> [beluga_core_adaptation_state_atom_t] {
    // Literal codec field-kind ledger; construction defines input only.
    let kinds: [UInt32] = [
        2,2,2,1,7,2,2,2,2,2,2,2,10,2,2,4,4,4,2,2,
        7,7,7,10,2,4,7,2,10,2,2,2,4,4,4,3,1,3,2,10,
        10,4,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,
        3,3,3,3,3,2,2,1,1,1,1,1,1,1,1,3,1,1,1,1,
        1,1,1,1,1,3,1,3,10,4,6,2,2,2,2,3,2,2,2,2,
        2,3,2,2,2,2,2,3,2,2,2,2,2,3,2,2,2,2,2,3,
        2,2,2,2,2,3,2,2,2,2,2,3,2,2,2,2,2,3,2,5,
        4,5,2,1,4,4,1,3,3,3,1,4,1,4,4,4,4,3,4,10,
        3,1,3,10,1,1,4,10,1,4,8,10,1,4,7,2,2,2,3
    ]
    assert(kinds.count == 179)
    var current = kinds.enumerated().map { index, kind -> beluga_core_adaptation_state_atom_t in
        let offset = UInt64(index)
        let low: UInt64
        switch kind {
        case 1: low = 10000 + offset
        case 2: low = 1000 + offset
        case 3: low = 0x7ff8000000000000 + offset
        case 6: low = 20000 + offset
        case 10: low = 1000000 + offset
        default: low = 0
        }
        return beluga_core_adaptation_state_atom_t(kind: kind, present: 1, high: 0, low: low)
    }
    for index in [15,16,25,33,41,140,145,151,154,156,158,169,173] { current[index].low = 1 }
    for (index, value) in [(4,5),(20,3),(21,4),(22,6),(26,1),(174,2),(139,250),(141,251),(170,1)] {
        current[index].low = UInt64(value)
    }
    current[168].low = UInt64.max
    current[171].high = -1; current[171].low = UInt64.max - 6
    current[172].low = UInt64.max
    return current
}
private func owner216Absent(_ atoms: inout [beluga_core_adaptation_state_atom_t], _ indices: [Int]) {
    for index in indices { atoms[index].present = 0; atoms[index].high = 0; atoms[index].low = 0 }
}
private func owner216RawCall(_ request: beluga_core_adaptation_owner_clocked_event_request_t,
    _ current: [beluga_core_adaptation_state_atom_t], _ outputCount: UInt32 = 179,
    header: beluga_core_adaptation_state_header_t = .init(abi: 1, domain: 2, phase: 1, count: 179),
    mode: UInt32 = 0, missingCallback: Bool = false
) -> (UInt32, [[UInt8]], [[UInt8]], UInt32) {
    let inputBefore = [owner105PODBytes(request), owner105PODBytes(header), owner105ArrayBytes(current)]
    var outputHeader = beluga_core_adaptation_state_header_t(abi: 161, domain: 162, phase: 163, count: 164)
    var outputAtoms = Array(repeating: beluga_core_adaptation_state_atom_t(kind: 777, present: 778, high: -779, low: 780), count: 179)
    var metadata = beluga_core_adaptation_owner_event_metadata_t(abi: 801, operation: 802, scope: 803,
        read_count: 804, invocation: 805, revision: 806, peer: 807, peer_present: 808, bound: 809,
        route: 810, sample: 811, enabled: 812, lease: 813, queue_fault: 814, rtt_fault: 815)
    var edits = Array(repeating: beluga_core_adaptation_time_edit_t(action: 901, source: 902,
        index: 903, ordinal: 904, high: -905, low: 906), count: 13)
    var coordinates = Array(repeating: beluga_core_adaptation_time_coordinate_t(present: 1001,
        reserved: 1002, high: -1003, low: 1004), count: 13)
    var reads = Array(repeating: beluga_core_adaptation_clock_reply_t(abi: 1101, status: 1102,
        site: 1103, ordinal: 1104, invocation: 1105, high: -1106, low: 1107, reserved: 1108), count: 15)
    let before = [owner105PODBytes(outputHeader), owner105ArrayBytes(outputAtoms), owner105PODBytes(metadata),
        owner105ArrayBytes(edits), owner105ArrayBytes(coordinates), owner105ArrayBytes(reads)]
    var clock = Owner216ClockContext(calls: 0, mode: mode)
    let status = withUnsafeMutablePointer(to: &clock) { clockPointer in
        withUnsafePointer(to: request) { requestPointer in
            withUnsafePointer(to: header) { headerPointer in
                current.withUnsafeBufferPointer { atomsPointer in
                    outputAtoms.withUnsafeMutableBufferPointer { outputPointer in
                        edits.withUnsafeMutableBufferPointer { editPointer in
                            coordinates.withUnsafeMutableBufferPointer { coordinatePointer in
                                reads.withUnsafeMutableBufferPointer { readPointer in
                                    beluga_core_network_adaptation_owner_clocked_event(requestPointer,
                                        headerPointer, atomsPointer.baseAddress!, 179,
                                        missingCallback ? nil : owner216Clock, UnsafeMutableRawPointer(clockPointer),
                                        &outputHeader, outputPointer.baseAddress!, outputCount, &metadata,
                                        editPointer.baseAddress!, 13, coordinatePointer.baseAddress!, 13,
                                        readPointer.baseAddress!, 15)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    assert([owner105PODBytes(request), owner105PODBytes(header), owner105ArrayBytes(current)] == inputBefore)
    return (status, [owner105PODBytes(outputHeader), owner105ArrayBytes(outputAtoms),
        owner105PODBytes(metadata), owner105ArrayBytes(edits), owner105ArrayBytes(coordinates),
        owner105ArrayBytes(reads)], before, clock.calls)
}
private func adaptationOwnerClockedSmokeV1() {
    assert(MemoryLayout<beluga_core_adaptation_owner_clocked_event_request_t>.size == 48)
    assert(MemoryLayout<beluga_core_adaptation_owner_clocked_event_request_t>.stride == 48)
    assert(MemoryLayout<beluga_core_adaptation_owner_clocked_event_request_t>.alignment == 8)
    assert(MemoryLayout<beluga_core_adaptation_owner_clocked_event_request_t>.offset(of: \beluga_core_adaptation_owner_clocked_event_request_t.abi) == 0)
    assert(MemoryLayout<beluga_core_adaptation_owner_clocked_event_request_t>.offset(of: \beluga_core_adaptation_owner_clocked_event_request_t.operation) == 4)
    assert(MemoryLayout<beluga_core_adaptation_owner_clocked_event_request_t>.offset(of: \beluga_core_adaptation_owner_clocked_event_request_t.generation) == 8)
    assert(MemoryLayout<beluga_core_adaptation_owner_clocked_event_request_t>.offset(of: \beluga_core_adaptation_owner_clocked_event_request_t.invocation) == 16)
    assert(MemoryLayout<beluga_core_adaptation_owner_clocked_event_request_t>.offset(of: \beluga_core_adaptation_owner_clocked_event_request_t.show) == 24)
    assert(MemoryLayout<beluga_core_adaptation_owner_clocked_event_request_t>.offset(of: \beluga_core_adaptation_owner_clocked_event_request_t.minimum) == 32)
    assert(MemoryLayout<beluga_core_adaptation_owner_clocked_event_request_t>.offset(of: \beluga_core_adaptation_owner_clocked_event_request_t.flag) == 40)
    assert(MemoryLayout<beluga_core_adaptation_owner_clocked_event_request_t>.offset(of: \beluga_core_adaptation_owner_clocked_event_request_t.minimum_present) == 44)
    let request = beluga_core_adaptation_owner_clocked_event_request_t(abi: 1, operation: 216,
        generation: 0, invocation: 0xfedcba9876543210, show: 0, minimum: 0, flag: 0, minimum_present: 0)
    let current = owner216SmokeSeed()
    let actual = owner216RawCall(request, current)
    assert(actual.0 == 1 && actual.3 == 1)
    // Literal complete successor; no reducer or result decoder constructs expected values.
    var expected = current
    for index in [5,6,7,8,9,10,25,145,158] { expected[index].low = 0 }
    owner216Absent(&expected, [21,26,27,28,146,147,148,159,160,170,171,172])
    expected[168].low = 0
    let expectedHeader = beluga_core_adaptation_state_header_t(abi: 1, domain: 2, phase: 2, count: 179)
    let expectedMetadata = beluga_core_adaptation_owner_event_metadata_t(abi: 1, operation: 216,
        scope: 2, read_count: 1, invocation: 0xfedcba9876543210, revision: 0, peer: 10003,
        peer_present: 1, bound: 0, route: 0, sample: 0, enabled: 0, lease: 0, queue_fault: 1, rtt_fault: 0)
    var expectedEdits = Array(repeating: beluga_core_adaptation_time_edit_t(), count: 13)
    expectedEdits[2].action = 2; expectedEdits[3].action = 2
    expectedEdits[6].action = 1; expectedEdits[7].action = 1; expectedEdits[12].action = 2
    var expectedCoordinates = Array(repeating: beluga_core_adaptation_time_coordinate_t(), count: 13)
    expectedCoordinates[6] = .init(present: 1, reserved: 0, high: 0, low: 1000039)
    expectedCoordinates[7] = .init(present: 1, reserved: 0, high: 0, low: 1000040)
    var expectedReads = Array(repeating: beluga_core_adaptation_clock_reply_t(), count: 15)
    expectedReads[0] = .init(abi: 1, status: 1, site: 2, ordinal: 0,
        invocation: 0xfedcba9876543210, high: 0, low: 9000000, reserved: 0)
    assert(actual.1 == [owner105PODBytes(expectedHeader), owner105ArrayBytes(expected),
        owner105PODBytes(expectedMetadata), owner105ArrayBytes(expectedEdits),
        owner105ArrayBytes(expectedCoordinates), owner105ArrayBytes(expectedReads)])

    var lazyRequest = request; lazyRequest.operation = 202
    var lazyCurrent = current; owner216Absent(&lazyCurrent, [20])
    let lazy = owner216RawCall(lazyRequest, lazyCurrent)
    assert(lazy.0 == 1 && lazy.3 == 0)
    var lazyExpected = lazyCurrent
    owner216Absent(&lazyExpected, [164,165,167,159,160])
    for index in [166,153,154,158] { lazyExpected[index].low = 0 }
    let lazyMetadata = beluga_core_adaptation_owner_event_metadata_t(abi: 1, operation: 202,
        scope: 1, read_count: 0, invocation: 0xfedcba9876543210, revision: UInt64.max, peer: 10003,
        peer_present: 1, bound: 0, route: 0, sample: 0, enabled: 0, lease: 0, queue_fault: 1, rtt_fault: 0)
    var lazyEdits = Array(repeating: beluga_core_adaptation_time_edit_t(), count: 13)
    for index in [0,1,2,6,7] { lazyEdits[index].action = 1 }
    lazyEdits[3].action = 2; lazyEdits[5].action = 2
    var lazyCoordinates = Array(repeating: beluga_core_adaptation_time_coordinate_t(), count: 13)
    for (index, value) in [(0,1000012),(1,1000023),(2,1000028),(6,1000039),(7,1000040)] {
        lazyCoordinates[index] = .init(present: 1, reserved: 0, high: 0, low: UInt64(value))
    }
    let lazyReads = Array(repeating: beluga_core_adaptation_clock_reply_t(), count: 15)
    assert(lazy.1 == [owner105PODBytes(expectedHeader), owner105ArrayBytes(lazyExpected),
        owner105PODBytes(lazyMetadata), owner105ArrayBytes(lazyEdits),
        owner105ArrayBytes(lazyCoordinates), owner105ArrayBytes(lazyReads)])

    for mode in 0..<8 {
        var deniedRequest = request; var deniedAtoms = current
        var deniedHeader = beluga_core_adaptation_state_header_t(abi: 1, domain: 2, phase: 1, count: 179)
        var outputCount: UInt32 = 179; var clockMode: UInt32 = 0
        if mode == 0 { deniedRequest.operation = 201 }
        if mode == 1 { deniedRequest.abi = 2 }
        if mode == 2 { deniedAtoms[88].kind = 99 }
        if mode == 3 { outputCount = 178 }
        if mode == 5 { clockMode = 1 }
        if mode == 6 { clockMode = 2 }
        if mode == 7 { deniedHeader.phase = 2 }
        let denied = owner216RawCall(deniedRequest, deniedAtoms, outputCount,
            header: deniedHeader, mode: clockMode, missingCallback: mode == 4)
        assert(denied.0 == (mode == 5 ? 3 : mode == 6 ? 4 : 2))
        assert(denied.3 == (mode == 5 || mode == 6 ? 1 : 0))
        assert(denied.1 == denied.2) // every byte of all six unpublished outputs
    }
}
adaptationOwnerClockedSmokeV1()
print("BelugaCore Swift adaptation Owner clocked PASS: layout, two full179 cuts, lazy callback, eight untouched denials")

// Additive PUBLIC501 import/link smoke; completed None and scalar byte shape
// do not establish Prepared222, native Instant/route custody, or actor adoption.
private func owner501Offset<T, V>(_ field: KeyPath<T, V>, _ expected: Int) {
    assert(MemoryLayout<T>.offset(of: field) == expected)
}
private func owner501RawCall(_ request: beluga_core_adaptation_owner_prepare_request_t,
    _ current: [beluga_core_adaptation_state_atom_t], _ outputCount: UInt32 = 222,
    header: beluga_core_adaptation_state_header_t = .init(abi: 1, domain: 2, phase: 1, count: 179),
    report: beluga_core_adaptation_owner_report_t = .init(),
    observed: beluga_core_adaptation_time_coordinate_t = .init(), missingCallback: Bool = false
) -> (UInt32, [[UInt8]], [[UInt8]], UInt32) {
    var outputHeader = beluga_core_adaptation_state_header_t(abi: 161, domain: 162, phase: 163, count: 164)
    var outputAtoms = Array(repeating: beluga_core_adaptation_state_atom_t(kind: 777, present: 778, high: -779, low: 780), count: 222)
    var metadata = beluga_core_adaptation_owner_event_metadata_t(abi: 801, operation: 802, scope: 803,
        read_count: 804, invocation: 805, revision: 806, peer: 807, peer_present: 808, bound: 809,
        route: 810, sample: 811, enabled: 812, lease: 813, queue_fault: 814, rtt_fault: 815)
    var outcome = beluga_core_adaptation_owner_prepare_outcome_t(abi: 821, operation: 822,
        invocation: 823, prepared_present: 824, reserved: 825)
    var edits = Array(repeating: beluga_core_adaptation_time_edit_t(action: 901, source: 902,
        index: 903, ordinal: 904, high: -905, low: 906), count: 13)
    var coordinates = Array(repeating: beluga_core_adaptation_time_coordinate_t(present: 1001,
        reserved: 1002, high: -1003, low: 1004), count: 13)
    var reads = Array(repeating: beluga_core_adaptation_clock_reply_t(abi: 1101, status: 1102,
        site: 1103, ordinal: 1104, invocation: 1105, high: -1106, low: 1107, reserved: 1108), count: 15)
    let before = [owner105PODBytes(outputHeader), owner105ArrayBytes(outputAtoms), owner105PODBytes(metadata),
        owner105PODBytes(outcome), owner105ArrayBytes(edits), owner105ArrayBytes(coordinates), owner105ArrayBytes(reads)]
    var clock = Owner216ClockContext()
    let status = withUnsafeMutablePointer(to: &clock) { clockPointer in
        withUnsafePointer(to: request) { requestPointer in
            withUnsafePointer(to: header) { headerPointer in
                withUnsafePointer(to: report) { reportPointer in
                    withUnsafePointer(to: observed) { observedPointer in
                        current.withUnsafeBufferPointer { atomsPointer in
                            // Inspect exact passed temporary storage, not just the original values.
                            let borrowedBefore = [owner105PODBytes(requestPointer.pointee), owner105PODBytes(headerPointer.pointee),
                                owner105ArrayBytes(Array(atomsPointer)), owner105PODBytes(reportPointer.pointee),
                                owner105PODBytes(observedPointer.pointee)]
                            let result = outputAtoms.withUnsafeMutableBufferPointer { outputPointer in
                                edits.withUnsafeMutableBufferPointer { editPointer in
                                    coordinates.withUnsafeMutableBufferPointer { coordinatePointer in
                                        reads.withUnsafeMutableBufferPointer { readPointer in
                                            beluga_core_network_adaptation_owner_prepare_event(requestPointer, headerPointer,
                                                atomsPointer.baseAddress!, 179, reportPointer, observedPointer,
                                                missingCallback ? nil : owner216Clock, UnsafeMutableRawPointer(clockPointer),
                                                &outputHeader, outputPointer.baseAddress!, outputCount, &metadata, &outcome,
                                                editPointer.baseAddress!, 13, coordinatePointer.baseAddress!, 13,
                                                readPointer.baseAddress!, 15)
                                        }
                                    }
                                }
                            }
                            assert([owner105PODBytes(requestPointer.pointee), owner105PODBytes(headerPointer.pointee),
                                owner105ArrayBytes(Array(atomsPointer)), owner105PODBytes(reportPointer.pointee),
                                owner105PODBytes(observedPointer.pointee)] == borrowedBefore)
                            return result
                        }
                    }
                }
            }
        }
    }
    return (status, [owner105PODBytes(outputHeader), owner105ArrayBytes(outputAtoms), owner105PODBytes(metadata),
        owner105PODBytes(outcome), owner105ArrayBytes(edits), owner105ArrayBytes(coordinates),
        owner105ArrayBytes(reads)], before, clock.calls)
}
private func adaptationOwnerPrepareSmokeV1() {
    assert(MemoryLayout<beluga_core_adaptation_owner_prepare_request_t>.size == 56)
    assert(MemoryLayout<beluga_core_adaptation_owner_prepare_request_t>.stride == 56)
    assert(MemoryLayout<beluga_core_adaptation_owner_prepare_request_t>.alignment == 8)
    owner501Offset(\beluga_core_adaptation_owner_prepare_request_t.abi, 0)
    owner501Offset(\beluga_core_adaptation_owner_prepare_request_t.operation, 4)
    owner501Offset(\beluga_core_adaptation_owner_prepare_request_t.invocation, 8)
    owner501Offset(\beluga_core_adaptation_owner_prepare_request_t.source_generation, 16)
    owner501Offset(\beluga_core_adaptation_owner_prepare_request_t.expected_revision, 24)
    owner501Offset(\beluga_core_adaptation_owner_prepare_request_t.current_generation, 32)
    owner501Offset(\beluga_core_adaptation_owner_prepare_request_t.entry_flags, 40)
    owner501Offset(\beluga_core_adaptation_owner_prepare_request_t.capacity_only, 44)
    owner501Offset(\beluga_core_adaptation_owner_prepare_request_t.allows_resume, 48)
    owner501Offset(\beluga_core_adaptation_owner_prepare_request_t.report_present, 52)
    assert(MemoryLayout<beluga_core_adaptation_owner_prepare_outcome_t>.size == 24)
    assert(MemoryLayout<beluga_core_adaptation_owner_prepare_outcome_t>.stride == 24)
    assert(MemoryLayout<beluga_core_adaptation_owner_prepare_outcome_t>.alignment == 8)
    owner501Offset(\beluga_core_adaptation_owner_prepare_outcome_t.abi, 0)
    owner501Offset(\beluga_core_adaptation_owner_prepare_outcome_t.operation, 4)
    owner501Offset(\beluga_core_adaptation_owner_prepare_outcome_t.invocation, 8)
    owner501Offset(\beluga_core_adaptation_owner_prepare_outcome_t.prepared_present, 16)
    owner501Offset(\beluga_core_adaptation_owner_prepare_outcome_t.reserved, 20)
    assert(MemoryLayout<beluga_core_adaptation_owner_report_t>.size == 192)
    assert(MemoryLayout<beluga_core_adaptation_owner_report_t>.stride == 192)
    assert(MemoryLayout<beluga_core_adaptation_owner_report_t>.alignment == 8)
    owner501Offset(\beluga_core_adaptation_owner_report_t.peer, 0)
    owner501Offset(\beluga_core_adaptation_owner_report_t.capture_active, 8)
    owner501Offset(\beluga_core_adaptation_owner_report_t.automatically_suspended, 12)
    owner501Offset(\beluga_core_adaptation_owner_report_t.strict, 16)
    owner501Offset(\beluga_core_adaptation_owner_report_t.incoming_present, 20)
    owner501Offset(\beluga_core_adaptation_owner_report_t.equal_to_retained, 24)
    owner501Offset(\beluga_core_adaptation_owner_report_t.observation_kind, 28)
    owner501Offset(\beluga_core_adaptation_owner_report_t.collection_sequence_present, 32)
    owner501Offset(\beluga_core_adaptation_owner_report_t.bandwidth_present, 36)
    owner501Offset(\beluga_core_adaptation_owner_report_t.current_rtt_present, 40)
    owner501Offset(\beluga_core_adaptation_owner_report_t.packets_present, 44)
    owner501Offset(\beluga_core_adaptation_owner_report_t.delay_present, 48)
    owner501Offset(\beluga_core_adaptation_owner_report_t.native_timestamp_present, 52)
    owner501Offset(\beluga_core_adaptation_owner_report_t.fingerprint_length, 56)
    owner501Offset(\beluga_core_adaptation_owner_report_t.reserved, 60)
    owner501Offset(\beluga_core_adaptation_owner_report_t.collection_sequence, 64)
    owner501Offset(\beluga_core_adaptation_owner_report_t.bandwidth_bits, 72)
    owner501Offset(\beluga_core_adaptation_owner_report_t.current_rtt_bits, 80)
    owner501Offset(\beluga_core_adaptation_owner_report_t.packets, 88)
    owner501Offset(\beluga_core_adaptation_owner_report_t.delay_bits, 96)
    owner501Offset(\beluga_core_adaptation_owner_report_t.native_timestamp_bits, 104)
    owner501Offset(\beluga_core_adaptation_owner_report_t.fingerprint, 112)
    owner501Offset(\beluga_core_adaptation_owner_report_t.measurement_total_bits, 176)
    owner501Offset(\beluga_core_adaptation_owner_report_t.measurement_responses, 184)
    let admitted = beluga_core_adaptation_owner_prepare_request_t(abi: 1, operation: 501,
        invocation: 0xfedcba9876543210, source_generation: 42, expected_revision: UInt64.max,
        current_generation: 42, entry_flags: 127, capacity_only: 0, allows_resume: 0, report_present: 0)
    let current = owner216SmokeSeed()
    let emptyHeader = beluga_core_adaptation_state_header_t()
    let emptyAtoms = Array(repeating: beluga_core_adaptation_state_atom_t(), count: 222)
    let expectedMetadata = beluga_core_adaptation_owner_event_metadata_t(abi: 1, operation: 501, scope: 1,
        read_count: 0, invocation: 0xfedcba9876543210, revision: UInt64.max, peer: 10003, peer_present: 1,
        bound: 0, route: 0, sample: 0, enabled: 0, lease: 0, queue_fault: 1, rtt_fault: 0)
    let expectedOutcome = beluga_core_adaptation_owner_prepare_outcome_t(abi: 1, operation: 501,
        invocation: 0xfedcba9876543210, prepared_present: 0, reserved: 0)
    let emptyEdits = Array(repeating: beluga_core_adaptation_time_edit_t(), count: 13)
    let emptyCoordinates = Array(repeating: beluga_core_adaptation_time_coordinate_t(), count: 13)
    let emptyReads = Array(repeating: beluga_core_adaptation_clock_reply_t(), count: 15)
    let expected = [owner105PODBytes(emptyHeader), owner105ArrayBytes(emptyAtoms), owner105PODBytes(expectedMetadata),
        owner105PODBytes(expectedOutcome), owner105ArrayBytes(emptyEdits), owner105ArrayBytes(emptyCoordinates),
        owner105ArrayBytes(emptyReads)]
    for mode in 0..<5 {
        var request = admitted
        if mode == 0 { request.entry_flags &= ~UInt32(1) }
        if mode == 1 { request.entry_flags &= ~UInt32(2) }
        if mode == 2 { request.current_generation = 43 }
        if mode == 3 { request.expected_revision = UInt64.max - 1 }
        if mode == 4 { request.entry_flags &= ~UInt32(4) }
        let actual = owner501RawCall(request, current)
        assert(actual.0 == 1 && actual.3 == 0)
        assert(actual.1 == expected) // seven complete output objects, including zero222
    }
    for mode in 0..<15 {
        var request = admitted; request.entry_flags = 0
        var atoms = current
        var header = beluga_core_adaptation_state_header_t(abi: 1, domain: 2, phase: 1, count: 179)
        var report = beluga_core_adaptation_owner_report_t()
        var observed = beluga_core_adaptation_time_coordinate_t()
        var outputCount: UInt32 = 222
        if mode == 0 { request.operation = 401 }
        if mode == 1 { request.abi = 2 }
        if mode == 2 { request.invocation = 0 }
        if mode == 3 { request.entry_flags = 256 }
        if mode == 4 { request.capacity_only = 2 }
        if mode == 5 { request.allows_resume = 2 }
        if mode == 6 { request.report_present = 2 }
        if mode == 7 { report.peer = 42 }
        if mode == 8 { request.report_present = 1; report.reserved = 1 }
        if mode == 9 { atoms[178].kind = 99 }
        if mode == 10 { outputCount = 221 }
        if mode == 12 { observed.reserved = 1 }
        if mode == 13 { request.entry_flags = 127 }
        if mode == 14 { header.phase = 2 }
        let denied = owner501RawCall(request, atoms, outputCount, header: header,
            report: report, observed: observed, missingCallback: mode == 11)
        assert(denied.0 == 2 && denied.3 == 0)
        assert(denied.1 == denied.2) // all seven fresh sentinels remain untouched
    }
}
adaptationOwnerPrepareSmokeV1()
print("BelugaCore Swift adaptation Owner prepare PASS: layouts, full179 lazy None, fifteen untouched denials")

// Additive public601 import/link smoke. Scalar Prepared222 inputs are synthetic,
// not native seals, Optional/Instant/provider permissions, or actor adoption.
private func owner601PreparedSeed(_ current: [beluga_core_adaptation_state_atom_t]) -> [beluga_core_adaptation_state_atom_t] {
    let tail: [UInt32] = [
        1,1,1,6,4,4,4,7,2,2,2,3,7,2,2,2,3,6,4,
        1,4,4,4,4,2,1,1,1,1,1,3,3,1,2,2,6,6,6,6,1,6,4,
        4,6,7,1,1,1,2,2,1,1,1,1
    ]
    assert(current.count == 179 && tail.count == 54)
    var prepared = Array(current.prefix(168)) + tail.map {
        beluga_core_adaptation_state_atom_t(kind: $0, present: 0, high: 0, low: 0)
    }
    for index in 168...174 { prepared[index].present = 1 }
    for index in 180...186 { prepared[index].present = 1 }
    prepared[210].present = 1
    prepared[168].low = 42; prepared[169].low = UInt64.max
    prepared[170].low = 99 // applying revision deliberately differs
    prepared[180].low = 2; prepared[181].low = 333333
    prepared[182].low = 444444; prepared[183].low = 30
    prepared[184].low = 0x3ff0000000000000
    prepared[0].low = 32123456
    prepared[12].high = -1; prepared[12].low = UInt64.max - 9 // -10 attoseconds
    return prepared
}
private func owner601RawCall(_ originalRequest: beluga_core_adaptation_owner_inactive_request_t,
    _ originalCurrent: [beluga_core_adaptation_state_atom_t],
    _ originalPrepared: [beluga_core_adaptation_state_atom_t], _ outputCount: UInt32 = 179,
    currentHeader originalCurrentHeader: beluga_core_adaptation_state_header_t = .init(abi: 1, domain: 2, phase: 1, count: 179),
    preparedHeader originalPreparedHeader: beluga_core_adaptation_state_header_t = .init(abi: 1, domain: 4, phase: 3, count: 222),
    missingCallback: Bool = false
) -> (UInt32, [[UInt8]], [[UInt8]], UInt32) {
    // Owned scalar storage and uniqued input arrays; compare the exact buffers
    // C borrowed before and after return, not re-materialized value parameters.
    var request = originalRequest, currentHeader = originalCurrentHeader, preparedHeader = originalPreparedHeader
    var current = originalCurrent.map { $0 }, prepared = originalPrepared.map { $0 }
    var outputHeader = beluga_core_adaptation_state_header_t(abi: 161, domain: 162, phase: 163, count: 164)
    var outputAtoms = Array(repeating: beluga_core_adaptation_state_atom_t(kind: 777, present: 778, high: -779, low: 780), count: 179)
    var metadata = beluga_core_adaptation_owner_event_metadata_t(abi: 801, operation: 802, scope: 803,
        read_count: 804, invocation: 805, revision: 806, peer: 807, peer_present: 808, bound: 809,
        route: 810, sample: 811, enabled: 812, lease: 813, queue_fault: 814, rtt_fault: 815)
    var outcome = beluga_core_adaptation_owner_inactive_outcome_t(abi: 821, operation: 822,
        invocation: 823, disposition: 824, route: 825)
    var edits = Array(repeating: beluga_core_adaptation_time_edit_t(action: 901, source: 902,
        index: 903, ordinal: 904, high: -905, low: 906), count: 13)
    var coordinates = Array(repeating: beluga_core_adaptation_time_coordinate_t(present: 1001,
        reserved: 1002, high: -1003, low: 1004), count: 13)
    var reads = Array(repeating: beluga_core_adaptation_clock_reply_t(abi: 1101, status: 1102,
        site: 1103, ordinal: 1104, invocation: 1105, high: -1106, low: 1107, reserved: 1108), count: 15)
    let before = [owner105PODBytes(outputHeader), owner105ArrayBytes(outputAtoms), owner105PODBytes(metadata),
        owner105PODBytes(outcome), owner105ArrayBytes(edits), owner105ArrayBytes(coordinates), owner105ArrayBytes(reads)]
    var clock = Owner216ClockContext()
    let status = withUnsafeMutablePointer(to: &clock) { clockPointer in
        withUnsafePointer(to: &request) { requestPointer in
            withUnsafePointer(to: &currentHeader) { currentHeaderPointer in
                withUnsafePointer(to: &preparedHeader) { preparedHeaderPointer in
                    current.withUnsafeMutableBufferPointer { currentPointer in
                        prepared.withUnsafeMutableBufferPointer { preparedPointer in
                            let borrowedBefore = [owner105PODBytes(requestPointer.pointee), owner105PODBytes(currentHeaderPointer.pointee),
                                owner105ArrayBytes(Array(currentPointer)), owner105PODBytes(preparedHeaderPointer.pointee),
                                owner105ArrayBytes(Array(preparedPointer))]
                            let result = outputAtoms.withUnsafeMutableBufferPointer { outputPointer in
                                edits.withUnsafeMutableBufferPointer { editPointer in
                                    coordinates.withUnsafeMutableBufferPointer { coordinatePointer in
                                        reads.withUnsafeMutableBufferPointer { readPointer in
                                            beluga_core_network_adaptation_owner_adopt_inactive(requestPointer,
                                                currentHeaderPointer, currentPointer.baseAddress!, 179,
                                                preparedHeaderPointer, preparedPointer.baseAddress!, 222,
                                                missingCallback ? nil : owner216Clock, UnsafeMutableRawPointer(clockPointer),
                                                &outputHeader, outputPointer.baseAddress!, outputCount, &metadata, &outcome,
                                                editPointer.baseAddress!, 13, coordinatePointer.baseAddress!, 13,
                                                readPointer.baseAddress!, 15)
                                        }
                                    }
                                }
                            }
                            assert([owner105PODBytes(requestPointer.pointee), owner105PODBytes(currentHeaderPointer.pointee),
                                owner105ArrayBytes(Array(currentPointer)), owner105PODBytes(preparedHeaderPointer.pointee),
                                owner105ArrayBytes(Array(preparedPointer))] == borrowedBefore)
                            return result
                        }
                    }
                }
            }
        }
    }
    return (status, [owner105PODBytes(outputHeader), owner105ArrayBytes(outputAtoms), owner105PODBytes(metadata),
        owner105PODBytes(outcome), owner105ArrayBytes(edits), owner105ArrayBytes(coordinates), owner105ArrayBytes(reads)], before, clock.calls)
}
private func adaptationOwnerInactiveSmokeV1() {
    assert(MemoryLayout<beluga_core_adaptation_owner_inactive_request_t>.size == 32)
    assert(MemoryLayout<beluga_core_adaptation_owner_inactive_request_t>.stride == 32)
    assert(MemoryLayout<beluga_core_adaptation_owner_inactive_request_t>.alignment == 8)
    owner501Offset(\beluga_core_adaptation_owner_inactive_request_t.abi, 0)
    owner501Offset(\beluga_core_adaptation_owner_inactive_request_t.operation, 4)
    owner501Offset(\beluga_core_adaptation_owner_inactive_request_t.invocation, 8)
    owner501Offset(\beluga_core_adaptation_owner_inactive_request_t.current_generation, 16)
    owner501Offset(\beluga_core_adaptation_owner_inactive_request_t.exact_peer, 24)
    owner501Offset(\beluga_core_adaptation_owner_inactive_request_t.suspended, 28)
    assert(MemoryLayout<beluga_core_adaptation_owner_inactive_outcome_t>.size == 24)
    assert(MemoryLayout<beluga_core_adaptation_owner_inactive_outcome_t>.stride == 24)
    assert(MemoryLayout<beluga_core_adaptation_owner_inactive_outcome_t>.alignment == 8)
    owner501Offset(\beluga_core_adaptation_owner_inactive_outcome_t.abi, 0)
    owner501Offset(\beluga_core_adaptation_owner_inactive_outcome_t.operation, 4)
    owner501Offset(\beluga_core_adaptation_owner_inactive_outcome_t.invocation, 8)
    owner501Offset(\beluga_core_adaptation_owner_inactive_outcome_t.disposition, 16)
    owner501Offset(\beluga_core_adaptation_owner_inactive_outcome_t.route, 20)
    let admitted = beluga_core_adaptation_owner_inactive_request_t(abi: 1, operation: 601,
        invocation: 0xfedcba9876543210, current_generation: 42, exact_peer: 1, suspended: 0)
    let current = owner216SmokeSeed()
    assert(current[41].low == 1 && current[140].low == 1) // sticky demand fault: exact zero-read typed cut
    let resultHeader = beluga_core_adaptation_state_header_t(abi: 1, domain: 2, phase: 2, count: 179)
    let timeAtoms = [12,23,28,159,163,167,39,40,88]
    for mode in 0..<4 {
        var request = admitted
        var prepared = owner601PreparedSeed(current)
        if mode == 1 { request.exact_peer = 0 }
        if mode == 2 { request.current_generation = 43 }
        if mode == 3 { prepared[169].low = UInt64.max - 1 }
        let actual = owner601RawCall(request, current, prepared)
        assert(actual.0 == 1 && actual.3 == 0)
        var expectedAtoms = current
        if mode == 0 {
            expectedAtoms.replaceSubrange(0..<168, with: prepared.prefix(168)); expectedAtoms[168].low = 0
        }
        let expectedMetadata = beluga_core_adaptation_owner_event_metadata_t(abi: 1, operation: 601, scope: 2,
            read_count: 0, invocation: 0xfedcba9876543210, revision: mode == 0 ? 0 : UInt64.max,
            peer: 10003, peer_present: 1, bound: 0, route: 0, sample: 0, enabled: 0, lease: 0, queue_fault: 1, rtt_fault: 0)
        let expectedOutcome = beluga_core_adaptation_owner_inactive_outcome_t(abi: 1, operation: 601,
            invocation: 0xfedcba9876543210, disposition: mode == 0 ? 1 : 0, route: 0)
        var expectedEdits = Array(repeating: beluga_core_adaptation_time_edit_t(), count: 13)
        var expectedCoordinates = Array(repeating: beluga_core_adaptation_time_coordinate_t(), count: 13)
        for (index, position) in timeAtoms.enumerated() {
            let value = (mode == 0 ? prepared : current)[position]
            expectedEdits[index] = beluga_core_adaptation_time_edit_t(action: mode == 0 ? 3 : 1,
                source: mode == 0 ? 2 : 0, index: mode == 0 ? UInt32(index) : 0, ordinal: 0, high: 0, low: 0)
            expectedCoordinates[index] = beluga_core_adaptation_time_coordinate_t(present: value.present,
                reserved: 0, high: value.high, low: value.low)
        }
        let expectedReads = Array(repeating: beluga_core_adaptation_clock_reply_t(), count: 15)
        assert(actual.1 == [owner105PODBytes(resultHeader), owner105ArrayBytes(expectedAtoms), owner105PODBytes(expectedMetadata),
            owner105PODBytes(expectedOutcome), owner105ArrayBytes(expectedEdits), owner105ArrayBytes(expectedCoordinates),
            owner105ArrayBytes(expectedReads)]) // seven complete output objects
    }
    for mode in 0..<12 {
        var request = admitted, atoms = current
        var prepared = owner601PreparedSeed(current)
        var ch = beluga_core_adaptation_state_header_t(abi: 1, domain: 2, phase: 1, count: 179)
        var ph = beluga_core_adaptation_state_header_t(abi: 1, domain: 4, phase: 3, count: 222)
        var outputCount: UInt32 = 179
        if mode == 0 { request.operation = 501 }
        if mode == 1 { request.abi = 2 }
        if mode == 2 { request.invocation = 0 }
        if mode == 3 { request.exact_peer = 2 }
        if mode == 4 { request.suspended = 2 }
        if mode == 5 { atoms[178].kind = 99 }
        if mode == 6 { prepared[221].kind = 99 }
        if mode == 7 { ch.phase = 2 }
        if mode == 8 { ph.domain = 2 }
        if mode == 9 { ph.phase = 2 }
        if mode == 10 { outputCount = 178 }
        let denied = owner601RawCall(request, atoms, prepared, outputCount,
            currentHeader: ch, preparedHeader: ph, missingCallback: mode == 11)
        assert(denied.0 == 2 && denied.3 == 0 && denied.1 == denied.2)
    }
}
adaptationOwnerInactiveSmokeV1()
print("BelugaCore Swift adaptation Owner inactive PASS: layouts, full179 adoption/stale, nine origins, twelve untouched denials")

// Public701 import/link smoke. Synthetic POD does not seal native Prepared custody.
private func owner701RawCall(_ originalRequest: beluga_core_adaptation_owner_begin_active_request_t,
    _ originalCurrent: [beluga_core_adaptation_state_atom_t],
    _ originalPrepared: [beluga_core_adaptation_state_atom_t], _ outputCount: UInt32 = 179,
    currentHeader originalCurrentHeader: beluga_core_adaptation_state_header_t = .init(abi: 1, domain: 2, phase: 1, count: 179),
    preparedHeader originalPreparedHeader: beluga_core_adaptation_state_header_t = .init(abi: 1, domain: 4, phase: 3, count: 222),
    missingCallback: Bool = false, outputPreparedCount: UInt32 = 222, editCount: UInt32 = 13
) -> (UInt32, [[UInt8]], [[UInt8]], UInt32) {
    // Owned scalar storage and uniqued input arrays; compare the exact buffers
    // C borrowed before and after return, not re-materialized value parameters.
    var request = originalRequest, currentHeader = originalCurrentHeader, preparedHeader = originalPreparedHeader
    var current = originalCurrent.map { $0 }, prepared = originalPrepared.map { $0 }
    var outputHeader = beluga_core_adaptation_state_header_t(abi: 161, domain: 162, phase: 163, count: 164)
    var outputAtoms = Array(repeating: beluga_core_adaptation_state_atom_t(kind: 777, present: 778, high: -779, low: 780), count: 179)
    var outputPreparedHeader = beluga_core_adaptation_state_header_t(abi: 171, domain: 172, phase: 173, count: 174)
    var outputPreparedAtoms = Array(repeating: beluga_core_adaptation_state_atom_t(kind: 787, present: 788, high: -789, low: 790), count: 222)
    var metadata = beluga_core_adaptation_owner_event_metadata_t(abi: 801, operation: 802, scope: 803,
        read_count: 804, invocation: 805, revision: 806, peer: 807, peer_present: 808, bound: 809,
        route: 810, sample: 811, enabled: 812, lease: 813, queue_fault: 814, rtt_fault: 815)
    var outcome = beluga_core_adaptation_owner_begin_active_outcome_t(abi: 821, operation: 822,
        invocation: 823, disposition: 824, route: 825, prepared_present: 826, reserved: 827)
    var edits = Array(repeating: beluga_core_adaptation_time_edit_t(action: 901, source: 902,
        index: 903, ordinal: 904, high: -905, low: 906), count: 13)
    var coordinates = Array(repeating: beluga_core_adaptation_time_coordinate_t(present: 1001,
        reserved: 1002, high: -1003, low: 1004), count: 13)
    var reads = Array(repeating: beluga_core_adaptation_clock_reply_t(abi: 1101, status: 1102,
        site: 1103, ordinal: 1104, invocation: 1105, high: -1106, low: 1107, reserved: 1108), count: 15)
    let before = [owner105PODBytes(outputHeader), owner105ArrayBytes(outputAtoms), owner105PODBytes(outputPreparedHeader),
        owner105ArrayBytes(outputPreparedAtoms), owner105PODBytes(metadata),
        owner105PODBytes(outcome), owner105ArrayBytes(edits), owner105ArrayBytes(coordinates), owner105ArrayBytes(reads)]
    var clock = Owner216ClockContext()
    let status = withUnsafeMutablePointer(to: &clock) { clockPointer in
        withUnsafePointer(to: &request) { requestPointer in
            withUnsafePointer(to: &currentHeader) { currentHeaderPointer in
                withUnsafePointer(to: &preparedHeader) { preparedHeaderPointer in
                    current.withUnsafeMutableBufferPointer { currentPointer in
                        prepared.withUnsafeMutableBufferPointer { preparedPointer in
                            let borrowedBefore = [owner105PODBytes(requestPointer.pointee), owner105PODBytes(currentHeaderPointer.pointee),
                                owner105ArrayBytes(Array(currentPointer)), owner105PODBytes(preparedHeaderPointer.pointee),
                                owner105ArrayBytes(Array(preparedPointer))]
                            let result = outputPreparedAtoms.withUnsafeMutableBufferPointer { outputPreparedPointer in
                                outputAtoms.withUnsafeMutableBufferPointer { outputPointer in
                                edits.withUnsafeMutableBufferPointer { editPointer in
                                    coordinates.withUnsafeMutableBufferPointer { coordinatePointer in
                                        reads.withUnsafeMutableBufferPointer { readPointer in
                                            beluga_core_network_adaptation_owner_begin_active(requestPointer,
                                                currentHeaderPointer, currentPointer.baseAddress!, 179,
                                                preparedHeaderPointer, preparedPointer.baseAddress!, 222,
                                                missingCallback ? nil : owner216Clock, UnsafeMutableRawPointer(clockPointer),
                                                &outputHeader, outputPointer.baseAddress!, outputCount, &outputPreparedHeader,
                                                outputPreparedPointer.baseAddress!, outputPreparedCount, &metadata, &outcome,
                                                editPointer.baseAddress!, editCount, coordinatePointer.baseAddress!, 13,
                                                readPointer.baseAddress!, 15)
                                        }
                                    }
                                }
                            }
                            }
                            assert([owner105PODBytes(requestPointer.pointee), owner105PODBytes(currentHeaderPointer.pointee),
                                owner105ArrayBytes(Array(currentPointer)), owner105PODBytes(preparedHeaderPointer.pointee),
                                owner105ArrayBytes(Array(preparedPointer))] == borrowedBefore)
                            return result
                        }
                    }
                }
            }
        }
    }
    return (status, [owner105PODBytes(outputHeader), owner105ArrayBytes(outputAtoms), owner105PODBytes(outputPreparedHeader),
        owner105ArrayBytes(outputPreparedAtoms), owner105PODBytes(metadata),
        owner105PODBytes(outcome), owner105ArrayBytes(edits), owner105ArrayBytes(coordinates), owner105ArrayBytes(reads)], before, clock.calls)
}
private func adaptationOwnerBeginActiveSmokeV1() {
    assert(MemoryLayout<beluga_core_adaptation_owner_begin_active_request_t>.size == 24)
    assert(MemoryLayout<beluga_core_adaptation_owner_begin_active_request_t>.stride == 24)
    assert(MemoryLayout<beluga_core_adaptation_owner_begin_active_request_t>.alignment == 8)
    owner501Offset(\beluga_core_adaptation_owner_begin_active_request_t.abi, 0)
    owner501Offset(\beluga_core_adaptation_owner_begin_active_request_t.operation, 4)
    owner501Offset(\beluga_core_adaptation_owner_begin_active_request_t.invocation, 8)
    owner501Offset(\beluga_core_adaptation_owner_begin_active_request_t.resource_flags, 16)
    owner501Offset(\beluga_core_adaptation_owner_begin_active_request_t.reserved, 20)
    assert(MemoryLayout<beluga_core_adaptation_owner_begin_active_outcome_t>.size == 32)
    assert(MemoryLayout<beluga_core_adaptation_owner_begin_active_outcome_t>.stride == 32)
    assert(MemoryLayout<beluga_core_adaptation_owner_begin_active_outcome_t>.alignment == 8)
    owner501Offset(\beluga_core_adaptation_owner_begin_active_outcome_t.abi, 0)
    owner501Offset(\beluga_core_adaptation_owner_begin_active_outcome_t.operation, 4)
    owner501Offset(\beluga_core_adaptation_owner_begin_active_outcome_t.invocation, 8)
    owner501Offset(\beluga_core_adaptation_owner_begin_active_outcome_t.disposition, 16)
    owner501Offset(\beluga_core_adaptation_owner_begin_active_outcome_t.route, 20)
    owner501Offset(\beluga_core_adaptation_owner_begin_active_outcome_t.prepared_present, 24)
    owner501Offset(\beluga_core_adaptation_owner_begin_active_outcome_t.reserved, 28)
    let invocation: UInt64 = 0xfedcba9876543210
    for mode in 0..<16 {
        var request = beluga_core_adaptation_owner_begin_active_request_t(abi: 1, operation: 701,
            invocation: invocation, resource_flags: 0, reserved: 0)
        var current = owner216SmokeSeed(), prepared = owner601PreparedSeed(owner216SmokeSeed())
        prepared[89].low = 0; prepared[140].low = 0
        if mode == 1 {
            current[173].low = 1; current[174].low = 2
            current[175].low = 333333; current[176].low = 444444; current[177].low = 30
            current[178].low = 0x3ff0000000000000
        } else {
            current[173].low = 0
            for index in 174...178 { current[index].present = 0; current[index].high = 0; current[index].low = 0 }
        }
        var ch = beluga_core_adaptation_state_header_t(abi: 1, domain: 2, phase: 1, count: 179)
        var ph = beluga_core_adaptation_state_header_t(abi: 1, domain: 4, phase: 3, count: 222)
        var outputCount: UInt32 = 179, outputPreparedCount: UInt32 = 222, editCount: UInt32 = 13
        if mode == 2 { request.operation = 702 }
        if mode == 3 { request.abi = 2 }
        if mode == 4 { request.invocation = 0 }
        if mode == 5 { request.resource_flags = 64 }
        if mode == 6 { request.reserved = 1 }
        if mode == 7 { current[178].kind = 99 }
        if mode == 8 { prepared[221].kind = 99 }
        if mode == 9 { ch.phase = 2 }
        if mode == 10 { ph.domain = 2 }
        if mode == 11 { ph.phase = 2 }
        if mode == 12 { outputCount = 178 }
        if mode == 13 { outputPreparedCount = 221 }
        if mode == 15 { editCount = 12 }
        let actual = owner701RawCall(request, current, prepared, outputCount, currentHeader: ch, preparedHeader: ph,
            missingCallback: mode == 14, outputPreparedCount: outputPreparedCount, editCount: editCount)
        assert(actual.3 == 0)
        if mode >= 2 { assert(actual.0 == 2 && actual.1 == actual.2); continue }
        assert(actual.0 == 1)
        let resultHeader = beluga_core_adaptation_state_header_t(abi: 1, domain: 2, phase: 2, count: 179)
        let resultPreparedHeader = mode == 1 ? ph : beluga_core_adaptation_state_header_t()
        let resultPrepared = mode == 1 ? prepared : Array(repeating: beluga_core_adaptation_state_atom_t(), count: 222)
        let metadata = beluga_core_adaptation_owner_event_metadata_t(abi: 1, operation: 701, scope: 2,
            read_count: 0, invocation: invocation, revision: UInt64.max, peer: 10003, peer_present: 1,
            bound: 0, route: 0, sample: 0, enabled: 0, lease: 0, queue_fault: 1, rtt_fault: 0)
        let outcome = beluga_core_adaptation_owner_begin_active_outcome_t(abi: 1, operation: 701,
            invocation: invocation, disposition: UInt32(mode), route: 0, prepared_present: UInt32(mode), reserved: 0)
        var edits = Array(repeating: beluga_core_adaptation_time_edit_t(), count: 13)
        var coordinates = Array(repeating: beluga_core_adaptation_time_coordinate_t(), count: 13)
        for (index, position) in [12,23,28,159,163,167,39,40,88].enumerated() {
            let value = current[position]
            edits[index] = beluga_core_adaptation_time_edit_t(action: 1, source: 0, index: 0, ordinal: 0, high: 0, low: 0)
            coordinates[index] = beluga_core_adaptation_time_coordinate_t(present: value.present, reserved: 0, high: value.high, low: value.low)
        }
        assert(actual.1 == [owner105PODBytes(resultHeader), owner105ArrayBytes(current), owner105PODBytes(resultPreparedHeader),
            owner105ArrayBytes(resultPrepared), owner105PODBytes(metadata), owner105PODBytes(outcome), owner105ArrayBytes(edits),
            owner105ArrayBytes(coordinates), owner105ArrayBytes(Array(repeating: beluga_core_adaptation_clock_reply_t(), count: 15))])
    }
}
adaptationOwnerBeginActiveSmokeV1()
print("BelugaCore Swift adaptation Owner begin-active PASS: layouts, exact179/222 Return/NoNativeApply, fourteen untouched denials")

// Public702/703/704 Swift import/link smoke; synthetic POD is not native custody.
private struct OwnerCompletionEffect {
    var calls: UInt32 = 0
    var invocation: UInt64 = 0
    var fps: Int64 = 0
    var validationCalls: UInt32 = 0
    var validationInvocation: UInt64 = 0
    var validationCounts: [UInt32] = []
    var draft: [[UInt8]] = []
    var trace: [UInt32] = []
    var reply: UInt32 = 1
}
private let ownerCompletionOutput: beluga_core_adaptation_owner_output_callback_t = { context, invocation, fps in
    guard let context else { return }
    let effect = context.assumingMemoryBound(to: OwnerCompletionEffect.self)
    effect.pointee.trace.append(2)
    effect.pointee.calls += 1
    effect.pointee.invocation = invocation
    effect.pointee.fps = fps
}
private let ownerCompletionValidate: beluga_core_adaptation_owner_validation_callback_t = {
    context, invocation, header, atoms, atomCount, metadata, outcome, edits, editCount, coordinates, coordinateCount in
    guard let context else { return 2 }
    let effect = context.assumingMemoryBound(to: OwnerCompletionEffect.self)
    effect.pointee.validationCalls += 1
    effect.pointee.validationInvocation = invocation
    effect.pointee.validationCounts = [atomCount, editCount, coordinateCount]
    effect.pointee.trace.append(1)
    guard let header, let atoms, let metadata, let outcome, let edits, let coordinates,
        atomCount == 179, editCount == 13, coordinateCount == 13 else { return 2 }
    effect.pointee.draft = [owner105PODBytes(header.pointee),
        owner105ArrayBytes(Array(UnsafeBufferPointer(start: atoms, count: 179))),
        owner105PODBytes(metadata.pointee), owner105PODBytes(outcome.pointee),
        owner105ArrayBytes(Array(UnsafeBufferPointer(start: edits, count: 13))),
        owner105ArrayBytes(Array(UnsafeBufferPointer(start: coordinates, count: 13)))]
    return effect.pointee.reply
}
private func ownerCompletionRawCall(_ originalRequest: beluga_core_adaptation_owner_completion_request_t,
    _ originalCurrent: [beluga_core_adaptation_state_atom_t],
    _ originalPrepared: [beluga_core_adaptation_state_atom_t],
    originalOperation: UInt32, currentHeader originalCurrentHeader: beluga_core_adaptation_state_header_t,
    preparedHeader originalPreparedHeader: beluga_core_adaptation_state_header_t,
    outputCount: UInt32 = 179, editCount: UInt32 = 13, coordinateCount: UInt32 = 13,
    missingCallback: Bool = false, validated: Bool = false, missingValidator: Bool = false,
    validatorReply: UInt32 = 1
) -> (UInt32, [[UInt8]], [[UInt8]], UInt32, OwnerCompletionEffect) {
    var request = originalRequest, currentHeader = originalCurrentHeader, preparedHeader = originalPreparedHeader
    var current = originalCurrent.map { $0 }, prepared = originalPrepared.map { $0 }
    var outputHeader = beluga_core_adaptation_state_header_t(abi: 161, domain: 162, phase: 163, count: 164)
    var outputAtoms = Array(repeating: beluga_core_adaptation_state_atom_t(kind: 777, present: 778, high: -779, low: 780), count: 179)
    var metadata = beluga_core_adaptation_owner_event_metadata_t(abi: 801, operation: 802, scope: 803,
        read_count: 804, invocation: 805, revision: 806, peer: 807, peer_present: 808, bound: 809,
        route: 810, sample: 811, enabled: 812, lease: 813, queue_fault: 814, rtt_fault: 815)
    var completion = beluga_core_adaptation_owner_completion_outcome_t(abi: 821, operation: 822,
        invocation: 823, disposition: 824, route: 825, fps_changed: 826, reserved: 827)
    var failure = beluga_core_adaptation_owner_failure_outcome_t(abi: 821, operation: 822,
        invocation: 823, disposition: 824, route: 825, semantic_error: 826, attempted_reads: 827)
    var edits = Array(repeating: beluga_core_adaptation_time_edit_t(action: 901, source: 902,
        index: 903, ordinal: 904, high: -905, low: 906), count: 13)
    var coordinates = Array(repeating: beluga_core_adaptation_time_coordinate_t(present: 1001,
        reserved: 1002, high: -1003, low: 1004), count: 13)
    var reads = Array(repeating: beluga_core_adaptation_clock_reply_t(abi: 1101, status: 1102,
        site: 1103, ordinal: 1104, invocation: 1105, high: -1106, low: 1107, reserved: 1108), count: 15)
    let before = [owner105PODBytes(outputHeader), owner105ArrayBytes(outputAtoms), owner105PODBytes(metadata),
        originalOperation == 703 ? owner105PODBytes(failure) : owner105PODBytes(completion),
        owner105ArrayBytes(edits), owner105ArrayBytes(coordinates), owner105ArrayBytes(reads)]
    var clock = Owner216ClockContext(), effect = OwnerCompletionEffect()
    effect.reply = validatorReply
    let status = withUnsafeMutablePointer(to: &effect) { effectPointer in
        withUnsafeMutablePointer(to: &clock) { clockPointer in
            withUnsafePointer(to: &request) { requestPointer in
                withUnsafePointer(to: &currentHeader) { ch in
                    withUnsafePointer(to: &preparedHeader) { ph in
                        current.withUnsafeMutableBufferPointer { ca in
                            prepared.withUnsafeMutableBufferPointer { pa in
                                let borrowedBefore = [owner105PODBytes(requestPointer.pointee), owner105PODBytes(ch.pointee),
                                    owner105ArrayBytes(Array(ca)), owner105PODBytes(ph.pointee), owner105ArrayBytes(Array(pa))]
                                let result = outputAtoms.withUnsafeMutableBufferPointer { oa in
                                    edits.withUnsafeMutableBufferPointer { ep in
                                        coordinates.withUnsafeMutableBufferPointer { cp in
                                            reads.withUnsafeMutableBufferPointer { rp in
                                                if originalOperation == 702 {
                                                    if validated {
                                                        return beluga_core_network_adaptation_owner_finish_success_validated(requestPointer,
                                                            ch, ca.baseAddress!, 179, ph, pa.baseAddress!, 222,
                                                            missingValidator ? nil : ownerCompletionValidate,
                                                            missingCallback ? nil : ownerCompletionOutput, UnsafeMutableRawPointer(effectPointer),
                                                            &outputHeader, oa.baseAddress!, outputCount, &metadata, &completion,
                                                            ep.baseAddress!, editCount, cp.baseAddress!, coordinateCount)
                                                    }
                                                    return beluga_core_network_adaptation_owner_finish_success(requestPointer,
                                                        ch, ca.baseAddress!, 179, ph, pa.baseAddress!, 222,
                                                        missingCallback ? nil : ownerCompletionOutput, UnsafeMutableRawPointer(effectPointer),
                                                        &outputHeader, oa.baseAddress!, outputCount, &metadata, &completion,
                                                        ep.baseAddress!, editCount, cp.baseAddress!, coordinateCount)
                                                }
                                                if originalOperation == 703 {
                                                    return beluga_core_network_adaptation_owner_finish_failure(requestPointer,
                                                        ch, ca.baseAddress!, 179, ph, pa.baseAddress!, 222,
                                                        missingCallback ? nil : owner216Clock, UnsafeMutableRawPointer(clockPointer),
                                                        &outputHeader, oa.baseAddress!, outputCount, &metadata, &failure,
                                                        ep.baseAddress!, editCount, cp.baseAddress!, coordinateCount, rp.baseAddress!, 15)
                                                }
                                                return beluga_core_network_adaptation_owner_final_adopt(requestPointer,
                                                    ch, ca.baseAddress!, 179, ph, pa.baseAddress!, 222,
                                                    &outputHeader, oa.baseAddress!, outputCount, &metadata, &completion,
                                                    ep.baseAddress!, editCount, cp.baseAddress!, coordinateCount)
                                            }
                                        }
                                    }
                                }
                                assert([owner105PODBytes(requestPointer.pointee), owner105PODBytes(ch.pointee),
                                    owner105ArrayBytes(Array(ca)), owner105PODBytes(ph.pointee), owner105ArrayBytes(Array(pa))] == borrowedBefore)
                                return result
                            }
                        }
                    }
                }
            }
        }
    }
    return (status, [owner105PODBytes(outputHeader), owner105ArrayBytes(outputAtoms), owner105PODBytes(metadata),
        originalOperation == 703 ? owner105PODBytes(failure) : owner105PODBytes(completion),
        owner105ArrayBytes(edits), owner105ArrayBytes(coordinates), owner105ArrayBytes(reads)], before, clock.calls, effect)
}
private func adaptationOwnerCompletionSmokeV1() {
    assert(MemoryLayout<beluga_core_adaptation_owner_completion_request_t>.size == 32)
    assert(MemoryLayout<beluga_core_adaptation_owner_completion_request_t>.stride == 32)
    assert(MemoryLayout<beluga_core_adaptation_owner_completion_request_t>.alignment == 8)
    owner501Offset(\beluga_core_adaptation_owner_completion_request_t.abi, 0)
    owner501Offset(\beluga_core_adaptation_owner_completion_request_t.operation, 4)
    owner501Offset(\beluga_core_adaptation_owner_completion_request_t.invocation, 8)
    owner501Offset(\beluga_core_adaptation_owner_completion_request_t.current_generation, 16)
    owner501Offset(\beluga_core_adaptation_owner_completion_request_t.facts, 24)
    owner501Offset(\beluga_core_adaptation_owner_completion_request_t.reserved, 28)
    assert(MemoryLayout<beluga_core_adaptation_owner_failure_request_t>.size == 32)
    assert(MemoryLayout<beluga_core_adaptation_owner_completion_outcome_t>.size == 32)
    assert(MemoryLayout<beluga_core_adaptation_owner_completion_outcome_t>.stride == 32)
    assert(MemoryLayout<beluga_core_adaptation_owner_completion_outcome_t>.alignment == 8)
    owner501Offset(\beluga_core_adaptation_owner_completion_outcome_t.abi, 0)
    owner501Offset(\beluga_core_adaptation_owner_completion_outcome_t.operation, 4)
    owner501Offset(\beluga_core_adaptation_owner_completion_outcome_t.invocation, 8)
    owner501Offset(\beluga_core_adaptation_owner_completion_outcome_t.disposition, 16)
    owner501Offset(\beluga_core_adaptation_owner_completion_outcome_t.route, 20)
    owner501Offset(\beluga_core_adaptation_owner_completion_outcome_t.fps_changed, 24)
    owner501Offset(\beluga_core_adaptation_owner_completion_outcome_t.reserved, 28)
    assert(MemoryLayout<beluga_core_adaptation_owner_failure_outcome_t>.size == 32)
    assert(MemoryLayout<beluga_core_adaptation_owner_failure_outcome_t>.stride == 32)
    assert(MemoryLayout<beluga_core_adaptation_owner_failure_outcome_t>.alignment == 8)
    owner501Offset(\beluga_core_adaptation_owner_failure_outcome_t.abi, 0)
    owner501Offset(\beluga_core_adaptation_owner_failure_outcome_t.operation, 4)
    owner501Offset(\beluga_core_adaptation_owner_failure_outcome_t.invocation, 8)
    owner501Offset(\beluga_core_adaptation_owner_failure_outcome_t.disposition, 16)
    owner501Offset(\beluga_core_adaptation_owner_failure_outcome_t.route, 20)
    owner501Offset(\beluga_core_adaptation_owner_failure_outcome_t.semantic_error, 24)
    owner501Offset(\beluga_core_adaptation_owner_failure_outcome_t.attempted_reads, 28)
    let invocation: UInt64 = 0xfedcba9876543210
    for operation: UInt32 in 702...704 {
        for mode in 0..<15 {
            var request = beluga_core_adaptation_owner_completion_request_t(abi: 1, operation: operation,
                invocation: invocation, current_generation: 42, facts: mode == 0 ? 0 : (operation == 704 ? 1 : 511), reserved: 0)
            var current = owner216SmokeSeed(), prepared = owner601PreparedSeed(owner216SmokeSeed())
            prepared[170].low = UInt64.max; prepared[185].low = 2
            prepared[151].low = 0; prepared[154].low = 0
            if mode == 2 && operation == 702 { current[177].low = 30 }
            var ch = beluga_core_adaptation_state_header_t(abi: 1, domain: 2, phase: 1, count: 179)
            var ph = beluga_core_adaptation_state_header_t(abi: 1, domain: 4, phase: 3, count: 222)
            var outputCount: UInt32 = 179, editCount: UInt32 = 13, coordinateCount: UInt32 = 13
            if mode == 3 { request.abi = 2 }
            if mode == 4 { request.operation = 701 }
            if mode == 5 { request.invocation = 0 }
            if mode == 6 { request.facts = operation == 704 ? 2 : 512 }
            if mode == 7 { request.reserved = 1 }
            if mode == 8 { current[178].kind = 99 }
            if mode == 9 { prepared[221].kind = 99 }
            if mode == 10 { ch.phase = 2 }
            if mode == 11 { ph.phase = 2 }
            if mode == 12 { outputCount = 178 }
            if mode == 13 { editCount = 12 }
            if mode == 14 && operation == 704 { coordinateCount = 12 }
            let actual = ownerCompletionRawCall(request, current, prepared, originalOperation: operation,
                currentHeader: ch, preparedHeader: ph, outputCount: outputCount, editCount: editCount,
                coordinateCount: coordinateCount, missingCallback: mode == 14)
            assert(actual.3 == 0)
            if operation == 702 {
                for admission in 0..<5 {
                    let replies: [UInt32] = [1, 0, 2, UInt32.max]
                    let checked = ownerCompletionRawCall(request, current, prepared, originalOperation: 702,
                        currentHeader: ch, preparedHeader: ph, outputCount: outputCount, editCount: editCount,
                        coordinateCount: coordinateCount, missingCallback: mode == 14, validated: true,
                        missingValidator: admission == 4, validatorReply: admission < 4 ? replies[admission] : 1)
                    assert(checked.3 == 0)
                    if mode >= 3 || admission == 4 {
                        assert(checked.0 == 2 && checked.1 == checked.2)
                        assert(checked.4.validationCalls == 0 && checked.4.calls == 0 && checked.4.trace.isEmpty)
                    } else {
                        assert(checked.4.validationCalls == 1 && checked.4.validationInvocation == invocation)
                        assert(checked.4.validationCounts == [179, 13, 13])
                        assert(checked.4.draft == Array(actual.1.prefix(6)))
                        if admission == 0 {
                            assert(checked.0 == 1 && checked.1 == actual.1 && checked.4.calls == actual.4.calls)
                            assert(checked.4.trace == (actual.4.calls == 1 ? [1, 2] : [1]))
                            if checked.4.calls == 1 { assert(checked.4.invocation == invocation && checked.4.fps == 30) }
                        } else {
                            assert(checked.0 == 3 && checked.1 == checked.2 && checked.4.calls == 0 && checked.4.trace == [1])
                        }
                    }
                }
            }
            if mode >= 3 { assert(actual.0 == 2 && actual.1 == actual.2 && actual.4.calls == 0); continue }
            assert(actual.0 == 1)
            let accepted = mode != 0
            var expected = current
            if accepted && operation == 702 {
                expected[173].low = 1
                for index in 0..<5 { expected[174+index].low = prepared[180+index].low }
            } else if accepted && operation == 703 { expected[168].low = 0 }
            else if accepted && operation == 704 {
                for index in 0..<168 { expected[index] = prepared[index] }
                expected[168].low = 0
            }
            let route: UInt32 = accepted && operation == 704 ? 2 : 0
            let fpsChanged: UInt32 = accepted && operation == 702 && mode != 2 ? 1 : 0
            let header = beluga_core_adaptation_state_header_t(abi: 1, domain: 2, phase: 2, count: 179)
            let metadata = beluga_core_adaptation_owner_event_metadata_t(abi: 1, operation: operation, scope: 2,
                read_count: 0, invocation: invocation, revision: expected[168].low, peer: 10003, peer_present: 1,
                bound: 0, route: route, sample: 0, enabled: 0, lease: 0, queue_fault: 1, rtt_fault: 0)
            let completion = beluga_core_adaptation_owner_completion_outcome_t(abi: 1, operation: operation,
                invocation: invocation, disposition: accepted ? 1 : 0, route: route, fps_changed: fpsChanged, reserved: 0)
            let failure = beluga_core_adaptation_owner_failure_outcome_t(abi: 1, operation: 703,
                invocation: invocation, disposition: accepted ? 1 : 0, route: 0, semantic_error: 0, attempted_reads: 0)
            var edits = Array(repeating: beluga_core_adaptation_time_edit_t(), count: 13)
            var coordinates = Array(repeating: beluga_core_adaptation_time_coordinate_t(), count: 13)
            for (index, position) in [12,23,28,159,163,167,39,40,88].enumerated() {
                let value = expected[position]
                if accepted && operation == 704 {
                    edits[index] = beluga_core_adaptation_time_edit_t(action: value.present == 1 ? 3 : 2,
                        source: value.present == 1 ? 2 : 0, index: value.present == 1 ? UInt32(index) : 0, ordinal: 0, high: 0, low: 0)
                } else { edits[index] = beluga_core_adaptation_time_edit_t(action: 1, source: 0, index: 0, ordinal: 0, high: 0, low: 0) }
                coordinates[index] = beluga_core_adaptation_time_coordinate_t(present: value.present, reserved: 0, high: value.high, low: value.low)
            }
            let reads = operation == 703 ? owner105ArrayBytes(Array(repeating: beluga_core_adaptation_clock_reply_t(), count: 15)) : actual.2[6]
            assert(actual.1 == [owner105PODBytes(header), owner105ArrayBytes(expected), owner105PODBytes(metadata),
                operation == 703 ? owner105PODBytes(failure) : owner105PODBytes(completion),
                owner105ArrayBytes(edits), owner105ArrayBytes(coordinates), reads])
            assert(actual.4.calls == fpsChanged)
            if fpsChanged == 1 { assert(actual.4.invocation == invocation && actual.4.fps == 30) }
        }
    }
}
adaptationOwnerCompletionSmokeV1()
print("BelugaCore Swift adaptation Owner completion PASS: 702/703/704 layouts, exact179 results, untouched denials")
print("BelugaCore Swift adaptation Owner validated702 PASS: actual private bundle, validator-before-effect, stale/sameFPS, strict denial and missing thunks")

// Add at EOF of the existing BelugaCore import smoke. No native clock/device calls.
private func micEvidenceBytes<T>(_ value: T) -> [UInt8] {
    withUnsafeBytes(of: value) { Array($0) }
}
private func micEvidenceOffset<T, U>(_ key: KeyPath<T, U>, _ expected: Int) {
    assert(MemoryLayout<T>.offset(of: key) == expected)
}
private func micEvidenceMark(_ values: [beluga_core_microphone_optional_u64_t]) -> beluga_core_microphone_watermark_t {
    assert(values.count == 4)
    return beluga_core_microphone_watermark_t(present: 1, reserved: 0,
        fields: (values[0], values[1], values[2], values[3]))
}
private func microphoneForwardingEvidenceSmokeV1() {
    assert(MemoryLayout<beluga_core_microphone_optional_u64_t>.size == 16)
    assert(MemoryLayout<beluga_core_microphone_progress_t>.size == 40)
    assert(MemoryLayout<beluga_core_microphone_readiness_facts_t>.size == 96)
    assert(MemoryLayout<beluga_core_microphone_readiness_result_t>.size == 16)
    assert(MemoryLayout<beluga_core_microphone_watermark_t>.size == 72)
    assert(MemoryLayout<beluga_core_microphone_watermark_state_t>.size == 80)
    assert(MemoryLayout<beluga_core_microphone_watermark_event_t>.size == 80)
    assert(MemoryLayout<beluga_core_microphone_watermark_result_t>.size == 96)
    assert(MemoryLayout<beluga_core_microphone_freshness_state_t>.size == 40)
    assert(MemoryLayout<beluga_core_microphone_freshness_event_t>.size == 32)
    assert(MemoryLayout<beluga_core_microphone_freshness_result_t>.size == 16)
    assert(MemoryLayout<beluga_core_microphone_watermark_result_t>.alignment == 8)
    micEvidenceOffset(\beluga_core_microphone_optional_u64_t.value, 8)
    micEvidenceOffset(\beluga_core_microphone_progress_t.post_start_callback_count, 8)
    micEvidenceOffset(\beluga_core_microphone_progress_t.successful_pull_count, 16)
    micEvidenceOffset(\beluga_core_microphone_progress_t.successful_frame_count, 24)
    micEvidenceOffset(\beluga_core_microphone_progress_t.enqueue_failure_count, 32)
    micEvidenceOffset(\beluga_core_microphone_readiness_facts_t.current, 8)
    micEvidenceOffset(\beluga_core_microphone_readiness_facts_t.previous_present, 48)
    micEvidenceOffset(\beluga_core_microphone_readiness_facts_t.previous, 56)
    micEvidenceOffset(\beluga_core_microphone_readiness_result_t.continuing, 12)
    micEvidenceOffset(\beluga_core_microphone_watermark_t.fields, 8)
    micEvidenceOffset(\beluga_core_microphone_watermark_state_t.retained, 8)
    micEvidenceOffset(\beluga_core_microphone_watermark_event_t.current, 8)
    micEvidenceOffset(\beluga_core_microphone_watermark_result_t.status, 80)
    micEvidenceOffset(\beluga_core_microphone_watermark_result_t.continuous, 84)
    micEvidenceOffset(\beluga_core_microphone_watermark_result_t.did_advance, 88)
    micEvidenceOffset(\beluga_core_microphone_freshness_state_t.advancement_count, 8)
    micEvidenceOffset(\beluga_core_microphone_freshness_state_t.consecutive_stale_samples, 16)
    micEvidenceOffset(\beluga_core_microphone_freshness_state_t.deadline, 24)
    micEvidenceOffset(\beluga_core_microphone_freshness_event_t.maximum_stale_samples, 8)
    micEvidenceOffset(\beluga_core_microphone_freshness_event_t.now, 16)
    micEvidenceOffset(\beluga_core_microphone_freshness_result_t.fresh, 8)

    let previous = beluga_core_microphone_progress_t(queue_running: 1, reserved: 0,
        post_start_callback_count: 1, successful_pull_count: 1, successful_frame_count: 479, enqueue_failure_count: 0)
    let current = beluga_core_microphone_progress_t(queue_running: 1, reserved: 0,
        post_start_callback_count: 2, successful_pull_count: 1, successful_frame_count: 480, enqueue_failure_count: 0)
    let facts = beluga_core_microphone_readiness_facts_t(abi_version: 1, reserved: 0, current: current,
        previous_present: 1, previous_reserved: 0, previous: previous)
    let beforeFacts = micEvidenceBytes(facts)
    let healthy = beluga_core_microphone_readiness_result_t(abi_version: 1, status: 1, ready: 1, continuing: 1)
    let notContinuing = beluga_core_microphone_readiness_result_t(abi_version: 1, status: 1, ready: 1, continuing: 0)
    let invalidHealth = beluga_core_microphone_readiness_result_t(abi_version: 1, status: 0, ready: 0, continuing: 0)
    assert(micEvidenceBytes(beluga_core_microphone_forwarding_readiness_decide(facts)) == micEvidenceBytes(healthy))
    assert(micEvidenceBytes(facts) == beforeFacts)
    for mode in 0..<8 {
        var bad = facts
        if mode == 0 { bad.abi_version = 2 }; if mode == 1 { bad.reserved = 1 }
        if mode == 2 { bad.current.queue_running = 2 }; if mode == 3 { bad.current.reserved = 1 }
        if mode == 4 { bad.previous_present = 2 }; if mode == 5 { bad.previous_reserved = 1 }
        if mode == 6 { bad.previous.queue_running = 2 }; if mode == 7 { bad.previous.reserved = 1 }
        let before = micEvidenceBytes(bad)
        assert(micEvidenceBytes(beluga_core_microphone_forwarding_readiness_decide(bad)) == micEvidenceBytes(invalidHealth))
        assert(micEvidenceBytes(bad) == before)
    }
    var absent = facts; absent.previous_present = 0; absent.previous.queue_running = 9; absent.previous.reserved = 7
    assert(micEvidenceBytes(beluga_core_microphone_forwarding_readiness_decide(absent)) == micEvidenceBytes(notContinuing))
    for counter in 0..<2 {
        var notGrowing = facts
        if counter == 0 { notGrowing.current.post_start_callback_count = 1 } else { notGrowing.current.successful_frame_count = 479 }
        assert(micEvidenceBytes(beluga_core_microphone_forwarding_readiness_decide(notGrowing)) == micEvidenceBytes(notContinuing))
    }

    let present = { (value: UInt64) in beluga_core_microphone_optional_u64_t(present: 1, reserved: 0, value: value) }
    let gap = beluga_core_microphone_optional_u64_t(present: 0, reserved: 0, value: UInt64.max)
    let state = beluga_core_microphone_watermark_state_t(abi_version: 1, reserved: 0,
        retained: micEvidenceMark([present(10), present(100), present(20), present(200)]))
    let event = beluga_core_microphone_watermark_event_t(abi_version: 1, reserved: 0,
        current: micEvidenceMark([present(11), present(101), gap, gap]))
    let beforeState = micEvidenceBytes(state), beforeEvent = micEvidenceBytes(event)
    let expectedState = beluga_core_microphone_watermark_state_t(abi_version: 1, reserved: 0,
        retained: micEvidenceMark([present(11), present(101), present(20), present(200)]))
    let expected = beluga_core_microphone_watermark_result_t(state: expectedState, status: 1, continuous: 1, did_advance: 1, reserved: 0)
    assert(micEvidenceBytes(beluga_core_microphone_forwarding_watermark_step(state, event)) == micEvidenceBytes(expected))
    assert(micEvidenceBytes(state) == beforeState && micEvidenceBytes(event) == beforeEvent)
    for mode in 0..<8 {
        var badState = state, badEvent = event
        if mode == 0 { badState.abi_version = 2 }; if mode == 1 { badState.reserved = 1 }
        if mode == 2 { badState.retained.present = 2 }; if mode == 3 { badState.retained.fields.0.reserved = 1 }
        if mode == 4 { badEvent.abi_version = 2 }; if mode == 5 { badEvent.reserved = 1 }
        if mode == 6 { badEvent.current.present = 2 }; if mode == 7 { badEvent.current.fields.0.present = 2 }
        let before = micEvidenceBytes(badState), beforeEvent = micEvidenceBytes(badEvent)
        let refused = beluga_core_microphone_watermark_result_t(state: badState, status: 0, continuous: 0, did_advance: 0, reserved: 0)
        assert(micEvidenceBytes(beluga_core_microphone_forwarding_watermark_step(badState, badEvent)) == micEvidenceBytes(refused))
        assert(micEvidenceBytes(badState) == before && micEvidenceBytes(badEvent) == beforeEvent)
    }
    var regressed = event; regressed.current.fields.0.value = 9
    let unchanged = beluga_core_microphone_watermark_result_t(state: state, status: 1, continuous: 0, did_advance: 0, reserved: 0)
    assert(micEvidenceBytes(beluga_core_microphone_forwarding_watermark_step(state, regressed)) == micEvidenceBytes(unchanged))
    var noSample = regressed; noSample.current.present = 0; noSample.current.fields.0.present = 9; noSample.current.fields.0.reserved = 7
    assert(micEvidenceBytes(beluga_core_microphone_forwarding_watermark_step(state, noSample)) == micEvidenceBytes(unchanged))

    let freshState = beluga_core_microphone_freshness_state_t(abi_version: 1, reserved: 0,
        advancement_count: 1, consecutive_stale_samples: 0, deadline: present(100))
    let freshEvent = beluga_core_microphone_freshness_event_t(abi_version: 1, reserved: 0,
        maximum_stale_samples: 3, now: gap)
    let needsNow = beluga_core_microphone_freshness_result_t(abi_version: 1, status: 2, fresh: 0, reserved: 0)
    assert(micEvidenceBytes(beluga_core_microphone_forwarding_freshness_decide(freshState, freshEvent)) == micEvidenceBytes(needsNow))
    // Explicit numeric calls only; the smoke does not sample or authorize any native clock.
    for now: UInt64 in [99, 100] {
        var supplied = freshEvent; supplied.now = present(now)
        let evaluated = beluga_core_microphone_freshness_result_t(abi_version: 1, status: 1, fresh: now == 99 ? 1 : 0, reserved: 0)
        assert(micEvidenceBytes(beluga_core_microphone_forwarding_freshness_decide(freshState, supplied)) == micEvidenceBytes(evaluated))
    }
    var noDeadline = freshState; noDeadline.deadline.present = 0
    let notFresh = beluga_core_microphone_freshness_result_t(abi_version: 1, status: 1, fresh: 0, reserved: 0)
    assert(micEvidenceBytes(beluga_core_microphone_forwarding_freshness_decide(noDeadline, freshEvent)) == micEvidenceBytes(notFresh))
    for mode in 0..<8 {
        var badState = freshState, badEvent = freshEvent
        if mode == 0 { badState.abi_version = 2 }; if mode == 1 { badState.reserved = 1 }
        if mode == 2 { badState.deadline.present = 2 }; if mode == 3 { badState.deadline.reserved = 1 }
        if mode == 4 { badEvent.abi_version = 2 }; if mode == 5 { badEvent.reserved = 1 }
        if mode == 6 { badEvent.now.present = 2 }; if mode == 7 { badEvent.now.reserved = 1 }
        let before = micEvidenceBytes(badState), beforeEvent = micEvidenceBytes(badEvent)
        let refused = beluga_core_microphone_freshness_result_t(abi_version: 1, status: 0, fresh: 0, reserved: 0)
        assert(micEvidenceBytes(beluga_core_microphone_forwarding_freshness_decide(badState, badEvent)) == micEvidenceBytes(refused))
        assert(micEvidenceBytes(badState) == before && micEvidenceBytes(badEvent) == beforeEvent)
    }
}
microphoneForwardingEvidenceSmokeV1()
print("BelugaCore Swift microphone evidence ABI PASS: copied layouts, whole results, refusal and conditional NeedsNow")

// Reuse the existing copied-layout helpers. Explicit scalars only, not a native clock.
private func microphoneForwardingResultCorrelationSmokeV1() {
    let previous = beluga_core_microphone_progress_t(queue_running: 1, reserved: 0,
        post_start_callback_count: 1, successful_pull_count: 1, successful_frame_count: 479, enqueue_failure_count: 0)
    let current = beluga_core_microphone_progress_t(queue_running: 1, reserved: 0,
        post_start_callback_count: 2, successful_pull_count: 1, successful_frame_count: 480, enqueue_failure_count: 0)
    let facts = beluga_core_microphone_readiness_facts_t(abi_version: 1, reserved: 0, current: current,
        previous_present: 1, previous_reserved: 0, previous: previous)
    let ready = beluga_core_microphone_readiness_result_t(abi_version: 1, status: 1, ready: 1, continuing: 1)
    let factsBytes = micEvidenceBytes(facts), readyBytes = micEvidenceBytes(ready)
    assert(beluga_core_microphone_forwarding_readiness_result_is_valid(facts, ready) == 1)
    let falseReady = beluga_core_microphone_readiness_result_t(abi_version: 1, status: 1, ready: 0, continuing: 0)
    assert(beluga_core_microphone_forwarding_readiness_result_is_valid(facts, falseReady) == 0)
    var unready = facts; unready.current.successful_pull_count = 0
    assert(beluga_core_microphone_forwarding_readiness_result_is_valid(unready, falseReady) == 1)
    var invalidFacts = facts; invalidFacts.abi_version = 2
    let invalidReady = beluga_core_microphone_readiness_result_t(abi_version: 1, status: 0, ready: 0, continuing: 0)
    assert(beluga_core_microphone_forwarding_readiness_result_is_valid(invalidFacts, invalidReady) == 0)
    assert(micEvidenceBytes(facts) == factsBytes && micEvidenceBytes(ready) == readyBytes)

    let present = { (value: UInt64) in beluga_core_microphone_optional_u64_t(present: 1, reserved: 0, value: value) }
    let gap = beluga_core_microphone_optional_u64_t(present: 0, reserved: 0, value: 0)
    let before = beluga_core_microphone_watermark_state_t(abi_version: 1, reserved: 0,
        retained: micEvidenceMark([present(10), present(100), present(20), present(200)]))
    let event = beluga_core_microphone_watermark_event_t(abi_version: 1, reserved: 0,
        current: micEvidenceMark([present(11), present(101), gap, gap]))
    let next = beluga_core_microphone_watermark_state_t(abi_version: 1, reserved: 0,
        retained: micEvidenceMark([present(11), present(101), present(20), present(200)]))
    let marked = beluga_core_microphone_watermark_result_t(state: next, status: 1, continuous: 1, did_advance: 1, reserved: 0)
    let beforeBytes = micEvidenceBytes(before), eventBytes = micEvidenceBytes(event), markedBytes = micEvidenceBytes(marked)
    assert(beluga_core_microphone_forwarding_watermark_result_is_valid(before, event, marked) == 1)
    let unchanged = beluga_core_microphone_watermark_result_t(state: before, status: 1, continuous: 0, did_advance: 0, reserved: 0)
    assert(beluga_core_microphone_forwarding_watermark_result_is_valid(before, event, unchanged) == 0)
    var regressed = event; regressed.current.fields.0.value = 9
    assert(beluga_core_microphone_forwarding_watermark_result_is_valid(before, regressed, unchanged) == 1)
    var invalidEvent = event; invalidEvent.abi_version = 2
    let invalidMarked = beluga_core_microphone_watermark_result_t(state: before, status: 0, continuous: 0, did_advance: 0, reserved: 0)
    assert(beluga_core_microphone_forwarding_watermark_result_is_valid(before, invalidEvent, invalidMarked) == 0)
    assert(micEvidenceBytes(before) == beforeBytes && micEvidenceBytes(event) == eventBytes && micEvidenceBytes(marked) == markedBytes)

    let state = beluga_core_microphone_freshness_state_t(abi_version: 1, reserved: 0,
        advancement_count: 1, consecutive_stale_samples: 0, deadline: present(100))
    let sample = beluga_core_microphone_freshness_event_t(abi_version: 1, reserved: 0,
        maximum_stale_samples: 3, now: beluga_core_microphone_optional_u64_t(present: 0, reserved: 0, value: UInt64.max))
    let needsNow = beluga_core_microphone_freshness_result_t(abi_version: 1, status: 2, fresh: 0, reserved: 0)
    let stateBytes = micEvidenceBytes(state), sampleBytes = micEvidenceBytes(sample), resultBytes = micEvidenceBytes(needsNow)
    assert(beluga_core_microphone_forwarding_freshness_result_is_valid(state, sample, needsNow) == 1)
    let fresh = beluga_core_microphone_freshness_result_t(abi_version: 1, status: 1, fresh: 1, reserved: 0)
    assert(beluga_core_microphone_forwarding_freshness_result_is_valid(state, sample, fresh) == 0)
    var supplied = sample; supplied.now = present(99)
    assert(beluga_core_microphone_forwarding_freshness_result_is_valid(state, supplied, fresh) == 1)
    supplied.now.value = 100
    let notFresh = beluga_core_microphone_freshness_result_t(abi_version: 1, status: 1, fresh: 0, reserved: 0)
    assert(beluga_core_microphone_forwarding_freshness_result_is_valid(state, supplied, notFresh) == 1)
    var invalidState = state; invalidState.abi_version = 2
    let invalidFresh = beluga_core_microphone_freshness_result_t(abi_version: 1, status: 0, fresh: 0, reserved: 0)
    assert(beluga_core_microphone_forwarding_freshness_result_is_valid(invalidState, sample, invalidFresh) == 0)
    assert(micEvidenceBytes(state) == stateBytes && micEvidenceBytes(sample) == sampleBytes && micEvidenceBytes(needsNow) == resultBytes)
}
microphoneForwardingResultCorrelationSmokeV1()
print("BelugaCore Swift microphone result correlation PASS: exact result, coherent corruption, refusal and NeedsNow")

// Additive per-key retry ABI coverage; preserve all earlier import smokes.
// Imported PODs and two genuine exports only; no facsimile product declarations.
private typealias MicRetryConfig = beluga_core_microphone_forwarding_retry_config_t
private typealias MicRetryState = beluga_core_microphone_forwarding_retry_state_t
private typealias MicRetryEvent = beluga_core_microphone_forwarding_retry_event_t
private typealias MicRetryResult = beluga_core_microphone_forwarding_retry_result_t

private func micRetryStateEqual(_ a: MicRetryState, _ b: MicRetryState) -> Bool {
    a.abi_version == b.abi_version && a.present == b.present &&
        a.may_retry == b.may_retry && a.reserved == b.reserved && a.count == b.count
}
private func micRetryResultEqual(_ a: MicRetryResult, _ b: MicRetryResult) -> Bool {
    micRetryStateEqual(a.state, b.state) && a.status == b.status &&
        a.decision == b.decision && a.redrive_action == b.redrive_action &&
        a.reserved == b.reserved
}
private func micRetryOffset<T, U>(_ key: KeyPath<T, U>, _ expected: Int) {
    precondition(MemoryLayout<T>.offset(of: key) == expected)
}
private func micRetryState(_ count: Int64, _ permission: UInt32) -> MicRetryState {
    MicRetryState(abi_version: 1, present: count == 0 ? 0 : 1,
        may_retry: permission, reserved: 0, count: count)
}
private func micRetryResult(_ state: MicRetryState, _ decision: UInt32, _ redrive: UInt32) -> MicRetryResult {
    MicRetryResult(state: state, status: 1, decision: decision, redrive_action: redrive, reserved: 0)
}
private func micRetryAssertRefused(_ config: MicRetryConfig, _ before: MicRetryState, _ event: MicRetryEvent) {
    let expected = MicRetryResult(state: before, status: 0, decision: 0, redrive_action: 0, reserved: 0)
    let actual = beluga_core_microphone_forwarding_retry_step(config, before, event)
    precondition(micRetryResultEqual(actual, expected))
    precondition(beluga_core_microphone_forwarding_retry_result_is_valid(config, before, event, expected) == 0)
    var forged = expected; forged.status = 1
    precondition(beluga_core_microphone_forwarding_retry_result_is_valid(config, before, event, forged) == 0)
}

private func microphoneForwardingRetrySmokeV1() {
    precondition(MemoryLayout<MicRetryConfig>.size == 16 && MemoryLayout<MicRetryConfig>.alignment == 8)
    precondition(MemoryLayout<MicRetryState>.size == 24 && MemoryLayout<MicRetryState>.alignment == 8)
    precondition(MemoryLayout<MicRetryEvent>.size == 16 && MemoryLayout<MicRetryEvent>.alignment == 4)
    precondition(MemoryLayout<MicRetryResult>.size == 40 && MemoryLayout<MicRetryResult>.alignment == 8)
    micRetryOffset(\MicRetryConfig.abi_version, 0)
    micRetryOffset(\MicRetryConfig.reserved, 4)
    micRetryOffset(\MicRetryConfig.maximum_attempt_count, 8)
    micRetryOffset(\MicRetryState.abi_version, 0)
    micRetryOffset(\MicRetryState.present, 4)
    micRetryOffset(\MicRetryState.may_retry, 8)
    micRetryOffset(\MicRetryState.reserved, 12)
    micRetryOffset(\MicRetryState.count, 16)
    micRetryOffset(\MicRetryEvent.opcode, 0)
    micRetryOffset(\MicRetryEvent.failure_category, 4)
    micRetryOffset(\MicRetryEvent.bridge_faulted, 8)
    micRetryOffset(\MicRetryEvent.reserved, 12)
    micRetryOffset(\MicRetryResult.state, 0)
    micRetryOffset(\MicRetryResult.status, 24)
    micRetryOffset(\MicRetryResult.decision, 28)
    micRetryOffset(\MicRetryResult.redrive_action, 32)
    micRetryOffset(\MicRetryResult.reserved, 36)

    let config = MicRetryConfig(abi_version: 1, reserved: 0, maximum_attempt_count: 3)
    let maximum = MicRetryConfig(abi_version: 1, reserved: 0, maximum_attempt_count: Int64.max)
    let eligible = MicRetryEvent(opcode: 1, failure_category: 0, bridge_faulted: 0, reserved: 0)
    let record = MicRetryEvent(opcode: 2, failure_category: 0, bridge_faulted: 0, reserved: 0)
    let failure = MicRetryEvent(opcode: 3, failure_category: 3, bridge_faulted: 0, reserved: 0)
    let exhaust = MicRetryEvent(opcode: 4, failure_category: 0, bridge_faulted: 0, reserved: 0)
    var faultedEligible = eligible; faultedEligible.bridge_faulted = 1
    var admissionFailure = failure; admissionFailure.failure_category = 4
    var faultedFailure = failure; faultedFailure.bridge_faulted = 1
    // Handwritten scalar states; the candidate output never constructs an expectation.
    let cases: [(MicRetryConfig, MicRetryState, MicRetryEvent, MicRetryResult)] = [
        (config, micRetryState(0, 0), eligible, micRetryResult(micRetryState(0, 0), 1, 0)),
        (config, micRetryState(1, 1), eligible, micRetryResult(micRetryState(1, 1), 1, 0)),
        (config, micRetryState(3, 1), eligible, micRetryResult(micRetryState(3, 1), 0, 0)),
        (config, micRetryState(0, 0), faultedEligible, micRetryResult(micRetryState(0, 0), 0, 0)),
        (config, micRetryState(0, 0), record, micRetryResult(micRetryState(1, 0), 0, 0)),
        (config, micRetryState(1, 1), record, micRetryResult(micRetryState(2, 0), 0, 0)),
        (config, micRetryState(3, 1), record, micRetryResult(micRetryState(4, 0), 0, 0)),
        (config, micRetryState(1, 0), failure, micRetryResult(micRetryState(1, 1), 1, 2)),
        (config, micRetryState(1, 1), admissionFailure, micRetryResult(micRetryState(1, 1), 0, 1)),
        (config, micRetryState(0, 0), failure, micRetryResult(micRetryState(0, 0), 0, 1)),
        (config, micRetryState(3, 1), failure, micRetryResult(micRetryState(3, 1), 0, 1)),
        (config, micRetryState(1, 1), faultedFailure, micRetryResult(micRetryState(1, 1), 0, 1)),
        (config, micRetryState(0, 0), exhaust, micRetryResult(micRetryState(0, 0), 0, 0)),
        (config, micRetryState(1, 1), exhaust, micRetryResult(micRetryState(1, 0), 0, 1)),
        (maximum, micRetryState(Int64.max - 1, 1), record, micRetryResult(micRetryState(Int64.max, 0), 0, 0)),
        (maximum, micRetryState(Int64.max, 1), eligible, micRetryResult(micRetryState(Int64.max, 1), 0, 0))
    ]
    for (config, before, event, expected) in cases {
        let actual = beluga_core_microphone_forwarding_retry_step(config, before, event)
        precondition(micRetryResultEqual(actual, expected))
        precondition(beluga_core_microphone_forwarding_retry_result_is_valid(config, before, event, expected) == 1)
        // Nine individually changed fields, status=2, and coherent replacement history.
        for field in 0..<11 {
            var corrupt = expected
            switch field {
            case 0: corrupt.state.abi_version = 2
            case 1: corrupt.state.present ^= 1
            case 2: corrupt.state.may_retry ^= 1
            case 3: corrupt.state.reserved = 1
            case 4: corrupt.state.count = 7
            case 5: corrupt.status = 0
            case 6: corrupt.decision ^= 1
            case 7: corrupt.redrive_action = expected.redrive_action == 2 ? 1 : 2
            case 8: corrupt.reserved = 1
            case 9: corrupt.status = 2
            case 10: corrupt.state = expected.state.present == 0 ? micRetryState(7, 0) : micRetryState(0, 0)
            default: preconditionFailure("Unexpected retry corruption field")
            }
            precondition(!micRetryResultEqual(corrupt, expected))
            precondition(beluga_core_microphone_forwarding_retry_result_is_valid(config, before, event, corrupt) == 0)
            precondition(micRetryResultEqual(actual, expected))
        }
    }

    let before = micRetryState(1, 1)
    var badABI0 = config; badABI0.abi_version = 0
    var badABI2 = config; badABI2.abi_version = 2
    var badReserved = config; badReserved.reserved = 1
    let badConfigs = [badABI0, badABI2, badReserved,
        MicRetryConfig(abi_version: 1, reserved: 0, maximum_attempt_count: 0),
        MicRetryConfig(abi_version: 1, reserved: 0, maximum_attempt_count: -1),
        MicRetryConfig(abi_version: 1, reserved: 0, maximum_attempt_count: Int64.min)]
    for bad in badConfigs { micRetryAssertRefused(bad, before, eligible) }
    for field in 0..<10 {
        var bad = before
        switch field {
        case 0: bad.abi_version = 0
        case 1: bad.abi_version = 2
        case 2: bad.present = 2
        case 3: bad.may_retry = 2
        case 4: bad.reserved = 1
        case 5: bad.count = 0
        case 6: bad.count = -1
        case 7: bad.count = Int64.min
        case 8: bad = MicRetryState(abi_version: 1, present: 0, may_retry: 0, reserved: 0, count: 1)
        case 9: bad = MicRetryState(abi_version: 1, present: 0, may_retry: 1, reserved: 0, count: 0)
        default: preconditionFailure("Unexpected retry malformed state")
        }
        micRetryAssertRefused(config, bad, eligible)
    }
    let badEvents = [
        MicRetryEvent(opcode: 0, failure_category: 0, bridge_faulted: 0, reserved: 0),
        MicRetryEvent(opcode: 5, failure_category: 0, bridge_faulted: 0, reserved: 0),
        MicRetryEvent(opcode: UInt32.max, failure_category: 0, bridge_faulted: 0, reserved: 0),
        MicRetryEvent(opcode: 1, failure_category: 0, bridge_faulted: 0, reserved: 1),
        MicRetryEvent(opcode: 1, failure_category: 0, bridge_faulted: 2, reserved: 0),
        MicRetryEvent(opcode: 1, failure_category: 1, bridge_faulted: 0, reserved: 0),
        MicRetryEvent(opcode: 2, failure_category: 3, bridge_faulted: 0, reserved: 0),
        MicRetryEvent(opcode: 2, failure_category: 0, bridge_faulted: 1, reserved: 0),
        MicRetryEvent(opcode: 4, failure_category: 3, bridge_faulted: 0, reserved: 0),
        MicRetryEvent(opcode: 4, failure_category: 0, bridge_faulted: 1, reserved: 0),
        MicRetryEvent(opcode: 3, failure_category: 0, bridge_faulted: 0, reserved: 0),
        MicRetryEvent(opcode: 3, failure_category: 12, bridge_faulted: 0, reserved: 0),
        MicRetryEvent(opcode: 3, failure_category: UInt32.max, bridge_faulted: 1, reserved: 0),
        MicRetryEvent(opcode: 3, failure_category: 3, bridge_faulted: 2, reserved: 0)
    ]
    for bad in badEvents { micRetryAssertRefused(config, before, bad) }
    micRetryAssertRefused(maximum, micRetryState(Int64.max, 1), record)
}
microphoneForwardingRetrySmokeV1()
print("BelugaCore Swift microphone retry ABI PASS: literal layouts/results, all-field correlation, refusal and signed overflow")

typealias UpdateAdmissionRequest = beluga_core_update_admission_request_t
typealias UpdateAdmissionResult = beluga_core_update_admission_result_t
precondition(MemoryLayout<UpdateAdmissionRequest>.size == 8 && MemoryLayout<UpdateAdmissionRequest>.alignment == 4)
precondition(MemoryLayout<UpdateAdmissionResult>.size == 24 && MemoryLayout<UpdateAdmissionResult>.alignment == 4)
precondition([MemoryLayout<UpdateAdmissionRequest>.offset(of: \UpdateAdmissionRequest.abi_version),
              MemoryLayout<UpdateAdmissionRequest>.offset(of: \UpdateAdmissionRequest.flags)] == [0, 4])
precondition([MemoryLayout<UpdateAdmissionResult>.offset(of: \UpdateAdmissionResult.abi_version),
              MemoryLayout<UpdateAdmissionResult>.offset(of: \UpdateAdmissionResult.status),
              MemoryLayout<UpdateAdmissionResult>.offset(of: \UpdateAdmissionResult.permits_update),
              MemoryLayout<UpdateAdmissionResult>.offset(of: \UpdateAdmissionResult.is_in_progress),
              MemoryLayout<UpdateAdmissionResult>.offset(of: \UpdateAdmissionResult.can_check),
              MemoryLayout<UpdateAdmissionResult>.offset(of: \UpdateAdmissionResult.status_kind)] == [0, 4, 8, 12, 16, 20])
for flags: UInt32 in 0..<512 {
    let request = UpdateAdmissionRequest(abi_version: 1, flags: flags)
    let actual = beluga_core_update_admission_decide(request)
    let permits = flags & 1 != 0 && flags & 16 != 0 && flags & 14 == 0
    let release = flags & 32 != 0, busy = flags & 192 != 0, failed = flags & 256 != 0
    let progress = release && (busy || failed)
    let kind: UInt32 = !release ? 0 : failed ? 1 : busy ? 2 : permits ? 3 : 4
    precondition(actual.abi_version == 1 && actual.status == 0 && actual.permits_update == (permits ? 1 : 0)
        && actual.is_in_progress == (progress ? 1 : 0) && actual.can_check == (release && !progress && permits ? 1 : 0)
        && actual.status_kind == kind)
    precondition(beluga_core_update_admission_result_is_valid(request, actual) == 1)
    for field in 0..<6 {
        var corrupt = actual
        switch field {
        case 0: corrupt.abi_version = 2
        case 1: corrupt.status = 1
        case 2: corrupt.permits_update ^= 1
        case 3: corrupt.is_in_progress ^= 1
        case 4: corrupt.can_check ^= 1
        default: corrupt.status_kind = (corrupt.status_kind + 1) % 5
        }
        precondition(beluga_core_update_admission_result_is_valid(request, corrupt) == 0)
    }
}
for bit in 9..<32 {
    let request = UpdateAdmissionRequest(abi_version: 1, flags: 49 | (UInt32(1) << bit))
    let denied = beluga_core_update_admission_decide(request)
    precondition(denied.status == 1 && denied.permits_update == 0 && denied.can_check == 0
        && denied.is_in_progress == 1 && denied.status_kind == 1)
    precondition(beluga_core_update_admission_result_is_valid(request, denied) == 0)
}
let invalidUpdateABI = UpdateAdmissionRequest(abi_version: 2, flags: 49)
let invalidUpdateResult = beluga_core_update_admission_decide(invalidUpdateABI)
precondition(invalidUpdateResult.status == 1 && beluga_core_update_admission_result_is_valid(invalidUpdateABI, invalidUpdateResult) == 0)
print("BelugaCore Swift updater admission ABI PASS: exact layouts, 512 parity cases, all-field correlation and refusal")

// Copied SDK admission smoke; never starts Sparkle or queries native authority.
private func updateSparkleAdmissionSmokeV1() {
    typealias Request = beluga_core_update_sparkle_admission_request_t
    typealias Result = beluga_core_update_sparkle_admission_result_t
    precondition(MemoryLayout<Request>.size == 12 && MemoryLayout<Request>.stride == 12
        && MemoryLayout<Request>.alignment == 4)
    precondition(MemoryLayout<Result>.size == 12 && MemoryLayout<Result>.stride == 12
        && MemoryLayout<Result>.alignment == 4)
    precondition([MemoryLayout<Request>.offset(of: \Request.abi_version),
        MemoryLayout<Request>.offset(of: \Request.phase), MemoryLayout<Request>.offset(of: \Request.flags)] == [0, 4, 8])
    precondition([MemoryLayout<Result>.offset(of: \Result.abi_version),
        MemoryLayout<Result>.offset(of: \Result.status), MemoryLayout<Result>.offset(of: \Result.action)] == [0, 4, 8])
    let actions: [UInt32] = [1, 2, 1, 3, 1, 2, 1, 5, 3, 4, 3, 6]
    for phase: UInt32 in 1...2 {
        let count: UInt32 = phase == 1 ? 8 : 4
        for flags in 0..<count {
            let request = Request(abi_version: 1, phase: phase, flags: flags)
            let actual = beluga_core_update_sparkle_admission_decide(request)
            precondition(actual.abi_version == 1 && actual.status == 0
                && actual.action == actions[Int((phase == 1 ? 0 : 8) + flags)])
            precondition(beluga_core_update_sparkle_admission_result_is_valid(request, actual) == 1)
            for field in 0..<3 {
                var corrupt = actual
                if field == 0 { corrupt.abi_version = 2 }
                else if field == 1 { corrupt.status = 1 }
                else { corrupt.action = corrupt.action % 6 + 1 }
                precondition(beluga_core_update_sparkle_admission_result_is_valid(request, corrupt) == 0)
            }
            for bit in (phase == 1 ? 3 : 2)..<32 {
                let invalid = Request(abi_version: 1, phase: phase, flags: flags | UInt32(1) << bit)
                let refused = beluga_core_update_sparkle_admission_decide(invalid)
                precondition(refused.abi_version == 1 && refused.status == 1 && refused.action == 0)
                precondition(beluga_core_update_sparkle_admission_result_is_valid(invalid, refused) == 0)
            }
        }
    }
    for invalid in [Request(abi_version: 0, phase: 1, flags: 7),
        Request(abi_version: 2, phase: 2, flags: 3), Request(abi_version: 1, phase: 0, flags: 0),
        Request(abi_version: 1, phase: 3, flags: 0), Request(abi_version: 1, phase: .max, flags: 0)] {
        let refused = beluga_core_update_sparkle_admission_decide(invalid)
        precondition(refused.abi_version == 1 && refused.status == 1 && refused.action == 0)
        precondition(beluga_core_update_sparkle_admission_result_is_valid(invalid, refused) == 0)
    }
    print("BelugaCore Swift SDK admission ABI PASS: exact layouts, twelve phases, whole correlation and refusal")
}
updateSparkleAdmissionSmokeV1()

// Copied inner selector only; no native SDK, identity or retirement effects.
private func updateUnarmedCompletionSmokeV1() {
    typealias Request = beluga_core_update_unarmed_completion_request_t
    typealias Result = beluga_core_update_unarmed_completion_result_t
    precondition(MemoryLayout<Request>.size == 12 && MemoryLayout<Request>.stride == 12
        && MemoryLayout<Request>.alignment == 4)
    precondition(MemoryLayout<Result>.size == 12 && MemoryLayout<Result>.stride == 12
        && MemoryLayout<Result>.alignment == 4)
    precondition([MemoryLayout<Request>.offset(of: \Request.abi_version),
        MemoryLayout<Request>.offset(of: \Request.flags), MemoryLayout<Request>.offset(of: \Request.failure_kind)] == [0, 4, 8])
    precondition([MemoryLayout<Result>.offset(of: \Result.abi_version),
        MemoryLayout<Result>.offset(of: \Result.status), MemoryLayout<Result>.offset(of: \Result.reason)] == [0, 4, 8])
    let goldens: [Request] = [.init(abi_version: 1, flags: 0, failure_kind: 0),
        .init(abi_version: 1, flags: 3, failure_kind: 0), .init(abi_version: 1, flags: 960, failure_kind: 1),
        .init(abi_version: 1, flags: 960, failure_kind: 2), .init(abi_version: 1, flags: 544, failure_kind: 0),
        .init(abi_version: 1, flags: 491536, failure_kind: 0)]
    for (index, request) in goldens.enumerated() {
        let actual = beluga_core_update_unarmed_completion_decide(request)
        precondition(actual.abi_version == 1 && actual.status == 0 && actual.reason == UInt32(index))
        precondition(beluga_core_update_unarmed_completion_result_is_valid(request, actual) == 1)
        for field in 0..<3 {
            var corrupt = actual
            if field == 0 { corrupt.abi_version = 2 }
            else if field == 1 { corrupt.status = 1 }
            else { corrupt.reason = (corrupt.reason + 1) % 6 }
            precondition(beluga_core_update_unarmed_completion_result_is_valid(request, corrupt) == 0)
        }
        for (otherIndex, other) in goldens.enumerated() {
            let copied = beluga_core_update_unarmed_completion_decide(other)
            precondition(beluga_core_update_unarmed_completion_result_is_valid(request, copied) == (index == otherIndex ? 1 : 0))
        }
        for bit in 19..<32 {
            var invalid = request; invalid.flags |= UInt32(1) << bit
            let refusal = beluga_core_update_unarmed_completion_decide(invalid)
            precondition(refusal.abi_version == 1 && refusal.status == 1 && refusal.reason == 0)
            precondition(beluga_core_update_unarmed_completion_result_is_valid(invalid, refusal) == 0)
        }
    }
    for invalid in [Request(abi_version: 0, flags: 3, failure_kind: 0),
        Request(abi_version: 2, flags: 3, failure_kind: 0), Request(abi_version: 1, flags: 960, failure_kind: 3),
        Request(abi_version: 1, flags: 960, failure_kind: .max)] {
        let refusal = beluga_core_update_unarmed_completion_decide(invalid)
        precondition(refusal.abi_version == 1 && refusal.status == 1 && refusal.reason == 0)
        precondition(beluga_core_update_unarmed_completion_result_is_valid(invalid, refusal) == 0)
    }
    print("BelugaCore Swift unarmed completion ABI PASS: copied layouts, six reasons, whole correlation and refusal")
}
updateUnarmedCompletionSmokeV1()

// Genuine imported records/exports; no native SDK object or callback enters Rust.
private func updateAbortSmokeV1() {
    typealias Request = beluga_core_update_abort_request_t
    typealias Result = beluga_core_update_abort_result_t
    precondition(MemoryLayout<Request>.size == 8 && MemoryLayout<Request>.stride == 8
        && MemoryLayout<Request>.alignment == 4)
    precondition(MemoryLayout<Result>.size == 12 && MemoryLayout<Result>.stride == 12
        && MemoryLayout<Result>.alignment == 4)
    precondition([MemoryLayout<Request>.offset(of: \Request.abi_version),
        MemoryLayout<Request>.offset(of: \Request.flags)] == [0, 4])
    precondition([MemoryLayout<Result>.offset(of: \Result.abi_version),
        MemoryLayout<Result>.offset(of: \Result.status), MemoryLayout<Result>.offset(of: \Result.action)] == [0, 4, 8])
    let literalAction: (UInt32) -> UInt32 = { flags in
        if flags & 1 != 0 && flags & 2 != 0 && flags & 4 != 0
            && flags & 8 == 0 && flags & 16 != 0 { return 1 }
        return flags & 32 != 0 ? 2 : 3
    }
    for flags in UInt32(0)..<UInt32(64) {
        let request = Request(abi_version: 1, flags: flags)
        let expected = literalAction(flags)
        let actual = beluga_core_update_abort_decide(request)
        precondition(actual.abi_version == 1 && actual.status == 0 && actual.action == expected)
        precondition(beluga_core_update_abort_result_is_valid(request, actual) == 1)
        for value in [UInt32(0), 1, 2, 3, 4, .max] {
            for field in 0..<3 {
                var changed = actual
                if field == 0 { changed.abi_version = value }
                else if field == 1 { changed.status = value }
                else { changed.action = value }
                let same: UInt32 = changed.abi_version == 1 && changed.status == 0 && changed.action == expected ? 1 : 0
                precondition(beluga_core_update_abort_result_is_valid(request, changed) == same)
            }
        }
        for other in UInt32(0)..<UInt32(64) {
            let copied = beluga_core_update_abort_decide(Request(abi_version: 1, flags: other))
            precondition(copied.abi_version == 1 && copied.status == 0 && copied.action == literalAction(other))
            precondition(beluga_core_update_abort_result_is_valid(request, copied) == (copied.action == expected ? 1 : 0))
        }
        for bit in 6..<32 {
            let invalid = Request(abi_version: 1, flags: flags | (UInt32(1) << bit))
            let denied = beluga_core_update_abort_decide(invalid)
            precondition(denied.abi_version == 1 && denied.status == 1 && denied.action == 0)
            precondition(beluga_core_update_abort_result_is_valid(invalid, denied) == 0)
            for action in UInt32(1)...UInt32(3) {
                precondition(beluga_core_update_abort_result_is_valid(invalid,
                    Result(abi_version: 1, status: 0, action: action)) == 0)
            }
        }
        for abi in [UInt32(0), 2, .max] {
            let invalid = Request(abi_version: abi, flags: flags)
            let denied = beluga_core_update_abort_decide(invalid)
            precondition(denied.abi_version == 1 && denied.status == 1 && denied.action == 0)
            precondition(beluga_core_update_abort_result_is_valid(invalid, denied) == 0)
            for action in UInt32(1)...UInt32(3) {
                precondition(beluga_core_update_abort_result_is_valid(invalid,
                    Result(abi_version: 1, status: 0, action: action)) == 0)
            }
        }
    }
    print("BelugaCore Swift abort classifier ABI PASS: copied layouts, 64 carriers, whole correlation and refusal")
}
updateAbortSmokeV1()

private func handoffSourceSmokeV1() {
    typealias Prepare = beluga_core_handoff_source_prepare_facts_t
    typealias Match = beluga_core_handoff_source_match_facts_t
    typealias Result = beluga_core_handoff_source_result_t
    precondition(MemoryLayout<Prepare>.size == 56 && MemoryLayout<Prepare>.stride == 56
        && MemoryLayout<Prepare>.alignment == 8)
    precondition([MemoryLayout<Prepare>.offset(of: \Prepare.abi_version),
        MemoryLayout<Prepare>.offset(of: \Prepare.reserved), MemoryLayout<Prepare>.offset(of: \Prepare.flags),
        MemoryLayout<Prepare>.offset(of: \Prepare.position), MemoryLayout<Prepare>.offset(of: \Prepare.duration),
        MemoryLayout<Prepare>.offset(of: \Prepare.rate), MemoryLayout<Prepare>.offset(of: \Prepare.observed_at_page_ms),
        MemoryLayout<Prepare>.offset(of: \Prepare.phone_position)] == [0, 4, 8, 16, 24, 32, 40, 48])
    precondition(MemoryLayout<Match>.size == 88 && MemoryLayout<Match>.stride == 88
        && MemoryLayout<Match>.alignment == 8)
    precondition([MemoryLayout<Match>.offset(of: \Match.abi_version),
        MemoryLayout<Match>.offset(of: \Match.reserved), MemoryLayout<Match>.offset(of: \Match.flags),
        MemoryLayout<Match>.offset(of: \Match.anchor_position), MemoryLayout<Match>.offset(of: \Match.anchor_duration),
        MemoryLayout<Match>.offset(of: \Match.anchor_rate), MemoryLayout<Match>.offset(of: \Match.anchor_observed_at_page_ms),
        MemoryLayout<Match>.offset(of: \Match.phone_position), MemoryLayout<Match>.offset(of: \Match.current_position),
        MemoryLayout<Match>.offset(of: \Match.current_duration), MemoryLayout<Match>.offset(of: \Match.current_rate),
        MemoryLayout<Match>.offset(of: \Match.current_observed_at_page_ms)] == [0, 4, 8, 16, 24, 32, 40, 48, 56, 64, 72, 80])
    precondition(MemoryLayout<Result>.size == 16 && MemoryLayout<Result>.alignment == 4)
    precondition([MemoryLayout<Result>.offset(of: \Result.abi_version),
        MemoryLayout<Result>.offset(of: \Result.status), MemoryLayout<Result>.offset(of: \Result.allowed),
        MemoryLayout<Result>.offset(of: \Result.reserved)] == [0, 4, 8, 12])
    var p = Prepare(abi_version: 1, reserved: 0, flags: 127, position: 15.0.bitPattern,
        duration: 120.0.bitPattern, rate: 1.0.bitPattern, observed_at_page_ms: 50_000.0.bitPattern,
        phone_position: 15.0.bitPattern)
    var m = Match(abi_version: 1, reserved: 0, flags: 127, anchor_position: p.position,
        anchor_duration: p.duration, anchor_rate: p.rate, anchor_observed_at_page_ms: p.observed_at_page_ms,
        phone_position: p.phone_position, current_position: p.position, current_duration: p.duration,
        current_rate: p.rate, current_observed_at_page_ms: p.observed_at_page_ms)
    for flags in UInt64(0)..<128 {
        p.flags = flags; m.flags = flags
        let pr = beluga_core_handoff_source_prepare(p), mr = beluga_core_handoff_source_matches(m)
        precondition(pr.abi_version == 1 && pr.status == 1 && pr.reserved == 0 && pr.allowed == (flags == 127 ? 1 : 0))
        precondition(mr.abi_version == 1 && mr.status == 1 && mr.reserved == 0 && mr.allowed == (flags == 127 ? 1 : 0))
        precondition(beluga_core_handoff_source_prepare_result_is_valid(p, pr) == 1)
        precondition(beluga_core_handoff_source_matches_result_is_valid(m, mr) == 1)
        var forged = pr; forged.allowed ^= 1
        precondition(beluga_core_handoff_source_prepare_result_is_valid(p, forged) == 0)
        forged = mr; forged.allowed ^= 1
        precondition(beluga_core_handoff_source_matches_result_is_valid(m, forged) == 0)
    }
    p.flags = 128; m.flags = 128
    let pr = beluga_core_handoff_source_prepare(p), mr = beluga_core_handoff_source_matches(m)
    precondition(pr.status == 0 && pr.allowed == 0 && mr.status == 0 && mr.allowed == 0)
    precondition(beluga_core_handoff_source_prepare_result_is_valid(p, pr) == 0)
    precondition(beluga_core_handoff_source_matches_result_is_valid(m, mr) == 0)
    print("BelugaCore Swift handoff source ABI PASS: exact layouts, timeline/phone boundaries, whole correlation and refusal")
}
handoffSourceSmokeV1()

private func microphoneInputLeaseSmokeV1() {
    typealias Facts = beluga_core_microphone_input_lease_facts_t
    typealias Result = beluga_core_microphone_input_lease_result_t
    precondition(MemoryLayout<Facts>.size == 32 && MemoryLayout<Facts>.stride == 32
        && MemoryLayout<Facts>.alignment == 8)
    precondition(MemoryLayout<Result>.size == 20 && MemoryLayout<Result>.stride == 20
        && MemoryLayout<Result>.alignment == 4)
    precondition([MemoryLayout<Facts>.offset(of: \Facts.abi_version),
        MemoryLayout<Facts>.offset(of: \Facts.opcode), MemoryLayout<Facts>.offset(of: \Facts.disposition),
        MemoryLayout<Facts>.offset(of: \Facts.reserved), MemoryLayout<Facts>.offset(of: \Facts.attempt_count),
        MemoryLayout<Facts>.offset(of: \Facts.maximum_attempt_count)] == [0, 4, 8, 12, 16, 24])
    precondition([MemoryLayout<Result>.offset(of: \Result.abi_version),
        MemoryLayout<Result>.offset(of: \Result.status), MemoryLayout<Result>.offset(of: \Result.opcode),
        MemoryLayout<Result>.offset(of: \Result.action), MemoryLayout<Result>.offset(of: \Result.reserved)] == [0, 4, 8, 12, 16])
    let rows: [(UInt32, UInt32, Int64, Int64, UInt32)] = [
        (1, 0, 0, 3, 1), (1, 0, 3, 3, 2), (1, 0, .max - 1, .max, 1), (1, 0, .max, .max, 2),
        (2, 1, 0, 0, 3), (2, 2, 0, 0, 4), (2, 3, 0, 0, 5),
        (3, 2, 1, 3, 6), (3, 2, 3, 3, 7), (3, 3, 1, 3, 7),
        (4, 0, 0, 0, 8), (4, 1, 0, 0, 9), (4, 2, 0, 0, 10), (4, 3, 0, 0, 9)]
    for (operation, disposition, count, maximum, expected) in rows {
        let input = Facts(abi_version: 1, opcode: operation, disposition: disposition,
            reserved: 0, attempt_count: count, maximum_attempt_count: maximum)
        let actual = beluga_core_microphone_input_lease_decide(input)
        precondition(actual.abi_version == 1 && actual.status == 1 && actual.opcode == operation
            && actual.action == expected && actual.reserved == 0)
        precondition(beluga_core_microphone_input_lease_result_is_valid(input, actual) == 1)
        for value in [UInt32(0), 1, 2, 3, 4, 10, 11, .max] {
            for field in 0..<5 {
                var changed = actual
                if field == 0 { changed.abi_version = value }
                else if field == 1 { changed.status = value }
                else if field == 2 { changed.opcode = value }
                else if field == 3 { changed.action = value }
                else { changed.reserved = value }
                let same: UInt32 = changed.abi_version == 1 && changed.status == 1
                    && changed.opcode == operation && changed.action == expected && changed.reserved == 0 ? 1 : 0
                precondition(beluga_core_microphone_input_lease_result_is_valid(input, changed) == same)
            }
        }
        for action in UInt32(1)...UInt32(10) {
            var coherent = actual; coherent.action = action
            precondition(beluga_core_microphone_input_lease_result_is_valid(input, coherent) == (action == expected ? 1 : 0))
        }
    }
    let invalid: [(UInt32, UInt32, UInt32, UInt32, Int64, Int64)] = [
        (0, 1, 0, 0, 0, 3), (2, 1, 0, 0, 0, 3), (1, 1, 0, 1, 0, 3),
        (1, 0, 0, 0, 0, 3), (1, 5, 0, 0, 0, 3), (1, .max, 0, 0, 0, 3),
        (1, 1, 1, 0, 0, 3), (1, 1, 0, 0, -1, 3), (1, 1, 0, 0, 0, 0),
        (1, 2, 0, 0, 0, 0), (1, 2, 4, 0, 0, 0), (1, 2, 1, 0, 1, 0),
        (1, 2, 1, 0, 0, 1), (1, 3, 4, 0, 1, 3), (1, 3, 2, 0, 0, 3),
        (1, 3, 2, 0, 1, 0), (1, 4, 4, 0, 0, 0), (1, 4, 0, 0, 1, 0),
        (1, 4, 0, 0, 0, 1)]
    for (abi, operation, disposition, reserved, count, maximum) in invalid {
        let input = Facts(abi_version: abi, opcode: operation, disposition: disposition,
            reserved: reserved, attempt_count: count, maximum_attempt_count: maximum)
        let denied = beluga_core_microphone_input_lease_decide(input)
        precondition(denied.abi_version == 1 && denied.status == 0 && denied.opcode == 0
            && denied.action == 0 && denied.reserved == 0)
        precondition(beluga_core_microphone_input_lease_result_is_valid(input, denied) == 0)
        precondition(beluga_core_microphone_input_lease_result_is_valid(input,
            Result(abi_version: 1, status: 1, opcode: 1, action: 1, reserved: 0)) == 0)
    }
    print("BelugaCore Swift input lease ABI PASS: four copied operations, literal layouts, full-width counts and whole refusal")
}
microphoneInputLeaseSmokeV1()

private func microphoneOutputFormatSmokeV1() {
    typealias Facts = beluga_core_microphone_output_format_facts_t
    typealias Observation = beluga_core_microphone_output_format_observation_t
    typealias Result = beluga_core_microphone_output_format_result_t
    precondition(MemoryLayout<Facts>.size == 80 && MemoryLayout<Facts>.stride == 80
        && MemoryLayout<Facts>.alignment == 8)
    precondition([MemoryLayout<Facts>.offset(of: \Facts.abi_version),
        MemoryLayout<Facts>.offset(of: \Facts.wire_reserved),
        MemoryLayout<Facts>.offset(of: \Facts.stream_description_status),
        MemoryLayout<Facts>.offset(of: \Facts.device_sample_rate_status),
        MemoryLayout<Facts>.offset(of: \Facts.device_channel_count_status),
        MemoryLayout<Facts>.offset(of: \Facts.converter_error_read_status),
        MemoryLayout<Facts>.offset(of: \Facts.stream_sample_rate_bits),
        MemoryLayout<Facts>.offset(of: \Facts.stream_format_id),
        MemoryLayout<Facts>.offset(of: \Facts.stream_format_flags),
        MemoryLayout<Facts>.offset(of: \Facts.stream_bytes_per_packet),
        MemoryLayout<Facts>.offset(of: \Facts.stream_frames_per_packet),
        MemoryLayout<Facts>.offset(of: \Facts.stream_bytes_per_frame),
        MemoryLayout<Facts>.offset(of: \Facts.stream_channels_per_frame),
        MemoryLayout<Facts>.offset(of: \Facts.stream_bits_per_channel),
        MemoryLayout<Facts>.offset(of: \Facts.stream_reserved),
        MemoryLayout<Facts>.offset(of: \Facts.device_sample_rate_bits),
        MemoryLayout<Facts>.offset(of: \Facts.device_channel_count),
        MemoryLayout<Facts>.offset(of: \Facts.converter_error)] == [0, 4, 8, 12, 16, 20, 24, 32, 36, 40, 44, 48, 52, 56, 60, 64, 72, 76])
    precondition(MemoryLayout<Observation>.size == 56 && MemoryLayout<Observation>.stride == 56
        && MemoryLayout<Observation>.alignment == 8)
    precondition([MemoryLayout<Observation>.offset(of: \Observation.sample_rate_bits),
        MemoryLayout<Observation>.offset(of: \Observation.format_id),
        MemoryLayout<Observation>.offset(of: \Observation.format_flags),
        MemoryLayout<Observation>.offset(of: \Observation.bytes_per_packet),
        MemoryLayout<Observation>.offset(of: \Observation.frames_per_packet),
        MemoryLayout<Observation>.offset(of: \Observation.bytes_per_frame),
        MemoryLayout<Observation>.offset(of: \Observation.channels_per_frame),
        MemoryLayout<Observation>.offset(of: \Observation.bits_per_channel),
        MemoryLayout<Observation>.offset(of: \Observation.stream_reserved),
        MemoryLayout<Observation>.offset(of: \Observation.device_sample_rate_bits),
        MemoryLayout<Observation>.offset(of: \Observation.device_channel_count),
        MemoryLayout<Observation>.offset(of: \Observation.converter_error)] == [0, 8, 12, 16, 20, 24, 28, 32, 36, 40, 48, 52])
    precondition(MemoryLayout<Result>.size == 96 && MemoryLayout<Result>.stride == 96
        && MemoryLayout<Result>.alignment == 8)
    precondition([MemoryLayout<Result>.offset(of: \Result.abi_version),
        MemoryLayout<Result>.offset(of: \Result.status),
        MemoryLayout<Result>.offset(of: \Result.accepted),
        MemoryLayout<Result>.offset(of: \Result.reason),
        MemoryLayout<Result>.offset(of: \Result.actual_core_audio_status),
        MemoryLayout<Result>.offset(of: \Result.actual_u32),
        MemoryLayout<Result>.offset(of: \Result.actual_rate_bits),
        MemoryLayout<Result>.offset(of: \Result.observation),
        MemoryLayout<Result>.offset(of: \Result.wire_reserved)] == [0, 4, 8, 12, 16, 20, 24, 32, 88])
    let valid = Facts(abi_version: 1, wire_reserved: 0,
        stream_description_status: 0, device_sample_rate_status: 0,
        device_channel_count_status: 0, converter_error_read_status: 0,
        stream_sample_rate_bits: 0x40e7_7000_0000_0000, stream_format_id: 0x6c70_636d,
        stream_format_flags: 12, stream_bytes_per_packet: 2, stream_frames_per_packet: 1,
        stream_bytes_per_frame: 2, stream_channels_per_frame: 1, stream_bits_per_channel: 16,
        stream_reserved: 0, device_sample_rate_bits: 0x40e7_7000_0000_0000,
        device_channel_count: 1, converter_error: 0)
    let expectedSuccess = Result(abi_version: 1, status: 1, accepted: 1, reason: 0,
        actual_core_audio_status: 0, actual_u32: 0, actual_rate_bits: 0,
        observation: Observation(sample_rate_bits: 0x40e7_7000_0000_0000, format_id: 0x6c70_636d,
            format_flags: 12, bytes_per_packet: 2, frames_per_packet: 1, bytes_per_frame: 2,
            channels_per_frame: 1, bits_per_channel: 16, stream_reserved: 0,
            device_sample_rate_bits: 0x40e7_7000_0000_0000, device_channel_count: 1,
            converter_error: 0), wire_reserved: 0)
    func expect(_ actual: Result, _ expected: Result) {
        precondition(actual.abi_version == expected.abi_version)
        precondition(actual.status == expected.status)
        precondition(actual.accepted == expected.accepted)
        precondition(actual.reason == expected.reason)
        precondition(actual.actual_core_audio_status == expected.actual_core_audio_status)
        precondition(actual.actual_u32 == expected.actual_u32)
        precondition(actual.actual_rate_bits == expected.actual_rate_bits)
        precondition(actual.observation.sample_rate_bits == expected.observation.sample_rate_bits)
        precondition(actual.observation.format_id == expected.observation.format_id)
        precondition(actual.observation.format_flags == expected.observation.format_flags)
        precondition(actual.observation.bytes_per_packet == expected.observation.bytes_per_packet)
        precondition(actual.observation.frames_per_packet == expected.observation.frames_per_packet)
        precondition(actual.observation.bytes_per_frame == expected.observation.bytes_per_frame)
        precondition(actual.observation.channels_per_frame == expected.observation.channels_per_frame)
        precondition(actual.observation.bits_per_channel == expected.observation.bits_per_channel)
        precondition(actual.observation.stream_reserved == expected.observation.stream_reserved)
        precondition(actual.observation.device_sample_rate_bits == expected.observation.device_sample_rate_bits)
        precondition(actual.observation.device_channel_count == expected.observation.device_channel_count)
        precondition(actual.observation.converter_error == expected.observation.converter_error)
        precondition(actual.wire_reserved == expected.wire_reserved)
    }
    func failGuard(_ facts: inout Facts, _ reason: UInt32) {
        switch reason {
        case 1: facts.stream_description_status = Int32.min + 1
        case 2: facts.device_sample_rate_status = Int32.min + 2
        case 3: facts.device_channel_count_status = Int32.min + 3
        case 4: facts.converter_error_read_status = Int32.min + 4
        case 5: facts.stream_sample_rate_bits = 0x7ff8_0000_0000_0042
        case 6: facts.stream_format_id = UInt32.max
        case 7: facts.stream_format_flags = UInt32.max
        case 8: facts.stream_bytes_per_packet = UInt32.max
        case 9: facts.stream_frames_per_packet = UInt32.max
        case 10: facts.stream_bytes_per_frame = UInt32.max
        case 11: facts.stream_channels_per_frame = UInt32.max
        case 12: facts.stream_bits_per_channel = UInt32.max
        case 13: facts.stream_reserved = UInt32.max
        case 14: facts.device_sample_rate_bits = 0xfff8_0000_0000_005a
        case 15: facts.device_channel_count = UInt32.max
        case 16: facts.converter_error = UInt32.max
        default: preconditionFailure("unknown output format reason")
        }
    }
    func corruptionRefusal(_ facts: Facts, _ actual: Result) {
        precondition(beluga_core_microphone_output_format_result_is_valid(facts, actual) == 1)
        for field in 0..<20 {
            var changed = actual
            switch field {
            case 0: changed.abi_version ^= 1
            case 1: changed.status ^= 1
            case 2: changed.accepted ^= 1
            case 3: changed.reason ^= 1
            case 4: changed.actual_core_audio_status ^= 1
            case 5: changed.actual_u32 ^= 1
            case 6: changed.actual_rate_bits ^= 1
            case 7: changed.observation.sample_rate_bits ^= 1
            case 8: changed.observation.format_id ^= 1
            case 9: changed.observation.format_flags ^= 1
            case 10: changed.observation.bytes_per_packet ^= 1
            case 11: changed.observation.frames_per_packet ^= 1
            case 12: changed.observation.bytes_per_frame ^= 1
            case 13: changed.observation.channels_per_frame ^= 1
            case 14: changed.observation.bits_per_channel ^= 1
            case 15: changed.observation.stream_reserved ^= 1
            case 16: changed.observation.device_sample_rate_bits ^= 1
            case 17: changed.observation.device_channel_count ^= 1
            case 18: changed.observation.converter_error ^= 1
            case 19: changed.wire_reserved ^= 1
            default: preconditionFailure("unknown output format result field")
            }
            precondition(beluga_core_microphone_output_format_result_is_valid(facts, changed) == 0)
        }
    }
    let success = beluga_core_microphone_output_format_decide(valid)
    expect(success, expectedSuccess)
    corruptionRefusal(valid, success)
    for reason in UInt32(1)...UInt32(16) {
        var facts = valid
        failGuard(&facts, reason)
        var expected = Result()
        expected.abi_version = 1; expected.status = 1; expected.reason = reason
        if reason <= 4 { expected.actual_core_audio_status = Int32.min + Int32(reason) }
        else if reason == 5 { expected.actual_rate_bits = 0x7ff8_0000_0000_0042 }
        else if reason == 14 { expected.actual_rate_bits = 0xfff8_0000_0000_005a }
        else { expected.actual_u32 = .max }
        let actual = beluga_core_microphone_output_format_decide(facts)
        expect(actual, expected)
        corruptionRefusal(facts, actual)
        precondition(beluga_core_microphone_output_format_result_is_valid(facts, success) == 0)
        precondition(beluga_core_microphone_output_format_result_is_valid(valid, actual) == 0)
        if reason < 16 {
            for later in (reason + 1)...UInt32(16) {
                failGuard(&facts, later)
                let ordered = beluga_core_microphone_output_format_decide(facts)
                expect(ordered, expected)
                precondition(beluga_core_microphone_output_format_result_is_valid(facts, ordered) == 1)
            }
        }
    }
    // Raw words are never normalized, including signed/signaling NaN payloads.
    let rejectedRates: [UInt64] = [
        0, 0x8000_0000_0000_0000, 0x7ff0_0000_0000_0000, 0xfff0_0000_0000_0000,
        0x7ff8_0000_0000_0042, 0xfff8_0000_0000_005a, 0x7ff0_0000_0000_0001,
        1, 0x8000_0000_0000_0001, 0x40e7_6fff_ffff_ffff, 0x40e7_7000_0000_0001]
    for rate in rejectedRates {
        for device in [false, true] {
            var facts = valid
            if device { facts.device_sample_rate_bits = rate }
            else { facts.stream_sample_rate_bits = rate }
            var expected = Result()
            expected.abi_version = 1; expected.status = 1
            expected.reason = device ? 14 : 5; expected.actual_rate_bits = rate
            let actual = beluga_core_microphone_output_format_decide(facts)
            expect(actual, expected)
            corruptionRefusal(facts, actual)
        }
    }
    var expectedInvalid = Result(); expectedInvalid.abi_version = 1
    for abi in [UInt32(0), 2, .max] {
        var invalid = valid; invalid.abi_version = abi
        let denied = beluga_core_microphone_output_format_decide(invalid)
        expect(denied, expectedInvalid)
        precondition(beluga_core_microphone_output_format_result_is_valid(invalid, denied) == 0)
        precondition(beluga_core_microphone_output_format_result_is_valid(invalid, success) == 0)
    }
    for reserved in [UInt32(1), .max] {
        var invalid = valid; invalid.wire_reserved = reserved
        let denied = beluga_core_microphone_output_format_decide(invalid)
        expect(denied, expectedInvalid)
        precondition(beluga_core_microphone_output_format_result_is_valid(invalid, denied) == 0)
        precondition(beluga_core_microphone_output_format_result_is_valid(invalid, success) == 0)
    }
    print("BelugaCore Swift output format ABI PASS: literal layouts, sixteen ordered guards, exact observations and whole refusal")
}
microphoneOutputFormatSmokeV1()
