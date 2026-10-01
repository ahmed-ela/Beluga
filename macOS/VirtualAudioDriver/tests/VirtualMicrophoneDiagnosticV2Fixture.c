#include "OpensteamerVirtualMicrophoneDriver.h"
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Offline Swift decoder fixture. Its layout comes from the production header;
 * it never loads an installed driver or opens any audio device. */
int main(int argc, char **argv) {
  if (argc != 4) return 2;
  const char *mode = argv[1];
  const bool active = strcmp(mode, "active-overflow") == 0;
  const bool revision = strcmp(mode, "new-registry-revision") == 0;
  const bool identity = strcmp(mode, "new-registry-identity") == 0;
  const bool failure = strcmp(mode, "failure-evidence") == 0;
  if (!active && !revision && !identity && !failure &&
      strcmp(mode, "idle-overflow") != 0) return 3;

  enum { kFixtureCount = 70 };
  const size_t byteCount = sizeof(OSVADiagnosticSnapshotV2Header) +
      kFixtureCount * sizeof(OSVADiagnosticRegistryClientSnapshot);
  unsigned char *bytes = calloc(1, byteCount);
  if (bytes == NULL) return 4;
  OSVADiagnosticSnapshotV2Header *header = (void *)bytes;
  OSVADiagnosticRegistryClientSnapshot *records =
      (void *)(bytes + sizeof(*header));
  header->schema_version = kOSVADiagnosticSnapshotV2SchemaVersion;
  header->header_size = sizeof(*header);
  header->total_byte_count = byteCount;
  header->registry_record_count = kFixtureCount;
  header->registry_record_size = sizeof(*records);
  header->registry_revision = kFixtureCount + (revision || active || failure);
  header->core_slot_capacity = kOSVADiagnosticClientSlotCapacity;
  OSVADiagnosticSnapshotV2State *state = &header->state;
  state->snapshot_sequence = strtoull(argv[2], NULL, 10);
  state->captured_host_ticks = strtoull(argv[3], NULL, 10);
  state->driver_instance_generation = 77;
  state->driver_lifecycle_sequence = 72;
  state->core_lifecycle_sequence = 8;
  state->host_ticks_per_second = 24000000;
  state->last_issued_seed = 7;
  state->last_issued_session_id = 11;
  state->global_start_attempt_count = state->global_start_transition_count = 1;
  state->global_stop_attempt_count = state->global_stop_transition_count = 1;
  state->seed_create_count = state->seed_clear_count = 1;
  state->driver_registered_count = kFixtureCount;
  state->visible_driver_registered_count = kFixtureCount / 2;
  state->hidden_driver_registered_count = kFixtureCount / 2;
  state->driver_client_add_attempt_count = kFixtureCount;
  state->driver_client_add_count = kFixtureCount;
  state->invariant_flags =
      kOSVADiagnosticSnapshotCoreInitialized |
      kOSVADiagnosticInvariantGlobalMatchesCoreSlots |
      kOSVADiagnosticInvariantEndpointsMatchCoreSlots |
      kOSVADiagnosticInvariantDriverStartsMatchCoreSlots |
      kOSVADiagnosticInvariantIdleImpliesClockCleared |
      kOSVADiagnosticInvariantActiveImpliesClockValid |
      kOSVADiagnosticInvariantActiveSlotCountsWithinCapacity |
      kOSVADiagnosticInvariantStartStopBalancedAtIdle |
      kOSVADiagnosticInvariantSeedCreateClearBalancedAtIdle |
      kOSVADiagnosticInvariantRingGenerationMatchesCurrentSeed |
      kOSVADiagnosticInvariantNoActiveSlotReferencesRetiredGeneration |
      kOSVADiagnosticInvariantCompleteRegistryInventory;
  for (size_t index = 0; index < kFixtureCount; ++index) {
    OSVADiagnosticDriverClientSlotSnapshot *client = &records[index].client;
    records[index].registry_index = index;
    client->generation = index + 1;
    client->registration_host_ticks = client->last_transition_host_ticks = 1;
    client->flags = kOSVADiagnosticDriverSlotRegistered;
    client->device_object_id = index % 2 == 0 ?
        kOSVAObjectIDVisibleInputDevice : kOSVAObjectIDHiddenWriterDevice;
    client->client_id = (UInt32)index + 1000;
    client->process_id = (SInt32)index + 2000;
    client->endpoint_role = index % 2 == 0 ?
        kOSVADiagnosticEndpointVisibleInput : kOSVADiagnosticEndpointHiddenWriter;
    client->core_client_slot = UINT32_MAX;
  }
  if (identity) records[69].client.process_id += 1;
  if (active) {
    state->invariant_flags |= kOSVADiagnosticSnapshotTimelineActive;
    state->timeline_seed = state->current_seed_generation = 7;
    state->anchor_host_ticks = 1;
    state->active_client_count = state->hidden_writer_active_count = 1;
    state->core_active_slot_count = state->core_active_slot_bitmap = 1;
    state->driver_started_count = state->hidden_driver_started_count = 1;
    state->global_start_attempt_count = state->global_start_transition_count = 2;
    state->seed_create_count = 2;
    OSVADiagnosticDriverClientSlotSnapshot *client = &records[69].client;
    client->flags |= kOSVADiagnosticDriverSlotStarted |
        kOSVADiagnosticDriverSlotLeaseValid;
    client->start_host_ticks = client->last_transition_host_ticks = 2;
    client->lease_session_id = 11;
    client->lease_timeline_seed = 7;
    client->core_client_slot = 0;
    client->io_start_depth = 1;
    header->core_client_slots[0] = (OSVADiagnosticCoreClientSlotSnapshot){
        .session_id = 11,
        .client_id = ((UInt64)client->device_object_id << 32) | client->client_id,
        .timeline_seed = 7,
        .endpoint_role = kOSVADiagnosticEndpointHiddenWriter,
    };
  }
  if (failure) {
    state->driver_client_add_attempt_count += 1;
    state->zero_timestamp[0].epoch_mapping_unavailable_count = 2;
    state->io[1].epoch_mapping_unavailable_count = 3;
    header->last_admission_failure = (OSVADiagnosticAdmissionFailureSnapshot){
        .sequence = 1,
        .host_ticks = 2,
        .registry_index = UINT64_MAX,
        .operation = kOSVADiagnosticAdmissionAdd,
        .reason = kOSVADiagnosticFailureRegistrationAllocation,
        .device_object_id = kOSVAObjectIDVisibleInputDevice,
        .client_id = 990,
        .process_id = 2114,
        .status = kAudioHardwareUnspecifiedError,
    };
  }
  const bool wrote = fwrite(bytes, byteCount, 1, stdout) == 1;
  free(bytes);
  return wrote ? 0 : 5;
}
