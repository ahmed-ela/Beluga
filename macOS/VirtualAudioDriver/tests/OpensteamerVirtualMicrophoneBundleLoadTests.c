#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreFoundation/CoreFoundation.h>

#include "../include/OpensteamerVirtualMicrophoneDriver.h"

#include <stdbool.h>
#include <inttypes.h>
#include <stdio.h>
#include <string.h>

typedef void *(*OSVADriverFactoryFunction)(CFAllocatorRef allocator,
                                           CFUUIDRef requested_type_uuid);

static bool OSVACFStringEqualsCString(CFStringRef value,
                                      const char *expected) {
  if (value == NULL || expected == NULL) {
    return false;
  }
  CFStringRef expected_string =
      CFStringCreateWithCString(kCFAllocatorDefault, expected,
                                kCFStringEncodingUTF8);
  if (expected_string == NULL) {
    return false;
  }
  bool equal = CFEqual(value, expected_string);
  CFRelease(expected_string);
  return equal;
}

#define OSVA_IDLE_STATE(state)                                                  \
  ((state).active_client_count == 0 &&                                          \
   (state).visible_input_active_count == 0 &&                                   \
   (state).hidden_writer_active_count == 0 &&                                   \
   (state).core_active_slot_count == 0 &&                                       \
   (state).core_active_slot_bitmap == 0 &&                                      \
   (state).driver_registered_count == 0 &&                                      \
   (state).visible_driver_registered_count == 0 &&                              \
   (state).hidden_driver_registered_count == 0 &&                               \
   (state).driver_started_count == 0 &&                                         \
   (state).visible_driver_started_count == 0 &&                                 \
   (state).hidden_driver_started_count == 0 &&                                  \
   (state).timeline_seed == 0 && (state).current_seed_generation == 0 &&         \
   (state).anchor_host_ticks == 0 &&                                            \
   (state).global_start_transition_count == (state).global_stop_transition_count && \
   (state).seed_create_count == (state).seed_clear_count &&                      \
   (state).driver_lifecycle_sequence != 0 &&                                    \
   ((state).core_lifecycle_sequence & 1U) == 0)

static bool OSVAIdleDiagnosticSnapshotsAreExact(
    const OSVADiagnosticSnapshot *v1,
    const OSVADiagnosticSnapshotV2Header *v2,
    const OSVADiagnosticCoreClientSlotSnapshot *expected_core) {
  const UInt64 idle_flags = UINT64_C(0x3ff01);
  if (!OSVA_IDLE_STATE(*v1) || !OSVA_IDLE_STATE(v2->state) ||
      v1->driver_registered_slot_bitmap != 0 ||
      v1->driver_started_slot_bitmap != 0 ||
      v1->invariant_flags != idle_flags ||
      v2->state.invariant_flags !=
          (idle_flags | kOSVADiagnosticInvariantCompleteRegistryInventory) ||
      v2->schema_version != kOSVADiagnosticSnapshotV2SchemaVersion ||
      v2->header_size != sizeof(*v2) || v2->total_byte_count != sizeof(*v2) ||
      v2->registry_record_count != 0 ||
      v2->registry_record_size != sizeof(OSVADiagnosticRegistryClientSnapshot) ||
      v2->core_slot_capacity != kOSVADiagnosticClientSlotCapacity ||
      v2->reserved_header != 0 ||
      v2->state.driver_instance_generation != v1->driver_instance_generation) {
    return false;
  }
  for (size_t endpoint = 0; endpoint < 2; ++endpoint) {
    if (v1->io_work_loop[endpoint].current_count != 0 ||
        v2->state.io_work_loop[endpoint].current_count != 0 ||
        v1->io_work_loop[endpoint].begin_count !=
            v1->io_work_loop[endpoint].end_count ||
        v2->state.io_work_loop[endpoint].begin_count !=
            v2->state.io_work_loop[endpoint].end_count) {
      return false;
    }
  }
  const OSVADiagnosticCoreClientSlotSnapshot pristine = {0};
  for (size_t index = 0; index < kOSVADiagnosticClientSlotCapacity; ++index) {
    const OSVADiagnosticCoreClientSlotSnapshot *expected =
        expected_core == NULL ? &pristine : &expected_core[index];
    const OSVADiagnosticDriverClientSlotSnapshot *removed =
        &v1->driver_client_slots[index];
    if (expected->session_id != 0 ||
        memcmp(&v1->core_client_slots[index], expected, sizeof(*expected)) != 0 ||
        memcmp(&v2->core_client_slots[index], expected, sizeof(*expected)) != 0 ||
        removed->flags != 0 || removed->io_start_depth != 0 ||
        removed->lease_session_id != 0 || removed->lease_timeline_seed != 0 ||
        removed->core_client_slot != UINT32_MAX || removed->device_object_id != 0 ||
        removed->client_id != 0 || removed->process_id != 0 ||
        removed->endpoint_role != kOSVADiagnosticEndpointNone ||
        removed->registration_host_ticks != 0 || removed->start_host_ticks != 0 ||
        removed->reserved != 0) {
      return false;
    }
  }
  return true;
}

static bool OSVAValidateIdleSnapshotMutations(
    const OSVADiagnosticSnapshot *v1,
    const OSVADiagnosticSnapshotV2Header *v2,
    const OSVADiagnosticCoreClientSlotSnapshot *expected_core) {
  OSVADiagnosticSnapshotV2Header mutant;
  OSVADiagnosticSnapshot v1_mutant;
  unsigned rejected = 0;
#define REJECT_V2_MUTATION(field, value)                                        \
  do {                                                                         \
    mutant = *v2;                                                              \
    mutant.field = (value);                                                     \
    if (OSVAIdleDiagnosticSnapshotsAreExact(v1, &mutant, expected_core)) {       \
      fprintf(stderr, "FAIL idle validator accepted v2 mutation: %s\n", #field); \
      return false;                                                            \
    }                                                                          \
    ++rejected;                                                                \
  } while (0)
  REJECT_V2_MUTATION(core_client_slots[0].session_id, 1);
  REJECT_V2_MUTATION(core_client_slots[0].client_id,
                     v2->core_client_slots[0].client_id ^ 1U);
  REJECT_V2_MUTATION(core_client_slots[0].timeline_seed,
                     v2->core_client_slots[0].timeline_seed ^ 1U);
  REJECT_V2_MUTATION(core_client_slots[0].endpoint_role,
                     v2->core_client_slots[0].endpoint_role ^ 1U);
  REJECT_V2_MUTATION(core_client_slots[0].reserved, 1);
  REJECT_V2_MUTATION(core_client_slots[63].session_id, 1);
  REJECT_V2_MUTATION(state.active_client_count, 1);
  REJECT_V2_MUTATION(state.visible_input_active_count, 1);
  REJECT_V2_MUTATION(state.hidden_writer_active_count, 1);
  REJECT_V2_MUTATION(state.core_active_slot_count, 1);
  REJECT_V2_MUTATION(state.core_active_slot_bitmap, 1);
  REJECT_V2_MUTATION(state.driver_registered_count, 1);
  REJECT_V2_MUTATION(state.visible_driver_registered_count, 1);
  REJECT_V2_MUTATION(state.hidden_driver_registered_count, 1);
  REJECT_V2_MUTATION(state.driver_started_count, 1);
  REJECT_V2_MUTATION(state.visible_driver_started_count, 1);
  REJECT_V2_MUTATION(state.hidden_driver_started_count, 1);
  REJECT_V2_MUTATION(state.timeline_seed, 1);
  REJECT_V2_MUTATION(state.current_seed_generation, 1);
  REJECT_V2_MUTATION(state.anchor_host_ticks, 1);
  REJECT_V2_MUTATION(state.global_stop_transition_count,
                     v2->state.global_stop_transition_count + 1);
  REJECT_V2_MUTATION(state.seed_clear_count, v2->state.seed_clear_count + 1);
  REJECT_V2_MUTATION(state.driver_lifecycle_sequence,
                     0);
  REJECT_V2_MUTATION(state.core_lifecycle_sequence,
                     v2->state.core_lifecycle_sequence | 1U);
  REJECT_V2_MUTATION(state.io_work_loop[0].current_count, 1);
  REJECT_V2_MUTATION(state.io_work_loop[1].end_count,
                     v2->state.io_work_loop[1].end_count + 1);
  REJECT_V2_MUTATION(state.invariant_flags,
                     v2->state.invariant_flags ^
                         kOSVADiagnosticInvariantCompleteRegistryInventory);
  REJECT_V2_MUTATION(total_byte_count, sizeof(*v2) + 1);
  REJECT_V2_MUTATION(registry_record_count, 1);
  REJECT_V2_MUTATION(core_slot_capacity, 63);
#undef REJECT_V2_MUTATION
#define REJECT_V1_MUTATION(field, value)                                        \
  do {                                                                         \
    v1_mutant = *v1;                                                            \
    v1_mutant.field = (value);                                                  \
    if (OSVAIdleDiagnosticSnapshotsAreExact(&v1_mutant, v2, expected_core)) {    \
      fprintf(stderr, "FAIL idle validator accepted v1 mutation: %s\n", #field); \
      return false;                                                            \
    }                                                                          \
    ++rejected;                                                                \
  } while (0)
  REJECT_V1_MUTATION(driver_registered_slot_bitmap, 1);
  REJECT_V1_MUTATION(driver_started_slot_bitmap, 1);
  REJECT_V1_MUTATION(driver_client_slots[0].flags,
                     kOSVADiagnosticDriverSlotRegistered);
  REJECT_V1_MUTATION(core_client_slots[0].session_id, 1);
  REJECT_V1_MUTATION(io_work_loop[0].current_count, 1);
#undef REJECT_V1_MUTATION
  printf("PASS: %s idle diagnostic validator rejected %u one-field mutations\n",
         expected_core == NULL ? "pristine" : "retired", rejected);
  return true;
}

static bool OSVAValidateDiagnosticSnapshotProperty(
    AudioServerPlugInDriverRef driver, AudioObjectID device_object_id,
    const OSVADiagnosticCoreClientSlotSnapshot *expected_core) {
  AudioObjectPropertyAddress address = {
      .mSelector = kOSVADiagnosticSnapshotProperty,
      .mScope = kAudioObjectPropertyScopeGlobal,
      .mElement = kAudioObjectPropertyElementMain,
  };
  if (!(*driver)->HasProperty(driver, device_object_id, 0, &address)) {
    return false;
  }
  AudioObjectPropertyAddress info_address = {
      .mSelector = kAudioObjectPropertyCustomPropertyInfoList,
      .mScope = kAudioObjectPropertyScopeGlobal,
      .mElement = kAudioObjectPropertyElementMain,
  };
  if (!(*driver)->HasProperty(driver, device_object_id, 0, &info_address)) {
    return false;
  }
  Boolean settable = true;
  if ((*driver)->IsPropertySettable(driver, device_object_id, 0, &address,
                                    &settable) != noErr ||
      settable) {
    return false;
  }
  UInt32 size = 0;
  if ((*driver)->GetPropertyDataSize(driver, device_object_id, 0, &address, 0,
                                     NULL, &size) != noErr ||
      size != sizeof(CFPropertyListRef)) {
    return false;
  }
  UInt32 info_size = 0;
  AudioServerPlugInCustomPropertyInfo info[2];
  UInt32 info_used = 0;
  if ((*driver)->GetPropertyDataSize(driver, device_object_id, 0, &info_address,
                                     0, NULL, &info_size) != noErr ||
      info_size != sizeof(info) ||
      (*driver)->GetPropertyData(driver, device_object_id, 0, &info_address, 0,
                                 NULL, (UInt32)sizeof(info), &info_used,
                                 info) != noErr ||
      info_used != sizeof(info) ||
      info[0].mSelector != kOSVADiagnosticSnapshotProperty ||
      info[1].mSelector != kOSVADiagnosticSnapshotV2Property ||
      info[0].mPropertyDataType !=
          kAudioServerPlugInCustomPropertyDataTypeCFPropertyList ||
      info[1].mPropertyDataType !=
          kAudioServerPlugInCustomPropertyDataTypeCFPropertyList ||
      info[0].mQualifierDataType !=
          kAudioServerPlugInCustomPropertyDataTypeNone ||
      info[1].mQualifierDataType !=
          kAudioServerPlugInCustomPropertyDataTypeNone) {
    return false;
  }
  CFPropertyListRef property = NULL;
  UInt32 used = 0;
  if ((*driver)->GetPropertyData(driver, device_object_id, 0, &address, 0, NULL,
                                 (UInt32)sizeof(property), &used,
                                 &property) != noErr ||
      used != sizeof(property) || property == NULL ||
      CFGetTypeID(property) != CFDataGetTypeID()) {
    if (property != NULL) {
      CFRelease(property);
    }
    return false;
  }
  CFDataRef data = (CFDataRef)property;
  if (CFDataGetLength(data) != (CFIndex)sizeof(OSVADiagnosticSnapshot)) {
    CFRelease(property);
    return false;
  }
  OSVADiagnosticSnapshot snapshot;
  CFDataGetBytes(data, CFRangeMake(0, CFDataGetLength(data)),
                 (UInt8 *)&snapshot);
  CFRelease(property);
  property = NULL;
  if (snapshot.schema_version != kOSVADiagnosticSnapshotSchemaVersion ||
      snapshot.struct_size != sizeof(snapshot) ||
      snapshot.client_slot_capacity != kOSVADiagnosticClientSlotCapacity ||
      snapshot.driver_instance_generation == 0 ||
      (snapshot.invariant_flags &
       kOSVADiagnosticSnapshotCoreInitialized) == 0 ||
      snapshot.active_client_count != 0 || snapshot.timeline_seed != 0 ||
      snapshot.anchor_host_ticks != 0) {
    return false;
  }
  if ((*driver)->SetPropertyData(
          driver, device_object_id, 0, &address, 0, NULL,
          (UInt32)sizeof(property), &property) !=
      kAudioHardwareIllegalOperationError) {
    return false;
  }
  address.mSelector = kOSVADiagnosticSnapshotV2Property;
  settable = true;
  size = 0;
  if (!(*driver)->HasProperty(driver, device_object_id, 0, &address) ||
      (*driver)->IsPropertySettable(driver, device_object_id, 0, &address,
                                    &settable) != noErr || settable ||
      (*driver)->GetPropertyDataSize(driver, device_object_id, 0, &address, 0,
                                     NULL, &size) != noErr ||
      size != sizeof(CFPropertyListRef)) {
    return false;
  }
  used = 0;
  if ((*driver)->GetPropertyData(driver, device_object_id, 0, &address, 0, NULL,
                                 (UInt32)sizeof(property), &used,
                                 &property) != noErr ||
      used != sizeof(property) || property == NULL ||
      CFGetTypeID(property) != CFDataGetTypeID()) {
    if (property != NULL) {
      CFRelease(property);
    }
    return false;
  }
  data = (CFDataRef)property;
  OSVADiagnosticSnapshotV2Header v2;
  if (CFDataGetLength(data) != (CFIndex)sizeof(v2)) {
    CFRelease(property);
    return false;
  }
  CFDataGetBytes(data, CFRangeMake(0, CFDataGetLength(data)), (UInt8 *)&v2);
  CFRelease(property);
  property = NULL;
  if (!OSVAIdleDiagnosticSnapshotsAreExact(&snapshot, &v2, expected_core)) {
    fprintf(stderr,
            "FAIL %s idle diagnostic state or exact retired metadata: "
            "v1flags=%" PRIx64 " v2flags=%" PRIx64
            " v1bitmaps=%" PRIx64 ":%" PRIx64 "\n",
            expected_core == NULL ? "pristine" : "retired",
            snapshot.invariant_flags, v2.state.invariant_flags,
            snapshot.driver_registered_slot_bitmap,
            snapshot.driver_started_slot_bitmap);
    fprintf(stderr, "slot0 core=%" PRIu64 ":%" PRIu64 ":%" PRIu64
                    ":%u:%u driver=%" PRIu64 ":%" PRIu64 ":%" PRIu64
                    ":%" PRIu64 ":%u:%u:%u:%u:%u:%u lifecycle=%" PRIu64
                    ":%" PRIu64 " loops=%" PRIu64 ":%" PRIu64 ":%" PRIu64 "\n",
            snapshot.core_client_slots[0].session_id,
            snapshot.core_client_slots[0].client_id,
            snapshot.core_client_slots[0].timeline_seed,
            snapshot.core_client_slots[0].endpoint_role,
            snapshot.core_client_slots[0].reserved,
            snapshot.driver_client_slots[0].generation,
            snapshot.driver_client_slots[0].registration_host_ticks,
            snapshot.driver_client_slots[0].start_host_ticks,
            snapshot.driver_client_slots[0].last_transition_host_ticks,
            snapshot.driver_client_slots[0].flags,
            snapshot.driver_client_slots[0].device_object_id,
            snapshot.driver_client_slots[0].client_id,
            snapshot.driver_client_slots[0].endpoint_role,
            snapshot.driver_client_slots[0].core_client_slot,
            snapshot.driver_client_slots[0].io_start_depth,
            snapshot.driver_lifecycle_sequence, snapshot.core_lifecycle_sequence,
            snapshot.io_work_loop[0].current_count,
            snapshot.io_work_loop[0].begin_count,
            snapshot.io_work_loop[0].end_count);
    return false;
  }
  return OSVAValidateIdleSnapshotMutations(&snapshot, &v2, expected_core) &&
         (*driver)->SetPropertyData(
             driver, device_object_id, 0, &address, 0, NULL,
             (UInt32)sizeof(property), &property) ==
         kAudioHardwareIllegalOperationError;
}

#define BUNDLE_CHECK(condition)                                                \
  do {                                                                         \
    if (!(condition)) {                                                        \
      fprintf(stderr, "FAIL built driver %s:%d: %s\n", __FILE__, __LINE__,     \
              #condition);                                                     \
      return false;                                                            \
    }                                                                          \
  } while (0)

static bool OSVACopyLoadedV1Snapshot(AudioServerPlugInDriverRef driver,
                                     OSVADiagnosticSnapshot *snapshot) {
  AudioObjectPropertyAddress address = {
      .mSelector = kOSVADiagnosticSnapshotProperty,
      .mScope = kAudioObjectPropertyScopeGlobal,
      .mElement = kAudioObjectPropertyElementMain,
  };
  CFPropertyListRef property = NULL;
  UInt32 used = 0;
  if ((*driver)->GetPropertyData(driver, kOSVAObjectIDHiddenWriterDevice, 0,
                                 &address, 0, NULL, (UInt32)sizeof(property),
                                 &used, &property) != noErr ||
      used != sizeof(property) || property == NULL ||
      CFGetTypeID(property) != CFDataGetTypeID()) {
    if (property != NULL) {
      CFRelease(property);
    }
    return false;
  }
  CFDataRef data = (CFDataRef)property;
  if (CFDataGetLength(data) != (CFIndex)sizeof(*snapshot)) {
    CFRelease(property);
    return false;
  }
  CFDataGetBytes(data, CFRangeMake(0, CFDataGetLength(data)), (UInt8 *)snapshot);
  CFRelease(property);
  return snapshot->schema_version == kOSVADiagnosticSnapshotSchemaVersion &&
         snapshot->struct_size == sizeof(*snapshot);
}

static bool OSVAValidateLoadedPressureInventory(
    AudioServerPlugInDriverRef driver, const OSVADiagnosticSnapshot *before,
    UInt32 writer_id, UInt32 reader_id, UInt32 idle_count,
    OSVADiagnosticCoreClientSlotSnapshot *expected_retired_core) {
  enum { kPressureRegistryCapacity = 146 };
  BUNDLE_CHECK(idle_count == 72);
  AudioObjectPropertyAddress address = {
      .mSelector = kOSVADiagnosticSnapshotV2Property,
      .mScope = kAudioObjectPropertyScopeGlobal,
      .mElement = kAudioObjectPropertyElementMain,
  };
  CFPropertyListRef property = NULL;
  UInt32 used = 0;
  BUNDLE_CHECK((*driver)->GetPropertyData(
      driver, kOSVAObjectIDHiddenWriterDevice, 0, &address, 0, NULL,
      (UInt32)sizeof(property), &used, &property) == noErr);
  if (used != sizeof(property) || property == NULL ||
      CFGetTypeID(property) != CFDataGetTypeID()) {
    if (property != NULL) CFRelease(property);
    return false;
  }
  CFDataRef data = (CFDataRef)property;
  OSVADiagnosticSnapshotV2Header header;
  OSVADiagnosticRegistryClientSnapshot records[kPressureRegistryCapacity];
  const CFIndex expected_bytes =
      (CFIndex)(sizeof(header) + sizeof(records));
  if (CFDataGetLength(data) != expected_bytes) {
    CFRelease(property);
    return false;
  }
  CFDataGetBytes(data, CFRangeMake(0, (CFIndex)sizeof(header)), (UInt8 *)&header);
  CFDataGetBytes(data, CFRangeMake((CFIndex)sizeof(header),
                                  (CFIndex)sizeof(records)), (UInt8 *)records);
  CFRelease(property);
  BUNDLE_CHECK(header.schema_version == kOSVADiagnosticSnapshotV2SchemaVersion);
  BUNDLE_CHECK(header.header_size == sizeof(header));
  BUNDLE_CHECK(header.total_byte_count == (UInt64)expected_bytes);
  BUNDLE_CHECK(header.registry_record_count == kPressureRegistryCapacity);
  BUNDLE_CHECK(header.registry_record_size == sizeof(records[0]));
  BUNDLE_CHECK(header.core_slot_capacity == kOSVADiagnosticClientSlotCapacity);
  BUNDLE_CHECK(header.reserved_header == 0 && header.registry_revision != 0);
  BUNDLE_CHECK(header.state.driver_instance_generation ==
                before->driver_instance_generation);
  BUNDLE_CHECK(header.state.invariant_flags == UINT64_C(0x7ff03));
  BUNDLE_CHECK(header.state.timeline_seed == before->timeline_seed &&
                header.state.current_seed_generation == before->timeline_seed &&
                header.state.anchor_host_ticks == before->anchor_host_ticks);
  BUNDLE_CHECK(header.state.active_client_count == 2 &&
                header.state.core_active_slot_count == 2 &&
                header.state.visible_input_active_count == 1 &&
                header.state.hidden_writer_active_count == 1 &&
                header.state.driver_started_count == 2 &&
                header.state.visible_driver_started_count == 1 &&
                header.state.hidden_driver_started_count == 1);
  BUNDLE_CHECK(header.state.driver_registered_count == kPressureRegistryCapacity &&
                header.state.visible_driver_registered_count == idle_count + 1 &&
                header.state.hidden_driver_registered_count == idle_count + 1);
  bool seen_idle[2][72] = {{false}};
  bool seen_writer = false, seen_reader = false;
  UInt64 active_bitmap = 0;
  UInt32 writer_slot = UINT32_MAX, reader_slot = UINT32_MAX;
  for (size_t index = 0; index < kPressureRegistryCapacity; ++index) {
    const OSVADiagnosticRegistryClientSnapshot *record = &records[index];
    const OSVADiagnosticDriverClientSlotSnapshot *client = &record->client;
    BUNDLE_CHECK(record->registry_index != UINT64_MAX &&
                  (index == 0 || records[index - 1].registry_index <
                                     record->registry_index));
    BUNDLE_CHECK(client->generation != 0 && client->registration_host_ticks != 0 &&
                  client->last_transition_host_ticks != 0 && client->reserved == 0);
    for (size_t previous = 0; previous < index; ++previous) {
      BUNDLE_CHECK(records[previous].client.generation != client->generation);
    }
    const bool visible = client->device_object_id == kOSVAObjectIDVisibleInputDevice;
    BUNDLE_CHECK(visible || client->device_object_id == kOSVAObjectIDHiddenWriterDevice);
    BUNDLE_CHECK(client->endpoint_role ==
                  (visible ? kOSVADiagnosticEndpointVisibleInput :
                             kOSVADiagnosticEndpointHiddenWriter));
    if ((!visible && client->client_id == writer_id) ||
        (visible && client->client_id == reader_id)) {
      bool *seen = visible ? &seen_reader : &seen_writer;
      BUNDLE_CHECK(!*seen);
      *seen = true;
      BUNDLE_CHECK(client->flags == (kOSVADiagnosticDriverSlotRegistered |
                                     kOSVADiagnosticDriverSlotStarted |
                                     kOSVADiagnosticDriverSlotLeaseValid));
      BUNDLE_CHECK(client->io_start_depth == 1 && client->start_host_ticks != 0 &&
                    client->lease_session_id != 0 &&
                    client->lease_timeline_seed == before->timeline_seed &&
                    client->core_client_slot < kOSVADiagnosticClientSlotCapacity);
      const OSVADiagnosticCoreClientSlotSnapshot *core =
          &header.core_client_slots[client->core_client_slot];
      BUNDLE_CHECK(core->session_id == client->lease_session_id &&
                    core->client_id ==
                        (((UInt64)client->device_object_id << 32) | client->client_id) &&
                    core->timeline_seed == client->lease_timeline_seed &&
                    core->endpoint_role == client->endpoint_role && core->reserved == 0);
      if (visible) {
        reader_slot = client->core_client_slot;
        BUNDLE_CHECK(client->process_id == 5002);
      } else {
        writer_slot = client->core_client_slot;
        BUNDLE_CHECK(memcmp(client, &before->driver_client_slots[0],
                            sizeof(*client)) == 0);
      }
      BUNDLE_CHECK((active_bitmap & (UINT64_C(1) << client->core_client_slot)) == 0);
      active_bitmap |= UINT64_C(1) << client->core_client_slot;
    } else {
      BUNDLE_CHECK(client->client_id >= 3000 && client->client_id < 3000 + idle_count);
      const UInt32 idle_index = client->client_id - 3000;
      const size_t endpoint = visible ? 0 : 1;
      BUNDLE_CHECK(!seen_idle[endpoint][idle_index]);
      seen_idle[endpoint][idle_index] = true;
      BUNDLE_CHECK(client->process_id == (SInt32)(4000 + idle_index) &&
                    client->flags == kOSVADiagnosticDriverSlotRegistered &&
                    client->io_start_depth == 0 && client->start_host_ticks == 0 &&
                    client->lease_session_id == 0 && client->lease_timeline_seed == 0 &&
                    client->core_client_slot == UINT32_MAX);
    }
  }
  BUNDLE_CHECK(seen_writer && seen_reader && writer_slot != reader_slot);
  BUNDLE_CHECK(header.state.core_active_slot_bitmap == active_bitmap);
  for (size_t index = 0; index < kOSVADiagnosticClientSlotCapacity; ++index) {
    if (index != reader_slot) {
      BUNDLE_CHECK(memcmp(&header.core_client_slots[index],
                          &before->core_client_slots[index],
                          sizeof(header.core_client_slots[index])) == 0);
    }
    expected_retired_core[index] = header.core_client_slots[index];
    expected_retired_core[index].session_id = 0;
  }
  address.mSelector = kOSVADiagnosticSnapshotProperty;
  const AudioObjectID devices[2] = {
      kOSVAObjectIDVisibleInputDevice, kOSVAObjectIDHiddenWriterDevice};
  for (size_t endpoint = 0; endpoint < 2; ++endpoint) {
    property = NULL;
    used = 0;
    const OSStatus status = (*driver)->GetPropertyData(
        driver, devices[endpoint], 0, &address, 0, NULL,
        (UInt32)sizeof(property), &used, &property);
    if (property != NULL) CFRelease(property);
    BUNDLE_CHECK(status == kOSVADiagnosticSnapshotUnavailableError &&
                  property == NULL && used == 0);
  }
  puts("PASS: loaded production driver complete v2 pressure inventory and unavailable v1");
  return true;
}

static bool OSVAValidateLoadedRegistrationPressurePCM(
    AudioServerPlugInDriverRef driver) {
  enum { kIdleCount = 72, kFrameCount = 6 };
  AudioServerPlugInClientInfo writer = {
      .mClientID = 1001,
      .mProcessID = 2001,
      .mIsNativeEndian = true,
      .mBundleID = CFSTR("com.elamin.opensteamer.built-driver-tests"),
  };
  BUNDLE_CHECK((*driver)->AddDeviceClient(
      driver, kOSVAObjectIDHiddenWriterDevice, &writer) == noErr);
  BUNDLE_CHECK((*driver)->StartIO(driver, kOSVAObjectIDHiddenWriterDevice,
                                 writer.mClientID) == noErr);
  OSVADiagnosticSnapshot before;
  BUNDLE_CHECK(OSVACopyLoadedV1Snapshot(driver, &before));
  BUNDLE_CHECK(before.active_client_count == 1);
  BUNDLE_CHECK(before.timeline_seed != 0);
  BUNDLE_CHECK(before.driver_client_slots[0].client_id == writer.mClientID);
  BUNDLE_CHECK((before.driver_client_slots[0].flags &
                kOSVADiagnosticDriverSlotLeaseValid) != 0);
  AudioServerPlugInClientInfo idle[kIdleCount];
  for (UInt32 index = 0; index < kIdleCount; ++index) {
    idle[index] = writer;
    idle[index].mClientID = 3000U + index;
    idle[index].mProcessID = (pid_t)(4000U + index);
    BUNDLE_CHECK((*driver)->AddDeviceClient(
        driver, kOSVAObjectIDVisibleInputDevice, &idle[index]) == noErr);
    BUNDLE_CHECK((*driver)->AddDeviceClient(
        driver, kOSVAObjectIDHiddenWriterDevice, &idle[index]) == noErr);
  }
  Float32 source[kFrameCount] = {
      0.125F, -0.25F, 0.5F, -0.75F, 1.0F, -1.0F};
  Float32 destination[kFrameCount];
  AudioServerPlugInIOCycleInfo outputCycle;
  memset(&outputCycle, 0, sizeof(outputCycle));
  outputCycle.mOutputTime.mSampleTime = 512.0;
  outputCycle.mOutputTime.mFlags = kAudioTimeStampSampleTimeValid;
  BUNDLE_CHECK((*driver)->DoIOOperation(
      driver, kOSVAObjectIDHiddenWriterDevice, kOSVAObjectIDHiddenWriterStream,
      writer.mClientID, kAudioServerPlugInIOOperationWriteMix, kFrameCount,
      &outputCycle, source, NULL) == noErr);
  AudioServerPlugInClientInfo reader = writer;
  reader.mClientID = 5001;
  reader.mProcessID = 5002;
  BUNDLE_CHECK((*driver)->AddDeviceClient(
      driver, kOSVAObjectIDVisibleInputDevice, &reader) == noErr);
  BUNDLE_CHECK((*driver)->StartIO(driver, kOSVAObjectIDVisibleInputDevice,
                                 reader.mClientID) == noErr);
  OSVADiagnosticCoreClientSlotSnapshot expected_retired_core[
      kOSVADiagnosticClientSlotCapacity];
  BUNDLE_CHECK(OSVAValidateLoadedPressureInventory(
      driver, &before, writer.mClientID, reader.mClientID, kIdleCount,
      expected_retired_core));
  AudioServerPlugInIOCycleInfo inputCycle;
  memset(&inputCycle, 0, sizeof(inputCycle));
  inputCycle.mInputTime.mSampleTime = 512.0;
  inputCycle.mInputTime.mFlags = kAudioTimeStampSampleTimeValid;
  memset(destination, 0, sizeof(destination));
  BUNDLE_CHECK((*driver)->DoIOOperation(
      driver, kOSVAObjectIDVisibleInputDevice, kOSVAObjectIDVisibleInputStream,
      reader.mClientID, kAudioServerPlugInIOOperationReadInput, kFrameCount,
      &inputCycle, destination, NULL) == noErr);
  BUNDLE_CHECK(memcmp(source, destination, sizeof(source)) == 0);
  Float64 sample = -1.0;
  UInt64 host = 0;
  UInt64 seed = 0;
  BUNDLE_CHECK((*driver)->GetZeroTimeStamp(
      driver, kOSVAObjectIDVisibleInputDevice, reader.mClientID, &sample,
      &host, &seed) == noErr);
  BUNDLE_CHECK(seed == before.timeline_seed && host != 0);
  BUNDLE_CHECK((*driver)->StopIO(driver, kOSVAObjectIDVisibleInputDevice,
                                reader.mClientID) == noErr);
  BUNDLE_CHECK((*driver)->RemoveDeviceClient(
      driver, kOSVAObjectIDVisibleInputDevice, &reader) == noErr);
  for (UInt32 index = 0; index < kIdleCount; ++index) {
    BUNDLE_CHECK((*driver)->RemoveDeviceClient(
        driver, kOSVAObjectIDVisibleInputDevice, &idle[index]) == noErr);
    BUNDLE_CHECK((*driver)->RemoveDeviceClient(
        driver, kOSVAObjectIDHiddenWriterDevice, &idle[index]) == noErr);
  }
  OSVADiagnosticSnapshot after;
  BUNDLE_CHECK(OSVACopyLoadedV1Snapshot(driver, &after));
  BUNDLE_CHECK(after.active_client_count == 1 && after.driver_registered_count == 1);
  BUNDLE_CHECK(after.timeline_seed == before.timeline_seed);
  BUNDLE_CHECK(after.anchor_host_ticks == before.anchor_host_ticks);
  BUNDLE_CHECK(memcmp(&before.driver_client_slots[0],
                      &after.driver_client_slots[0],
                      sizeof(before.driver_client_slots[0])) == 0);
  for (size_t index = 0; index < kOSVADiagnosticClientSlotCapacity; ++index) {
    OSVADiagnosticCoreClientSlotSnapshot expected = expected_retired_core[index];
    expected.session_id = before.core_client_slots[index].session_id;
    BUNDLE_CHECK(memcmp(&after.core_client_slots[index], &expected,
                        sizeof(expected)) == 0);
  }
  BUNDLE_CHECK((*driver)->StopIO(driver, kOSVAObjectIDHiddenWriterDevice,
                                writer.mClientID) == noErr);
  BUNDLE_CHECK((*driver)->RemoveDeviceClient(
      driver, kOSVAObjectIDHiddenWriterDevice, &writer) == noErr);
  BUNDLE_CHECK(OSVAValidateDiagnosticSnapshotProperty(
      driver, kOSVAObjectIDVisibleInputDevice, expected_retired_core));
  BUNDLE_CHECK(OSVAValidateDiagnosticSnapshotProperty(
      driver, kOSVAObjectIDHiddenWriterDevice, expected_retired_core));
  puts("PASS: loaded driver pristine and retired idle contract mutations");
  puts("PASS: loaded production driver idle-registration pressure and exact PCM");
  return true;
}

int main(int argc, char **argv) {
  if (argc != 2 || argv[1] == NULL || argv[1][0] != '/') {
    fprintf(stderr,
            "usage: OpensteamerVirtualMicrophoneBundleLoadTests "
            "/absolute/path/OpensteamerVirtualMicrophone.driver\n");
    return 64;
  }

  CFURLRef bundle_url = CFURLCreateFromFileSystemRepresentation(
      kCFAllocatorDefault, (const UInt8 *)argv[1], (CFIndex)strlen(argv[1]),
      true);
  if (bundle_url == NULL) {
    fprintf(stderr, "unable to create driver bundle URL\n");
    return 1;
  }
  CFBundleRef bundle = CFBundleCreate(kCFAllocatorDefault, bundle_url);
  CFRelease(bundle_url);
  if (bundle == NULL) {
    fprintf(stderr, "unable to create driver CFBundle\n");
    return 1;
  }
  if (!OSVACFStringEqualsCString(
          CFBundleGetIdentifier(bundle),
          "com.elamin.opensteamer.VirtualMicrophoneDriver")) {
    fprintf(stderr, "loaded driver bundle identifier is not exact\n");
    CFRelease(bundle);
    return 1;
  }
  CFErrorRef load_error = NULL;
  if (!CFBundleLoadExecutableAndReturnError(bundle, &load_error)) {
    CFStringRef description =
        load_error == NULL ? NULL : CFErrorCopyDescription(load_error);
    char description_buffer[1024] = "unavailable";
    if (description != NULL) {
      (void)CFStringGetCString(description, description_buffer,
                               sizeof(description_buffer),
                               kCFStringEncodingUTF8);
      CFRelease(description);
    }
    fprintf(stderr, "unable to load driver bundle executable: %s\n",
            description_buffer);
    if (load_error != NULL) {
      CFRelease(load_error);
    }
    CFRelease(bundle);
    return 1;
  }

  void *factory_symbol = CFBundleGetFunctionPointerForName(
      bundle, CFSTR("OpensteamerVirtualMicrophone_Create"));
  OSVADriverFactoryFunction factory = NULL;
  _Static_assert(sizeof(factory) == sizeof(factory_symbol),
                 "Darwin function and data pointers must have equal size");
  memcpy(&factory, &factory_symbol, sizeof(factory));
  if (factory == NULL) {
    fprintf(stderr, "driver factory export is unavailable\n");
    CFBundleUnloadExecutable(bundle);
    CFRelease(bundle);
    return 1;
  }

  CFUUIDRef unsupported_type = CFUUIDCreateFromString(
      kCFAllocatorDefault,
      CFSTR("00000000-0000-0000-0000-000000000001"));
  if (unsupported_type == NULL ||
      factory(kCFAllocatorDefault, unsupported_type) != NULL) {
    fprintf(stderr, "driver factory accepted an unsupported plug-in type\n");
    if (unsupported_type != NULL) {
      CFRelease(unsupported_type);
    }
    CFBundleUnloadExecutable(bundle);
    CFRelease(bundle);
    return 1;
  }
  CFRelease(unsupported_type);

  AudioServerPlugInDriverRef driver = factory(
      kCFAllocatorDefault, kAudioServerPlugInTypeUUID);
  if (driver == NULL || *driver == NULL) {
    fprintf(stderr, "driver factory did not return its production interface\n");
    CFBundleUnloadExecutable(bundle);
    CFRelease(bundle);
    return 1;
  }
  LPVOID queried = NULL;
  HRESULT query_status = (*driver)->QueryInterface(
      driver, CFUUIDGetUUIDBytes(kAudioServerPlugInDriverInterfaceUUID),
      &queried);
  if (query_status != S_OK || queried != driver) {
    fprintf(stderr, "driver interface QueryInterface contract failed\n");
    CFBundleUnloadExecutable(bundle);
    CFRelease(bundle);
    return 1;
  }
  if ((*driver)->Release(driver) == 0) {
    fprintf(stderr, "driver interface reference accounting underflowed\n");
    CFBundleUnloadExecutable(bundle);
    CFRelease(bundle);
    return 1;
  }

  static const AudioServerPlugInHostInterface diagnostic_test_host = {0};
  if ((*driver)->Initialize(driver, &diagnostic_test_host) != noErr ||
      !OSVAValidateDiagnosticSnapshotProperty(
          driver, kOSVAObjectIDVisibleInputDevice, NULL) ||
      !OSVAValidateDiagnosticSnapshotProperty(
          driver, kOSVAObjectIDHiddenWriterDevice, NULL)) {
    fprintf(stderr,
            "loaded production driver diagnostic snapshot contract failed\n");
    CFBundleUnloadExecutable(bundle);
    CFRelease(bundle);
    return 1;
  }
  AudioObjectPropertyAddress diagnostic_address = {
      .mSelector = kOSVADiagnosticSnapshotProperty,
      .mScope = kAudioObjectPropertyScopeGlobal,
      .mElement = kAudioObjectPropertyElementMain,
  };
  AudioObjectPropertyAddress diagnostic_info_address = {
      .mSelector = kAudioObjectPropertyCustomPropertyInfoList,
      .mScope = kAudioObjectPropertyScopeGlobal,
      .mElement = kAudioObjectPropertyElementMain,
  };
  AudioObjectPropertyAddress diagnostic_v2_address = diagnostic_address;
  diagnostic_v2_address.mSelector = kOSVADiagnosticSnapshotV2Property;
  if ((*driver)->HasProperty(driver, kOSVAObjectIDPlugIn, 0,
                             &diagnostic_address) ||
      (*driver)->HasProperty(driver, kOSVAObjectIDVisibleInputStream, 0,
                             &diagnostic_address) ||
      (*driver)->HasProperty(driver, kOSVAObjectIDHiddenWriterStream, 0,
                             &diagnostic_address) ||
      (*driver)->HasProperty(driver, kOSVAObjectIDPlugIn, 0,
                             &diagnostic_v2_address) ||
      (*driver)->HasProperty(driver, kOSVAObjectIDVisibleInputStream, 0,
                             &diagnostic_v2_address) ||
      (*driver)->HasProperty(driver, kOSVAObjectIDHiddenWriterStream, 0,
                             &diagnostic_v2_address) ||
      (*driver)->HasProperty(driver, kOSVAObjectIDPlugIn, 0,
                             &diagnostic_info_address) ||
      (*driver)->HasProperty(driver, kOSVAObjectIDVisibleInputStream, 0,
                             &diagnostic_info_address) ||
      (*driver)->HasProperty(driver, kOSVAObjectIDHiddenWriterStream, 0,
                             &diagnostic_info_address)) {
    fprintf(stderr,
            "diagnostic snapshot leaked outside the two device objects\n");
    CFBundleUnloadExecutable(bundle);
    CFRelease(bundle);
    return 1;
  }

  if (!OSVAValidateLoadedRegistrationPressurePCM(driver)) {
    fprintf(stderr, "loaded production driver registration-pressure PCM failed\n");
    CFBundleUnloadExecutable(bundle);
    CFRelease(bundle);
    return 1;
  }
  CFBundleUnloadExecutable(bundle);
  CFRelease(bundle);
  puts("PASS: loaded built driver bundle and resolved production interface");
  return 0;
}
