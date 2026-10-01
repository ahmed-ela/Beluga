#include "OpensteamerVirtualMicrophoneDriver.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Offline native ABI fixture only, never linked into the production helper.
 * The initialized state matches Driver.c's Initialize lifecycle=1 and the
 * core's zero lifecycle; it deliberately does not impersonate a public probe. */
int main(int argc, char **argv) {
  if (argc != 4) return 2;
  OSVADiagnosticSnapshotV2Header header = {0};
  header.schema_version = kOSVADiagnosticSnapshotV2SchemaVersion;
  header.header_size = sizeof(header);
  header.total_byte_count = sizeof(header);
  header.registry_record_size = sizeof(OSVADiagnosticRegistryClientSnapshot);
  header.core_slot_capacity = kOSVADiagnosticClientSlotCapacity;
  header.state.snapshot_sequence = strtoull(argv[2], NULL, 10);
  header.state.captured_host_ticks = strtoull(argv[3], NULL, 10);
  header.state.driver_instance_generation = 77;
  header.state.driver_lifecycle_sequence = 1;
  header.state.host_ticks_per_second = 24000000;
  header.state.invariant_flags =
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
  const char *mode = argv[1];
  if (strcmp(mode, "life-zero") == 0) header.state.driver_lifecycle_sequence = 0;
  else if (strcmp(mode, "history") == 0) header.state.driver_client_add_attempt_count = 1;
  else if (strcmp(mode, "revision") == 0) header.registry_revision = 1;
  else if (strcmp(mode, "retired-core") == 0) header.core_client_slots[63].client_id = 1;
  else if (strcmp(mode, "io-history") == 0) header.state.io[1].operation_call_count = 1;
  else if (strcmp(mode, "reserved") == 0) header.reserved[7] = 1;
  else if (strcmp(mode, "pristine") != 0) return 3;
  return fwrite(&header, sizeof(header), 1, stdout) == 1 ? 0 : 4;
}
