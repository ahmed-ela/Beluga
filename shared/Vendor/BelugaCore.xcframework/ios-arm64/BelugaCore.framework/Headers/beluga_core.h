#ifndef BELUGA_CORE_H
#define BELUGA_CORE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    BELUGA_CORE_ABI_VERSION = 1,
    BELUGA_CORE_HAS_STARTED = 1u << 0,
    BELUGA_CORE_FINISHED = 1u << 1,
    BELUGA_CORE_CHANGING_PHONE = 1u << 2,
    BELUGA_CORE_REQUEST_IN_FLIGHT = 1u << 3,
    BELUGA_CORE_PHASE_READY = 1u << 4,
    BELUGA_CORE_TARGET_PRESENT = 1u << 5,
    BELUGA_CORE_COMMAND_INSTALLED = 1u << 6,
    BELUGA_CORE_KNOWN_FLAGS = 127
};

enum {
    BELUGA_CORE_READY = 0,
    BELUGA_CORE_STOPPED = 1,
    BELUGA_CORE_NOT_STARTED = 2,
    BELUGA_CORE_CHANGING_PHONE_REASON = 3,
    BELUGA_CORE_REQUEST_IN_FLIGHT_REASON = 4,
    BELUGA_CORE_WAITING_SESSION = 5,
    BELUGA_CORE_TARGET_ABSENT = 6,
    BELUGA_CORE_COMMAND_UNAVAILABLE = 7,
    BELUGA_CORE_UNKNOWN_ABI = 8,
    BELUGA_CORE_UNKNOWN_FLAGS = 9
};

/* Returned booleans are exactly 0 or 1. Invalid input is always disabled.
 * Visibility depends only on the known HAS_STARTED bit, even on rejection.
 * This projection does not replace exact-target native dispatch fencing. */
typedef struct {
    uint32_t abi_version;
    uint32_t visible;
    uint32_t enabled;
    uint32_t reason;
} beluga_core_handoff_menu_policy_t;

uint32_t beluga_core_abi_version(void);
beluga_core_handoff_menu_policy_t beluga_core_handoff_menu_policy(
    uint32_t abi_version, uint32_t flags);

/* Opaque nonzero exchange tokens retain the native String identity contract.
 * Rust never receives, owns, or dereferences a native String or pointer. */
typedef struct {
    uint32_t abi_version;
    uint32_t run_state; /* idle=0, inviting=1, paired=2, stopped=3 */
    uint64_t active_token;
    uint64_t media_token;
} beluga_core_host_lifecycle_state_t;

typedef struct {
    uint32_t opcode; /* start=0, paired=1, ready=2, media=3, left=4, ended=5, stop=6 */
    uint32_t argument; /* start only: has paired viewer, exactly 0 or 1 */
    uint64_t exchange_token;
    uint64_t original_utf8_length; /* ready only: exact native input byte count */
} beluga_core_host_lifecycle_event_t;

typedef struct {
    beluga_core_host_lifecycle_state_t state;
    uint32_t status; /* applied=0, rejected=1, no change=2, invalid input=3 */
} beluga_core_host_lifecycle_result_t;

beluga_core_host_lifecycle_state_t beluga_core_host_lifecycle_initial(void);
beluga_core_host_lifecycle_result_t beluga_core_host_lifecycle_step(
    uint32_t abi_version, beluga_core_host_lifecycle_state_t state,
    beluga_core_host_lifecycle_event_t event);

/* Exact native receipt/envelope identities are bridged to nonzero tokens.
 * Effects revoke or return results; no effect authorizes a native pause. */
typedef struct {
    uint32_t abi_version;
    uint32_t host_phase; /* empty=0, admitted=1, replied=2 */
    uint64_t host_receipt;
    uint64_t host_envelope;
    uint32_t host_result; /* none=0, mac paused=1, not applied=2, unknown=3 */
    uint32_t reserved;
    uint64_t viewer_envelope;
    uint64_t viewer_offer;
} beluga_core_handoff_transactions_state_t;

typedef struct {
    uint32_t opcode; /* admit=0, finish=1, begin viewer=2, complete=3, expire=4, clear=5 */
    uint32_t argument; /* begin viewer only: native envelope validity, 0 or 1 */
    uint64_t receipt_token;
    uint64_t envelope_token;
    uint64_t offer_token;
    uint32_t result;
    uint32_t reserved;
} beluga_core_handoff_transactions_event_t;

typedef struct {
    beluga_core_handoff_transactions_state_t state;
    uint32_t status; /* applied=0, rejected=1, no change=2, invalid=3 */
    uint32_t effects; /* revoke host=1, return host reply=2, emit viewer completion=4 */
    uint64_t revoked_receipt;
    uint64_t completed_offer;
    uint32_t completed_result;
    uint32_t reserved;
} beluga_core_handoff_transactions_result_t;

beluga_core_handoff_transactions_state_t beluga_core_handoff_transactions_initial(void);
beluga_core_handoff_transactions_result_t beluga_core_handoff_transactions_step(
    uint32_t abi_version, beluga_core_handoff_transactions_state_t state,
    beluga_core_handoff_transactions_event_t event);

/* All floating values below are copied IEEE-754 Double bits, never integer clocks.
 * Native facts preserve original String/UUID equality. Primary matching is separate
 * from commit header matching. Receipt token is 0 unless the ENTIRE supplied native
 * receipt equals the current receipt; prepareCommit uses that supplied envelope.
 * No accepted offer, scalar output or effect proves playback or authorizes Pause. */
enum {
    BELUGA_CORE_OFFERS_RETIRE_SENT = 1, BELUGA_CORE_OFFERS_RETIRE_RECEIVED = 2,
    BELUGA_CORE_OFFERS_MINT_SENT = 4, BELUGA_CORE_OFFERS_MINT_RECEIVED = 8,
    BELUGA_CORE_OFFERS_AUTH_EQUAL = 1, BELUGA_CORE_OFFERS_ID_EQUAL = 2,
    BELUGA_CORE_OFFERS_CONTEXT_EQUAL = 4, BELUGA_CORE_OFFERS_VIDEO_EQUAL = 8,
    BELUGA_CORE_OFFERS_KNOWN_NATIVE_MATCHES = 15,
    BELUGA_CORE_OFFERS_KNOWN_PRIMARY_FLAGS = 511
};

typedef struct {
    uint64_t flags; /* original update.isValid, item, YouTube source/artwork, playing,
                    * canPause, canSeek, position, duration: bits0..8 respectively */
    uint64_t native_matches; /* primary versus owned/incoming offer: context4 | video8 */
    uint64_t revision;
    uint64_t position;
    uint64_t duration;
    uint64_t rate;
} beluga_core_handoff_offers_primary_t;

typedef struct {
    uint32_t text_valid; /* exact native context byte/control-scalar and video-ID rules */
    uint32_t reserved;
    uint64_t sequence;
    uint64_t revision;
    uint64_t position;
    uint64_t duration;
    uint64_t rate;
    uint64_t lifetime;
} beluga_core_handoff_offers_envelope_t;

typedef struct {
    uint32_t present;
    uint32_t video_equal;
    uint64_t position;
    uint64_t duration;
    uint64_t rate;
    uint64_t observed_at;
    uint64_t deadline;
} beluga_core_handoff_offers_source_t;

typedef struct {
    uint64_t token;
    uint64_t sequence;
    uint64_t revision;
    uint64_t position;
    uint64_t duration;
    uint64_t rate;
    uint64_t lifetime;
    uint64_t origin;
    uint64_t deadline;
    uint64_t last_observation;
    uint64_t last_position;
} beluga_core_handoff_offers_timeline_t;

typedef struct {
    uint32_t abi;
    uint32_t presence; /* sent1, received2, sentStateAt4, receivedStateAt8 */
    uint32_t terminal;
    uint32_t reserved;
    uint64_t next_sent;
    uint64_t highest_received;
    uint64_t sent_at;
    uint64_t received_at;
    beluga_core_handoff_offers_timeline_t sent;
    beluga_core_handoff_offers_timeline_t received;
} beluga_core_handoff_offers_state_t;

typedef struct {
    uint32_t opcode; /* recordSent0, recordReceived1, prepareSent2, sentFailed3,
                     * consumeSent4, receive5, consumeReceived6, prepareCommit7,
                     * discardReceived8, clearTransient9; reset uses initial() */
    uint32_t reserved;
    uint64_t token;
    uint64_t native_matches; /* header/request native comparisons, distinct from primary */
    uint64_t now;
    uint64_t phone_position;
    uint64_t phone_observed_at;
    beluga_core_handoff_offers_primary_t primary;
    beluga_core_handoff_offers_envelope_t envelope;
    beluga_core_handoff_offers_source_t source;
} beluga_core_handoff_offers_event_t;

typedef struct {
    beluga_core_handoff_offers_state_t state;
    uint32_t status; /* valid step0 (may decline while burning/retiring), invalid3 */
    uint32_t decision; /* none0, sentReady1, receivedReady2, receivedConsumed3,
                       * sentConsumed4, commitReady5 */
    uint32_t effects; /* retireSent1, retireReceived2, mintSent4, mintReceived8 */
    uint32_t reserved;
    uint64_t retired_sent;
    uint64_t retired_received;
    uint64_t minted_token;
    uint64_t sequence;
    uint64_t lifetime;
    uint64_t deadline;
} beluga_core_handoff_offers_result_t;

beluga_core_handoff_offers_state_t beluga_core_handoff_offers_initial(void);
beluga_core_handoff_offers_result_t beluga_core_handoff_offers_step(
    uint32_t abi_version, beluga_core_handoff_offers_state_t state,
    beluga_core_handoff_offers_event_t event);

/* Additive copied ABI1 phone-operation policy.
 * Floating fields are copied IEEE-754 Double bits, never integer clock units.
 * Native operation/page/video/evidence/completion comparisons are distinct facts.
 * This local policy does not consume a transport offer or authorize a native Pause.
 * Whole evidence equality includes its private native UUID and Double == semantics.
 */
typedef struct {
    uint64_t position;
    uint64_t duration;
    uint64_t rate;
    uint64_t deadline;
    uint64_t position_observed_at;
} beluga_core_youtube_handoff_operation_request_t;

typedef struct {
    uint64_t token;
    uint64_t position;
    uint64_t rate;
    uint64_t observed_at;
} beluga_core_youtube_handoff_operation_evidence_t;

typedef struct {
    uint32_t abi;
    uint32_t phase; /* preparing0 ready1 playRequired2 verifying3 confirmed4
                    * awaitingMacPause5 localPlayback6 failed7 */
    uint32_t failure; /* none0, original failure declaration order1..14 */
    uint32_t mac_pause; /* notRequested0 pending1 paused2 notApplied3 unknown4 */
    uint32_t flags; /* visible1 hasBeenVisible2 ready4 evidenceRevoked8 */
    uint32_t presence; /* firstPlaying1 latestPlaying2 latestState4 evidence8 reply16 */
    uint32_t sequence;
    uint32_t reserved;
    beluga_core_youtube_handoff_operation_request_t request;
    uint64_t last_now;
    uint64_t first_position;
    uint64_t first_at;
    uint64_t latest_playing_at;
    int32_t latest_state;
    uint32_t latest_state_reserved;
    beluga_core_youtube_handoff_operation_evidence_t evidence;
    uint64_t reply_deadline;
} beluga_core_youtube_handoff_operation_state_t;

typedef struct {
    uint32_t opcode; /* visibility0 poll1 receive2 current3 begin4 completion5 fail6 */
    uint32_t flags; /* visible1 operationEq2 pageEq4 videoEq8 proofEq16 completionEq32 */
    uint32_t presence; /* sample state1 position2 duration4 rate8; partial is legal */
    uint32_t sequence;
    uint32_t kind; /* ready0 blocked1 sample2 error3 unsupportedRate4 */
    int32_t sample_state;
    uint32_t completion; /* unused0 macPaused1 notApplied2 outcomeUnknown3 */
    uint32_t failure;
    uint64_t now;
    uint64_t proof_token;
    uint64_t candidate_token; /* 0 is exhaustion only at an actually eligible mint */
    uint64_t sample_position;
    uint64_t sample_duration;
    uint64_t sample_rate;
} beluga_core_youtube_handoff_operation_event_t;

typedef struct {
    beluga_core_youtube_handoff_operation_state_t state;
    uint32_t status; /* valid product step0, malformed ABI/state/event3 */
    uint32_t event; /* none0 playRequired1 confirmed2 movedToPhone3 failed4 */
    uint32_t accepted; /* exactly0/1; current and begin only */
    uint32_t failure; /* nonzero only if event4; silent current failure remains0 */
} beluga_core_youtube_handoff_operation_result_t;

/* Initial now is copied unchanged, including -Infinity, NaN and signed zero.
 * The request is independently constructed/validated by the native owner.
 * Malformed step inputs return byte-identical input state, no event and false.
 * Canonically absent option payloads are all zero. Optional observed times may
 * be negative when the original arbitrary initial clock admits them.
 * Candidate0 does not refuse unrelated/ignored/existing-proof branches; a truly
 * eligible new proof fails invalidBridge after normal clock/sequence processing.
 */
beluga_core_youtube_handoff_operation_state_t beluga_core_youtube_handoff_operation_initial(
    beluga_core_youtube_handoff_operation_request_t request, uint64_t now);
beluga_core_youtube_handoff_operation_result_t beluga_core_youtube_handoff_operation_step(
    uint32_t abi_version, beluga_core_youtube_handoff_operation_state_t state,
    beluga_core_youtube_handoff_operation_event_t event);

/* Sixth scalar contract. Native generation equality, callback invocation,
 * exact one-use owner custody and durable record effects stay in Swift. */
#define BELUGA_INVITATION_ACCEPTANCE_ABI_VERSION UINT32_C(1)
enum beluga_invitation_acceptance_opcode {
    BELUGA_INVITATION_ARM = 0,
    BELUGA_INVITATION_PREPARE_ADMISSION = 1,
    BELUGA_INVITATION_PREPARE_COMPLETION = 2,
    BELUGA_INVITATION_ACKNOWLEDGE_CALLBACK = 3,
    BELUGA_INVITATION_CANCEL = 4
};
enum beluga_invitation_acceptance_status {
    BELUGA_INVITATION_APPLIED = 0,
    BELUGA_INVITATION_IGNORED = 1,
    BELUGA_INVITATION_NEEDS_CALLBACK = 2,
    BELUGA_INVITATION_NOT_RECOVERABLE = 3,
    BELUGA_INVITATION_NOT_ACTIVE = 4,
    BELUGA_INVITATION_CALLBACK_FAILED = 5,
    BELUGA_INVITATION_STALE_PREPARED_PLAN = 6,
    BELUGA_INVITATION_INVALID_INPUT = 7
};
enum beluga_invitation_callback_kind {
    BELUGA_INVITATION_NO_CALLBACK = 0,
    BELUGA_INVITATION_ADMISSION_CALLBACK = 1,
    BELUGA_INVITATION_COMPLETION_CALLBACK = 2
};
enum beluga_invitation_pairing_phase {
    BELUGA_INVITATION_PHASE_OTHER = 0,
    BELUGA_INVITATION_PHASE_ACCEPTED_ISSUED = 1,
    BELUGA_INVITATION_PHASE_ACTIVE = 2
};
enum beluga_invitation_callback_outcome {
    BELUGA_INVITATION_CALLBACK_UNUSED = 0,
    BELUGA_INVITATION_CALLBACK_SUCCEEDED = 1,
    BELUGA_INVITATION_CALLBACK_THREW = 2
};

typedef struct {
    uint32_t abi_version;
    uint32_t flags;
} beluga_core_invitation_acceptance_state_t;
typedef struct {
    uint32_t opcode;
    uint32_t generation_matches;
    uint32_t phase;
    uint32_t admission_callback_present;
    uint32_t prepared_kind;
    uint32_t prepared_flags;
    uint32_t owner_matches;
    uint32_t callback_outcome;
} beluga_core_invitation_acceptance_event_t;
typedef struct {
    beluga_core_invitation_acceptance_state_t state;
    beluga_core_invitation_acceptance_state_t callback_success_state;
    uint32_t status;
    uint32_t completion_succeeded;
    uint32_t callback_kind;
    uint32_t prepared_flags;
} beluga_core_invitation_acceptance_result_t;

/* State flags: armed1, admission callback2, completion callback4, admission consumed8.
 * Legal states: 0,5,7,13,15. No UUID, closure, record, pointer, heap or secret crosses ABI.
 * All structs are copied and have alignment4; expected sizes State8/Event32/Result32.
 * NeedsCallback: state unchanged; success candidate authoritative but not committed;
 * callback kind1/2 and prepared_flags==before.flags. Native exact one-use custody mandatory.
 * Success is never inferred from a copied callback-kind/status field.
 */
beluga_core_invitation_acceptance_state_t beluga_core_invitation_acceptance_initial(void);
beluga_core_invitation_acceptance_result_t beluga_core_invitation_acceptance_step(
    uint32_t abi_version,
    beluga_core_invitation_acceptance_state_t state,
    beluga_core_invitation_acceptance_event_t event
);

/* Seventh copied scalar contract: bounded replay-window value policy only.
 * AEAD/JSON decoding, admitted peer/exchange ownership, resets and errors stay
 * native. All UInt64 sequences, including zero and UINT64_MAX, are legal.
 * Empty is canonical has_highest0/highest0/bitmap0; highest0/bitmap1 is populated.
 * Populated requires bit0 and no bit for a negative sequence when highest<63.
 * Malformed ABI/state and replay refusals preserve every input state field.
 * There is no opcode, reset effect, pointer, token, callback or secret.
 */
#define BELUGA_SIGNALING_REPLAY_ABI_VERSION UINT32_C(1)
#define BELUGA_SIGNALING_REPLAY_WINDOW_SIZE UINT64_C(64)
enum beluga_signaling_replay_decision {
    BELUGA_SIGNALING_REPLAY_ACCEPTED = 0,
    BELUGA_SIGNALING_REPLAY_DUPLICATE = 1,
    BELUGA_SIGNALING_REPLAY_OUTSIDE_WINDOW = 2,
    BELUGA_SIGNALING_REPLAY_INVALID_INPUT = 3
};
typedef struct {
    uint32_t abi_version;
    uint32_t has_highest;
    uint64_t highest;
    uint64_t bitmap;
} beluga_core_signaling_replay_state_t; /* size24 alignment8 */
typedef struct {
    beluga_core_signaling_replay_state_t state;
    uint32_t decision;
    uint32_t reserved; /* always zero */
} beluga_core_signaling_replay_result_t; /* size32 alignment8 */

beluga_core_signaling_replay_state_t beluga_core_signaling_replay_initial(void);
beluga_core_signaling_replay_result_t beluga_core_signaling_replay_step(
    uint32_t abi_version, beluga_core_signaling_replay_state_t state, uint64_t sequence);

/* Eighth copied scalar contract: an existing native catalog checkpoint attempt.
 * The candidate is not persisted state, an owner handle or storage-success proof.
 * Native calls commit it only after the original synchronous store returns.
 * Revoke retains binding; Readback requires the entire fresh snapshot, not owner.
 * Every refusal, unknown ABI/opcode/flag or nonboolean fact preserves input state.
 * No UUID, key, pointer, callback, counter or allocation crosses this boundary. */
typedef struct {
    uint32_t abi_version;
    uint32_t flags; /* bound=1, revoked=2; all four combinations legal */
} beluga_core_pairing_catalog_checkpoint_state_t; /* size8 alignment4 */
typedef struct {
    uint32_t opcode; /* add=0, update=1, revoke=2, readback=3 */
    uint32_t owner_valid; /* exact native process owner, boolean */
    uint32_t binding_matches; /* all three native UUIDs match, boolean */
    uint32_t snapshot_matches; /* full fresh durable snapshot matches, boolean */
} beluga_core_pairing_catalog_checkpoint_event_t; /* size16 alignment4 */
typedef struct {
    beluga_core_pairing_catalog_checkpoint_state_t candidate_state;
    uint32_t decision; /* allowed=0, stale attempt=1, invalid input=3 */
} beluga_core_pairing_catalog_checkpoint_result_t; /* size12 alignment4 */

beluga_core_pairing_catalog_checkpoint_state_t beluga_core_pairing_catalog_checkpoint_initial(void);
beluga_core_pairing_catalog_checkpoint_result_t beluga_core_pairing_catalog_checkpoint_step(
    uint32_t abi_version, beluga_core_pairing_catalog_checkpoint_state_t state,
    beluga_core_pairing_catalog_checkpoint_event_t event);

/* Ninth stateless copied-value policy. Native active-pair/identity/request
 * authentication and original constructors precede actual counter commitment.
 * All UInt64 snapshot values are representable, including outbound zero. A
 * Proposed result is not constructor, persistence, authorization or send proof.
 * Invalid input is unchanged; both reserved inputs and unused outbound sequence
 * must be zero. There is no reset, owned ledger, initial symbol or pointer. */
enum {
    BELUGA_RECONNECT_COUNTERS_RESERVE_OUTBOUND = 0,
    BELUGA_RECONNECT_COUNTERS_ADMIT_INBOUND = 1,
    BELUGA_RECONNECT_COUNTERS_PROPOSED = 0,
    BELUGA_RECONNECT_COUNTERS_SEQUENCE_EXHAUSTED = 1,
    BELUGA_RECONNECT_COUNTERS_STALE_SEQUENCE = 2,
    BELUGA_RECONNECT_COUNTERS_INVALID_INPUT = 3
};
typedef struct {
    uint32_t abi_version;
    uint32_t reserved;
    uint64_t next_outbound;
    uint64_t highest_accepted;
} beluga_core_reconnect_counters_state_t; /* size24 alignment8 */
typedef struct {
    uint32_t opcode;
    uint32_t reserved;
    uint64_t request_sequence; /* reserve=0; inbound accepts full UInt64 domain */
} beluga_core_reconnect_counters_event_t; /* size16 alignment8 */
typedef struct {
    beluga_core_reconnect_counters_state_t candidate_state;
    uint32_t decision;
    uint32_t reserved; /* always zero */
} beluga_core_reconnect_counters_result_t; /* size32 alignment8 */

beluga_core_reconnect_counters_result_t beluga_core_reconnect_counters_step(
    uint32_t abi_version, beluga_core_reconnect_counters_state_t state,
    beluga_core_reconnect_counters_event_t event);

/* Stateless pairing recovery plan. Native authentication, signing and durable writes remain mandatory. */
typedef struct {
    uint32_t abi_version;
    uint32_t reserved;
    uint32_t local_role;
    uint32_t pairing_state;
    uint32_t recovery_phase;
    uint32_t reserved_tail;
} beluga_core_pairing_commit_state_t;

typedef struct {
    uint32_t opcode;
    uint32_t reserved;
    uint32_t commit_id_matches;
    uint32_t reserved_tail;
} beluga_core_pairing_commit_event_t;

typedef struct {
    beluga_core_pairing_commit_state_t candidate_state;
    uint32_t decision;
    uint32_t action;
    uint32_t auth_phase;
    uint32_t reserved;
} beluga_core_pairing_commit_result_t;

beluga_core_pairing_commit_result_t beluga_core_pairing_commit_step(
    uint32_t abi_version, beluga_core_pairing_commit_state_t state,
    beluga_core_pairing_commit_event_t event);

/* Eleventh copied scalar contract: supported-player source arbitration only.
 * Native fetch generations, snapshots, tokens, metadata and effects stay native.
 * selected: none0/browser1/Music2; child: no-media0/paused1/playing2/retry3.
 * Both structs are copied, alignment4; input20/output16. ABI1/reserved0 only.
 * action: invalid0/retry1/publish2. Retry carries the unchanged selected hold;
 * publish carries none0/browser1/Music2. Invalid is canonical ABI1/action0/source0.
 * A source ordinal never grants native snapshot or command authority by itself.
 */
typedef struct {
    uint32_t abi_version;
    uint32_t selected_source;
    uint32_t browser_observation;
    uint32_t music_observation;
    uint32_t reserved;
} beluga_core_supported_player_arbitration_input_t;

typedef struct {
    uint32_t abi_version;
    uint32_t action;
    uint32_t primary_or_hold;
    uint32_t reserved;
} beluga_core_supported_player_arbitration_output_t;

beluga_core_supported_player_arbitration_output_t beluga_core_supported_player_arbitrate(
    beluga_core_supported_player_arbitration_input_t input);

/* Copied availability retry policy; no socket, session, timer or native effects.
 * States: delay in {1,2,4,8,16,30}/validated0, or delay1/validated1.
 * Event0: successfully handled parsed waiting/ready; event1: iteration failure.
 * A WebSocket upgrade alone is not a policy event.
 * Decision0: observed valid state; decision1: retry after the original delay;
 * decision2: invalid input, preserving the exact raw state and zeroing outputs.
 * ABI1 and reserved0 only. Native must validate correlation before commitment.
 */
typedef struct {
    uint32_t abi_version;
    uint32_t next_delay_seconds;
    uint32_t has_validated_connection;
    uint32_t reserved;
} beluga_core_availability_retry_state_t;

typedef struct {
    uint32_t opcode;
    uint32_t reserved;
} beluga_core_availability_retry_event_t;

typedef struct {
    beluga_core_availability_retry_state_t candidate_state;
    uint32_t decision;
    uint32_t became_validated;
    uint32_t retry_delay_seconds;
    uint32_t reserved;
} beluga_core_availability_retry_result_t;

beluga_core_availability_retry_result_t beluga_core_availability_retry_step(
    uint32_t abi_version,
    beluga_core_availability_retry_state_t before,
    beluga_core_availability_retry_event_t event);


/* Three copied scalar policies; ABI1, reserved0, closed status/decision domains.
 * Safe-output retry: signed 64-bit constructor limits independently clamp to1;
 * transition events1=tick/2=failure/3=reset. Status0 refuses exact unchanged raw
 * state; status1 accepts. Tick0=none/1=wait/2=attempt. No timing or route effect.
 * System start: closed booleans; status1/mode0 is legitimate no-match, not an
 * invalid bridge. Modes1=alreadyLive/2=resumeExisting/3=startNew.
 * Hosted-call results: status1/value0 is legitimate refusal/None. Admission
 * values0/1; evidence0=None/1=inactive/2=preflightArmed/3=active. Presence0
 * ignores payload; UUID bytes and u64 counters are copied without truncation.
 * These projections mint no native authority. Native validates correlation
 * before committing state or effects; all ownership/effect guards stay native.
 * Public declarations remain C++-compatible; layout assertions live in smokes.
 */
typedef struct {
    uint32_t abi_version, reserved;
    int64_t maximum_failed_attempt_count, maximum_backoff_tick_count, capped_cooldown_tick_count;
} beluga_core_safe_output_retry_config_t;
typedef struct {
    uint32_t abi_version, reserved;
    int64_t maximum_failed_attempt_count, maximum_backoff_tick_count, capped_cooldown_tick_count;
    int64_t failed_attempt_count, backoff_tick_count, cooldown_tick_count;
} beluga_core_safe_output_retry_state_t;
typedef struct {
    beluga_core_safe_output_retry_state_t state;
    uint32_t status, tick_decision;
} beluga_core_safe_output_retry_result_t;
typedef struct {
    uint32_t abi_version, reserved;
    uint32_t is_live, is_paused_for_recovery, has_source, has_sink;
    uint32_t has_valid_authorization, peer_generation_matches;
} beluga_core_system_audio_start_facts_t;
typedef struct {
    uint32_t abi_version, status, mode, reserved;
} beluga_core_system_audio_start_decision_t;
typedef struct {
    uint32_t abi_version, reserved;
    uint64_t observation_sequence, highest_admitted_sequence;
    uint32_t observation_challenge_present, current_challenge_present;
    int64_t current_protocol_version;
    uint64_t observation_challenge_sequence, current_challenge_sequence;
    uint8_t observation_nonce[16], observation_call_epoch_nonce[16];
    uint8_t current_nonce[16], current_call_epoch_nonce[16];
} beluga_core_hosted_call_observation_facts_t;
typedef struct {
    uint32_t abi_version, reserved, active, armed;
} beluga_core_hosted_call_evidence_facts_t;
typedef struct {
    uint32_t abi_version, reserved, audio_present, challenge_present;
    uint64_t audio_generation, challenge_generation, current_generation;
} beluga_core_hosted_call_peer_facts_t;
typedef struct {
    uint32_t abi_version, status, value, reserved;
} beluga_core_hosted_call_decision_t;
beluga_core_safe_output_retry_result_t beluga_core_safe_output_retry_initialize(beluga_core_safe_output_retry_config_t);
beluga_core_safe_output_retry_result_t beluga_core_safe_output_retry_transition(beluga_core_safe_output_retry_state_t, uint32_t event);
beluga_core_system_audio_start_decision_t beluga_core_system_audio_start(beluga_core_system_audio_start_facts_t);
beluga_core_hosted_call_decision_t beluga_core_hosted_call_observation(beluga_core_hosted_call_observation_facts_t);
beluga_core_hosted_call_decision_t beluga_core_hosted_call_evidence(beluga_core_hosted_call_evidence_facts_t);
beluga_core_hosted_call_decision_t beluga_core_hosted_call_peer_generation(beluga_core_hosted_call_peer_facts_t);

/* Copied inputs only. No pointers, ownership, allocation, display IO or wire changes. */
typedef struct {
    uint32_t abi_version, reserved;
    uint32_t required_vendor_id, required_product_id, required_serial_number;
    uint32_t requires_sole_main_display, display_id;
    uint32_t observed_vendor_id, observed_product_id, observed_serial_number;
    uint32_t is_online, is_active, main_display_id, sole_online_display_id;
    uint64_t online_display_count;
} beluga_core_display_requirement_facts_t;
typedef struct {
    uint32_t abi_version, status, value, reserved;
} beluga_core_display_boolean_decision_t;
typedef struct {
    uint32_t abi_version, reserved, vendor_id, product_id;
} beluga_core_source_dimension_kind_facts_t;
typedef struct {
    uint32_t abi_version, status, kind, reserved;
} beluga_core_source_dimension_kind_decision_t;
typedef struct {
    uint32_t abi_version, reserved, vendor_id, product_id;
    int64_t logical_width, logical_height;
    int64_t core_graphics_logical_width, core_graphics_logical_height;
    int64_t core_graphics_pixel_width, core_graphics_pixel_height;
    double filter_content_width, filter_content_height, point_pixel_scale;
} beluga_core_source_dimensions_facts_t;
typedef struct {
    uint32_t abi_version, status, kind, has_dimensions;
    int64_t width, height;
} beluga_core_source_dimensions_decision_t;
typedef struct {
    uint32_t abi_version, reserved;
    int64_t before_width, before_height, after_width, after_height;
} beluga_core_source_dimensions_stability_facts_t;
beluga_core_display_boolean_decision_t beluga_core_display_requirement_admission(beluga_core_display_requirement_facts_t);
beluga_core_source_dimension_kind_decision_t beluga_core_source_dimension_kind(beluga_core_source_dimension_kind_facts_t);
beluga_core_source_dimensions_decision_t beluga_core_source_dimensions(beluga_core_source_dimensions_facts_t);
beluga_core_display_boolean_decision_t beluga_core_source_dimensions_stable(beluga_core_source_dimensions_stability_facts_t);

/* Exact copied signed input; rounded f64 bits are projected without normalization. */
typedef struct {
    uint32_t abi_version, reserved;
    int64_t source_width, source_height, maximum_width;
} beluga_core_output_dimensions_facts_t;
typedef struct {
    uint32_t abi_version, status, decision, reserved;
    int64_t width, height;
    uint64_t rounded_height_bits;
} beluga_core_output_dimensions_decision_t;
beluga_core_output_dimensions_decision_t beluga_core_output_dimensions(beluga_core_output_dimensions_facts_t);

/* ICE policy owns no native task/socket/timer. All values are copied, ABI 1. */
typedef struct {
    int64_t maximum_attempts;
    uint32_t grace_positive;
    uint32_t reserved;
} beluga_core_ice_recovery_config_t;
typedef struct {
    uint32_t abi_version;
    uint32_t phase;
    uint64_t epoch;
    int64_t attempts;
    int64_t maximum_attempts;
    uint32_t exhaustion_delivered;
    uint32_t grace_positive;
    uint32_t cursor;
    uint32_t reserved;
} beluga_core_ice_recovery_state_t;
typedef struct {
    uint32_t abi_version;
    uint32_t opcode;
    uint64_t workflow_epoch;
    uint32_t task_cancelled;
    uint32_t succeeded;
    uint32_t wait_kind;
    uint32_t reserved;
} beluga_core_ice_recovery_event_t;
typedef struct {
    uint32_t status;
    uint32_t reserved;
    beluga_core_ice_recovery_config_t copied_config;
    beluga_core_ice_recovery_state_t candidate_state;
} beluga_core_ice_recovery_init_result_t;
typedef struct {
    uint32_t abi_version;
    uint32_t status;
    beluga_core_ice_recovery_state_t copied_before;
    beluga_core_ice_recovery_event_t copied_event;
    beluga_core_ice_recovery_state_t candidate_state;
    uint32_t effect;
    uint32_t flags;
    uint64_t reserved;
} beluga_core_ice_recovery_result_t;
beluga_core_ice_recovery_init_result_t beluga_core_ice_recovery_initialize(
    uint32_t abi_version, beluga_core_ice_recovery_config_t config);
beluga_core_ice_recovery_result_t beluga_core_ice_recovery_step(
    uint32_t abi_version, beluga_core_ice_recovery_state_t before,
    beluga_core_ice_recovery_event_t event);

/* Client screen liveness is diagnostic only: no effects or ownership fields. */
typedef struct {
    uint64_t present; /* exactly 0/1; absent value must be zero */
    uint64_t value;
} beluga_core_screen_liveness_optional_t;

typedef struct {
    uint64_t generation;
    uint64_t observed_at;
    uint64_t track_attached;
    uint64_t cover; /* none=0, bandwidth=1, privacy=2, resuming=3, hidden=4 */
    uint64_t inbound_present;
    beluga_core_screen_liveness_optional_t inbound_bytes;
    beluga_core_screen_liveness_optional_t inbound_packets;
    beluga_core_screen_liveness_optional_t decoded_frames;
    beluga_core_screen_liveness_optional_t inbound_width;
    beluga_core_screen_liveness_optional_t inbound_height;
    beluga_core_screen_liveness_optional_t frames_per_second_bits;
    uint64_t render_present;
    uint64_t presented_frames;
    uint64_t content_samples;
    uint64_t content_changes;
    uint64_t presented_at;
    uint64_t render_width_bits;
    uint64_t render_height_bits;
} beluga_core_screen_liveness_sample_t;

typedef struct {
    uint64_t previous_present;
    beluga_core_screen_liveness_optional_t last_change_at;
    beluga_core_screen_liveness_sample_t previous;
} beluga_core_screen_liveness_state_t;

typedef struct {
    uint64_t liveness; /* covered intent=0, covered=1, missing=2, awaiting=3,
                       * RTP stalled=4, decode stalled=5, presentation stalled=6,
                       * presenting unchanged=7, presenting live=8 */
    uint64_t reset_reason; /* none=0, initial=1, generation=2, regression=3 */
    uint64_t generation;
    uint64_t track_attached;
    uint64_t cover;
    beluga_core_screen_liveness_optional_t inbound_bytes;
    beluga_core_screen_liveness_optional_t inbound_byte_delta;
    beluga_core_screen_liveness_optional_t inbound_packets;
    beluga_core_screen_liveness_optional_t inbound_packet_delta;
    beluga_core_screen_liveness_optional_t decoded_frames;
    beluga_core_screen_liveness_optional_t decoded_frame_delta;
    beluga_core_screen_liveness_optional_t presented_frames;
    beluga_core_screen_liveness_optional_t presented_frame_delta;
    beluga_core_screen_liveness_optional_t content_samples;
    beluga_core_screen_liveness_optional_t content_sample_delta;
    beluga_core_screen_liveness_optional_t content_changes;
    beluga_core_screen_liveness_optional_t content_change_delta;
    beluga_core_screen_liveness_optional_t presentation_age_ms;
    beluga_core_screen_liveness_optional_t frame_width;
    beluga_core_screen_liveness_optional_t frame_height;
    beluga_core_screen_liveness_optional_t frames_per_second_bits;
} beluga_core_screen_liveness_snapshot_t;

typedef struct {
    uint64_t abi_version;
    uint64_t status; /* applied=0, malformed input=3; neither grants authority */
    uint64_t reserved;
    beluga_core_screen_liveness_state_t state;
    beluga_core_screen_liveness_snapshot_t snapshot;
} beluga_core_screen_liveness_result_t;

beluga_core_screen_liveness_result_t beluga_core_screen_liveness_observe(
    uint64_t abi_version, beluga_core_screen_liveness_state_t state,
    beluga_core_screen_liveness_sample_t sample);

/* Proposed additive declarations; no canonical header change yet. */
typedef struct {
    uint32_t abi_version;
    uint32_t reserved;
    uint32_t stage; /* prepared=0, possiblyArmed=1, installedVerified=2, readyToRelease=3 */
    uint32_t broker_present;
    uint32_t candidate_present;
    uint32_t recorded_readiness_present;
    uint32_t installed_fresh;
    uint32_t readiness_fresh;
    uint32_t challenge_present;
    uint32_t reserved_tail;
} BelugaUpdateOperationState;

typedef struct {
    uint32_t opcode; /* closed 0..13; facts and unused-zero rules in integration plan */
    uint32_t reserved;
    uint32_t fact0;
    uint32_t fact1;
    uint32_t fact2;
    uint32_t fact3;
    uint32_t fact4;
    uint32_t fact5;
    uint32_t fact6;
    uint32_t reserved_tail;
} BelugaUpdateOperationEvent;

typedef struct {
    BelugaUpdateOperationState candidate_state;
    uint32_t decision; /* accepted=0, denied=1, invalidInput=2 */
    uint32_t action; /* closed symbolic assignment 0..8, never a native effect */
    uint32_t predicate; /* exactly 0/1, nonzero only for accepted queries */
    uint32_t reserved;
} BelugaUpdateOperationResult;

BelugaUpdateOperationResult beluga_core_update_operation_step(
    uint32_t abi_version, BelugaUpdateOperationState before, BelugaUpdateOperationEvent event);

/* Queue evidence only. Native statistics, clock instants and encoding effects stay native. */
typedef struct {
    uint32_t abi_version;
    uint32_t reserved;
    uint32_t packets_present;
    uint32_t delay_present;
    uint32_t low_present;
    uint32_t soft_present;
    uint64_t packets;
    uint64_t delay_bits;
    uint64_t pressure_count;
} beluga_core_packet_send_queue_state_t;

typedef struct {
    uint32_t opcode; /* ordinary=0, capacity=1, tier reset=2, path reset=3, low lease query=4 */
    uint32_t packets_present;
    uint32_t delay_present;
    uint32_t rtt_inflated;
    uint64_t packets;
    uint64_t delay_bits;
    int64_t low_age_seconds;
    int64_t low_age_attoseconds;
    int64_t soft_age_seconds;
    int64_t soft_age_attoseconds;
} beluga_core_packet_send_queue_event_t;

typedef struct {
    uint32_t abi_version;
    uint32_t status; /* malformed=0, legitimate policy outcome=1 */
    uint32_t observation; /* unavailable/reset=0, no packets=1, measured=2 */
    uint32_t low_action; /* retain=0, clear=1, stamp now=2 */
    uint32_t soft_action;
    uint32_t sample_inflated;
    uint32_t immediate;
    uint32_t inflated;
    uint32_t upgrade;
    uint32_t capacity_growth;
    uint64_t measured_delay_bits;
    beluga_core_packet_send_queue_state_t state;
} beluga_core_packet_send_queue_result_t;

beluga_core_packet_send_queue_result_t beluga_core_packet_send_queue_step(
    beluga_core_packet_send_queue_state_t state, beluga_core_packet_send_queue_event_t event);

/* Append inside the existing header's extern-C boundary. Copied ABI only. */
typedef struct {
    uint64_t fingerprint_words[8];
    uint64_t total_bits;
    uint64_t responses;
} beluga_core_rtt_evidence_measurement_t;

typedef struct {
    uint32_t abi_version, reserved, baseline_present, bootstrap_count;
    uint32_t disposition, health, uses_native, provisional, permits_initial, distinct_count;
    uint32_t last_measured_present, advancement_present, age_present, watermark_present;
    uint32_t fence_present, fence_current_present, reserved2, reserved3;
    uint64_t baseline_bits, last_measured_bits, bootstrap_bits[3];
    int64_t age_seconds, age_attoseconds;
    beluga_core_rtt_evidence_measurement_t watermark, fence;
    uint64_t fence_current_bits;
} beluga_core_rtt_evidence_state_t;

typedef struct {
    uint32_t opcode, observation_kind, current_present, fingerprint_length, route_changed, reserved;
    uint64_t current_bits;
    beluga_core_rtt_evidence_measurement_t measurement;
    int64_t age_seconds, age_attoseconds;
} beluga_core_rtt_evidence_event_t;

typedef struct {
    uint32_t abi_version, status, fresh_pressure, allows_upgrade, legacy_missing, clock_action;
    uint32_t validation_disposition, primary_lease_current, reserved, reserved2;
    beluga_core_rtt_evidence_state_t state;
} beluga_core_rtt_evidence_result_t;

beluga_core_rtt_evidence_result_t beluga_core_rtt_evidence_step(
    beluga_core_rtt_evidence_state_t before, beluga_core_rtt_evidence_event_t event);
uint32_t beluga_core_rtt_evidence_result_is_valid(
    beluga_core_rtt_evidence_state_t before, beluga_core_rtt_evidence_event_t event,
    beluga_core_rtt_evidence_result_t result);

/* Append to the existing reviewed public header; fixed copied layouts, no pointers. */
typedef struct {
    uint32_t abi_version;
    uint32_t configured_cap;
    uint32_t current_tier;
    uint32_t bandwidth_present;
    uint64_t bandwidth_bits;
} beluga_core_tier_demand_facts_t;

typedef struct {
    uint32_t abi_version;
    uint32_t status;
    uint32_t current_tier;
    uint32_t reserved;
    uint32_t basis_points;
    uint32_t baseline_video;
    uint32_t maximum_tier_video;
    uint32_t maximum_video;
    uint32_t maximum_total_rtp;
    uint32_t minimum_sustainable;
    uint32_t initial_tier;
    uint32_t sustainable_tier;
    uint32_t upgrade_present;
    uint32_t upgrade_tier;
    uint32_t direct_threshold_present;
    uint32_t direct_threshold_minimum;
    uint64_t required_bitrate_bits;
    uint64_t direct_threshold_bits;
} beluga_core_tier_demand_projection_t;

beluga_core_tier_demand_projection_t beluga_core_tier_demand_project(
    beluga_core_tier_demand_facts_t facts);
uint32_t beluga_core_tier_demand_projection_is_valid(
    beluga_core_tier_demand_facts_t facts, beluga_core_tier_demand_projection_t projection);

typedef struct {
    uint32_t abi_version;
    uint32_t is_open;
    uint64_t lifecycle;
    uint64_t command_epoch;
} beluga_core_media_command_gate_state_t;

typedef struct {
    uint32_t opcode;
    uint32_t context_is_current;
    uint32_t reserved0;
    uint32_t reserved1;
    uint64_t candidate_lifecycle;
    uint64_t candidate_command_epoch;
} beluga_core_media_command_gate_event_t;

typedef struct {
    uint32_t abi_version;
    uint32_t status;
    uint32_t allowed;
    uint32_t reserved;
    beluga_core_media_command_gate_state_t state;
} beluga_core_media_command_gate_result_t;

beluga_core_media_command_gate_result_t beluga_core_media_command_gate_step(
    beluga_core_media_command_gate_state_t state, beluga_core_media_command_gate_event_t event);
uint32_t beluga_core_media_command_gate_result_is_valid(
    beluga_core_media_command_gate_state_t state, beluga_core_media_command_gate_event_t event,
    beluga_core_media_command_gate_result_t result);

/* Complete scalar suspension transcript. Native UUID/String/proof custody stays native.
 * ABI version 1; sizes/alignment: state 88/8, event 64/8, result 128/8.
 * Status-0 canonical denial is never a successor/reset and never validates. */
typedef struct {
    uint32_t abi_version;
    uint32_t phase;
    uint64_t next_generation;
    uint64_t screen_request_id;
    uint64_t suspension_generation;
    uint64_t peer_generation;
    uint64_t visibility_epoch;
    uint64_t recovery_epoch;
    uint64_t prior_screen_request_id;
    uint64_t prior_suspension_generation;
    uint32_t cover_confirmed;
    uint32_t inactive_confirmed;
    uint32_t custody_mask;
    uint32_t reserved;
} beluga_core_screen_suspension_state_t;

typedef struct {
    uint32_t opcode;
    uint32_t flags;
    uint32_t native_facts;
    uint32_t reserved;
    uint64_t screen_request_id;
    uint64_t peer_generation;
    uint64_t visibility_epoch;
    uint64_t recovery_epoch;
    uint64_t notice_screen_request_id;
    uint64_t notice_generation;
} beluga_core_screen_suspension_event_t;

typedef struct {
    uint32_t abi_version;
    uint32_t status;
    uint32_t accepted;
    uint32_t custody_action;
    beluga_core_screen_suspension_state_t state;
    uint32_t query_flags;
    uint32_t reserved;
    uint64_t produced_notice_screen_request_id;
    uint64_t produced_notice_generation;
} beluga_core_screen_suspension_result_t;

beluga_core_screen_suspension_result_t beluga_core_screen_suspension_step(
    beluga_core_screen_suspension_state_t state, beluga_core_screen_suspension_event_t event);
uint32_t beluga_core_screen_suspension_result_is_valid(
    beluga_core_screen_suspension_state_t state, beluga_core_screen_suspension_event_t event,
    beluga_core_screen_suspension_result_t result);
typedef struct {
    uint32_t abi_version;
    uint32_t stage;
    uint32_t operation;
    uint32_t flags;
    uint32_t count;
    uint32_t selected_slot;
    uint32_t target_slot;
    uint32_t duplicate_axes;
    uint32_t previous_phase;
    uint32_t candidate_phase;
    uint32_t previous_recovery;
    uint32_t candidate_recovery;
    uint32_t reserved0;
    uint32_t reserved1;
    uint64_t revision;
    uint64_t previous_outbound;
    uint64_t candidate_outbound;
    uint64_t previous_accepted;
    uint64_t candidate_accepted;
    uint64_t reserved2;
} beluga_core_phone_catalog_input_t;

typedef struct {
    uint32_t abi_version;
    uint32_t status;
    uint32_t error;
    uint32_t action;
    uint32_t count;
    uint32_t selected_slot;
    uint32_t target_slot;
    uint32_t reserved;
    uint32_t slot0;
    uint32_t slot1;
    uint32_t slot2;
    uint32_t slot3;
    uint32_t slot4;
    uint32_t slot5;
    uint32_t slot6;
    uint32_t slot7;
    uint64_t revision;
} beluga_core_phone_catalog_result_t;

beluga_core_phone_catalog_result_t beluga_core_phone_catalog_decide(
    beluga_core_phone_catalog_input_t input);
uint32_t beluga_core_phone_catalog_result_is_valid(
    beluga_core_phone_catalog_input_t input, beluga_core_phone_catalog_result_t result);
/* Insert before the existing C++/header closing guards; preserve all other ABI. */
typedef struct {
    uint32_t abi_version;
    uint32_t phase;
    uint32_t operation;
    uint32_t eligible;
    uint32_t intent;
    uint32_t first_grant;
} beluga_core_runtime_catalog_state_t;

typedef struct {
    uint32_t opcode;
    uint32_t operation;
    uint32_t facts;
    uint32_t reserved;
} beluga_core_runtime_catalog_event_t;

typedef struct {
    beluga_core_runtime_catalog_state_t state;
    uint32_t status;
    uint32_t decision;
    uint32_t effect;
    uint32_t value;
} beluga_core_runtime_catalog_result_t;

beluga_core_runtime_catalog_result_t beluga_core_runtime_catalog_step(
    beluga_core_runtime_catalog_state_t state, beluga_core_runtime_catalog_event_t event);
uint32_t beluga_core_runtime_catalog_result_is_valid(
    beluga_core_runtime_catalog_state_t state, beluga_core_runtime_catalog_event_t event,
    beluga_core_runtime_catalog_result_t result);

/* Proposed source interface, not an installed BelugaCore artifact declaration.
 * Complete version-1 Owner snapshots contain 179 lossless tagged atoms. Native
 * route identity and actual Instant sidecars remain with the serial actor owner.
 * Numeric generations/flags are not a native authorization or effect receipt. */
enum {
    BELUGA_CORE_ADAPTATION_OWNER_STOP_SAMPLING = 105,
    BELUGA_CORE_ADAPTATION_OWNER_ACTIVATE_SHOW = 106,
    BELUGA_CORE_ADAPTATION_OWNER_RESUME_WITHOUT_REVISION = 107,
    BELUGA_CORE_ADAPTATION_OWNER_RESUME_AND_ADVANCE = 108,
    BELUGA_CORE_ADAPTATION_OWNER_COLLECTOR_GATE = 109,
    BELUGA_CORE_ADAPTATION_OWNER_ATOM_COUNT = 179,
    BELUGA_CORE_ADAPTATION_OWNER_TIME_COUNT = 13,
    BELUGA_CORE_ADAPTATION_OWNER_READ_COUNT = 15
};

typedef struct {
    uint32_t abi;
    uint32_t operation;
    uint64_t generation; /* 106 only; zero for all other operations */
    uint64_t invocation; /* nonzero */
    uint64_t show; /* 106 only; zero for all other operations */
    uint32_t capture_source_present; /* 109 only, exactly 0 or 1 */
    uint32_t resume_context_absent; /* 109 only, exactly 0 or 1 */
} beluga_core_adaptation_owner_event_request_t;

typedef struct {
    uint32_t abi, domain, phase, count;
} beluga_core_adaptation_state_header_t;

typedef struct {
    uint32_t kind, present;
    int64_t high;
    uint64_t low;
} beluga_core_adaptation_state_atom_t;

typedef struct {
    uint32_t action, source, index, ordinal;
    int64_t high;
    uint64_t low;
} beluga_core_adaptation_time_edit_t;

typedef struct {
    uint32_t present, reserved;
    int64_t high;
    uint64_t low;
} beluga_core_adaptation_time_coordinate_t;

typedef struct {
    uint32_t abi, status, site, ordinal;
    uint64_t invocation;
    int64_t high;
    uint64_t low, reserved;
} beluga_core_adaptation_clock_reply_t;

typedef struct {
    uint32_t abi, operation, scope, read_count;
    uint64_t invocation, revision, peer;
    uint32_t peer_present, bound, route, sample;
    uint32_t enabled, lease, queue_fault, rtt_fault;
} beluga_core_adaptation_owner_event_metadata_t;

/* Return 1: complete result. Return 2: unsupported operation/malformed shape,
 * every output untouched. No callback, observed snapshot or native resource pointer is
 * accepted. No other operation is admitted, including policy-only 101–104 or
 * initial clock-reading EndShow 202. Input header is exactly {1,2,1,179}; output
 * is {1,2,2,179}. All buffer counts below must equal their declared constants.
 * Six outputs must be initialized, valid, aligned and mutually disjoint from
 * each other and every input; no thread may mutate them through return. Pointer
 * checks cannot prove provenance/lifetime. Writes are sequential, not an atomic
 * multi-buffer commit. The actor must resolve/validate the whole result/sidecar
 * tuple before publishing. All replies are zero; metadata.scope=2/read_count=0.
 *
 * 105 is ONLY the later sampling cut: clears fast/lane/evidence/freshness,
 * wraps revision once, retains policy and applied. Never substitutes EndShow.
 * 106 preserves the typed exact peer/show/reserved guard but wraps revision once
 * even if that guard rejects activation; the caller still proves actual ACK.
 * 107/108 clear restoration+promotion; only 108 wraps revision once.
 * 109 clears fast only if source absent, reports source && context-absent in
 * metadata.enabled, and otherwise changes no state or revision.
 * Owned time slots: 105 EvidenceTime12; 107/108 PromotionDeadline2. Clear is
 * reported even for an already-absent value. All unowned edits/coordinates are
 * zero, not inferred Retain. For these operations bound/route/sample/lease=0. */
uint32_t beluga_core_network_adaptation_owner_zero_clock_event(
    const beluga_core_adaptation_owner_event_request_t *request,
    const beluga_core_adaptation_state_header_t *header,
    const beluga_core_adaptation_state_atom_t *atoms, uint32_t count,
    beluga_core_adaptation_state_header_t *output_header,
    beluga_core_adaptation_state_atom_t *output_atoms, uint32_t output_count,
    beluga_core_adaptation_owner_event_metadata_t *metadata,
    beluga_core_adaptation_time_edit_t *edits, uint32_t edit_count,
    beluga_core_adaptation_time_coordinate_t *coordinates, uint32_t coordinate_count,
    beluga_core_adaptation_clock_reply_t *reads, uint32_t read_count);

/* SOURCE-ONLY addendum after the existing adaptation Owner POD declarations,
 * before beluga_core.h's extern-C closing guard. No installed ABI claim. */
enum {
    BELUGA_CORE_ADAPTATION_OWNER_END_SHOW_WITHOUT_REVISION = 202,
    BELUGA_CORE_ADAPTATION_OWNER_ROUTE_INVALIDATED = 212,
    BELUGA_CORE_ADAPTATION_OWNER_END_SHOW_AND_ADVANCE = 213,
    BELUGA_CORE_ADAPTATION_OWNER_VISIBILITY_COMMAND = 214,
    BELUGA_CORE_ADAPTATION_OWNER_HIDE_HEALTH_REVOCATION = 215,
    BELUGA_CORE_ADAPTATION_OWNER_BEGIN_POST_RESUME_EPOCH = 216,
    BELUGA_CORE_ADAPTATION_OWNER_RESUME_ACCEPTED = 217,
    BELUGA_CORE_ADAPTATION_OWNER_RESUME_FAILED_AND_ADVANCE = 218
};

typedef struct {
    uint32_t abi, operation;
    uint64_t generation, invocation, show, minimum;
    uint32_t flag, minimum_present;
} beluga_core_adaptation_owner_clocked_event_request_t;

typedef uint32_t (*beluga_core_adaptation_owner_clock_callback_t)(
    void *context, uint64_t invocation, uint32_t site, uint32_t ordinal,
    beluga_core_adaptation_clock_reply_t *reply);

/* Exactly 202 and 212-218; policy-only 201/203-211 are denied before state decode
 * or provider use. Full179 input {1,2,1,179}; result {1,2,2,179}. Counts are
 * exactly 179/179/13/13/15. Return 1 fills six correlated output objects; 2 rejects
 * shape/arithmetic, 3 provider failure/budget, 4 reply mismatch, 5 time witness.
 * Every non-1 return leaves all output bytes untouched. Callback activity is
 * external and cannot be rolled back. Do not infer native rollback from refusal.
 * abi=1, invocation!=0. generation/show must be zero except 214 with flag=1;
 * flag is exactly 0/1 for 214 and zero otherwise. minimum_present is exactly
 * 0/1 for 216, zero otherwise; an absent minimum carries zero. minimum=0 for
 * every operation other than 216. No observed-policy snapshot is accepted.
 *
 * The callback is required even on a branch that performs no reads. It is invoked
 * lazily at original cuts, at most 15 times: sites RTT event=0, RTT apply=1,
 * queue reset=2, published lease=3, copy fence=4. Each accepted reply is exactly
 * {abi=1,status=1,requested site/ordinal/invocation,coordinate,reserved=0}; reply
 * coordinate is signed 128-bit attoseconds in high/low, representable as native
 * Duration Int64 seconds plus attoseconds. Unused replies are all zero. Never
 * cache, pre-sample or synthesize reads. A trusted caller independently derives
 * the native operation/read plan, supplies a live synchronous context, denies
 * same-frame reentry, catches native failures without unwinding across C, and
 * preserves every borrowed buffer until return. It must never modify/free those
 * buffers from inside the callback or another thread. Range checks cannot prove
 * allocation provenance, context lifetime, native identity or actor authority.
 *
 * 202 is the earlier Stop EndShow cut, no revision advance, metadata.scope=1.
 * It is not later Stop sampling bookkeeping 105. The other cuts have scope=2:
 * 212 advances before route invalidation; 213/214/216/217/218 advance after their
 * successful typed helper; 215 has no revision advance. Wrapping is unchanged.
 * Successful 212 always reports route=1 (Clear). For 214 Show, route=1 only
 * when reserve binds a new numeric peer; same-peer Show and Hide report route=0.
 * Clear requests a native sidecar clear, not permission to stop/replace native objects.
 * bound/sample/enabled/lease are zero in this batch. The typed policy may skip
 * all reads under a guard: no callback call is manufactured by this wrapper.
 *
 * Owned time masks (13 slots): 202/213/215/217=0x00ef, 212=0x10ef,
 * 214 show=0x01ff/hide=0x00ef, 216=0x10cc, 218=0x00cf. The original journal
 * emits Retain=1 or Clear=2 even for already-absent owned values; no Set occurs.
 * Unowned edits/coordinates are zero. Validate all179 atoms, metadata, all13
 * edits/coordinates and all15 correlated replies together, resolve native
 * sidecars, and re-prove exact actor/peer/Show ownership before one publication.
 * Writes are sequential, not concurrent atomic multi-buffer publication.
 * No ACK, authentication, route/resource admission, or native effect is granted. */
uint32_t beluga_core_network_adaptation_owner_clocked_event(
    const beluga_core_adaptation_owner_clocked_event_request_t *request,
    const beluga_core_adaptation_state_header_t *header,
    const beluga_core_adaptation_state_atom_t *atoms, uint32_t count,
    beluga_core_adaptation_owner_clock_callback_t callback, void *context,
    beluga_core_adaptation_state_header_t *output_header,
    beluga_core_adaptation_state_atom_t *output_atoms, uint32_t output_count,
    beluga_core_adaptation_owner_event_metadata_t *metadata,
    beluga_core_adaptation_time_edit_t *edits, uint32_t edit_count,
    beluga_core_adaptation_time_coordinate_t *coordinates, uint32_t coordinate_count,
    beluga_core_adaptation_clock_reply_t *reads, uint32_t read_count);


/* Addendum to beluga_core.h after the existing Owner/time/clock PODs, inside
 * its extern-C guard. SOURCE ONLY: no compiled or installed ABI claim. */
enum {
    BELUGA_CORE_ADAPTATION_OWNER_PREPARE = 501,
    BELUGA_CORE_ADAPTATION_PREPARED_DOMAIN = 4,
    BELUGA_CORE_ADAPTATION_PREPARED_PHASE = 3,
    BELUGA_CORE_ADAPTATION_PREPARED_ATOM_COUNT = 222
};

/* sizeof=56, align=8; offsets 0,4,8,16,24,32,40,44,48,52. */
typedef struct {
    uint32_t abi, operation;
    uint64_t invocation, source_generation, expected_revision, current_generation;
    uint32_t entry_flags, capacity_only, allows_resume, report_present;
} beluga_core_adaptation_owner_prepare_request_t;

/* sizeof=24, align=8; offsets 0,4,8,16,20. */
typedef struct {
    uint32_t abi, operation;
    uint64_t invocation;
    uint32_t prepared_present, reserved;
} beluga_core_adaptation_owner_prepare_outcome_t;

/* sizeof=192, align=8. peer0; fourteen u32 at8..60; six u64 at64..104;
 * fingerprint112 (64bytes), measurement_total_bits176, responses184.
 * Exact original nativeSnapshot facts, not cached diagnostic enrichment. */
typedef struct {
    uint64_t peer;
    uint32_t capture_active, automatically_suspended, strict;
    uint32_t incoming_present, equal_to_retained, observation_kind;
    uint32_t collection_sequence_present, bandwidth_present, current_rtt_present;
    uint32_t packets_present, delay_present, native_timestamp_present;
    uint32_t fingerprint_length, reserved;
    uint64_t collection_sequence, bandwidth_bits, current_rtt_bits;
    uint64_t packets, delay_bits, native_timestamp_bits;
    uint64_t fingerprint[8], measurement_total_bits, measurement_responses;
} beluga_core_adaptation_owner_report_t;

/* Exactly one actual full-Owner try_prepare_proposal call, never policy401.
 * Input header {1,2,1,179}; Some output header {1,4,3,222}. Required counts are
 * 179/222/13/13/15, and twelve numeric object ranges must be disjoint/aligned.
 * The callback is mandatory even on a zero-read branch. operation=501, abi=1,
 * invocation!=0; capacity_only/allows_resume/report_present are exact0/1.
 * entry_flags bits0..7: resume-context-absent, exact-peer, source-present,
 * sink-present, capture-valid, forwarding-valid, sink-allows, auto-suspended.
 * Other bits are denied. Entry peer/generation/revision/capture votes preserve
 * the original short-circuit semantics; there is no added stop/cancel vote.
 *
 * Return1 means completed Some or None, not adoption. Every non1 leaves all
 * seven output objects byte-unchanged: 2 shape/coordinate/consumed arithmetic,
 * 3 provider denial/budget, 4 reply correlation, 5 journal/origin/route witness.
 * Some: prepared_present=1, complete222/journals/coordinates/transcript.
 * None: prepared_present=0, zero header/222/edits/coordinates; metadata and
 * actual accepted reads remain correlated, even for a late None after reads.
 * Metadata scope=1, revision=original Owner revision; bound/sample/enabled/lease
 * are zero. Some metadata peer/fault/route reflect proposed policy; None peer
 * and faults reflect original Owner. Outcome reserved=0. Unused reads are zero.
 * Sequential output writes are not concurrent atomic publication.
 *
 * report_present=0 requires all192 report bytes zero. When present, flags and
 * optional presence fields are exact0/1; absent optional payloads are zero.
 * observation_kind0=nil/legacy,1=unavailable,2=measurement; non2 measurement
 * fields are zero. IEEE bits, all eight fingerprint words and original length
 * are preserved; overlong measurements reach existing subowner fault handling,
 * not truncation/hash/normalization. Native UTC timestamp is identity only.
 * observed_at is signed128 relative monotonic attoseconds in the existing Time
 * POD. It must be present on admitted entry; absent is allowed only on a pure
 * zero-read entry rejection. Present reports still structurally decode first.
 *
 * Original journals: Regular mask0x01ff, Capacity/Expiry mask0x00ef; unowned
 * edits/coordinates are zero. Retain=1/Clear=2, or Set=3 with the exact origin:
 * regular explicit PolicyObservedAt index0 and allowed original delta; sparse
 * deadline may alias CurrentInput ProbeDeadline index0, delta0. No ActualRead
 * origin is manufactured into these proposal policy times. All15 accepted
 * callback replies retain exact site/ordinal/invocation/native coordinate.
 * Route0=Retain,1=Clear,2=CopyIncoming; actual whole Optional values stay native.
 *
 * Caller owns valid initialized live exclusive buffers, stable borrowed input,
 * synchronous callback/context lifetime, no unwind, no buffer mutation, sticky
 * same-frame reentry refusal, original default-producer provenance, independently
 * derived lazy read permission and real Instant/route custody. Range checks do
 * not prove those obligations. This source boundary neither stores an Owner nor
 * grants actor/peer/native resource/effect/ACK/adoption authority. A genuine
 * native caller must validate all seven outputs together, resolve nine proposed
 * native policy Instants, retain original source+13Instants+anchor+whole routes,
 * and seal the one-use Prepared222 before any separate601/701 continuation. */
uint32_t beluga_core_network_adaptation_owner_prepare_event(
    const beluga_core_adaptation_owner_prepare_request_t *request,
    const beluga_core_adaptation_state_header_t *header,
    const beluga_core_adaptation_state_atom_t *atoms, uint32_t count,
    const beluga_core_adaptation_owner_report_t *report,
    const beluga_core_adaptation_time_coordinate_t *observed_at,
    beluga_core_adaptation_owner_clock_callback_t callback, void *context,
    beluga_core_adaptation_state_header_t *output_header,
    beluga_core_adaptation_state_atom_t *output_atoms, uint32_t output_count,
    beluga_core_adaptation_owner_event_metadata_t *metadata,
    beluga_core_adaptation_owner_prepare_outcome_t *outcome,
    beluga_core_adaptation_time_edit_t *edits, uint32_t edit_count,
    beluga_core_adaptation_time_coordinate_t *coordinates, uint32_t coordinate_count,
    beluga_core_adaptation_clock_reply_t *reads, uint32_t read_count);

/* Addendum to beluga_core.h, after the complete Owner/Prepared/time/clock PODs,
 * inside its extern-C guard. Source proposal, not a native custody grant. */
enum { BELUGA_CORE_ADAPTATION_OWNER_ADOPT_INACTIVE = 601 };

/* sizeof=32, align=8; offsets0,4,8,16,24,28. */
typedef struct {
    uint32_t abi, operation;
    uint64_t invocation, current_generation;
    uint32_t exact_peer, suspended;
} beluga_core_adaptation_owner_inactive_request_t;

/* sizeof=24, align=8; offsets0,4,8,16,20. */
typedef struct {
    uint32_t abi, operation;
    uint64_t invocation;
    uint32_t disposition, route;
} beluga_core_adaptation_owner_inactive_outcome_t;

/* One actual full-Owner try_adopt_inactive; no policy401 substitute or preview.
 * Request abi1, operation601, nonzero invocation; exact_peer/suspended are0/1.
 * Owner input header {1,2,1,179}, Prepared input {1,4,3,222}, result {1,2,2,179}.
 * Both full domains decode before stale entry. Exact counts179/222/179/13/13/15
 * precede pointer reads; all twelve known nonempty/aligned ranges are disjoint.
 * Callback mandatory even on a zero-read stale branch. Source generation and
 * expected revision come from Prepared; applying revision is NOT this fence.
 * There is no added capture/resource/resume-context/cancel/admission vote.
 *
 * Status1 completed: outcome echoes1/601/invocation; disposition0StaleReturn,
 * 1Adopted or2BeginNativeResume. The last is only a scalar decision, not native
 * resume authority. Route0Retain/1Clear/2CopyIncoming. Metadata scope2, same
 * route, actual accepted read_count, resulting revision/peer/faults;
 * bound/sample/enabled/lease remain0. Transcript unused tail is canonical0.
 * Non1 leaves every output unchanged:2 shape/range/coordinate/arithmetic,
 * 3 provider denial/budget,4 reply correlation,5 journal/source/route/rev/tail.
 * Successful writes to seven output objects are sequential, not concurrently
 * atomic publication. Five scalar input buffers stay unchanged.
 *
 * Stale emits the exact original179 atoms with result phase2, unchanged
 * revision/tail, Retain route, zero reads, nine current-policy Retain edits and
 * original coordinates. Admitted continuation copies the complete Prepared
 * policy, wraps current revision exactly once and preserves current atoms169
 * through178: fast/evidence/freshness/applied including IEEE payloads. All nine
 * policy Instant sidecars import CorrespondingPreparedInput(same slot)+0 or
 * Clear, even when coordinates are equal. A newly observed suspension RTT
 * fault may subsequently clear only slots0/1/2/3/5/6/7, never cooldown4 or RTT8.
 * Cadence9..11/evidence12 sidecars are zero and scalar owner tail is retained.
 * Mask0x01ff is representability, NOT clock or native-assignment permission.
 *
 * Route action and copied policy presence remain independent typed fields in
 * otherwise-admitted scalar pairs. Neither presence nor a decoded222 value
 * identifies the actual current/incoming Optional or proves native reachability.
 * Retain/Clear/Copy must eventually use same-owner actual current/nil/incoming
 * Optional custody retained by genuine501, never fabricate an object/token.
 *
 * Caller owns initialized valid/live exclusive POD, stable borrowed buffers,
 * exact synchronous callback/context lifetime, no unwind/mutation/reentry,
 * original supported default-producer provenance and independently derived
 * lazy []/L/LQ permission before each provider. Numeric ranges do not prove
 * pointer provenance, native currentness, immutable Optional/Instant custody,
 * prepared one-use sealing or those callback obligations. A future native
 * frame must retain original current179+13Instants+anchor and the same genuine
 * prepared222/nineInstants/routes, recapture original CURRENT (not Prepared),
 * validate all seven returned outputs, poison swallowed nested entry and
 * publish existing actor fields once. No active sender/await/failure/final
 * continuation, native effect, actor storage or product publication is wired. */
uint32_t beluga_core_network_adaptation_owner_adopt_inactive(
    const beluga_core_adaptation_owner_inactive_request_t *request,
    const beluga_core_adaptation_state_header_t *owner_header,
    const beluga_core_adaptation_state_atom_t *owner_atoms, uint32_t owner_count,
    const beluga_core_adaptation_state_header_t *prepared_header,
    const beluga_core_adaptation_state_atom_t *prepared_atoms, uint32_t prepared_count,
    beluga_core_adaptation_owner_clock_callback_t callback, void *context,
    beluga_core_adaptation_state_header_t *output_header,
    beluga_core_adaptation_state_atom_t *output_atoms, uint32_t output_count,
    beluga_core_adaptation_owner_event_metadata_t *metadata,
    beluga_core_adaptation_owner_inactive_outcome_t *outcome,
    beluga_core_adaptation_time_edit_t *edits, uint32_t edit_count,
    beluga_core_adaptation_time_coordinate_t *coordinates, uint32_t coordinate_count,
    beluga_core_adaptation_clock_reply_t *reads, uint32_t read_count);

/* Full Owner active-before-await decision; native actor wiring remains closed. */
enum { BELUGA_CORE_ADAPTATION_OWNER_BEGIN_ACTIVE = 701 };

/* sizeof=24, align=8; offsets0,4,8,16,20. */
typedef struct {
    uint32_t abi, operation;
    uint64_t invocation;
    uint32_t resource_flags, reserved;
} beluga_core_adaptation_owner_begin_active_request_t;

/* sizeof=32, align=8; offsets0,4,8,16,20,24,28. */
typedef struct {
    uint32_t abi, operation;
    uint64_t invocation;
    uint32_t disposition, route, prepared_present, reserved;
} beluga_core_adaptation_owner_begin_active_outcome_t;

/* One actual try_begin_active_apply on an unpublished local Owner draft.
 * Request abi1/op701/invocation!=0/reserved0; resource_flags bits0..5 describe
 * source/sink/capture/forwarding/base-dimensions/capturer presence, not authority.
 * Full Owner {1,2,1,179} and Prepared {1,4,3,222} decode before resource gating.
 * Exact counts179/222/179/222/13/13/15 and fourteen nonempty aligned disjoint
 * ranges precede pointer reads. Callback mandatory, including zero-read paths.
 * Status1: Owner {1,2,2,179}, outcome echoes request; disposition0Return,
 * 1NoNativeApply or2Apply. Route0Retain/1Clear. Return has prepared_present0
 * and zero returned Prepared header/222. Other dispositions retain the full
 * Prepared; only applying_revision atom170 may change. All Owner169..178 stay
 * exact, including IEEE payloads. Metadata scope2; bound/sample/enabled/lease0.
 * Restrictive fault retention precedes resource admission; attempt consumption
 * follows it. Preserve both separate wrapping revision sites and NaN comparison.
 * No peer/revision/capture/cancellation/resume vote is invented at this cut.
 * Nine owned policy journals are Retain/Clear; unowned9..12 edits/coordinates0.
 * All15 accepted replies retain exact correlation; unused transcript tail0.
 * Non1 leaves all nine outputs unchanged:2 shape/range/coordinate/arithmetic,
 * 3 provider denial/budget,4 correlation,5 forbidden assignment/result.
 * Successful output writes are sequential, not concurrently atomic.
 * Caller owns initialized live exclusive POD, stable five borrowed inputs,
 * actual synchronous callback/context lifetime, no unwind/reentry/mutation,
 * original native provenance and independent lazy read permission. Numeric
 * checks do not prove native resource/Optional/Instant/Prepared custody.
 * This API neither awaits nor grants a native effect or actor publication.
 * Genuine501 must seal one-use Prepared and native sidecars; the actor must
 * validate every output together and retain fresh original currentness.
 * Later failure703 deliberately publishes negative prefixes: never replace
 * that contract with this701 draft-discard refusal behavior. */
uint32_t beluga_core_network_adaptation_owner_begin_active(
    const beluga_core_adaptation_owner_begin_active_request_t *request,
    const beluga_core_adaptation_state_header_t *owner_header,
    const beluga_core_adaptation_state_atom_t *owner_atoms, uint32_t owner_count,
    const beluga_core_adaptation_state_header_t *prepared_header,
    const beluga_core_adaptation_state_atom_t *prepared_atoms, uint32_t prepared_count,
    beluga_core_adaptation_owner_clock_callback_t callback, void *context,
    beluga_core_adaptation_state_header_t *output_header,
    beluga_core_adaptation_state_atom_t *output_atoms, uint32_t output_count,
    beluga_core_adaptation_state_header_t *output_prepared_header,
    beluga_core_adaptation_state_atom_t *output_prepared_atoms, uint32_t output_prepared_count,
    beluga_core_adaptation_owner_event_metadata_t *metadata,
    beluga_core_adaptation_owner_begin_active_outcome_t *outcome,
    beluga_core_adaptation_time_edit_t *edits, uint32_t edit_count,
    beluga_core_adaptation_time_coordinate_t *coordinates, uint32_t coordinate_count,
    beluga_core_adaptation_clock_reply_t *reads, uint32_t read_count);


/* Post-await cuts remain separate: success702, failure703, fresh final704. */
enum {
    BELUGA_CORE_ADAPTATION_OWNER_FINISH_SUCCESS = 702,
    BELUGA_CORE_ADAPTATION_OWNER_FINISH_FAILURE = 703,
    BELUGA_CORE_ADAPTATION_OWNER_FINAL_ADOPT = 704
};

/* sizeof=32, align=8; offsets0,4,8,16,24,28.
 * facts bits0..8: exact peer/source/sink/capture authorization/forwarding
 * authorization, capture/forwarding authorization valid, sink active-use
 * permission, exact base dimensions. These are descriptions, NOT native grants.
 * Success702/failure703 permit facts0..511. Final704 permits only facts0..1
 * for a separately fresh exact-peer sample, never reused success facts. */
typedef struct {
    uint32_t abi, operation;
    uint64_t invocation, current_generation;
    uint32_t facts, reserved;
} beluga_core_adaptation_owner_completion_request_t;

typedef beluga_core_adaptation_owner_completion_request_t
    beluga_core_adaptation_owner_failure_request_t;

/* sizeof=32, align=8; offsets0,4,8,16,20,24,28. */
typedef struct {
    uint32_t abi, operation;
    uint64_t invocation;
    uint32_t disposition, route, fps_changed, reserved;
} beluga_core_adaptation_owner_completion_outcome_t;

/* Synchronous nonthrowing effect thunk. Its trusted caller-owned context must
 * retain the original capturer/base dimensions and exact native authority.
 * No await, reentry, unwind, denial, or mutation of borrowed input/output POD.
 * The thunk is mandatory for702 even when no output effect is reached. */
typedef void (*beluga_core_adaptation_owner_output_callback_t)(
    void *context, uint64_t invocation, int64_t fps);

/* Request abi1/op702/invocation!=0/reserved0. Counts179/222/179/13/13;
 * eleven aligned nonempty disjoint numeric ranges before any pointer reads.
 * Full Owner {1,2,1,179} and Prepared {1,4,3,222} decode BEFORE native output.
 * The success fence checks all nine facts, generation and applying revision.
 * Status1/disposition0 requests rollback of the exact returned native handle:
 * unchanged Owner, no callback. Status1/disposition1 records only applied
 * recommendation atoms173..178, without policy/revision or time adoption.
 * route0 and fps_changed0/1. Conditional changed-FPS callback runs exactly once
 * AFTER all fallible result/journal/Int32 validation, BEFORE six output writes.
 * After it there is no error branch, await, allocation or fallible publication.
 * Nine owned time slots Retain; unowned9..12 zero. Non1 leaves all six outputs
 * untouched AND invokes no effect:2 shape/range/domain,5 invalid result/journal.
 * Numeric pointer checking does not prove initialized allocation, provenance,
 * resource custody or actor serialization; output writes are not concurrent
 * atomic publication. Genuine one-use501 Prepared/native sidecars, the exact
 * returned handle and synchronized infallible native publication remain caller
 * obligations. Do not use a fallible generic importer after the output thunk.
 * Actual native adapter enrollment remains closed. */
uint32_t beluga_core_network_adaptation_owner_finish_success(
    const beluga_core_adaptation_owner_completion_request_t *request,
    const beluga_core_adaptation_state_header_t *owner_header,
    const beluga_core_adaptation_state_atom_t *owner_atoms, uint32_t owner_count,
    const beluga_core_adaptation_state_header_t *prepared_header,
    const beluga_core_adaptation_state_atom_t *prepared_atoms, uint32_t prepared_count,
    beluga_core_adaptation_owner_output_callback_t callback, void *context,
    beluga_core_adaptation_state_header_t *output_header,
    beluga_core_adaptation_state_atom_t *output_atoms, uint32_t output_count,
    beluga_core_adaptation_owner_event_metadata_t *metadata,
    beluga_core_adaptation_owner_completion_outcome_t *outcome,
    beluga_core_adaptation_time_edit_t *edits, uint32_t edit_count,
    beluga_core_adaptation_time_coordinate_t *coordinates, uint32_t coordinate_count);

/* Synchronous pre-effect validation of the ACTUAL private evaluated bundle.
 * Counts179/13/13; borrowed const pointers expire when this call returns. The
 * trusted context completes lossless native import/currentness validation and
 * may retain its sealed imported draft, not these foreign pointers. No await,
 * reentry, unwind, concurrent borrowed-POD access/mutation, native effect,
 * resource acquisition, clock read or actor-state publication. Finish every
 * allocation, conversion and sticky/currentness check before accepting. Native
 * custody and callback lifetime are caller obligations, not numeric proof.
 * Only return1 accepts; every other code denies the FPS thunk and output writes.
 * This relies on the trusted validator honoring its effect-free contract. */
typedef uint32_t (*beluga_core_adaptation_owner_validation_callback_t)(
    void *context, uint64_t invocation,
    const beluga_core_adaptation_state_header_t *header,
    const beluga_core_adaptation_state_atom_t *atoms, uint32_t atom_count,
    const beluga_core_adaptation_owner_event_metadata_t *metadata,
    const beluga_core_adaptation_owner_completion_outcome_t *outcome,
    const beluga_core_adaptation_time_edit_t *edits, uint32_t edit_count,
    const beluga_core_adaptation_time_coordinate_t *coordinates, uint32_t coordinate_count);

/* Additive702. All original shape/count/domain/Int32 rules above apply. BOTH
 * thunks are mandatory before any input read. Evaluate exactly once and invoke
 * validator exactly once on every valid bundle, including stale rollback and
 * same-FPS/no-applied paths. Non1 validator return yields status3, zero FPS and
 * six unchanged destination outputs. On acceptance, conditional FPS precedes
 * infallible six writes; no second evaluation/fence or fallible post-effect
 * importer is permitted. Old finish_success and final_adopt remain unchanged.
 * This scalar boundary does not activate native actor/production enrollment. */
uint32_t beluga_core_network_adaptation_owner_finish_success_validated(
    const beluga_core_adaptation_owner_completion_request_t *request,
    const beluga_core_adaptation_state_header_t *owner_header,
    const beluga_core_adaptation_state_atom_t *owner_atoms, uint32_t owner_count,
    const beluga_core_adaptation_state_header_t *prepared_header,
    const beluga_core_adaptation_state_atom_t *prepared_atoms, uint32_t prepared_count,
    beluga_core_adaptation_owner_validation_callback_t validator,
    beluga_core_adaptation_owner_output_callback_t callback, void *context,
    beluga_core_adaptation_state_header_t *output_header,
    beluga_core_adaptation_state_atom_t *output_atoms, uint32_t output_count,
    beluga_core_adaptation_owner_event_metadata_t *metadata,
    beluga_core_adaptation_owner_completion_outcome_t *outcome,
    beluga_core_adaptation_time_edit_t *edits, uint32_t edit_count,
    beluga_core_adaptation_time_coordinate_t *coordinates, uint32_t coordinate_count);

/* sizeof=32, align=8; offsets0,4,8,16,20,24,28. */
typedef struct {
    uint32_t abi, operation;
    uint64_t invocation;
    uint32_t disposition, route, semantic_error, attempted_reads;
} beluga_core_adaptation_owner_failure_outcome_t;

/* Request abi1/op703/invocation!=0/facts0..511/reserved0.
 * Counts179/222/179/13/13/15; twelve aligned nonempty disjoint numeric ranges.
 * Required synchronous clock callback/context has the original correlation,
 * lazy permission, no-unwind/reentry/mutation and native sidecar obligations.
 * Shape rejection2 precedes semantic retention. Generated-invalid5 publishes
 * nothing and requires fail-closed recovery, not successful Swift fallback.
 * Status1 publishes ALL SEVEN valid outputs, including semantic_error2/3/4:
 * disposition0 stale,1 retained ordinary,2 retained fast identity,3 adopted
 * terminal negative,4 semantic-error prefix. Caller MUST import a valid prefix
 * before propagating its semantic error; do not discard it as a701 refusal.
 * Preserve negative startup/attempt retention and capacity pre-F/pre-Q writes.
 * Revision increments once only on complete nonstale retention, never a prefix.
 * Metadata read_count counts accepted correlated replies; attempted_reads
 * counts all cuts including a rejected final cut. Unused15 reply tail zero.
 * route0Retain/1Clear/2CopyIncoming; copying absent Optional remains explicit.
 * Owner169..178 stays exact. Nine policy journal slots retain/clear or import
 * corresponding genuine Prepared; unowned9..12 zero. Non1 changes no outputs.
 * Scalar output writes are sequential, not actor adoption or native authority.
 * Sender failure yielded no handle; this grants no rollback/output effect. */
uint32_t beluga_core_network_adaptation_owner_finish_failure(
    const beluga_core_adaptation_owner_failure_request_t *request,
    const beluga_core_adaptation_state_header_t *owner_header,
    const beluga_core_adaptation_state_atom_t *owner_atoms, uint32_t owner_count,
    const beluga_core_adaptation_state_header_t *prepared_header,
    const beluga_core_adaptation_state_atom_t *prepared_atoms, uint32_t prepared_count,
    beluga_core_adaptation_owner_clock_callback_t callback, void *context,
    beluga_core_adaptation_state_header_t *output_header,
    beluga_core_adaptation_state_atom_t *output_atoms, uint32_t output_count,
    beluga_core_adaptation_owner_event_metadata_t *metadata,
    beluga_core_adaptation_owner_failure_outcome_t *outcome,
    beluga_core_adaptation_time_edit_t *edits, uint32_t edit_count,
    beluga_core_adaptation_time_coordinate_t *coordinates, uint32_t coordinate_count,
    beluga_core_adaptation_clock_reply_t *reads, uint32_t read_count);

/* Request abi1/op704/invocation!=0/facts0..1/reserved0. Same eleven ranges/counts
 * as702; no callback. A SEPARATELY FRESH exact peer/generation/applying revision
 * fence follows native output/applied recording, not cached pre-output facts.
 * Status1/disposition0 leaves Owner unchanged; disposition1 imports complete
 * Prepared policy atoms0..167 and wraps Owner revision once at atom168.
 * Owner169..178 remains exact; fps_changed0, reserved0; route0/1/2.
 * Each present owned time uses its corresponding Prepared origin, even equal
 * coordinates; absent times Clear; four unowned sidecars zero. Non1 leaves six
 * outputs unchanged (2 malformed input,5 invalid journal/result). Native route,
 * Optional/Instant and one-use custody are not reconstructed from scalar bits.
 * This API neither repeats702's effect nor authorizes actor/native adoption. */
uint32_t beluga_core_network_adaptation_owner_final_adopt(
    const beluga_core_adaptation_owner_completion_request_t *request,
    const beluga_core_adaptation_state_header_t *owner_header,
    const beluga_core_adaptation_state_atom_t *owner_atoms, uint32_t owner_count,
    const beluga_core_adaptation_state_header_t *prepared_header,
    const beluga_core_adaptation_state_atom_t *prepared_atoms, uint32_t prepared_count,
    beluga_core_adaptation_state_header_t *output_header,
    beluga_core_adaptation_state_atom_t *output_atoms, uint32_t output_count,
    beluga_core_adaptation_owner_event_metadata_t *metadata,
    beluga_core_adaptation_owner_completion_outcome_t *outcome,
    beluga_core_adaptation_time_edit_t *edits, uint32_t edit_count,
    beluga_core_adaptation_time_coordinate_t *coordinates, uint32_t coordinate_count);

/* Copied predicates only: no pointers, callbacks, clocks, native resources or owner admission.
 * Readiness/Watermark status: 0 invalid envelope; 1 evaluated (a false vote is legitimate).
 * Freshness status: 0 invalid; 1 evaluated; 2 NeedsNow with fresh=0, not permission to read a clock.
 * ABI is 1; all reserved fields must be zero when their carrier is decoded.
 * Flags/presence decode only 0/1. Absent outer Watermark ignores its four field carriers;
 * absent previous Progress ignores that Progress but still requires previous_reserved=0.
 * OptionalU64 absence ignores value, not reserved. Zero/MAX values remain ordinary counters.
 * Refused Watermark and accepted absent/discontinuous samples preserve raw before exactly.
 * did_advance combines continuity with strict packet OR byte growth, never jitter/sample growth.
 * Native Swift retains the original peer/track/attempt/privacy/currentness and clock authority. */
typedef struct { uint32_t present, reserved; uint64_t value; }
    beluga_core_microphone_optional_u64_t;
typedef struct {
    uint32_t queue_running, reserved;
    uint64_t post_start_callback_count, successful_pull_count, successful_frame_count, enqueue_failure_count;
} beluga_core_microphone_progress_t;
typedef struct {
    uint32_t abi_version, reserved;
    beluga_core_microphone_progress_t current;
    uint32_t previous_present, previous_reserved;
    beluga_core_microphone_progress_t previous;
} beluga_core_microphone_readiness_facts_t;
typedef struct { uint32_t abi_version, status, ready, continuing; }
    beluga_core_microphone_readiness_result_t;
typedef struct {
    uint32_t present, reserved;
    beluga_core_microphone_optional_u64_t fields[4]; /* packets, bytes, jitter emitted, total samples */
} beluga_core_microphone_watermark_t;
typedef struct { uint32_t abi_version, reserved; beluga_core_microphone_watermark_t retained; }
    beluga_core_microphone_watermark_state_t;
typedef struct { uint32_t abi_version, reserved; beluga_core_microphone_watermark_t current; }
    beluga_core_microphone_watermark_event_t;
typedef struct {
    beluga_core_microphone_watermark_state_t state;
    uint32_t status, continuous, did_advance, reserved;
} beluga_core_microphone_watermark_result_t;
typedef struct {
    uint32_t abi_version, reserved;
    uint64_t advancement_count;
    int64_t consecutive_stale_samples;
    beluga_core_microphone_optional_u64_t deadline;
} beluga_core_microphone_freshness_state_t;
typedef struct {
    uint32_t abi_version, reserved;
    int64_t maximum_stale_samples;
    beluga_core_microphone_optional_u64_t now;
} beluga_core_microphone_freshness_event_t;
typedef struct { uint32_t abi_version, status, fresh, reserved; }
    beluga_core_microphone_freshness_result_t;

beluga_core_microphone_readiness_result_t beluga_core_microphone_forwarding_readiness_decide(
    beluga_core_microphone_readiness_facts_t facts);
beluga_core_microphone_watermark_result_t beluga_core_microphone_forwarding_watermark_step(
    beluga_core_microphone_watermark_state_t before, beluga_core_microphone_watermark_event_t event);
beluga_core_microphone_freshness_result_t beluga_core_microphone_forwarding_freshness_decide(
    beluga_core_microphone_freshness_state_t before, beluga_core_microphone_freshness_event_t event);

/* Whole-field result correlation against the unchanged raw function above.
 * Return exactly 1 only for a matching accepted result, otherwise 0.
 * Readiness/Watermark expected status must be 1; Freshness may be 1 or 2.
 * A matching invalid status-0 result is NEVER valid. All returned fields,
 * including reserved/absent payload fields in a preserved state, must match.
 * By-value/POD only; no pointers, callbacks or clock/native authority. */
uint32_t beluga_core_microphone_forwarding_readiness_result_is_valid(
    beluga_core_microphone_readiness_facts_t facts,
    beluga_core_microphone_readiness_result_t result);
uint32_t beluga_core_microphone_forwarding_watermark_result_is_valid(
    beluga_core_microphone_watermark_state_t before,
    beluga_core_microphone_watermark_event_t event,
    beluga_core_microphone_watermark_result_t result);
uint32_t beluga_core_microphone_forwarding_freshness_result_is_valid(
    beluga_core_microphone_freshness_state_t before,
    beluga_core_microphone_freshness_event_t event,
    beluga_core_microphone_freshness_result_t result);

/* One copied per-key retry row, not native authority. ABI1; reserved fields0.
 * Config: sizeof16/align8/offsets0,4,8; maximum>=1, supplied after native clamp.
 * State: sizeof24/align8/offsets0,4,8,12,16; present/may_retry only0/1.
 * Absent requires count0/may_retry0; present requires count>=1. Above-cap counts
 * remain valid and deny retry; no clamp/reset. Event: sizeof16/align4/offsets
 * 0,4,8,12. Opcodes1 Eligible,2 RecordAttempt,3 RetryFailure,4 Exhaust.
 * Categories1 monitoring,2 output,3 start,4 admission,5 readiness,6 source
 * stalled,7 format,8 clock,9 enqueue,10 progress,11 bridge refusal; only
 * RetryFailure uses a category. Eligible/RetryFailure use bridge_faulted0/1;
 * RecordAttempt/Exhaust require it0. Other unused category fields require0.
 * Result: sizeof40/align8/offsets0,24,28,32,36; status0 invalid vs1 accepted.
 * Decision is a vote only for Eligible/RetryFailure. Redrive0 Retain,1 Clear,
 * 2 Request; absent Exhaust Retains, never creates history. Accepted false
 * RetryFailure preserves the whole prior row. Record uses checked signed
 * increment: overflow refuses with exact input retention, never wraps.
 * Native code owns keys/FIFO, exact resources/privacy/guard, row publication,
 * await fences and fault cleanup. No pointers, callbacks, clocks or resets. */
typedef struct { uint32_t abi_version, reserved; int64_t maximum_attempt_count; }
    beluga_core_microphone_forwarding_retry_config_t;
typedef struct {
    uint32_t abi_version, present, may_retry, reserved;
    int64_t count;
} beluga_core_microphone_forwarding_retry_state_t;
typedef struct { uint32_t opcode, failure_category, bridge_faulted, reserved; }
    beluga_core_microphone_forwarding_retry_event_t;
typedef struct {
    beluga_core_microphone_forwarding_retry_state_t state;
    uint32_t status, decision, redrive_action, reserved;
} beluga_core_microphone_forwarding_retry_result_t;

beluga_core_microphone_forwarding_retry_result_t beluga_core_microphone_forwarding_retry_step(
    beluga_core_microphone_forwarding_retry_config_t config,
    beluga_core_microphone_forwarding_retry_state_t before,
    beluga_core_microphone_forwarding_retry_event_t event);
/* Whole-field correlation through the unchanged pure step. Exactly1 only for
 * matching status1, including legitimate false. Matching status0 is never valid.
 * This re-evaluation has no side effects and grants no native custody. */
uint32_t beluga_core_microphone_forwarding_retry_result_is_valid(
    beluga_core_microphone_forwarding_retry_config_t config,
    beluga_core_microphone_forwarding_retry_state_t before,
    beluga_core_microphone_forwarding_retry_event_t event,
    beluga_core_microphone_forwarding_retry_result_t result);


/* Copied updater admission/menu presentation. Request ABI1 and only bits0..8:
 * interactive, active media, pending pairing, shares, teardown complete,
 * release, task present, needs readiness, failed. Request sizeof8/align4.
 * Result sizeof24/align4; status0 valid,1 invalid; booleans exactly0/1;
 * kinds0 development,1 recovery,2 owned,3 ready,4 unavailable.
 * Native Bundle/task/callback/signing/IPC/resource authority stays native.
 * The whole-result verifier returns exactly1 only for valid-input correlation;
 * even the exact conservative invalid denial cannot certify an ordinary vote. */
typedef struct { uint32_t abi_version, flags; }
    beluga_core_update_admission_request_t;
typedef struct {
    uint32_t abi_version, status, permits_update, is_in_progress, can_check, status_kind;
} beluga_core_update_admission_result_t;

beluga_core_update_admission_result_t beluga_core_update_admission_decide(
    beluga_core_update_admission_request_t request);
uint32_t beluga_core_update_admission_result_is_valid(
    beluga_core_update_admission_request_t request,
    beluga_core_update_admission_result_t result);

/* Copied two-phase manual SDK callback admission; sizeof12/align4 for both.
 * ABI1; phase1 flags exact callback/manual/pre-callback running=bits0/1/2;
 * phase2 flags retained/fresh requested=bits0/1. Native authority is invoked
 * between verified phases. No SDK object or callback crosses this boundary. */
typedef struct { uint32_t abi_version, phase, flags; }
    beluga_core_update_sparkle_admission_request_t;
typedef struct {
    uint32_t abi_version, status, action;
} beluga_core_update_sparkle_admission_result_t;
/* status0 valid,1 invalid. action0 none,1 foreign,2 non-manual,
 * 3 authority-not-retained,4 not-requested,5 query-authority,6 consume/admit. */
beluga_core_update_sparkle_admission_result_t beluga_core_update_sparkle_admission_decide(
    beluga_core_update_sparkle_admission_request_t request);
uint32_t beluga_core_update_sparkle_admission_result_is_valid(
    beluga_core_update_sparkle_admission_request_t request,
    beluga_core_update_sparkle_admission_result_t result);

/* Copied fresh-unarmed inner selector only: both records sizeof12/align4 and
 * three uint32 fields at offsets0/4/8. ABI1. Request flags only bits0..18:
 * no-update present/same finished; bound/admitted/decline present; cancelled;
 * failure acknowledged/abort/same finished; initial presentation; candidate
 * attempted/presented/binding; found item; finished error; decline SDK choice;
 * bound/admitted/found equal decline. Separate failure_kind0 absent,1 feed
 * fetch,2 feed parse/signature. Results status0 valid,1 invalid; reasons0 none,
 * 1 no-update,2 feed fetch failure,3 feed parse failure,4 cancellation,5 decline.
 * Unknown ABI/flags/kind yields ABI1/status1/reason0; whole verifier returns1
 * only valid complete request/result correlation. Exact invalid refusal is0.
 * Native eligibility, SDK idle, retained authority, object identity comparison,
 * candidate payload, observations and one-use retirement remain native. */
typedef struct { uint32_t abi_version, flags, failure_kind; }
    beluga_core_update_unarmed_completion_request_t;
typedef struct { uint32_t abi_version, status, reason; }
    beluga_core_update_unarmed_completion_result_t;
beluga_core_update_unarmed_completion_result_t beluga_core_update_unarmed_completion_decide(
    beluga_core_update_unarmed_completion_request_t request);
uint32_t beluga_core_update_unarmed_completion_result_is_valid(
    beluga_core_update_unarmed_completion_request_t request,
    beluga_core_update_unarmed_completion_result_t result);

/* Copied abort classifier. ABI1; flags bits0..5:
 * failure present,clean cycle,acknowledged,abort observed,same failure error,
 * same no-update error. First-if priority: present && clean && ack &&
 * !observed && same failure -> action1 mark; otherwise same no-update ->
 * action2 preserve; otherwise action3 poison. Invalid ABI/unknown flags
 * produce ABI1/status1/action0. Verifier returns exactly1 only for complete
 * valid correlation. Native identity, failure payload, mutation and emit stay native. */
typedef struct { uint32_t abi_version, flags; } beluga_core_update_abort_request_t;
typedef struct { uint32_t abi_version, status, action; } beluga_core_update_abort_result_t;
beluga_core_update_abort_result_t beluga_core_update_abort_decide(
    beluga_core_update_abort_request_t request);
uint32_t beluga_core_update_abort_result_is_valid(
    beluga_core_update_abort_request_t request,
    beluga_core_update_abort_result_t result);

/* Copied source preparation/match predicates. ABI1, reserved0, flags only bits0..6.
 * Prepare flags: native continuity/video valid, seek, playing, pause, duration/position present.
 * Match flags: native continuity/video equal, playing, pause, seek, duration/position present.
 * All Double fields are raw IEEE-754 bits; missing values are separate flags.
 * Sizes/alignments: prepare56/8, match88/8, result16/4.
 * Result status0 malformed,1 ordinary; allowed0/1, reserved0. Validators return1
 * only for whole valid-input correlation. No native ownership or pause authority. */
/* Every floating field is the original IEEE-754 Double.bitPattern, not a cast. */
typedef struct {
    uint32_t abi_version;
    uint32_t reserved;
    uint64_t flags;
    uint64_t position;
    uint64_t duration;
    uint64_t rate;
    uint64_t observed_at_page_ms;
    uint64_t phone_position;
} beluga_core_handoff_source_prepare_facts_t;

typedef struct {
    uint32_t abi_version;
    uint32_t reserved;
    uint64_t flags;
    uint64_t anchor_position;
    uint64_t anchor_duration;
    uint64_t anchor_rate;
    uint64_t anchor_observed_at_page_ms;
    uint64_t phone_position;
    uint64_t current_position;
    uint64_t current_duration;
    uint64_t current_rate;
    uint64_t current_observed_at_page_ms;
} beluga_core_handoff_source_match_facts_t;

typedef struct {
    uint32_t abi_version;
    uint32_t status;
    uint32_t allowed;
    uint32_t reserved;
} beluga_core_handoff_source_result_t;

beluga_core_handoff_source_result_t beluga_core_handoff_source_prepare(
    beluga_core_handoff_source_prepare_facts_t facts);
beluga_core_handoff_source_result_t beluga_core_handoff_source_matches(
    beluga_core_handoff_source_match_facts_t facts);
uint32_t beluga_core_handoff_source_prepare_result_is_valid(
    beluga_core_handoff_source_prepare_facts_t facts, beluga_core_handoff_source_result_t result);
uint32_t beluga_core_handoff_source_matches_result_is_valid(
    beluga_core_handoff_source_match_facts_t facts, beluga_core_handoff_source_result_t result);


/* Copied input-lease coordinator votes only. ABI1; Facts sizeof32/align8,
 * Result sizeof20/align4. Opcodes1 budget,2 acquisition outcome,3 release
 * continuation,4 release outcome. Result status1 accepted,0 refused; actions
 * 1..10 are operation-correlated. Invalid ABI/reserved/opcode/domain produces
 * ABI1/status0/opcode0/action0/reserved0. The verifier returns exactly1 only
 * for complete valid facts/result correlation; canonical refusal is invalid.
 * No route, generation, native key, authorization, listener, clock or effect
 * crosses this scalar boundary. Native ownership/context remains in Swift. */
typedef struct {
    uint32_t abi_version, opcode, disposition, reserved;
    int64_t attempt_count, maximum_attempt_count;
} beluga_core_microphone_input_lease_facts_t;
typedef struct {
    uint32_t abi_version, status, opcode, action, reserved;
} beluga_core_microphone_input_lease_result_t;
beluga_core_microphone_input_lease_result_t beluga_core_microphone_input_lease_decide(
    beluga_core_microphone_input_lease_facts_t facts);
uint32_t beluga_core_microphone_input_lease_result_is_valid(
    beluga_core_microphone_input_lease_facts_t facts,
    beluga_core_microphone_input_lease_result_t result);

/* ABI1 copied output-format facts only. Native getters, queue identity and
 * startup/privacy/cleanup effects remain native. Facts80/8, observation56/8,
 * result96/8. Float fields carry original IEEE-754 bits, never numeric casts.
 * status1 includes all16 legitimate first-rejection reasons as well as success;
 * status0 is malformed wire and never validates. Rejections copy only their
 * exact offending signed status/u32/rate bits; success copies all12 observations.
 * Whole-result validator returns exactly1 only for valid correlated facts. */
typedef struct {
    uint32_t abi_version, wire_reserved;
    int32_t stream_description_status, device_sample_rate_status;
    int32_t device_channel_count_status, converter_error_read_status;
    uint64_t stream_sample_rate_bits;
    uint32_t stream_format_id, stream_format_flags;
    uint32_t stream_bytes_per_packet, stream_frames_per_packet;
    uint32_t stream_bytes_per_frame, stream_channels_per_frame;
    uint32_t stream_bits_per_channel, stream_reserved;
    uint64_t device_sample_rate_bits;
    uint32_t device_channel_count, converter_error;
} beluga_core_microphone_output_format_facts_t;
typedef struct {
    uint64_t sample_rate_bits;
    uint32_t format_id, format_flags, bytes_per_packet, frames_per_packet;
    uint32_t bytes_per_frame, channels_per_frame, bits_per_channel, stream_reserved;
    uint64_t device_sample_rate_bits;
    uint32_t device_channel_count, converter_error;
} beluga_core_microphone_output_format_observation_t;
typedef struct {
    uint32_t abi_version, status, accepted, reason;
    int32_t actual_core_audio_status;
    uint32_t actual_u32;
    uint64_t actual_rate_bits;
    beluga_core_microphone_output_format_observation_t observation;
    uint64_t wire_reserved;
} beluga_core_microphone_output_format_result_t;
beluga_core_microphone_output_format_result_t beluga_core_microphone_output_format_decide(
    beluga_core_microphone_output_format_facts_t facts);
uint32_t beluga_core_microphone_output_format_result_is_valid(
    beluga_core_microphone_output_format_facts_t facts,
    beluga_core_microphone_output_format_result_t result);

#ifdef __cplusplus
}
#endif

#endif
