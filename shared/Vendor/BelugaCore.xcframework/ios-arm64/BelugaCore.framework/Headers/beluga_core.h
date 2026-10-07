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
#ifdef __cplusplus
}
#endif

#endif
