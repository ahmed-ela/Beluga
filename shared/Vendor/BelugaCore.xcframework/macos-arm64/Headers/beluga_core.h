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

#ifdef __cplusplus
}
#endif

#endif
