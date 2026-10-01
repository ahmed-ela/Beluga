#include "OpensteamerVirtualMicrophoneDriver.h"

#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>

#include <inttypes.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum {
  kReaderSchemaVersion = 1,
  kMaximumCoherenceAttempts = 8,
  kExitUsage = 64,
  kExitSchemaMismatch = 65,
  kExitPropertyUnavailable = 69,
  kExitInternalError = 70,
  kExitRetry = 75,
};

typedef enum SnapshotReadResult {
  kSnapshotReadOK = 0,
  kSnapshotReadSchemaMismatch,
  kSnapshotReadUnavailable,
  kSnapshotReadRetry,
  kSnapshotReadFailed,
} SnapshotReadResult;

typedef struct EndpointObservation {
  UInt64 snapshot_sequence;
  UInt64 captured_host_ticks;
} EndpointObservation;

_Static_assert(sizeof(AudioDeviceID) == sizeof(UInt32),
               "reader JSON assumes a 32-bit AudioDeviceID");
_Static_assert(sizeof(OSVADiagnosticTransitionSnapshot) == 72,
               "diagnostic transition schema changed");
_Static_assert(sizeof(OSVADiagnosticZeroTimestampSnapshot) == 136,
               "zero-timestamp diagnostic schema changed");
_Static_assert(sizeof(OSVADiagnosticIOSnapshot) == 208,
               "I/O diagnostic schema changed");
_Static_assert(sizeof(OSVADiagnosticIOWorkLoopSnapshot) == 72,
               "I/O work-loop diagnostic schema changed");
_Static_assert(sizeof(OSVADiagnosticSnapshot) ==
                   kOSVADiagnosticSnapshotByteCount,
               "diagnostic snapshot byte-count constant changed");
_Static_assert(sizeof(OSVADiagnosticSnapshot) <= UINT32_MAX,
               "diagnostic snapshot must fit Core Audio's UInt32 data size");
_Static_assert(kOSVADiagnosticEndpointVisibleInput == 1 &&
                   kOSVADiagnosticEndpointHiddenWriter == 2,
               "endpoint array indexing contract changed");

static AudioObjectPropertyAddress
PropertyAddress(AudioObjectPropertySelector selector) {
  AudioObjectPropertyAddress address = {
      .mSelector = selector,
      .mScope = kAudioObjectPropertyScopeGlobal,
      .mElement = kAudioObjectPropertyElementMain,
  };
  return address;
}

static OSStatus TranslateExactDeviceUID(const char *uid,
                                        AudioDeviceID *deviceID) {
  if (uid == NULL || deviceID == NULL) {
    return kAudio_ParamError;
  }
  *deviceID = kAudioObjectUnknown;
  CFStringRef qualifier = CFStringCreateWithCString(
      kCFAllocatorDefault, uid, kCFStringEncodingUTF8);
  if (qualifier == NULL) {
    return kAudio_MemFullError;
  }
  AudioObjectPropertyAddress address =
      PropertyAddress(kAudioHardwarePropertyTranslateUIDToDevice);
  UInt32 size = (UInt32)sizeof(*deviceID);
  const OSStatus status = AudioObjectGetPropertyData(
      kAudioObjectSystemObject, &address, (UInt32)sizeof(qualifier), &qualifier,
      &size, deviceID);
  CFRelease(qualifier);
  if (status != noErr) {
    return status;
  }
  return size == sizeof(*deviceID) ? noErr : kAudioHardwareBadPropertySizeError;
}

static bool DeviceUIDMatches(AudioDeviceID deviceID, const char *expectedUID) {
  if (deviceID == kAudioObjectUnknown || expectedUID == NULL) {
    return false;
  }
  AudioObjectPropertyAddress address =
      PropertyAddress(kAudioDevicePropertyDeviceUID);
  CFStringRef actualUID = NULL;
  UInt32 size = (UInt32)sizeof(actualUID);
  const OSStatus status = AudioObjectGetPropertyData(
      deviceID, &address, 0, NULL, &size, &actualUID);
  if (status != noErr || size != sizeof(actualUID) || actualUID == NULL ||
      CFGetTypeID(actualUID) != CFStringGetTypeID()) {
    if (actualUID != NULL) {
      CFRelease(actualUID);
    }
    return false;
  }
  CFStringRef expected = CFStringCreateWithCString(
      kCFAllocatorDefault, expectedUID, kCFStringEncodingUTF8);
  const bool matches = expected != NULL && CFEqual(actualUID, expected);
  if (expected != NULL) {
    CFRelease(expected);
  }
  CFRelease(actualUID);
  return matches;
}

static bool SnapshotSchemaIsExact(const OSVADiagnosticSnapshot *snapshot) {
  return snapshot != NULL &&
         snapshot->schema_version == kOSVADiagnosticSnapshotSchemaVersion &&
         snapshot->struct_size == sizeof(*snapshot) &&
         snapshot->client_slot_capacity ==
             kOSVADiagnosticClientSlotCapacity;
}

static SnapshotReadResult ResultForPropertyStatus(OSStatus status) {
  if (status == noErr) {
    return kSnapshotReadOK;
  }
  if (status == kAudioHardwareUnknownPropertyError) {
    return kSnapshotReadUnavailable;
  }
  if (status == kOSVADiagnosticSnapshotUnavailableError) {
    return kSnapshotReadRetry;
  }
  return kSnapshotReadFailed;
}

static SnapshotReadResult EvaluateCustomPropertyDeclarationsForSelector(
    const AudioServerPlugInCustomPropertyInfo *info, size_t count,
    AudioObjectPropertySelector selector) {
  if (info == NULL || count == 0) {
    return kSnapshotReadUnavailable;
  }
  bool found = false;
  for (size_t index = 0; index < count; ++index) {
    if (info[index].mSelector != selector) {
      continue;
    }
    if (found ||
        info[index].mPropertyDataType !=
            kAudioServerPlugInCustomPropertyDataTypeCFPropertyList ||
        info[index].mQualifierDataType !=
            kAudioServerPlugInCustomPropertyDataTypeNone) {
      return kSnapshotReadSchemaMismatch;
    }
    found = true;
  }
  return found ? kSnapshotReadOK : kSnapshotReadUnavailable;
}

static SnapshotReadResult EvaluateCustomPropertyDeclarations(
    const AudioServerPlugInCustomPropertyInfo *info, size_t count) {
  return EvaluateCustomPropertyDeclarationsForSelector(
      info, count, kOSVADiagnosticSnapshotProperty);
}

static SnapshotReadResult
ValidateCustomPropertyDeclarationForSelector(AudioDeviceID deviceID,
                                  OSStatus *statusOut,
                                  AudioObjectPropertySelector selector) {
  enum { kMaximumCustomPropertyCount = 32 };
  if (statusOut == NULL) {
    return kSnapshotReadFailed;
  }
  *statusOut = noErr;
  AudioObjectPropertyAddress address =
      PropertyAddress(kAudioObjectPropertyCustomPropertyInfoList);
  UInt32 size = 0;
  OSStatus status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, NULL,
                                                   &size);
  if (status != noErr) {
    *statusOut = status;
    return ResultForPropertyStatus(status);
  }
  if (size == 0 || size > kMaximumCustomPropertyCount *
                             (UInt32)sizeof(AudioServerPlugInCustomPropertyInfo) ||
      size % sizeof(AudioServerPlugInCustomPropertyInfo) != 0) {
    return kSnapshotReadSchemaMismatch;
  }

  AudioServerPlugInCustomPropertyInfo info[kMaximumCustomPropertyCount];
  memset(info, 0, sizeof(info));
  UInt32 returnedSize = size;
  status = AudioObjectGetPropertyData(deviceID, &address, 0, NULL,
                                      &returnedSize, info);
  if (status != noErr) {
    *statusOut = status;
    return ResultForPropertyStatus(status);
  }
  if (returnedSize != size ||
      returnedSize % sizeof(AudioServerPlugInCustomPropertyInfo) != 0) {
    return kSnapshotReadSchemaMismatch;
  }
  const size_t count =
      (size_t)returnedSize / sizeof(AudioServerPlugInCustomPropertyInfo);
  return EvaluateCustomPropertyDeclarationsForSelector(info, count, selector);
}

static SnapshotReadResult ValidateCustomPropertyDeclaration(
    AudioDeviceID deviceID, OSStatus *statusOut) {
  return ValidateCustomPropertyDeclarationForSelector(
      deviceID, statusOut, kOSVADiagnosticSnapshotProperty);
}

static SnapshotReadResult
DecodeSnapshotPropertyList(CFPropertyListRef propertyList,
                           OSVADiagnosticSnapshot *snapshot) {
  if (snapshot == NULL) {
    return kSnapshotReadFailed;
  }
  memset(snapshot, 0, sizeof(*snapshot));
  if (propertyList == NULL ||
      CFGetTypeID(propertyList) != CFDataGetTypeID()) {
    return kSnapshotReadSchemaMismatch;
  }
  CFDataRef data = (CFDataRef)propertyList;
  const CFIndex byteCount = CFDataGetLength(data);
  if (byteCount != (CFIndex)sizeof(*snapshot)) {
    return kSnapshotReadSchemaMismatch;
  }
  CFDataGetBytes(data, CFRangeMake(0, byteCount), (UInt8 *)snapshot);
  if (!SnapshotSchemaIsExact(snapshot)) {
    memset(snapshot, 0, sizeof(*snapshot));
    return kSnapshotReadSchemaMismatch;
  }
  return kSnapshotReadOK;
}

static SnapshotReadResult ReadSnapshot(AudioDeviceID deviceID,
                                       OSVADiagnosticSnapshot *snapshot,
                                       OSStatus *statusOut) {
  if (snapshot == NULL || statusOut == NULL) {
    return kSnapshotReadFailed;
  }
  *statusOut = noErr;
  AudioObjectPropertyAddress address =
      PropertyAddress(kOSVADiagnosticSnapshotProperty);
  UInt32 size = 0;
  OSStatus status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, NULL,
                                                   &size);
  if (status != noErr) {
    *statusOut = status;
    return ResultForPropertyStatus(status);
  }
  if (size != sizeof(CFPropertyListRef)) {
    return kSnapshotReadSchemaMismatch;
  }

  CFPropertyListRef propertyList = NULL;
  UInt32 returnedSize = size;
  status = AudioObjectGetPropertyData(deviceID, &address, 0, NULL,
                                      &returnedSize, &propertyList);
  if (status != noErr) {
    *statusOut = status;
    return ResultForPropertyStatus(status);
  }
  if (returnedSize != sizeof(propertyList)) {
    if (propertyList != NULL) {
      CFRelease(propertyList);
    }
    return kSnapshotReadSchemaMismatch;
  }
  SnapshotReadResult result =
      DecodeSnapshotPropertyList(propertyList, snapshot);
  if (propertyList != NULL) {
    CFRelease(propertyList);
  }
  return result;
}

static bool TransitionEqual(const OSVADiagnosticTransitionSnapshot *left,
                            const OSVADiagnosticTransitionSnapshot *right) {
  return left->host_ticks == right->host_ticks &&
         left->client_id == right->client_id &&
         left->pre_global_active_count == right->pre_global_active_count &&
         left->post_global_active_count == right->post_global_active_count &&
         left->driver_client_generation == right->driver_client_generation &&
         left->core_session_id == right->core_session_id &&
         left->reserved == right->reserved &&
         left->type == right->type &&
         left->endpoint_role == right->endpoint_role &&
         left->slot_index == right->slot_index &&
         left->process_id == right->process_id;
}

static bool
DriverSlotEqual(const OSVADiagnosticDriverClientSlotSnapshot *left,
                const OSVADiagnosticDriverClientSlotSnapshot *right) {
  return left->generation == right->generation &&
         left->registration_host_ticks == right->registration_host_ticks &&
         left->start_host_ticks == right->start_host_ticks &&
         left->last_transition_host_ticks == right->last_transition_host_ticks &&
         left->lease_session_id == right->lease_session_id &&
         left->lease_timeline_seed == right->lease_timeline_seed &&
         left->flags == right->flags &&
         left->device_object_id == right->device_object_id &&
         left->client_id == right->client_id &&
         left->process_id == right->process_id &&
         left->endpoint_role == right->endpoint_role &&
         left->core_client_slot == right->core_client_slot &&
         left->io_start_depth == right->io_start_depth &&
         left->reserved == right->reserved;
}

static bool CoreSlotEqual(const OSVADiagnosticCoreClientSlotSnapshot *left,
                          const OSVADiagnosticCoreClientSlotSnapshot *right) {
  return left->session_id == right->session_id &&
         left->client_id == right->client_id &&
         left->timeline_seed == right->timeline_seed &&
         left->endpoint_role == right->endpoint_role &&
         left->reserved == right->reserved;
}

/*
 * Observation sequence/time and the two real-time records may legitimately
 * advance between endpoint reads. Everything below is shared lifecycle state
 * and must agree when both lifecycle sequence numbers remain unchanged.
 */
static bool SharedStateEqual(const OSVADiagnosticSnapshot *left,
                             const OSVADiagnosticSnapshot *right) {
  if (!SnapshotSchemaIsExact(left) || !SnapshotSchemaIsExact(right) ||
      left->driver_instance_generation != right->driver_instance_generation ||
      left->invariant_flags != right->invariant_flags ||
      left->driver_lifecycle_sequence != right->driver_lifecycle_sequence ||
      left->core_lifecycle_sequence != right->core_lifecycle_sequence ||
      left->host_ticks_per_second != right->host_ticks_per_second ||
      left->timeline_seed != right->timeline_seed ||
      left->current_seed_generation != right->current_seed_generation ||
      left->anchor_host_ticks != right->anchor_host_ticks ||
      left->last_issued_seed != right->last_issued_seed ||
      left->last_issued_session_id != right->last_issued_session_id ||
      left->active_client_count != right->active_client_count ||
      left->visible_input_active_count !=
          right->visible_input_active_count ||
      left->hidden_writer_active_count !=
          right->hidden_writer_active_count ||
      left->core_active_slot_count != right->core_active_slot_count ||
      left->core_active_slot_bitmap != right->core_active_slot_bitmap ||
      left->driver_registered_count != right->driver_registered_count ||
      left->driver_started_count != right->driver_started_count ||
      left->visible_driver_registered_count !=
          right->visible_driver_registered_count ||
      left->hidden_driver_registered_count !=
          right->hidden_driver_registered_count ||
      left->visible_driver_started_count !=
          right->visible_driver_started_count ||
      left->hidden_driver_started_count !=
          right->hidden_driver_started_count ||
      left->driver_registered_slot_bitmap !=
          right->driver_registered_slot_bitmap ||
      left->driver_started_slot_bitmap != right->driver_started_slot_bitmap ||
      left->driver_client_add_attempt_count !=
          right->driver_client_add_attempt_count ||
      left->driver_client_add_count != right->driver_client_add_count ||
      left->driver_client_remove_attempt_count !=
          right->driver_client_remove_attempt_count ||
      left->driver_client_remove_count != right->driver_client_remove_count ||
      left->global_start_attempt_count != right->global_start_attempt_count ||
      left->global_start_transition_count !=
          right->global_start_transition_count ||
      left->global_stop_attempt_count != right->global_stop_attempt_count ||
      left->global_stop_transition_count !=
          right->global_stop_transition_count ||
      left->seed_create_count != right->seed_create_count ||
      left->seed_clear_count != right->seed_clear_count ||
      left->last_seed_create_host_ticks !=
          right->last_seed_create_host_ticks ||
      left->last_seed_clear_host_ticks !=
          right->last_seed_clear_host_ticks ||
      left->last_cleared_seed != right->last_cleared_seed ||
      left->last_cleared_seed_generation !=
          right->last_cleared_seed_generation ||
      left->last_cleared_anchor_host_ticks !=
          right->last_cleared_anchor_host_ticks ||
      left->reserved_header != right->reserved_header ||
      !TransitionEqual(&left->last_driver_transition,
                       &right->last_driver_transition) ||
      !TransitionEqual(&left->last_core_transition,
                       &right->last_core_transition) ||
      memcmp(left->reserved, right->reserved, sizeof(left->reserved)) != 0) {
    return false;
  }
  for (size_t index = 0; index < kOSVADiagnosticClientSlotCapacity; ++index) {
    if (!DriverSlotEqual(&left->driver_client_slots[index],
                         &right->driver_client_slots[index]) ||
        !CoreSlotEqual(&left->core_client_slots[index],
                       &right->core_client_slots[index])) {
      return false;
    }
  }
  return true;
}

static bool ExactTranslationsRemainStable(AudioDeviceID visibleDevice,
                                          AudioDeviceID writerDevice) {
  AudioDeviceID freshVisible = kAudioObjectUnknown;
  AudioDeviceID freshWriter = kAudioObjectUnknown;
  return TranslateExactDeviceUID(OSVA_VISIBLE_INPUT_DEVICE_UID,
                                 &freshVisible) == noErr &&
         TranslateExactDeviceUID(OSVA_HIDDEN_WRITER_DEVICE_UID, &freshWriter) ==
             noErr &&
         freshVisible == visibleDevice && freshWriter == writerDevice &&
         DeviceUIDMatches(freshVisible, OSVA_VISIBLE_INPUT_DEVICE_UID) &&
         DeviceUIDMatches(freshWriter, OSVA_HIDDEN_WRITER_DEVICE_UID);
}

static const char *BooleanJSON(bool value) { return value ? "true" : "false"; }

static void PrintTransition(const OSVADiagnosticTransitionSnapshot *value) {
  printf("{\"hostTicks\":%" PRIu64 ",\"clientID\":%" PRIu64
         ",\"preGlobalActiveCount\":%" PRIu64
         ",\"postGlobalActiveCount\":%" PRIu64
         ",\"driverClientGeneration\":%" PRIu64
         ",\"coreSessionID\":%" PRIu64
         ",\"type\":%" PRIu32 ",\"endpointRole\":%" PRIu32
         ",\"slotIndex\":%" PRIu32 ",\"processID\":%" PRId32 "}",
         value->host_ticks, value->client_id,
         value->pre_global_active_count, value->post_global_active_count,
         value->driver_client_generation, value->core_session_id, value->type,
         value->endpoint_role, value->slot_index, value->process_id);
}

static void PrintZeroTimestamp(const OSVADiagnosticZeroTimestampSnapshot *value,
                               UInt32 endpointRole) {
  printf("{\"endpointRole\":%" PRIu32 ",\"sequence\":%" PRIu64
         ",\"metadataSequence\":%" PRIu64
         ",\"metadataDroppedUpdateCount\":%" PRIu64
         ",\"epochMappingUnavailableCount\":%" PRIu64
         ",\"callCount\":%" PRIu64
         ",\"successfulReturnCount\":%" PRIu64
         ",\"fallbackReturnCount\":%" PRIu64
         ",\"failedReturnCount\":%" PRIu64
         ",\"lastCallHostTicks\":%" PRIu64
         ",\"lastSampleFrame\":%" PRIu64
         ",\"lastHostTicks\":%" PRIu64 ",\"lastSeed\":%" PRIu64
         ",\"lastSeedGeneration\":%" PRIu64
         ",\"lastCoreLifecycleSequence\":%" PRIu64
         ",\"lastCallCoreLifecycleSequence\":%" PRIu64
         ",\"lastClientID\":%" PRIu32 ",\"lastStatus\":%" PRId32
         ",\"flags\":%" PRIu32 "}",
         endpointRole, value->sequence, value->metadata_sequence,
         value->metadata_dropped_update_count,
         value->epoch_mapping_unavailable_count, value->call_count,
         value->successful_return_count, value->fallback_return_count,
         value->failed_return_count, value->last_call_host_ticks,
         value->last_sample_frame, value->last_host_ticks, value->last_seed,
         value->last_seed_generation,
         value->last_core_lifecycle_sequence,
         value->last_call_core_lifecycle_sequence, value->last_client_id,
         value->last_status, value->flags);
}

static void PrintIO(const OSVADiagnosticIOSnapshot *value,
                    UInt32 endpointRole) {
  printf("{\"endpointRole\":%" PRIu32 ",\"sequence\":%" PRIu64
         ",\"metadataSequence\":%" PRIu64
         ",\"metadataDroppedUpdateCount\":%" PRIu64
         ",\"operationCallCount\":%" PRIu64
         ",\"validCycleCount\":%" PRIu64
         ",\"invalidCycleCount\":%" PRIu64
         ",\"leaseUnavailableCount\":%" PRIu64
         ",\"epochMappingUnavailableCount\":%" PRIu64
         ",\"coreOKCount\":%" PRIu64 ",\"coreRetryCount\":%" PRIu64
         ",\"coreFailureCount\":%" PRIu64
         ",\"requestedFrameCount\":%" PRIu64
         ",\"transferredFrameCount\":%" PRIu64
         ",\"gapFrameCount\":%" PRIu64
         ",\"lastCycleSampleFrame\":%" PRIu64
         ",\"lastCycleHostTicks\":%" PRIu64
         ",\"lastPublishedFrameSeed\":%" PRIu64
         ",\"lastPublishedSeedGeneration\":%" PRIu64
         ",\"lastPublishedFrameSession\":%" PRIu64
         ",\"lastPublishedAbsoluteFrame\":%" PRIu64
         ",\"lastConsumedFrameSeed\":%" PRIu64
         ",\"lastConsumedSeedGeneration\":%" PRIu64
         ",\"lastConsumedFrameSession\":%" PRIu64
         ",\"lastConsumedAbsoluteFrame\":%" PRIu64
         ",\"lastClientID\":%" PRIu32 ",\"lastStatus\":%" PRId32
         ",\"flags\":%" PRIu32 "}",
         endpointRole, value->sequence, value->metadata_sequence,
         value->metadata_dropped_update_count,
         value->operation_call_count,
         value->valid_cycle_count, value->invalid_cycle_count,
         value->lease_unavailable_count,
         value->epoch_mapping_unavailable_count, value->core_ok_count,
         value->core_retry_count, value->core_failure_count,
         value->requested_frame_count, value->transferred_frame_count,
         value->gap_frame_count, value->last_cycle_sample_frame,
         value->last_cycle_host_ticks, value->last_published_frame_seed,
         value->last_published_seed_generation,
         value->last_published_frame_session,
         value->last_published_absolute_frame,
         value->last_consumed_frame_seed,
         value->last_consumed_seed_generation,
         value->last_consumed_frame_session,
         value->last_consumed_absolute_frame,
         value->last_client_id, value->last_status, value->flags);
}

static void
PrintIOWorkLoop(const OSVADiagnosticIOWorkLoopSnapshot *value,
                UInt32 endpointRole) {
  printf("{\"endpointRole\":%" PRIu32 ",\"sequence\":%" PRIu64
         ",\"metadataSequence\":%" PRIu64
         ",\"metadataDroppedUpdateCount\":%" PRIu64
         ",\"currentCount\":%" PRIu64 ",\"beginCount\":%" PRIu64
         ",\"endCount\":%" PRIu64 ",\"underflowCount\":%" PRIu64
         ",\"lastTransitionHostTicks\":%" PRIu64
         ",\"lastClientID\":%" PRIu32 ",\"flags\":%" PRIu32 "}",
         endpointRole, value->sequence, value->metadata_sequence,
         value->metadata_dropped_update_count,
         value->current_count, value->begin_count, value->end_count,
         value->underflow_count, value->last_transition_host_ticks,
         value->last_client_id, value->flags);
}

static void PrintDriverSlots(const OSVADiagnosticSnapshot *snapshot) {
  putchar('[');
  bool needsComma = false;
  for (UInt32 index = 0; index < snapshot->client_slot_capacity; ++index) {
    const OSVADiagnosticDriverClientSlotSnapshot *slot =
        &snapshot->driver_client_slots[index];
    if (slot->flags == 0 && slot->generation == 0 && slot->client_id == 0 &&
        slot->lease_session_id == 0) {
      continue;
    }
    if (needsComma) {
      putchar(',');
    }
    needsComma = true;
    printf("{\"slotIndex\":%" PRIu32 ",\"generation\":%" PRIu64
           ",\"registrationHostTicks\":%" PRIu64
           ",\"startHostTicks\":%" PRIu64
           ",\"lastTransitionHostTicks\":%" PRIu64
           ",\"leaseSessionID\":%" PRIu64
           ",\"leaseTimelineSeed\":%" PRIu64
           ",\"flags\":%" PRIu32 ",\"deviceObjectID\":%" PRIu32
           ",\"clientID\":%" PRIu32 ",\"processID\":%" PRId32
           ",\"endpointRole\":%" PRIu32
           ",\"coreClientSlot\":%" PRIu32
           ",\"ioStartDepth\":%" PRIu32 "}",
           index, slot->generation, slot->registration_host_ticks,
           slot->start_host_ticks, slot->last_transition_host_ticks,
           slot->lease_session_id,
           slot->lease_timeline_seed, slot->flags, slot->device_object_id,
           slot->client_id, slot->process_id, slot->endpoint_role,
           slot->core_client_slot, slot->io_start_depth);
  }
  putchar(']');
}

static void PrintCoreSlots(const OSVADiagnosticSnapshot *snapshot) {
  putchar('[');
  bool needsComma = false;
  for (UInt32 index = 0; index < snapshot->client_slot_capacity; ++index) {
    const OSVADiagnosticCoreClientSlotSnapshot *slot =
        &snapshot->core_client_slots[index];
    if (slot->session_id == 0 && slot->client_id == 0 &&
        slot->timeline_seed == 0 && slot->endpoint_role == 0) {
      continue;
    }
    if (needsComma) {
      putchar(',');
    }
    needsComma = true;
    printf("{\"slotIndex\":%" PRIu32 ",\"sessionID\":%" PRIu64
           ",\"clientID\":%" PRIu64 ",\"timelineSeed\":%" PRIu64
           ",\"endpointRole\":%" PRIu32 "}",
           index, slot->session_id, slot->client_id, slot->timeline_seed,
           slot->endpoint_role);
  }
  putchar(']');
}

static void PrintSnapshotJSON(
    AudioDeviceID visibleDevice, AudioDeviceID writerDevice,
    const char *mode,
    const EndpointObservation *visibleFirst,
    const EndpointObservation *writerObservation,
    const EndpointObservation *visibleFinal,
    const OSVADiagnosticSnapshot *snapshot) {
  const UInt64 requiredInvariantMask =
      kOSVADiagnosticInvariantGlobalMatchesCoreSlots |
      kOSVADiagnosticInvariantEndpointsMatchCoreSlots |
      kOSVADiagnosticInvariantDriverStartsMatchCoreSlots |
      kOSVADiagnosticInvariantIdleImpliesClockCleared |
      kOSVADiagnosticInvariantActiveImpliesClockValid |
      kOSVADiagnosticInvariantSlotCountsWithinCapacity |
      kOSVADiagnosticInvariantStartStopBalancedAtIdle |
      kOSVADiagnosticInvariantSeedCreateClearBalancedAtIdle |
      kOSVADiagnosticInvariantRingGenerationMatchesCurrentSeed |
      kOSVADiagnosticInvariantNoActiveSlotReferencesRetiredGeneration;
  const bool allInvariantsHold =
      (snapshot->invariant_flags & requiredInvariantMask) ==
      requiredInvariantMask;

  printf("{\"readerSchema\":%d,\"mode\":\"%s\",\"claim\":"
         "\"read-only-virtual-driver-diagnostic-snapshot\","
         "\"visibleDeviceUID\":\"%s\",\"visibleDeviceID\":%" PRIu32
         ",\"writerDeviceUID\":\"%s\",\"writerDeviceID\":%" PRIu32
         ",\"customPropertyDataType\":\"CFPropertyList\","
         "\"payloadConcreteType\":\"CFData\","
         "\"endpointReadsCoherent\":true,"
         "\"observations\":{\"visibleFirst\":{\"snapshotSequence\":%" PRIu64
         ",\"capturedHostTicks\":%" PRIu64
         "},\"writer\":{\"snapshotSequence\":%" PRIu64
         ",\"capturedHostTicks\":%" PRIu64
         "},\"visibleFinal\":{\"snapshotSequence\":%" PRIu64
         ",\"capturedHostTicks\":%" PRIu64 "}},"
         "\"snapshotSchemaVersion\":%" PRIu32
         ",\"snapshotStructSize\":%" PRIu32
         ",\"driverInstanceGeneration\":%" PRIu64
         ",\"invariantFlags\":\"%016" PRIx64 "\","
         "\"allDeclaredInvariantsHold\":%s,"
         "\"coreInitialized\":%s,\"timelineActive\":%s,"
         "\"driverLifecycleSequence\":%" PRIu64
         ",\"coreLifecycleSequence\":%" PRIu64
         ",\"hostTicksPerSecond\":%" PRIu64
         ",\"timelineSeed\":%" PRIu64
         ",\"currentSeedGeneration\":%" PRIu64
         ",\"anchorHostTicks\":%" PRIu64
         ",\"lastIssuedSeed\":%" PRIu64
         ",\"lastIssuedSessionID\":%" PRIu64
         ",\"activeClientCount\":%" PRIu64
         ",\"visibleInputActiveCount\":%" PRIu64
         ",\"hiddenWriterActiveCount\":%" PRIu64
         ",\"coreActiveSlotCount\":%" PRIu64
         ",\"coreActiveSlotBitmap\":\"%016" PRIx64 "\","
         "\"driverRegisteredCount\":%" PRIu64
         ",\"driverStartedCount\":%" PRIu64
         ",\"visibleDriverRegisteredCount\":%" PRIu64
         ",\"hiddenDriverRegisteredCount\":%" PRIu64
         ",\"visibleDriverStartedCount\":%" PRIu64
         ",\"hiddenDriverStartedCount\":%" PRIu64
         ",\"driverRegisteredSlotBitmap\":\"%016" PRIx64 "\","
         "\"driverStartedSlotBitmap\":\"%016" PRIx64 "\","
         "\"driverClientAddAttemptCount\":%" PRIu64
         ",\"driverClientAddCount\":%" PRIu64
         ",\"driverClientRemoveAttemptCount\":%" PRIu64
         ",\"driverClientRemoveCount\":%" PRIu64
         ",\"globalStartAttemptCount\":%" PRIu64
         ",\"globalStartTransitionCount\":%" PRIu64
         ",\"globalStopAttemptCount\":%" PRIu64
         ",\"globalStopTransitionCount\":%" PRIu64
         ",\"seedCreateCount\":%" PRIu64
         ",\"seedClearCount\":%" PRIu64
         ",\"lastSeedCreateHostTicks\":%" PRIu64
         ",\"lastSeedClearHostTicks\":%" PRIu64
         ",\"lastClearedSeed\":%" PRIu64
         ",\"lastClearedSeedGeneration\":%" PRIu64
         ",\"lastClearedAnchorHostTicks\":%" PRIu64
         ",\"clientSlotCapacity\":%" PRIu32 ",\"lastDriverTransition\":",
         kReaderSchemaVersion, mode, OSVA_VISIBLE_INPUT_DEVICE_UID,
         visibleDevice,
         OSVA_HIDDEN_WRITER_DEVICE_UID, writerDevice,
         visibleFirst->snapshot_sequence, visibleFirst->captured_host_ticks,
         writerObservation->snapshot_sequence,
         writerObservation->captured_host_ticks, visibleFinal->snapshot_sequence,
         visibleFinal->captured_host_ticks, snapshot->schema_version,
         snapshot->struct_size, snapshot->driver_instance_generation,
         snapshot->invariant_flags, BooleanJSON(allInvariantsHold),
         BooleanJSON((snapshot->invariant_flags &
                      kOSVADiagnosticSnapshotCoreInitialized) != 0),
         BooleanJSON((snapshot->invariant_flags &
                      kOSVADiagnosticSnapshotTimelineActive) != 0),
         snapshot->driver_lifecycle_sequence,
         snapshot->core_lifecycle_sequence, snapshot->host_ticks_per_second,
         snapshot->timeline_seed, snapshot->current_seed_generation,
         snapshot->anchor_host_ticks,
         snapshot->last_issued_seed, snapshot->last_issued_session_id,
         snapshot->active_client_count, snapshot->visible_input_active_count,
         snapshot->hidden_writer_active_count,
         snapshot->core_active_slot_count, snapshot->core_active_slot_bitmap,
         snapshot->driver_registered_count, snapshot->driver_started_count,
         snapshot->visible_driver_registered_count,
         snapshot->hidden_driver_registered_count,
         snapshot->visible_driver_started_count,
         snapshot->hidden_driver_started_count,
         snapshot->driver_registered_slot_bitmap,
         snapshot->driver_started_slot_bitmap,
         snapshot->driver_client_add_attempt_count,
         snapshot->driver_client_add_count,
         snapshot->driver_client_remove_attempt_count,
         snapshot->driver_client_remove_count,
         snapshot->global_start_attempt_count,
         snapshot->global_start_transition_count,
         snapshot->global_stop_attempt_count,
         snapshot->global_stop_transition_count, snapshot->seed_create_count,
         snapshot->seed_clear_count, snapshot->last_seed_create_host_ticks,
         snapshot->last_seed_clear_host_ticks, snapshot->last_cleared_seed,
         snapshot->last_cleared_seed_generation,
         snapshot->last_cleared_anchor_host_ticks,
         snapshot->client_slot_capacity);
  PrintTransition(&snapshot->last_driver_transition);
  printf(",\"lastCoreTransition\":");
  PrintTransition(&snapshot->last_core_transition);
  printf(",\"zeroTimestamp\":[");
  PrintZeroTimestamp(&snapshot->zero_timestamp[0],
                     kOSVADiagnosticEndpointVisibleInput);
  putchar(',');
  PrintZeroTimestamp(&snapshot->zero_timestamp[1],
                     kOSVADiagnosticEndpointHiddenWriter);
  printf("],\"io\":[");
  PrintIO(&snapshot->io[0], kOSVADiagnosticEndpointVisibleInput);
  putchar(',');
  PrintIO(&snapshot->io[1], kOSVADiagnosticEndpointHiddenWriter);
  printf("],\"ioWorkLoop\":[");
  PrintIOWorkLoop(&snapshot->io_work_loop[0],
                  kOSVADiagnosticEndpointVisibleInput);
  putchar(',');
  PrintIOWorkLoop(&snapshot->io_work_loop[1],
                  kOSVADiagnosticEndpointHiddenWriter);
  printf("],\"driverClientSlots\":");
  PrintDriverSlots(snapshot);
  printf(",\"coreClientSlots\":");
  PrintCoreSlots(snapshot);
  puts("}");
}

static int ExitCodeForReadFailure(SnapshotReadResult result) {
  switch (result) {
  case kSnapshotReadSchemaMismatch:
    return kExitSchemaMismatch;
  case kSnapshotReadUnavailable:
    return kExitPropertyUnavailable;
  case kSnapshotReadRetry:
    return kExitRetry;
  default:
    return kExitInternalError;
  }
}

static int PrintReadFailure(const char *endpoint, SnapshotReadResult result,
                            OSStatus status) {
  if (result == kSnapshotReadSchemaMismatch) {
    fprintf(stderr, "%s diagnostic property schema/size mismatch\n", endpoint);
    return ExitCodeForReadFailure(result);
  }
  if (result == kSnapshotReadUnavailable) {
    fprintf(stderr,
            "%s diagnostic property is unavailable; the loaded driver does "
            "not expose osDS schema v1\n",
            endpoint);
    return ExitCodeForReadFailure(result);
  }
  if (result == kSnapshotReadRetry) {
    fprintf(stderr, "%s diagnostic snapshot remained in transition\n",
            endpoint);
    return ExitCodeForReadFailure(result);
  }
  fprintf(stderr, "%s diagnostic property read failed with OSStatus %" PRId32
                  "\n",
          endpoint, status);
  return ExitCodeForReadFailure(result);
}

static int RunReader(void) {
  AudioDeviceID visibleDevice = kAudioObjectUnknown;
  AudioDeviceID writerDevice = kAudioObjectUnknown;
  OSStatus status =
      TranslateExactDeviceUID(OSVA_VISIBLE_INPUT_DEVICE_UID, &visibleDevice);
  if (status != noErr || visibleDevice == kAudioObjectUnknown) {
    fprintf(stderr, "exact visible-input UID translation failed with OSStatus "
                    "%" PRId32 "\n",
            status);
    return kExitPropertyUnavailable;
  }
  status =
      TranslateExactDeviceUID(OSVA_HIDDEN_WRITER_DEVICE_UID, &writerDevice);
  if (status != noErr || writerDevice == kAudioObjectUnknown) {
    fprintf(stderr, "exact hidden-writer UID translation failed with OSStatus "
                    "%" PRId32 "\n",
            status);
    return kExitPropertyUnavailable;
  }
  if (visibleDevice == writerDevice ||
      !DeviceUIDMatches(visibleDevice, OSVA_VISIBLE_INPUT_DEVICE_UID) ||
      !DeviceUIDMatches(writerDevice, OSVA_HIDDEN_WRITER_DEVICE_UID)) {
    fprintf(stderr, "translated virtual-microphone endpoint identity mismatch\n");
    return kExitPropertyUnavailable;
  }

  OSStatus declarationStatus = noErr;
  SnapshotReadResult declarationResult =
      ValidateCustomPropertyDeclaration(visibleDevice, &declarationStatus);
  if (declarationResult != kSnapshotReadOK) {
    return PrintReadFailure("visible-input custom-property declaration",
                            declarationResult, declarationStatus);
  }
  declarationResult =
      ValidateCustomPropertyDeclaration(writerDevice, &declarationStatus);
  if (declarationResult != kSnapshotReadOK) {
    return PrintReadFailure("hidden-writer custom-property declaration",
                            declarationResult, declarationStatus);
  }

  for (unsigned attempt = 0; attempt < kMaximumCoherenceAttempts; ++attempt) {
    OSVADiagnosticSnapshot visibleFirst;
    OSVADiagnosticSnapshot writer;
    OSVADiagnosticSnapshot visibleFinal;
    OSStatus readStatus = noErr;
    SnapshotReadResult result =
        ReadSnapshot(visibleDevice, &visibleFirst, &readStatus);
    if (result != kSnapshotReadOK) {
      if (result == kSnapshotReadRetry) {
        continue;
      }
      return PrintReadFailure("visible-input", result, readStatus);
    }
    result = ReadSnapshot(writerDevice, &writer, &readStatus);
    if (result != kSnapshotReadOK) {
      if (result == kSnapshotReadRetry) {
        continue;
      }
      return PrintReadFailure("hidden-writer", result, readStatus);
    }
    result = ReadSnapshot(visibleDevice, &visibleFinal, &readStatus);
    if (result != kSnapshotReadOK) {
      if (result == kSnapshotReadRetry) {
        continue;
      }
      return PrintReadFailure("visible-input", result, readStatus);
    }
    if (!SharedStateEqual(&visibleFirst, &writer) ||
        !SharedStateEqual(&writer, &visibleFinal) ||
        !ExactTranslationsRemainStable(visibleDevice, writerDevice)) {
      continue;
    }

    const EndpointObservation visibleFirstObservation = {
        .snapshot_sequence = visibleFirst.snapshot_sequence,
        .captured_host_ticks = visibleFirst.captured_host_ticks,
    };
    const EndpointObservation writerObservation = {
        .snapshot_sequence = writer.snapshot_sequence,
        .captured_host_ticks = writer.captured_host_ticks,
    };
    const EndpointObservation visibleFinalObservation = {
        .snapshot_sequence = visibleFinal.snapshot_sequence,
        .captured_host_ticks = visibleFinal.captured_host_ticks,
    };
    PrintSnapshotJSON(visibleDevice, writerDevice, "read-once",
                      &visibleFirstObservation, &writerObservation,
                      &visibleFinalObservation,
                      &visibleFinal);
    return 0;
  }

  fprintf(stderr,
          "diagnostic lifecycle changed throughout %d bounded coherence "
          "attempts; retry\n",
          kMaximumCoherenceAttempts);
  return kExitRetry;
}

static void InitializeSelfTestFixture(OSVADiagnosticSnapshot *snapshot) {
  memset(snapshot, 0, sizeof(*snapshot));
  snapshot->schema_version = kOSVADiagnosticSnapshotSchemaVersion;
  snapshot->struct_size = (UInt32)sizeof(*snapshot);
  snapshot->snapshot_sequence = 10;
  snapshot->captured_host_ticks = 20;
  snapshot->driver_instance_generation = 30;
  snapshot->invariant_flags =
      kOSVADiagnosticSnapshotCoreInitialized |
      kOSVADiagnosticInvariantGlobalMatchesCoreSlots |
      kOSVADiagnosticInvariantEndpointsMatchCoreSlots |
      kOSVADiagnosticInvariantDriverStartsMatchCoreSlots |
      kOSVADiagnosticInvariantIdleImpliesClockCleared |
      kOSVADiagnosticInvariantActiveImpliesClockValid |
      kOSVADiagnosticInvariantSlotCountsWithinCapacity |
      kOSVADiagnosticInvariantStartStopBalancedAtIdle |
      kOSVADiagnosticInvariantSeedCreateClearBalancedAtIdle |
      kOSVADiagnosticInvariantRingGenerationMatchesCurrentSeed |
      kOSVADiagnosticInvariantNoActiveSlotReferencesRetiredGeneration;
  snapshot->driver_lifecycle_sequence = 40;
  snapshot->core_lifecycle_sequence = 50;
  snapshot->host_ticks_per_second = UINT64_C(1000000000);
  snapshot->last_issued_seed = 3;
  snapshot->last_issued_session_id = 7;
  snapshot->seed_create_count = 3;
  snapshot->seed_clear_count = 3;
  snapshot->client_slot_capacity = kOSVADiagnosticClientSlotCapacity;
  snapshot->last_driver_transition = (OSVADiagnosticTransitionSnapshot){
      .host_ticks = 60,
      .client_id = 1001,
      .pre_global_active_count = 0,
      .post_global_active_count = 1,
      .driver_client_generation = 70,
      .core_session_id = 80,
      .type = kOSVADiagnosticTransitionIOStarted,
      .endpoint_role = kOSVADiagnosticEndpointVisibleInput,
      .slot_index = 4,
      .process_id = 4321,
  };
  snapshot->last_core_transition = snapshot->last_driver_transition;
  snapshot->zero_timestamp[0] = (OSVADiagnosticZeroTimestampSnapshot){
      .sequence = 4,
      .metadata_sequence = 2,
      .metadata_dropped_update_count = 3,
      .epoch_mapping_unavailable_count = 0,
      .call_count = 4,
      .successful_return_count = 3,
      .failed_return_count = 1,
      .last_call_host_ticks = 90,
      .last_sample_frame = 100,
      .last_host_ticks = 110,
      .last_seed = 3,
      .last_seed_generation = 3,
      .last_core_lifecycle_sequence = 48,
      .last_call_core_lifecycle_sequence = 50,
      .last_client_id = 1001,
      .last_status = 0,
      .flags = kOSVADiagnosticRecordPresent |
               kOSVADiagnosticRecordLastSuccessTupleValid |
               kOSVADiagnosticRecordLastCallValid |
               kOSVADiagnosticRecordEpochMappingValid,
  };
  snapshot->io[1] = (OSVADiagnosticIOSnapshot){
      .sequence = 6,
      .metadata_sequence = 2,
      .metadata_dropped_update_count = 5,
      .operation_call_count = 6,
      .valid_cycle_count = 6,
      .epoch_mapping_unavailable_count = 0,
      .core_ok_count = 6,
      .requested_frame_count = 24,
      .transferred_frame_count = 24,
      .last_cycle_sample_frame = 120,
      .last_cycle_host_ticks = 130,
      .last_published_frame_seed = 3,
      .last_published_seed_generation = 3,
      .last_published_frame_session = 7,
      .last_published_absolute_frame = 123,
      .last_client_id = 1002,
      .last_status = 0,
      .flags = kOSVADiagnosticRecordPresent |
               kOSVADiagnosticRecordLastSuccessTupleValid |
               kOSVADiagnosticRecordLastCallValid |
               kOSVADiagnosticRecordEpochMappingValid,
  };
  snapshot->io_work_loop[0] = (OSVADiagnosticIOWorkLoopSnapshot){
      .sequence = 9,
      .metadata_sequence = 2,
      .metadata_dropped_update_count = 8,
      .current_count = 2,
      .begin_count = 5,
      .end_count = 4,
      .underflow_count = 1,
      .last_transition_host_ticks = 140,
      .last_client_id = 1001,
      .flags = kOSVADiagnosticRecordPresent |
               kOSVADiagnosticRecordLastCallValid,
  };
}

static int RunSelfTest(void) {
  unsigned passed = 0;
  OSVADiagnosticSnapshot first;
  InitializeSelfTestFixture(&first);
  if (!SnapshotSchemaIsExact(&first)) {
    return 1;
  }
  passed += 1;

  OSVADiagnosticSnapshot changed = first;
  changed.schema_version += 1;
  if (SnapshotSchemaIsExact(&changed)) {
    return 1;
  }
  passed += 1;

  changed = first;
  changed.struct_size -= 1;
  if (SnapshotSchemaIsExact(&changed)) {
    return 1;
  }
  passed += 1;

  changed = first;
  changed.client_slot_capacity -= 1;
  if (SnapshotSchemaIsExact(&changed)) {
    return 1;
  }
  passed += 1;

  changed = first;
  changed.snapshot_sequence += 1;
  changed.captured_host_ticks += 100;
  changed.zero_timestamp[0].metadata_dropped_update_count += 1;
  changed.zero_timestamp[0].call_count += 1;
  changed.zero_timestamp[0].last_call_core_lifecycle_sequence += 2;
  changed.io[1].metadata_dropped_update_count += 1;
  changed.io[1].operation_call_count += 1;
  changed.io[1].last_published_seed_generation += 1;
  changed.io[1].last_consumed_seed_generation += 1;
  changed.io_work_loop[0].metadata_dropped_update_count += 1;
  changed.io_work_loop[0].current_count += 1;
  if (!SharedStateEqual(&first, &changed)) {
    return 1;
  }
  passed += 1;

  changed = first;
  changed.last_driver_transition.driver_client_generation += 1;
  if (SharedStateEqual(&first, &changed)) {
    return 1;
  }
  passed += 1;

  changed = first;
  changed.last_driver_transition.core_session_id += 1;
  if (SharedStateEqual(&first, &changed)) {
    return 1;
  }
  passed += 1;

  changed = first;
  changed.last_driver_transition.process_id += 1;
  if (SharedStateEqual(&first, &changed)) {
    return 1;
  }
  passed += 1;

  changed = first;
  changed.timeline_seed = 99;
  if (SharedStateEqual(&first, &changed)) {
    return 1;
  }
  passed += 1;

  changed = first;
  changed.driver_client_slots[4].flags =
      kOSVADiagnosticDriverSlotRegistered;
  if (SharedStateEqual(&first, &changed)) {
    return 1;
  }
  passed += 1;

  changed = first;
  changed.core_client_slots[2].session_id = 1;
  if (SharedStateEqual(&first, &changed)) {
    return 1;
  }
  passed += 1;

  if (ExitCodeForReadFailure(kSnapshotReadSchemaMismatch) !=
      kExitSchemaMismatch) {
    return 1;
  }
  passed += 1;
  if (ExitCodeForReadFailure(kSnapshotReadUnavailable) !=
      kExitPropertyUnavailable) {
    return 1;
  }
  passed += 1;
  if (ExitCodeForReadFailure(kSnapshotReadRetry) != kExitRetry) {
    return 1;
  }
  passed += 1;
  if (ExitCodeForReadFailure(kSnapshotReadFailed) != kExitInternalError) {
    return 1;
  }
  passed += 1;

  if (ResultForPropertyStatus(noErr) != kSnapshotReadOK) {
    return 1;
  }
  passed += 1;
  if (ResultForPropertyStatus(kAudioHardwareUnknownPropertyError) !=
      kSnapshotReadUnavailable) {
    return 1;
  }
  passed += 1;
  if (ResultForPropertyStatus(kOSVADiagnosticSnapshotUnavailableError) !=
      kSnapshotReadRetry) {
    return 1;
  }
  passed += 1;
  if (ResultForPropertyStatus(kAudioHardwareBadObjectError) !=
      kSnapshotReadFailed) {
    return 1;
  }
  passed += 1;

  const AudioServerPlugInCustomPropertyInfo exactDeclaration = {
      .mSelector = kOSVADiagnosticSnapshotProperty,
      .mPropertyDataType =
          kAudioServerPlugInCustomPropertyDataTypeCFPropertyList,
      .mQualifierDataType = kAudioServerPlugInCustomPropertyDataTypeNone,
  };
  if (EvaluateCustomPropertyDeclarations(&exactDeclaration, 1) !=
      kSnapshotReadOK) {
    return 1;
  }
  passed += 1;

  AudioServerPlugInCustomPropertyInfo wrongDeclaration = exactDeclaration;
  wrongDeclaration.mPropertyDataType =
      kAudioServerPlugInCustomPropertyDataTypeCFString;
  if (EvaluateCustomPropertyDeclarations(&wrongDeclaration, 1) !=
      kSnapshotReadSchemaMismatch) {
    return 1;
  }
  passed += 1;

  const AudioServerPlugInCustomPropertyInfo duplicateDeclarations[2] = {
      exactDeclaration,
      exactDeclaration,
  };
  if (EvaluateCustomPropertyDeclarations(duplicateDeclarations, 2) !=
      kSnapshotReadSchemaMismatch) {
    return 1;
  }
  passed += 1;

  wrongDeclaration = exactDeclaration;
  wrongDeclaration.mSelector = (AudioObjectPropertySelector)0x7A7A7A7A;
  if (EvaluateCustomPropertyDeclarations(&wrongDeclaration, 1) !=
      kSnapshotReadUnavailable) {
    return 1;
  }
  passed += 1;

  CFDataRef validData = CFDataCreate(kCFAllocatorDefault, (const UInt8 *)&first,
                                     (CFIndex)sizeof(first));
  OSVADiagnosticSnapshot decoded;
  if (validData == NULL ||
      DecodeSnapshotPropertyList(validData, &decoded) != kSnapshotReadOK ||
      !SharedStateEqual(&first, &decoded)) {
    if (validData != NULL) {
      CFRelease(validData);
    }
    return 1;
  }
  CFRelease(validData);
  passed += 1;

  CFDataRef shortData = CFDataCreate(kCFAllocatorDefault, (const UInt8 *)&first,
                                     (CFIndex)sizeof(first) - 1);
  if (shortData == NULL ||
      DecodeSnapshotPropertyList(shortData, &decoded) !=
          kSnapshotReadSchemaMismatch) {
    if (shortData != NULL) {
      CFRelease(shortData);
    }
    return 1;
  }
  CFRelease(shortData);
  passed += 1;

  CFStringRef wrongConcreteType = CFSTR("not snapshot bytes");
  if (DecodeSnapshotPropertyList(wrongConcreteType, &decoded) !=
      kSnapshotReadSchemaMismatch) {
    return 1;
  }
  passed += 1;

  OSVADiagnosticSnapshot wrongSchema = first;
  wrongSchema.schema_version += 1;
  CFDataRef wrongSchemaData =
      CFDataCreate(kCFAllocatorDefault, (const UInt8 *)&wrongSchema,
                   (CFIndex)sizeof(wrongSchema));
  if (wrongSchemaData == NULL ||
      DecodeSnapshotPropertyList(wrongSchemaData, &decoded) !=
          kSnapshotReadSchemaMismatch) {
    if (wrongSchemaData != NULL) {
      CFRelease(wrongSchemaData);
    }
    return 1;
  }
  CFRelease(wrongSchemaData);
  passed += 1;

  const EndpointObservation firstObservation = {
      .snapshot_sequence = first.snapshot_sequence,
      .captured_host_ticks = first.captured_host_ticks,
  };
  const EndpointObservation writerObservation = {
      .snapshot_sequence = first.snapshot_sequence + 1,
      .captured_host_ticks = first.captured_host_ticks + 1,
  };
  const EndpointObservation finalObservation = {
      .snapshot_sequence = first.snapshot_sequence + 2,
      .captured_host_ticks = first.captured_host_ticks + 2,
  };
  PrintSnapshotJSON(kOSVAObjectIDVisibleInputDevice,
                    kOSVAObjectIDHiddenWriterDevice, "self-test-fixture",
                    &firstObservation, &writerObservation, &finalObservation,
                    &first);

  printf("{\"schema\":1,\"mode\":\"self-test\",\"passed\":true,"
         "\"tests\":%u,\"coreAudioIOStarted\":false,"
         "\"routesMutated\":false}\n",
         passed);
  return 0;
}

typedef struct DecodedV2Snapshot {
  OSVADiagnosticSnapshotV2Header header;
  OSVADiagnosticRegistryClientSnapshot *registry;
} DecodedV2Snapshot;

static void ReleaseV2Snapshot(DecodedV2Snapshot *snapshot) {
  free(snapshot->registry);
  memset(snapshot, 0, sizeof(*snapshot));
}

static bool BytesAreZero(const void *bytes, size_t count) {
  const UInt8 *value = bytes;
  for (size_t index = 0; index < count; ++index)
    if (value[index] != 0) return false;
  return true;
}

static UInt64 V2InvariantMask(void) {
  return kOSVADiagnosticInvariantGlobalMatchesCoreSlots |
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
}

static bool V2HeaderGeometryIsExact(const OSVADiagnosticSnapshotV2Header *h,
                                  size_t byteCount) {
  const size_t headerSize = sizeof(*h);
  const size_t recordSize = sizeof(OSVADiagnosticRegistryClientSnapshot);
  return h->schema_version == kOSVADiagnosticSnapshotV2SchemaVersion &&
      h->header_size == headerSize && h->registry_record_size == recordSize &&
      byteCount >= headerSize &&
      byteCount <= kOSVADiagnosticSnapshotV2MaximumByteCount &&
      h->registry_record_count <=
          (kOSVADiagnosticSnapshotV2MaximumByteCount - headerSize) / recordSize &&
      h->registry_record_count <= (SIZE_MAX - headerSize) / recordSize &&
      headerSize + (size_t)h->registry_record_count * recordSize == byteCount &&
      h->total_byte_count == byteCount &&
      h->core_slot_capacity == kOSVADiagnosticClientSlotCapacity &&
      h->reserved_header == 0 &&
      BytesAreZero(h->reserved, sizeof(h->reserved));
}

static bool TransitionFieldsAreExact(
    const OSVADiagnosticTransitionSnapshot *transition, bool core) {
  return transition->reserved == 0 &&
      transition->type <= kOSVADiagnosticTransitionSeedCleared &&
      transition->endpoint_role <= kOSVADiagnosticEndpointHiddenWriter &&
      (transition->slot_index == UINT32_MAX ||
       transition->slot_index < kOSVADiagnosticClientSlotCapacity) &&
      (!core || transition->type != kOSVADiagnosticTransitionDriverClientAdded) &&
      (!core || transition->type != kOSVADiagnosticTransitionDriverClientRemoved);
}

static bool FailureFieldsAreExact(
    const OSVADiagnosticAdmissionFailureSnapshot *failure) {
  if (failure->sequence == 0) return BytesAreZero(failure, sizeof(*failure));
  if (failure->reserved != 0 || failure->host_ticks == 0 ||
      failure->operation < kOSVADiagnosticAdmissionAdd ||
      failure->operation > kOSVADiagnosticAdmissionStop ||
      failure->reason < kOSVADiagnosticFailureNotInitialized ||
      failure->reason > kOSVADiagnosticFailureCoreRejected ||
      (failure->device_object_id != kOSVAObjectIDVisibleInputDevice &&
       failure->device_object_id != kOSVAObjectIDHiddenWriterDevice) ||
      failure->status == noErr) return false;
  if ((failure->registry_index == UINT64_MAX) !=
      (failure->driver_client_generation == 0)) return false;
  if (failure->reason == kOSVADiagnosticFailureCoreRejected)
  {
    if ((failure->operation != kOSVADiagnosticAdmissionStart &&
         failure->operation != kOSVADiagnosticAdmissionStop) ||
        failure->registry_index == UINT64_MAX || failure->core_status < 1 ||
        failure->core_status > 15) return false;
    /* Frozen OSVAStatus-to-OSStatus mapping; failure status is exact evidence. */
    const bool illegal = failure->core_status == 1 || failure->core_status == 4 ||
        failure->core_status == 5 || failure->core_status == 7 ||
        failure->core_status == 8 || failure->core_status == 9 ||
        failure->core_status == 10;
    return failure->status == (illegal ? kAudioHardwareIllegalOperationError
                                     : kAudioHardwareUnspecifiedError);
  }
  if (failure->core_status != 0) return false;
  if (failure->reason == kOSVADiagnosticFailureRegistrationAllocation ||
      failure->reason == kOSVADiagnosticFailureIdentityExhausted)
    return failure->operation == kOSVADiagnosticAdmissionAdd &&
        failure->registry_index == UINT64_MAX &&
        failure->status == kAudioHardwareUnspecifiedError;
  if (failure->status != kAudioHardwareIllegalOperationError) return false;
  if (failure->reason == kOSVADiagnosticFailureDuplicateRegistration)
    return failure->operation == kOSVADiagnosticAdmissionAdd &&
        failure->registry_index != UINT64_MAX;
  if (failure->reason == kOSVADiagnosticFailureAlreadyStarted)
    return failure->operation == kOSVADiagnosticAdmissionStart &&
        failure->registry_index != UINT64_MAX;
  if (failure->reason == kOSVADiagnosticFailureNotStarted)
    return failure->operation == kOSVADiagnosticAdmissionStop &&
        failure->registry_index != UINT64_MAX;
  if (failure->reason == kOSVADiagnosticFailureRemoveWhileStarted)
    return failure->operation == kOSVADiagnosticAdmissionRemove &&
        failure->registry_index != UINT64_MAX;
  if (failure->reason == kOSVADiagnosticFailureMissingRegistration)
    return failure->operation != kOSVADiagnosticAdmissionAdd &&
        failure->registry_index == UINT64_MAX;
  return true;
}

static bool RTRecordFieldsAreExact(const OSVADiagnosticSnapshotV2State *s) {
  const UInt32 knownRecordFlags = kOSVADiagnosticRecordPresent |
      kOSVADiagnosticRecordLastSuccessTupleValid |
      kOSVADiagnosticRecordLastCallValid | kOSVADiagnosticRecordUsedFallback |
      kOSVADiagnosticRecordEpochMappingValid;
  for (size_t index = 0; index < 2; ++index) {
    const OSVADiagnosticZeroTimestampSnapshot *zero = &s->zero_timestamp[index];
    const OSVADiagnosticIOSnapshot *io = &s->io[index];
    const OSVADiagnosticIOWorkLoopSnapshot *loop = &s->io_work_loop[index];
    if (zero->reserved != 0 || io->reserved != 0 ||
        (zero->flags & ~knownRecordFlags) != 0 ||
        (io->flags & ~knownRecordFlags) != 0 ||
        (loop->flags & (UInt32)~(kOSVADiagnosticRecordPresent |
                                 kOSVADiagnosticRecordLastCallValid)) != 0 ||
        (zero->metadata_sequence & UINT64_C(1)) != 0 ||
        (io->metadata_sequence & UINT64_C(1)) != 0 ||
        (loop->metadata_sequence & UINT64_C(1)) != 0) return false;
  }
  return true;
}

static bool FlagMatches(UInt64 flags, UInt64 bit, bool condition) {
  return ((flags & bit) != 0) == condition;
}

static bool V2InventoryIsExact(const DecodedV2Snapshot *snapshot) {
  const OSVADiagnosticSnapshotV2Header *h = &snapshot->header;
  const OSVADiagnosticSnapshotV2State *s = &h->state;
  const UInt64 knownFlags = V2InvariantMask() |
      kOSVADiagnosticSnapshotCoreInitialized | kOSVADiagnosticSnapshotTimelineActive;
  if ((s->invariant_flags & ~knownFlags) != 0 ||
      (s->invariant_flags & kOSVADiagnosticInvariantCompleteRegistryInventory) == 0 ||
      (s->invariant_flags & kOSVADiagnosticSnapshotCoreInitialized) == 0 ||
      s->snapshot_sequence == 0 || s->captured_host_ticks == 0 ||
      s->driver_instance_generation == 0 || s->host_ticks_per_second == 0 ||
      (s->core_lifecycle_sequence & UINT64_C(1)) != 0 ||
      s->driver_registered_count != h->registry_record_count ||
      !TransitionFieldsAreExact(&s->last_driver_transition, false) ||
      !TransitionFieldsAreExact(&s->last_core_transition, true) ||
      !FailureFieldsAreExact(&h->last_admission_failure) ||
      !RTRecordFieldsAreExact(s)) return false;
  UInt64 registered[2] = {0, 0}, started[2] = {0, 0};
  UInt64 coreCount[2] = {0, 0}, coreBitmap = 0, references = 0;
  bool currentSlots = true, leasesMatch = true;
  for (size_t index = 0; index < kOSVADiagnosticClientSlotCapacity; ++index) {
    const OSVADiagnosticCoreClientSlotSnapshot *core = &h->core_client_slots[index];
    if (core->reserved != 0 || core->endpoint_role > 2) return false;
    if (core->session_id == 0) continue; /* Retired slots retain their metadata. */
    if (core->endpoint_role == 0) return false;
    coreCount[core->endpoint_role - 1] += 1;
    coreBitmap |= UINT64_C(1) << index;
    if (core->timeline_seed != s->timeline_seed) currentSlots = false;
  }
  for (size_t index = 0; index < (size_t)h->registry_record_count; ++index) {
    const OSVADiagnosticRegistryClientSnapshot *record = &snapshot->registry[index];
    const OSVADiagnosticDriverClientSlotSnapshot *client = &record->client;
    if (record->registry_index == UINT64_MAX ||
        (index != 0 && record->registry_index <= snapshot->registry[index - 1].registry_index) ||
        client->generation == 0 || client->registration_host_ticks == 0 ||
        client->last_transition_host_ticks == 0 || client->reserved != 0 ||
        (client->flags != kOSVADiagnosticDriverSlotRegistered &&
         client->flags != (kOSVADiagnosticDriverSlotRegistered |
                          kOSVADiagnosticDriverSlotStarted |
                          kOSVADiagnosticDriverSlotLeaseValid)) ||
        (client->device_object_id != kOSVAObjectIDVisibleInputDevice &&
         client->device_object_id != kOSVAObjectIDHiddenWriterDevice) ||
        client->endpoint_role !=
            (client->device_object_id == kOSVAObjectIDVisibleInputDevice ? 1U : 2U))
      return false;
    /* Complete inventory also rejects duplicate key/generation provenance. */
    for (size_t earlier = 0; earlier < index; ++earlier) {
      const OSVADiagnosticDriverClientSlotSnapshot *other = &snapshot->registry[earlier].client;
      if (other->generation == client->generation ||
          (other->device_object_id == client->device_object_id &&
           other->client_id == client->client_id)) return false;
    }
    const size_t role = client->endpoint_role - 1U;
    registered[role] += 1;
    if ((client->flags & kOSVADiagnosticDriverSlotStarted) == 0) {
      if (client->lease_session_id != 0 || client->lease_timeline_seed != 0 ||
          client->core_client_slot != UINT32_MAX || client->io_start_depth != 0)
        return false;
      continue;
    }
    started[role] += 1;
    if (client->io_start_depth != 1 || client->start_host_ticks == 0 ||
        client->lease_session_id == 0 || client->lease_timeline_seed == 0 ||
        client->core_client_slot >= kOSVADiagnosticClientSlotCapacity) return false;
    const OSVADiagnosticCoreClientSlotSnapshot *core =
        &h->core_client_slots[client->core_client_slot];
    const UInt64 bit = UINT64_C(1) << client->core_client_slot;
    const UInt64 key = ((UInt64)client->device_object_id << 32U) | client->client_id;
    if ((references & bit) != 0 || core->session_id != client->lease_session_id ||
        core->client_id != key || core->timeline_seed != client->lease_timeline_seed ||
        core->endpoint_role != client->endpoint_role) leasesMatch = false;
    references |= bit;
  }
  if (registered[0] != s->visible_driver_registered_count ||
      registered[1] != s->hidden_driver_registered_count ||
      started[0] != s->visible_driver_started_count ||
      started[1] != s->hidden_driver_started_count ||
      started[0] + started[1] != s->driver_started_count ||
      coreBitmap != s->core_active_slot_bitmap ||
      coreCount[0] + coreCount[1] != s->core_active_slot_count) return false;
  leasesMatch = leasesMatch && references == coreBitmap;
  const bool ringMatches = s->timeline_seed == 0 ||
      (s->timeline_seed == s->current_seed_generation &&
       ((s->io[1].last_published_frame_seed == s->timeline_seed) ==
        (s->io[1].last_published_seed_generation == s->current_seed_generation)) &&
       ((s->io[0].last_consumed_frame_seed == s->timeline_seed) ==
        (s->io[0].last_consumed_seed_generation == s->current_seed_generation)));
  return FlagMatches(s->invariant_flags, kOSVADiagnosticSnapshotTimelineActive,
                     s->timeline_seed != 0) &&
      FlagMatches(s->invariant_flags, kOSVADiagnosticInvariantGlobalMatchesCoreSlots,
                  s->active_client_count == s->core_active_slot_count) &&
      FlagMatches(s->invariant_flags, kOSVADiagnosticInvariantEndpointsMatchCoreSlots,
                  s->visible_input_active_count == coreCount[0] &&
                  s->hidden_writer_active_count == coreCount[1]) &&
      FlagMatches(s->invariant_flags, kOSVADiagnosticInvariantDriverStartsMatchCoreSlots,
                  leasesMatch) &&
      FlagMatches(s->invariant_flags, kOSVADiagnosticInvariantIdleImpliesClockCleared,
                  s->active_client_count != 0 ||
                  (s->timeline_seed == 0 && s->anchor_host_ticks == 0 &&
                   s->current_seed_generation == 0)) &&
      FlagMatches(s->invariant_flags, kOSVADiagnosticInvariantActiveImpliesClockValid,
                  s->active_client_count == 0 ||
                  (s->timeline_seed != 0 && s->anchor_host_ticks != 0 &&
                   s->current_seed_generation != 0)) &&
      FlagMatches(s->invariant_flags, kOSVADiagnosticInvariantActiveSlotCountsWithinCapacity,
                  s->core_active_slot_count <= 64 && s->driver_started_count <= 64) &&
      FlagMatches(s->invariant_flags, kOSVADiagnosticInvariantStartStopBalancedAtIdle,
                  s->active_client_count != 0 ||
                  s->global_start_transition_count == s->global_stop_transition_count) &&
      FlagMatches(s->invariant_flags, kOSVADiagnosticInvariantSeedCreateClearBalancedAtIdle,
                  s->active_client_count != 0 || s->seed_create_count == s->seed_clear_count) &&
      FlagMatches(s->invariant_flags, kOSVADiagnosticInvariantRingGenerationMatchesCurrentSeed,
                  ringMatches) &&
      FlagMatches(s->invariant_flags,
                  kOSVADiagnosticInvariantNoActiveSlotReferencesRetiredGeneration, currentSlots);
}

static SnapshotReadResult DecodeV2PropertyList(CFPropertyListRef propertyList,
                                             DecodedV2Snapshot *out) {
  memset(out, 0, sizeof(*out));
  if (propertyList == NULL || CFGetTypeID(propertyList) != CFDataGetTypeID())
    return kSnapshotReadSchemaMismatch;
  CFDataRef data = (CFDataRef)propertyList;
  const CFIndex length = CFDataGetLength(data);
  if (length < (CFIndex)sizeof(out->header) ||
      length > kOSVADiagnosticSnapshotV2MaximumByteCount)
    return kSnapshotReadSchemaMismatch;
  /* Only an aligned fixed header is decoded before checked geometry. */
  CFDataGetBytes(data, CFRangeMake(0, sizeof(out->header)), (UInt8 *)&out->header);
  if (!V2HeaderGeometryIsExact(&out->header, (size_t)length)) {
    memset(out, 0, sizeof(*out));
    return kSnapshotReadSchemaMismatch;
  }
  const size_t count = (size_t)out->header.registry_record_count;
  if (count != 0) {
    out->registry = calloc(count, sizeof(*out->registry));
    if (out->registry == NULL) { ReleaseV2Snapshot(out); return kSnapshotReadFailed; }
    CFDataGetBytes(data, CFRangeMake(sizeof(out->header),
                   (CFIndex)(count * sizeof(*out->registry))), (UInt8 *)out->registry);
  }
  if (!V2InventoryIsExact(out)) {
    ReleaseV2Snapshot(out);
    return kSnapshotReadSchemaMismatch;
  }
  return kSnapshotReadOK;
}

static SnapshotReadResult ReadV2Snapshot(AudioDeviceID device,
                                       DecodedV2Snapshot *out, OSStatus *statusOut) {
  memset(out, 0, sizeof(*out));
  *statusOut = noErr;
  AudioObjectPropertyAddress address = PropertyAddress(kOSVADiagnosticSnapshotV2Property);
  UInt32 size = 0;
  OSStatus status = AudioObjectGetPropertyDataSize(device, &address, 0, NULL, &size);
  if (status != noErr) { *statusOut = status; return ResultForPropertyStatus(status); }
  if (size != sizeof(CFPropertyListRef)) return kSnapshotReadSchemaMismatch;
  CFPropertyListRef propertyList = NULL;
  UInt32 returnedSize = size;
  status = AudioObjectGetPropertyData(device, &address, 0, NULL, &returnedSize, &propertyList);
  SnapshotReadResult result;
  if (status != noErr) { *statusOut = status; result = ResultForPropertyStatus(status); }
  else if (returnedSize != size) result = kSnapshotReadSchemaMismatch;
  else result = DecodeV2PropertyList(propertyList, out);
  if (propertyList != NULL) CFRelease(propertyList);
  return result;
}

static bool V2SharedStateEqual(const DecodedV2Snapshot *left,
                               const DecodedV2Snapshot *right) {
  OSVADiagnosticSnapshotV2Header l = left->header, r = right->header;
  l.state.snapshot_sequence = r.state.snapshot_sequence = 0;
  l.state.captured_host_ticks = r.state.captured_host_ticks = 0;
  /* Like v1, compare lifecycle/identity, not independently advancing RT reads.
   * Only local copies are normalized; final-read diagnostics remain intact. */
  memset(l.state.zero_timestamp, 0, sizeof(l.state.zero_timestamp));
  memset(r.state.zero_timestamp, 0, sizeof(r.state.zero_timestamp));
  memset(l.state.io, 0, sizeof(l.state.io));
  memset(r.state.io, 0, sizeof(r.state.io));
  memset(l.state.io_work_loop, 0, sizeof(l.state.io_work_loop));
  memset(r.state.io_work_loop, 0, sizeof(r.state.io_work_loop));
  return memcmp(&l, &r, sizeof(l)) == 0 &&
      (l.registry_record_count == 0 ||
       memcmp(left->registry, right->registry,
              (size_t)l.registry_record_count * sizeof(*left->registry)) == 0);
}

static void PrintV2JSON(AudioDeviceID visible, AudioDeviceID writer,
                        const char *mode, const DecodedV2Snapshot *snapshot) {
  const OSVADiagnosticSnapshotV2Header *h = &snapshot->header;
  const OSVADiagnosticSnapshotV2State *s = &h->state;
  printf("{\"readerSchema\":2,\"mode\":\"%s\",\"claim\":"
         "\"read-only-complete-virtual-driver-diagnostic-snapshot\","
         "\"visibleDeviceUID\":\"%s\",\"visibleDeviceID\":%" PRIu32
         ",\"writerDeviceUID\":\"%s\",\"writerDeviceID\":%" PRIu32
         ",\"endpointReadsCoherent\":true,\"snapshotSchemaVersion\":2,"
         "\"totalByteCount\":%" PRIu64 ",\"registryRecordCount\":%" PRIu64
         ",\"registryRecordSize\":%" PRIu64 ",\"registryRevision\":%" PRIu64
         ",\"completeRegistryInventory\":true,\"coreSlotCapacity\":%" PRIu32
         ",\"capacityInvariantScope\":\"active-core-resources-only\","
         "\"allDeclaredInvariantsHold\":%s,\"invariantFlags\":\"%016" PRIx64 "\""
         ",\"snapshotSequence\":%" PRIu64 ",\"capturedHostTicks\":%" PRIu64
         ",\"driverInstanceGeneration\":%" PRIu64 ",\"timelineSeed\":%" PRIu64
         ",\"currentSeedGeneration\":%" PRIu64 ",\"activeClientCount\":%" PRIu64
         ",\"driverRegisteredCount\":%" PRIu64 ",\"driverStartedCount\":%" PRIu64,
         mode, OSVA_VISIBLE_INPUT_DEVICE_UID, visible, OSVA_HIDDEN_WRITER_DEVICE_UID, writer,
         h->total_byte_count, h->registry_record_count, h->registry_record_size,
         h->registry_revision, h->core_slot_capacity,
         BooleanJSON((s->invariant_flags & V2InvariantMask()) == V2InvariantMask()),
         s->invariant_flags, s->snapshot_sequence, s->captured_host_ticks,
         s->driver_instance_generation, s->timeline_seed, s->current_seed_generation,
         s->active_client_count, s->driver_registered_count, s->driver_started_count);
#define OSVA_PRINT_V2_SCALAR(field, key) printf(",\"" key "\":%" PRIu64, s->field)
  OSVA_PRINT_V2_SCALAR(driver_lifecycle_sequence, "driverLifecycleSequence");
  OSVA_PRINT_V2_SCALAR(core_lifecycle_sequence, "coreLifecycleSequence");
  OSVA_PRINT_V2_SCALAR(host_ticks_per_second, "hostTicksPerSecond");
  OSVA_PRINT_V2_SCALAR(anchor_host_ticks, "anchorHostTicks");
  OSVA_PRINT_V2_SCALAR(last_issued_seed, "lastIssuedSeed");
  OSVA_PRINT_V2_SCALAR(last_issued_session_id, "lastIssuedSessionID");
  OSVA_PRINT_V2_SCALAR(visible_input_active_count, "visibleInputActiveCount");
  OSVA_PRINT_V2_SCALAR(hidden_writer_active_count, "hiddenWriterActiveCount");
  OSVA_PRINT_V2_SCALAR(core_active_slot_count, "coreActiveSlotCount");
  OSVA_PRINT_V2_SCALAR(core_active_slot_bitmap, "coreActiveSlotBitmap");
  OSVA_PRINT_V2_SCALAR(visible_driver_registered_count, "visibleDriverRegisteredCount");
  OSVA_PRINT_V2_SCALAR(hidden_driver_registered_count, "hiddenDriverRegisteredCount");
  OSVA_PRINT_V2_SCALAR(visible_driver_started_count, "visibleDriverStartedCount");
  OSVA_PRINT_V2_SCALAR(hidden_driver_started_count, "hiddenDriverStartedCount");
  OSVA_PRINT_V2_SCALAR(driver_client_add_attempt_count, "driverClientAddAttemptCount");
  OSVA_PRINT_V2_SCALAR(driver_client_add_count, "driverClientAddCount");
  OSVA_PRINT_V2_SCALAR(driver_client_remove_attempt_count, "driverClientRemoveAttemptCount");
  OSVA_PRINT_V2_SCALAR(driver_client_remove_count, "driverClientRemoveCount");
  OSVA_PRINT_V2_SCALAR(global_start_attempt_count, "globalStartAttemptCount");
  OSVA_PRINT_V2_SCALAR(global_start_transition_count, "globalStartTransitionCount");
  OSVA_PRINT_V2_SCALAR(global_stop_attempt_count, "globalStopAttemptCount");
  OSVA_PRINT_V2_SCALAR(global_stop_transition_count, "globalStopTransitionCount");
  OSVA_PRINT_V2_SCALAR(seed_create_count, "seedCreateCount");
  OSVA_PRINT_V2_SCALAR(seed_clear_count, "seedClearCount");
  OSVA_PRINT_V2_SCALAR(last_seed_create_host_ticks, "lastSeedCreateHostTicks");
  OSVA_PRINT_V2_SCALAR(last_seed_clear_host_ticks, "lastSeedClearHostTicks");
  OSVA_PRINT_V2_SCALAR(last_cleared_seed, "lastClearedSeed");
  OSVA_PRINT_V2_SCALAR(last_cleared_seed_generation, "lastClearedSeedGeneration");
  OSVA_PRINT_V2_SCALAR(last_cleared_anchor_host_ticks, "lastClearedAnchorHostTicks");
#undef OSVA_PRINT_V2_SCALAR
  printf(",\"lastAdmissionFailure\":");
  const OSVADiagnosticAdmissionFailureSnapshot *f = &h->last_admission_failure;
  printf("{\"sequence\":%" PRIu64 ",\"hostTicks\":%" PRIu64
         ",\"registryIndex\":%" PRIu64 ",\"driverClientGeneration\":%" PRIu64
         ",\"operation\":%" PRIu32 ",\"reason\":%" PRIu32
         ",\"deviceObjectID\":%" PRIu32 ",\"clientID\":%" PRIu32
         ",\"processID\":%" PRId32 ",\"status\":%" PRId32
         ",\"coreStatus\":%" PRId32 "},\"lastDriverTransition\":",
         f->sequence, f->host_ticks, f->registry_index, f->driver_client_generation,
         f->operation, f->reason, f->device_object_id, f->client_id,
         f->process_id, f->status, f->core_status);
  PrintTransition(&s->last_driver_transition);
  printf(",\"lastCoreTransition\":"); PrintTransition(&s->last_core_transition);
  printf(",\"zeroTimestamp\":["); PrintZeroTimestamp(&s->zero_timestamp[0], 1);
  putchar(','); PrintZeroTimestamp(&s->zero_timestamp[1], 2);
  printf("],\"io\":["); PrintIO(&s->io[0], 1); putchar(','); PrintIO(&s->io[1], 2);
  printf("],\"ioWorkLoop\":["); PrintIOWorkLoop(&s->io_work_loop[0], 1);
  putchar(','); PrintIOWorkLoop(&s->io_work_loop[1], 2);
  printf("],\"registry\":[");
  for (size_t index = 0; index < (size_t)h->registry_record_count; ++index) {
    const OSVADiagnosticRegistryClientSnapshot *r = &snapshot->registry[index];
    const OSVADiagnosticDriverClientSlotSnapshot *c = &r->client;
    if (index != 0) putchar(',');
    printf("{\"registryIndex\":%" PRIu64 ",\"generation\":%" PRIu64
           ",\"registrationHostTicks\":%" PRIu64 ",\"startHostTicks\":%" PRIu64
           ",\"lastTransitionHostTicks\":%" PRIu64 ",\"leaseSessionID\":%" PRIu64
           ",\"leaseTimelineSeed\":%" PRIu64 ",\"flags\":%" PRIu32
           ",\"deviceObjectID\":%" PRIu32 ",\"clientID\":%" PRIu32
           ",\"processID\":%" PRId32 ",\"endpointRole\":%" PRIu32
           ",\"coreClientSlot\":%" PRIu32 ",\"ioStartDepth\":%" PRIu32 "}",
           r->registry_index, c->generation, c->registration_host_ticks, c->start_host_ticks,
           c->last_transition_host_ticks, c->lease_session_id, c->lease_timeline_seed,
           c->flags, c->device_object_id, c->client_id, c->process_id,
           c->endpoint_role, c->core_client_slot, c->io_start_depth);
  }
  printf("],\"coreClientSlots\":[");
  for (size_t index = 0; index < kOSVADiagnosticClientSlotCapacity; ++index) {
    const OSVADiagnosticCoreClientSlotSnapshot *c = &h->core_client_slots[index];
    if (index != 0) putchar(',');
    printf("{\"slotIndex\":%zu,\"sessionID\":%" PRIu64 ",\"clientID\":%" PRIu64
           ",\"timelineSeed\":%" PRIu64 ",\"endpointRole\":%" PRIu32 "}",
           index, c->session_id, c->client_id, c->timeline_seed, c->endpoint_role);
  }
  printf("]}\n");
}

static int RunV2Reader(void) {
  AudioDeviceID visible = kAudioObjectUnknown, writer = kAudioObjectUnknown;
  OSStatus status = TranslateExactDeviceUID(OSVA_VISIBLE_INPUT_DEVICE_UID, &visible);
  if (status != noErr || visible == kAudioObjectUnknown) return kExitPropertyUnavailable;
  status = TranslateExactDeviceUID(OSVA_HIDDEN_WRITER_DEVICE_UID, &writer);
  if (status != noErr || writer == kAudioObjectUnknown || visible == writer ||
      !DeviceUIDMatches(visible, OSVA_VISIBLE_INPUT_DEVICE_UID) ||
      !DeviceUIDMatches(writer, OSVA_HIDDEN_WRITER_DEVICE_UID)) return kExitPropertyUnavailable;
  for (size_t index = 0; index < 2; ++index) {
    SnapshotReadResult declaration = ValidateCustomPropertyDeclarationForSelector(
        index == 0 ? visible : writer, &status, kOSVADiagnosticSnapshotV2Property);
    if (declaration != kSnapshotReadOK) {
      fprintf(stderr, "osD2 v2 custom-property declaration unavailable or invalid\n");
      return ExitCodeForReadFailure(declaration);
    }
  }
  for (unsigned attempt = 0; attempt < kMaximumCoherenceAttempts; ++attempt) {
    DecodedV2Snapshot first = {0}, middle = {0}, last = {0};
    SnapshotReadResult result = ReadV2Snapshot(visible, &first, &status);
    if (result == kSnapshotReadOK) result = ReadV2Snapshot(writer, &middle, &status);
    if (result == kSnapshotReadOK) result = ReadV2Snapshot(visible, &last, &status);
    const bool coherent = result == kSnapshotReadOK &&
        V2SharedStateEqual(&first, &middle) && V2SharedStateEqual(&middle, &last) &&
        ExactTranslationsRemainStable(visible, writer);
    if (coherent) PrintV2JSON(visible, writer, "read-v2-once", &last);
    ReleaseV2Snapshot(&first); ReleaseV2Snapshot(&middle); ReleaseV2Snapshot(&last);
    if (coherent) return 0;
    if (result != kSnapshotReadOK && result != kSnapshotReadRetry) {
      fprintf(stderr, "osD2 v2 read unavailable, failed, or exact schema invalid; OSStatus %" PRId32 "\n", status);
      return ExitCodeForReadFailure(result);
    }
  }
  fprintf(stderr, "osD2 v2 complete snapshot unavailable or remained in transition\n");
  return kExitRetry;
}

static SnapshotReadResult DecodeV2FixtureBytes(const void *bytes, size_t length,
                                              DecodedV2Snapshot *out) {
  CFDataRef data = CFDataCreate(kCFAllocatorDefault, bytes, (CFIndex)length);
  if (data == NULL) return kSnapshotReadFailed;
  SnapshotReadResult result = DecodeV2PropertyList(data, out);
  CFRelease(data);
  return result;
}

static int RunV2SelfTest(void) {
  enum { kFixtureCount = 70 };
  const size_t byteCount = sizeof(OSVADiagnosticSnapshotV2Header) +
      kFixtureCount * sizeof(OSVADiagnosticRegistryClientSnapshot);
  UInt8 *bytes = calloc(1, byteCount + 1);
  if (bytes == NULL) return kExitInternalError;
  OSVADiagnosticSnapshotV2Header *h = (void *)bytes;
  OSVADiagnosticRegistryClientSnapshot *r = (void *)(bytes + sizeof(*h));
  h->schema_version = 2;
  h->header_size = sizeof(*h);
  h->total_byte_count = byteCount;
  h->registry_record_count = kFixtureCount;
  h->registry_record_size = sizeof(*r);
  h->registry_revision = kFixtureCount;
  h->core_slot_capacity = 64;
  h->state.snapshot_sequence = 1;
  h->state.captured_host_ticks = 3;
  h->state.driver_instance_generation = 1;
  h->state.driver_lifecycle_sequence = kFixtureCount;
  h->state.core_lifecycle_sequence = 2;
  h->state.host_ticks_per_second = 1000000000;
  h->state.invariant_flags = V2InvariantMask() | kOSVADiagnosticSnapshotCoreInitialized;
  h->state.driver_registered_count = kFixtureCount;
  h->state.visible_driver_registered_count = kFixtureCount / 2;
  h->state.hidden_driver_registered_count = kFixtureCount / 2;
  h->state.driver_client_add_attempt_count = kFixtureCount;
  h->state.driver_client_add_count = kFixtureCount;
  for (size_t index = 0; index < kFixtureCount; ++index) {
    r[index].registry_index = index;
    r[index].client.generation = index + 1;
    r[index].client.registration_host_ticks = 1;
    r[index].client.last_transition_host_ticks = 1;
    r[index].client.flags = kOSVADiagnosticDriverSlotRegistered;
    r[index].client.device_object_id = index % 2 == 0 ?
        kOSVAObjectIDVisibleInputDevice : kOSVAObjectIDHiddenWriterDevice;
    r[index].client.client_id = (UInt32)index + 1000U;
    r[index].client.process_id = (SInt32)index + 2000;
    r[index].client.endpoint_role = index % 2 == 0 ? 1U : 2U;
    r[index].client.core_client_slot = UINT32_MAX;
  }
  DecodedV2Snapshot decoded = {0};
  unsigned passed = 0;
#define OSVA_V2_TEST(condition) do { \
    if (!(condition)) { fprintf(stderr, "v2 self-test failed at line %d\n", __LINE__); \
      ReleaseV2Snapshot(&decoded); free(bytes); return kExitInternalError; } \
    passed += 1; \
  } while (0)
  OSVA_V2_TEST(DecodeV2FixtureBytes(bytes, byteCount, &decoded) == kSnapshotReadOK);
  OSVA_V2_TEST(decoded.header.registry_record_count == 70 &&
               decoded.registry[69].registry_index == 69);
  PrintV2JSON(kOSVAObjectIDVisibleInputDevice, kOSVAObjectIDHiddenWriterDevice,
              "self-test-v2-fixture", &decoded);
  ReleaseV2Snapshot(&decoded);
#define OSVA_V2_REJECT_MUTATION(field, value) do { \
    __typeof__(field) retained = (field); (field) = (value); \
    OSVA_V2_TEST(DecodeV2FixtureBytes(bytes, byteCount, &decoded) == kSnapshotReadSchemaMismatch); \
    (field) = retained; \
  } while (0)
  OSVA_V2_TEST(DecodeV2FixtureBytes(bytes, sizeof(*h) - 1, &decoded) == kSnapshotReadSchemaMismatch);
  OSVA_V2_TEST(DecodeV2FixtureBytes(bytes, byteCount - 1, &decoded) == kSnapshotReadSchemaMismatch);
  OSVA_V2_TEST(DecodeV2FixtureBytes(bytes, byteCount + 1, &decoded) == kSnapshotReadSchemaMismatch);
  OSVA_V2_REJECT_MUTATION(h->schema_version, 1);
  OSVA_V2_REJECT_MUTATION(h->header_size, sizeof(*h) - 8);
  OSVA_V2_REJECT_MUTATION(h->registry_record_size, sizeof(*r) - 8);
  OSVA_V2_REJECT_MUTATION(h->registry_record_count, UINT64_MAX);
  OSVA_V2_REJECT_MUTATION(h->registry_record_count, kFixtureCount - 1);
  OSVA_V2_REJECT_MUTATION(h->total_byte_count, byteCount + 1);
  OSVA_V2_REJECT_MUTATION(h->total_byte_count, kOSVADiagnosticSnapshotV2MaximumByteCount + 1);
  OSVA_V2_REJECT_MUTATION(h->core_slot_capacity, 65);
  OSVA_V2_REJECT_MUTATION(h->reserved_header, 1);
  OSVA_V2_REJECT_MUTATION(h->reserved[0], 1);
  OSVA_V2_REJECT_MUTATION(h->state.invariant_flags,
      h->state.invariant_flags | (UINT64_C(1) << 63));
  OSVA_V2_REJECT_MUTATION(h->state.invariant_flags,
      h->state.invariant_flags & (UInt64)~(UInt64)kOSVADiagnosticInvariantCompleteRegistryInventory);
  OSVA_V2_REJECT_MUTATION(h->state.driver_registered_count, 69);
  OSVA_V2_REJECT_MUTATION(h->state.visible_driver_registered_count, 34);
  OSVA_V2_REJECT_MUTATION(h->state.core_active_slot_count, 1);
  OSVA_V2_REJECT_MUTATION(h->state.active_client_count, 1); /* False green is rejected. */
  OSVA_V2_REJECT_MUTATION(h->state.core_lifecycle_sequence, 3);
  OSVA_V2_REJECT_MUTATION(h->core_client_slots[0].reserved, 1);
  OSVA_V2_REJECT_MUTATION(r[69].registry_index, 68);
  OSVA_V2_REJECT_MUTATION(r[69].registry_index, UINT64_MAX);
  OSVA_V2_REJECT_MUTATION(r[69].client.generation, r[0].client.generation);
  OSVA_V2_REJECT_MUTATION(r[68].client.client_id, r[0].client.client_id);
  OSVA_V2_REJECT_MUTATION(r[69].client.endpoint_role, 1);
  OSVA_V2_REJECT_MUTATION(r[69].client.device_object_id, 999);
  OSVA_V2_REJECT_MUTATION(r[69].client.flags, 0);
  OSVA_V2_REJECT_MUTATION(r[69].client.flags, 8);
  OSVA_V2_REJECT_MUTATION(r[69].client.core_client_slot, 0);
  OSVA_V2_REJECT_MUTATION(r[69].client.lease_session_id, 1);
  OSVA_V2_REJECT_MUTATION(r[69].client.io_start_depth, 1);
  OSVA_V2_REJECT_MUTATION(r[69].client.reserved, 1);
  OSVA_V2_REJECT_MUTATION(h->state.io[0].reserved, 1);
  OSVA_V2_REJECT_MUTATION(h->state.io[0].flags, 32);
  OSVA_V2_REJECT_MUTATION(h->state.last_driver_transition.type, 7);
  OSVA_V2_REJECT_MUTATION(h->state.last_driver_transition.slot_index, 64);
  h->last_admission_failure = (OSVADiagnosticAdmissionFailureSnapshot){
      .sequence = 1, .host_ticks = 2, .registry_index = UINT64_MAX,
      .operation = kOSVADiagnosticAdmissionAdd,
      .reason = kOSVADiagnosticFailureRegistrationAllocation,
      .device_object_id = kOSVAObjectIDVisibleInputDevice, .client_id = 2345,
      .process_id = 3456, .status = kAudioHardwareUnspecifiedError,
  };
  OSVA_V2_TEST(DecodeV2FixtureBytes(bytes, byteCount, &decoded) == kSnapshotReadOK);
  ReleaseV2Snapshot(&decoded);
  OSVA_V2_REJECT_MUTATION(h->last_admission_failure.operation, 5);
  OSVA_V2_REJECT_MUTATION(h->last_admission_failure.reason, 10);
  OSVA_V2_REJECT_MUTATION(h->last_admission_failure.status, noErr);
  OSVA_V2_REJECT_MUTATION(h->last_admission_failure.core_status, 99);
  OSVA_V2_REJECT_MUTATION(h->last_admission_failure.reserved, 1);
  h->last_admission_failure = (OSVADiagnosticAdmissionFailureSnapshot){
      .sequence = 2, .host_ticks = 3, .registry_index = 1,
      .driver_client_generation = 2, .operation = kOSVADiagnosticAdmissionStart,
      .reason = kOSVADiagnosticFailureCoreRejected,
      .device_object_id = kOSVAObjectIDHiddenWriterDevice, .client_id = 1001,
      .process_id = 2001, .status = kAudioHardwareUnspecifiedError,
      .core_status = 6, /* Frozen OSVA_STATUS_CLIENT_CAPACITY_EXHAUSTED. */
  };
  OSVA_V2_TEST(DecodeV2FixtureBytes(bytes, byteCount, &decoded) == kSnapshotReadOK);
  ReleaseV2Snapshot(&decoded);
  OSVA_V2_REJECT_MUTATION(h->last_admission_failure.core_status, 0);
  OSVA_V2_REJECT_MUTATION(h->last_admission_failure.core_status, 16);
  OSVA_V2_REJECT_MUTATION(h->last_admission_failure.status, kAudioHardwareIllegalOperationError);
  OSVA_V2_REJECT_MUTATION(h->last_admission_failure.driver_client_generation, 0);
  UInt8 *oversized = calloc(1, kOSVADiagnosticSnapshotV2MaximumByteCount + 1U);
  OSVA_V2_TEST(oversized != NULL);
  SnapshotReadResult oversizedResult = DecodeV2FixtureBytes(
      oversized, kOSVADiagnosticSnapshotV2MaximumByteCount + 1U, &decoded);
  free(oversized);
  OSVA_V2_TEST(oversizedResult == kSnapshotReadSchemaMismatch);
  /* Lifetime failure counts remain readable evidence, never schema errors. */
  h->state.zero_timestamp[0].epoch_mapping_unavailable_count = 2;
  h->state.io[1].epoch_mapping_unavailable_count = 3;
  OSVA_V2_TEST(DecodeV2FixtureBytes(bytes, byteCount, &decoded) == kSnapshotReadOK);
  ReleaseV2Snapshot(&decoded);
  /* Positive active writer+reader fixture checks the full lease/seed mapping. */
  h->state.active_client_count = h->state.core_active_slot_count = 2;
  h->state.visible_input_active_count = h->state.hidden_writer_active_count = 1;
  h->state.driver_started_count = 2;
  h->state.visible_driver_started_count = h->state.hidden_driver_started_count = 1;
  h->state.timeline_seed = h->state.current_seed_generation = 5;
  h->state.anchor_host_ticks = 1;
  h->state.last_issued_seed = 5;
  h->state.last_issued_session_id = 11;
  h->state.core_active_slot_bitmap = 3;
  h->state.global_start_attempt_count = h->state.global_start_transition_count = 2;
  h->state.seed_create_count = 1;
  h->state.invariant_flags |= kOSVADiagnosticSnapshotTimelineActive;
  for (size_t index = 0; index < 2; ++index) {
    r[index].client.flags = kOSVADiagnosticDriverSlotRegistered |
        kOSVADiagnosticDriverSlotStarted | kOSVADiagnosticDriverSlotLeaseValid;
    r[index].client.start_host_ticks = 2;
    r[index].client.lease_session_id = index + 10;
    r[index].client.lease_timeline_seed = 5;
    r[index].client.core_client_slot = (UInt32)index;
    r[index].client.io_start_depth = 1;
    h->core_client_slots[index] = (OSVADiagnosticCoreClientSlotSnapshot){
        .session_id = index + 10,
        .client_id = ((UInt64)r[index].client.device_object_id << 32U) |
                     r[index].client.client_id,
        .timeline_seed = 5, .endpoint_role = r[index].client.endpoint_role,
    };
  }
  OSVA_V2_TEST(DecodeV2FixtureBytes(bytes, byteCount, &decoded) == kSnapshotReadOK);
  DecodedV2Snapshot second = {0};
  OSVA_V2_TEST(DecodeV2FixtureBytes(bytes, byteCount, &second) == kSnapshotReadOK);
  OSVA_V2_TEST(V2SharedStateEqual(&decoded, &second));
  second.header.state.snapshot_sequence += 1;
  second.header.state.captured_host_ticks += 1;
  OSVA_V2_TEST(V2SharedStateEqual(&decoded, &second));
  /* Healthy active callbacks advance observational records, not lifecycle. */
  const OSVADiagnosticSnapshotV2State retainedState = h->state;
  for (size_t index = 0; index < 2; ++index) {
    h->state.zero_timestamp[index].sequence += 1;
    h->state.zero_timestamp[index].metadata_sequence += 2;
    h->state.zero_timestamp[index].call_count += 1;
    h->state.zero_timestamp[index].successful_return_count += 1;
    h->state.zero_timestamp[index].last_call_host_ticks += 1;
    h->state.io[index].sequence += 1;
    h->state.io[index].metadata_sequence += 2;
    h->state.io[index].operation_call_count += 1;
    h->state.io[index].valid_cycle_count += 1;
    h->state.io[index].core_ok_count += 1;
    h->state.io[index].requested_frame_count += 1;
    h->state.io[index].transferred_frame_count += 1;
    h->state.io_work_loop[index].sequence += 2;
    h->state.io_work_loop[index].metadata_sequence += 2;
    h->state.io_work_loop[index].begin_count += 1;
    h->state.io_work_loop[index].end_count += 1;
    h->state.io_work_loop[index].last_transition_host_ticks += 1;
  }
  ReleaseV2Snapshot(&second);
  OSVA_V2_TEST(DecodeV2FixtureBytes(bytes, byteCount, &second) == kSnapshotReadOK);
  OSVA_V2_TEST(V2SharedStateEqual(&decoded, &second));
  /* Coherence comparison must not erase the final read's diagnostic evidence. */
  OSVA_V2_TEST(memcmp(second.header.state.zero_timestamp, h->state.zero_timestamp,
                     sizeof(h->state.zero_timestamp)) == 0 &&
               memcmp(second.header.state.io, h->state.io,
                      sizeof(h->state.io)) == 0 &&
               memcmp(second.header.state.io_work_loop, h->state.io_work_loop,
                      sizeof(h->state.io_work_loop)) == 0);
  h->state = retainedState;
  second.registry[69].client.process_id += 1;
  OSVA_V2_TEST(!V2SharedStateEqual(&decoded, &second));
  second.registry[69].client.process_id -= 1;
#define OSVA_V2_REJECT_COHERENCE_MUTATION(field) do { \
    __typeof__(field) retained = (field); (field) += 1; \
    OSVA_V2_TEST(!V2SharedStateEqual(&decoded, &second)); \
    (field) = retained; \
  } while (0)
  OSVA_V2_REJECT_COHERENCE_MUTATION(second.header.registry_revision);
  OSVA_V2_REJECT_COHERENCE_MUTATION(second.header.state.timeline_seed);
  OSVA_V2_REJECT_COHERENCE_MUTATION(second.header.core_client_slots[0].session_id);
  OSVA_V2_REJECT_COHERENCE_MUTATION(second.header.state.driver_lifecycle_sequence);
  OSVA_V2_REJECT_COHERENCE_MUTATION(second.header.state.core_lifecycle_sequence);
  OSVA_V2_REJECT_COHERENCE_MUTATION(second.header.last_admission_failure.sequence);
#undef OSVA_V2_REJECT_COHERENCE_MUTATION
  ReleaseV2Snapshot(&decoded); ReleaseV2Snapshot(&second);
  OSVA_V2_REJECT_MUTATION(r[0].client.lease_session_id, 99);
  OSVA_V2_REJECT_MUTATION(r[0].client.lease_timeline_seed, 4);
  OSVA_V2_REJECT_MUTATION(r[0].client.core_client_slot, 64);
  OSVA_V2_REJECT_MUTATION(r[0].client.io_start_depth, 2);
  OSVA_V2_REJECT_MUTATION(h->core_client_slots[0].timeline_seed, 4);
  OSVA_V2_REJECT_MUTATION(h->state.io[1].last_published_frame_seed, 5);
  /* The mismatch above is representable when its invariant is truthfully clear. */
  r[0].client.lease_session_id = 99;
  h->state.invariant_flags &= (UInt64)~(UInt64)kOSVADiagnosticInvariantDriverStartsMatchCoreSlots;
  OSVA_V2_TEST(DecodeV2FixtureBytes(bytes, byteCount, &decoded) == kSnapshotReadOK);
  ReleaseV2Snapshot(&decoded);
  r[0].client.lease_session_id = 10;
  h->state.invariant_flags |= kOSVADiagnosticInvariantDriverStartsMatchCoreSlots;
  /* A truthful non-green inventory is reportable; false-green was rejected above. */
  h->state.active_client_count = 3;
  h->state.timeline_seed = 0;
  h->state.invariant_flags &= (UInt64)~(UInt64)(kOSVADiagnosticSnapshotTimelineActive |
      kOSVADiagnosticInvariantNoActiveSlotReferencesRetiredGeneration);
  h->state.invariant_flags &= (UInt64)~(UInt64)(kOSVADiagnosticInvariantGlobalMatchesCoreSlots |
                                              kOSVADiagnosticInvariantActiveImpliesClockValid);
  OSVA_V2_TEST(DecodeV2FixtureBytes(bytes, byteCount, &decoded) == kSnapshotReadOK);
  ReleaseV2Snapshot(&decoded);
#undef OSVA_V2_REJECT_MUTATION
#undef OSVA_V2_TEST
  free(bytes);
  printf("{\"schema\":2,\"mode\":\"self-test-v2\",\"passed\":true,\"tests\":%u,"
         "\"coreAudioIOStarted\":false,\"routesMutated\":false}\n", passed);
  return 0;
}

int main(int argc, char *argv[]) {
  if (argc == 2 && strcmp(argv[1], "--self-test") == 0) {
    return RunSelfTest();
  }
  if (argc == 2 && strcmp(argv[1], "--read-once") == 0) {
    return RunReader();
  }
  if (argc == 2 && strcmp(argv[1], "--read-v2-once") == 0) return RunV2Reader();
  if (argc == 2 && strcmp(argv[1], "--self-test-v2") == 0) return RunV2SelfTest();
  fprintf(stderr, "usage: %s --self-test-v2 | --read-v2-once | --self-test | --read-once\n", argv[0]);
  return kExitUsage;
}
