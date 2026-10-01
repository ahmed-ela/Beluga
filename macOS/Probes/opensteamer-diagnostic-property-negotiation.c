#include <CoreAudio/CoreAudio.h>
#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_time.h>

#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

enum { kMaximumDeclarations = 32, kProbeSchema = 1 };
static const AudioObjectPropertySelector kV1Selector = 'osDS';
static const AudioObjectPropertySelector kV2Selector = 'osD2';
static const char *const kUIDs[2] = {
    "com.elamin.opensteamer.virtual-microphone.input",
    "com.elamin.opensteamer.virtual-microphone.writer",
};
static const uint64_t kMaximumWindowNanoseconds = UINT64_C(2000000000);

_Static_assert(sizeof(AudioDeviceID) == 4, "device identity wire width");
_Static_assert(sizeof(OSStatus) == 4, "status wire width");
_Static_assert(sizeof(CFPropertyListRef) == 8, "64-bit property ABI required");
_Static_assert(sizeof(AudioServerPlugInCustomPropertyInfo) == 12,
               "custom property declaration ABI");

typedef struct UIDRead {
  OSStatus status;
  UInt32 size;
  bool type_valid;
  bool matched;
} UIDRead;

typedef struct PropertyRead {
  bool advertised;
  bool has_property;
  OSStatus size_status;
  UInt32 size;
} PropertyRead;

typedef struct EndpointRead {
  AudioDeviceID id;
  OSStatus lookup_status;
  UInt32 lookup_size;
  bool metadata_attempted;
  UIDRead uid_before;
  UIDRead uid_after;
  bool declarations_have_property;
  OSStatus declarations_size_status;
  UInt32 declarations_size;
  bool declarations_data_attempted;
  OSStatus declarations_data_status;
  UInt32 declarations_returned_size;
  UInt32 declaration_count;
  AudioServerPlugInCustomPropertyInfo declarations[kMaximumDeclarations];
  PropertyRead v1;
  PropertyRead v2;
  AudioDeviceID final_id;
  OSStatus final_lookup_status;
  UInt32 final_lookup_size;
} EndpointRead;

typedef struct ProbeHAL {
  void *context;
  OSStatus (*lookup)(void *, const char *, AudioDeviceID *, UInt32 *);
  UIDRead (*uid)(void *, AudioDeviceID, const char *);
  bool (*has)(void *, AudioDeviceID, AudioObjectPropertySelector);
  OSStatus (*size)(void *, AudioDeviceID, AudioObjectPropertySelector, UInt32 *);
  OSStatus (*declarations)(void *, AudioDeviceID,
                           AudioServerPlugInCustomPropertyInfo *, UInt32 *);
  uint64_t (*ticks)(void *);
} ProbeHAL;

typedef enum ProbeResult {
  kAmbiguous, kLegacyV1, kV2Present
} ProbeResult;

typedef struct ProbeRecord {
  uint64_t ticks_before;
  uint64_t ticks_after;
  UInt32 timebase_numer;
  UInt32 timebase_denom;
  bool second_pass_attempted;
  EndpointRead passes[2][2];
  ProbeResult result;
  const char *reason;
} ProbeRecord;

static bool WindowValid(const ProbeRecord *record, uint64_t end) {
  return record->timebase_numer != 0 && record->timebase_denom != 0 &&
      end > record->ticks_before &&
      (__uint128_t)(end - record->ticks_before) * record->timebase_numer <=
          (__uint128_t)kMaximumWindowNanoseconds * record->timebase_denom;
}

static bool DeclarationSizeValid(UInt32 size) {
  return size != 0 && size <= sizeof(AudioServerPlugInCustomPropertyInfo) *
          kMaximumDeclarations &&
      size % sizeof(AudioServerPlugInCustomPropertyInfo) == 0;
}

static void CollectEndpoint(const ProbeHAL *hal, unsigned endpoint,
                            EndpointRead *read) {
  if (read->lookup_status != noErr || read->lookup_size != sizeof(read->id) ||
      read->id == kAudioObjectUnknown) return;
  read->metadata_attempted = true;
  read->uid_before = hal->uid(hal->context, read->id, kUIDs[endpoint]);
  read->declarations_have_property = hal->has(
      hal->context, read->id, kAudioObjectPropertyCustomPropertyInfoList);
  read->declarations_size_status = hal->size(hal->context, read->id,
      kAudioObjectPropertyCustomPropertyInfoList, &read->declarations_size);
  if (read->declarations_size_status == noErr &&
      DeclarationSizeValid(read->declarations_size)) {
    read->declarations_data_attempted = true;
    read->declarations_returned_size = read->declarations_size;
    read->declarations_data_status = hal->declarations(
        hal->context, read->id, read->declarations,
        &read->declarations_returned_size);
    if (read->declarations_data_status == noErr &&
        read->declarations_returned_size == read->declarations_size) {
      read->declaration_count = read->declarations_size /
          sizeof(AudioServerPlugInCustomPropertyInfo);
    }
  }
  PropertyRead *properties[2] = {&read->v1, &read->v2};
  const AudioObjectPropertySelector selectors[2] = {kV1Selector, kV2Selector};
  for (unsigned property = 0; property < 2; ++property) {
    for (UInt32 index = 0; index < read->declaration_count; ++index) {
      if (read->declarations[index].mSelector == selectors[property])
        properties[property]->advertised = true;
    }
    properties[property]->has_property = hal->has(
        hal->context, read->id, selectors[property]);
    properties[property]->size_status = hal->size(
        hal->context, read->id, selectors[property], &properties[property]->size);
  }
  read->uid_after = hal->uid(hal->context, read->id, kUIDs[endpoint]);
}

static void CollectPass(const ProbeHAL *hal, unsigned pass, ProbeRecord *record) {
  for (unsigned endpoint = 0; endpoint < 2; ++endpoint) {
    EndpointRead *read = &record->passes[pass][endpoint];
    read->lookup_status = hal->lookup(hal->context, kUIDs[endpoint],
        &read->id, &read->lookup_size);
  }
  for (unsigned index = 0; index < 2; ++index) {
    unsigned endpoint = pass == 0 ? index : 1 - index;
    CollectEndpoint(hal, endpoint, &record->passes[pass][endpoint]);
  }
  for (unsigned endpoint = 0; endpoint < 2; ++endpoint) {
    EndpointRead *read = &record->passes[pass][endpoint];
    read->final_lookup_status = hal->lookup(hal->context, kUIDs[endpoint],
        &read->final_id, &read->final_lookup_size);
  }
}

static bool UIDValid(const UIDRead *read) {
  return read->status == noErr && read->size == sizeof(CFStringRef) &&
      read->type_valid && read->matched;
}

static bool IdentityValid(const EndpointRead *read) {
  return read->metadata_attempted && read->lookup_status == noErr &&
      read->lookup_size == sizeof(read->id) && read->id != kAudioObjectUnknown &&
      read->final_lookup_status == noErr &&
      read->final_lookup_size == sizeof(read->id) && read->final_id == read->id &&
      UIDValid(&read->uid_before) && UIDValid(&read->uid_after);
}

static bool TypeValid(UInt32 type) {
  return type == kAudioServerPlugInCustomPropertyDataTypeNone ||
      type == kAudioServerPlugInCustomPropertyDataTypeCFString ||
      type == kAudioServerPlugInCustomPropertyDataTypeCFPropertyList;
}

static bool DeclarationsValid(const EndpointRead *read) {
  if (!read->declarations_have_property ||
      read->declarations_size_status != noErr ||
      !DeclarationSizeValid(read->declarations_size) ||
      !read->declarations_data_attempted ||
      read->declarations_data_status != noErr ||
      read->declarations_returned_size != read->declarations_size ||
      read->declaration_count != read->declarations_size /
          sizeof(AudioServerPlugInCustomPropertyInfo)) return false;
  for (UInt32 index = 0; index < read->declaration_count; ++index) {
    const AudioServerPlugInCustomPropertyInfo *item = &read->declarations[index];
    if (item->mSelector == 0 || !TypeValid(item->mPropertyDataType) ||
        !TypeValid(item->mQualifierDataType)) return false;
    for (UInt32 prior = 0; prior < index; ++prior)
      if (item->mSelector == read->declarations[prior].mSelector) return false;
    if ((item->mSelector == kV1Selector || item->mSelector == kV2Selector) &&
        (item->mPropertyDataType !=
             kAudioServerPlugInCustomPropertyDataTypeCFPropertyList ||
         item->mQualifierDataType != kAudioServerPlugInCustomPropertyDataTypeNone))
      return false;
  }
  return true;
}

static bool Present(const PropertyRead *read) {
  return read->advertised && read->has_property && read->size_status == noErr &&
      read->size == sizeof(CFPropertyListRef);
}

static bool Absent(const PropertyRead *read) {
  // The size output is undefined on an error; the exact status establishes absence.
  return !read->advertised && !read->has_property &&
      read->size_status == kAudioHardwareUnknownPropertyError;
}

static bool UIDEqual(const UIDRead *a, const UIDRead *b) {
  return a->status == b->status && a->size == b->size &&
      a->type_valid == b->type_valid && a->matched == b->matched;
}

static bool PropertyEqual(const PropertyRead *a, const PropertyRead *b) {
  return a->advertised == b->advertised && a->has_property == b->has_property &&
      a->size_status == b->size_status && a->size == b->size;
}

static bool EndpointEqual(const EndpointRead *a, const EndpointRead *b) {
  if (a->id != b->id || a->lookup_status != b->lookup_status ||
      a->lookup_size != b->lookup_size ||
      a->metadata_attempted != b->metadata_attempted ||
      !UIDEqual(&a->uid_before, &b->uid_before) ||
      !UIDEqual(&a->uid_after, &b->uid_after) ||
      a->declarations_have_property != b->declarations_have_property ||
      a->declarations_size_status != b->declarations_size_status ||
      a->declarations_size != b->declarations_size ||
      a->declarations_data_attempted != b->declarations_data_attempted ||
      a->declarations_data_status != b->declarations_data_status ||
      a->declarations_returned_size != b->declarations_returned_size ||
      a->declaration_count != b->declaration_count ||
      !PropertyEqual(&a->v1, &b->v1) || !PropertyEqual(&a->v2, &b->v2) ||
      a->final_id != b->final_id ||
      a->final_lookup_status != b->final_lookup_status ||
      a->final_lookup_size != b->final_lookup_size) return false;
  for (UInt32 index = 0; index < a->declaration_count; ++index) {
    if (a->declarations[index].mSelector != b->declarations[index].mSelector ||
        a->declarations[index].mPropertyDataType !=
            b->declarations[index].mPropertyDataType ||
        a->declarations[index].mQualifierDataType !=
            b->declarations[index].mQualifierDataType) return false;
  }
  return true;
}

static void Classify(ProbeRecord *record) {
  record->result = kAmbiguous;
  record->reason = "window-invalid";
  if (!record->second_pass_attempted || !WindowValid(record, record->ticks_after))
    return;
  record->reason = "identity-invalid";
  for (unsigned pass = 0; pass < 2; ++pass) {
    if (record->passes[pass][0].id == record->passes[pass][1].id) return;
    for (unsigned endpoint = 0; endpoint < 2; ++endpoint)
      if (!IdentityValid(&record->passes[pass][endpoint])) return;
  }
  record->reason = "declarations-invalid";
  for (unsigned pass = 0; pass < 2; ++pass)
    for (unsigned endpoint = 0; endpoint < 2; ++endpoint)
      if (!DeclarationsValid(&record->passes[pass][endpoint])) return;
  record->reason = "metadata-changed";
  for (unsigned endpoint = 0; endpoint < 2; ++endpoint)
    if (!EndpointEqual(&record->passes[0][endpoint],
                       &record->passes[1][endpoint])) return;
  bool legacy = true, v2 = true;
  for (unsigned pass = 0; pass < 2; ++pass) {
    for (unsigned endpoint = 0; endpoint < 2; ++endpoint) {
      const EndpointRead *read = &record->passes[pass][endpoint];
      legacy = legacy && Present(&read->v1) && Absent(&read->v2);
      v2 = v2 && Present(&read->v1) && Present(&read->v2);
    }
  }
  record->reason = "property-ambiguous";
  if (legacy || v2) {
    record->result = legacy ? kLegacyV1 : kV2Present;
    record->reason = "exact-stable-metadata";
  }
}

static ProbeRecord Collect(const ProbeHAL *hal, UInt32 numer, UInt32 denom) {
  ProbeRecord record;
  memset(&record, 0, sizeof(record));
  record.timebase_numer = numer;
  record.timebase_denom = denom;
  record.ticks_before = hal->ticks(hal->context);
  CollectPass(hal, 0, &record);
  if (WindowValid(&record, hal->ticks(hal->context))) {
    record.second_pass_attempted = true;
    CollectPass(hal, 1, &record);
  }
  record.ticks_after = hal->ticks(hal->context);
  Classify(&record);
  return record;
}

static const char *BooleanText(bool value) { return value ? "true" : "false"; }

static void PrintUID(FILE *out, const UIDRead *read, unsigned endpoint) {
  fprintf(out, "{\"status\":%" PRId32 ",\"sizeBytes\":%" PRIu32
      ",\"typeValid\":%s,\"matched\":%s,\"observedUID\":",
      read->status, read->size, BooleanText(read->type_valid),
      BooleanText(read->matched));
  if (UIDValid(read)) fprintf(out, "\"%s\"", kUIDs[endpoint]);
  else fputs("null", out);
  fputc('}', out);
}

static void PrintProperty(FILE *out, const PropertyRead *read) {
  fprintf(out, "{\"advertised\":%s,\"hasProperty\":%s,\"sizeStatus\":%"
      PRId32 ",\"sizeBytes\":%" PRIu32 "}",
      BooleanText(read->advertised), BooleanText(read->has_property),
      read->size_status, read->size);
}

static void PrintEndpoint(FILE *out, const EndpointRead *read, unsigned endpoint) {
  fprintf(out, "{\"expectedUID\":\"%s\",\"deviceID\":%" PRIu32
      ",\"lookupStatus\":%" PRId32 ",\"lookupSizeBytes\":%" PRIu32
      ",\"metadataAttempted\":%s,\"uidBefore\":", kUIDs[endpoint],
      read->id, read->lookup_status, read->lookup_size,
      BooleanText(read->metadata_attempted));
  PrintUID(out, &read->uid_before, endpoint);
  fputs(",\"uidAfter\":", out); PrintUID(out, &read->uid_after, endpoint);
  fprintf(out, ",\"declarations\":{\"hasProperty\":%s,\"sizeStatus\":%"
      PRId32 ",\"sizeBytes\":%" PRIu32 ",\"dataAttempted\":%s,"
      "\"dataStatus\":%" PRId32 ",\"returnedSizeBytes\":%" PRIu32
      ",\"count\":%" PRIu32 ",\"items\":[",
      BooleanText(read->declarations_have_property),
      read->declarations_size_status, read->declarations_size,
      BooleanText(read->declarations_data_attempted),
      read->declarations_data_status, read->declarations_returned_size,
      read->declaration_count);
  for (UInt32 index = 0; index < read->declaration_count; ++index) {
    const AudioServerPlugInCustomPropertyInfo *item = &read->declarations[index];
    fprintf(out, "%s{\"selector\":%" PRIu32 ",\"dataType\":%" PRIu32
        ",\"qualifierType\":%" PRIu32 "}", index == 0 ? "" : ",",
        item->mSelector, item->mPropertyDataType, item->mQualifierDataType);
  }
  fputs("]},\"v1\":", out); PrintProperty(out, &read->v1);
  fputs(",\"v2\":", out); PrintProperty(out, &read->v2);
  fprintf(out, ",\"finalDeviceID\":%" PRIu32 ",\"finalLookupStatus\":%"
      PRId32 ",\"finalLookupSizeBytes\":%" PRIu32 "}", read->final_id,
      read->final_lookup_status, read->final_lookup_size);
}

static void PrintRecord(FILE *out, const ProbeRecord *record) {
  const char *result = record->result == kLegacyV1 ? "legacy-v1" :
      record->result == kV2Present ? "v2-present" : "ambiguous";
  fprintf(out, "{\"schemaVersion\":%u,\"scope\":\"diagnostic-property-"
      "negotiation-only\",\"classification\":\"%s\",\"reason\":\"%s\","
      "\"pointerSizeBytes\":%zu,\"maximumDeclarationCount\":%u,"
      "\"maximumWindowNanoseconds\":%" PRIu64 ",\"hostTicksBefore\":%"
      PRIu64 ",\"hostTicksAfter\":%" PRIu64 ",\"timebaseNumer\":%" PRIu32
      ",\"timebaseDenom\":%" PRIu32 ",\"secondPassAttempted\":%s,"
      "\"passes\":[", kProbeSchema, result, record->reason,
      sizeof(CFPropertyListRef), kMaximumDeclarations, kMaximumWindowNanoseconds,
      record->ticks_before, record->ticks_after, record->timebase_numer,
      record->timebase_denom, BooleanText(record->second_pass_attempted));
  for (unsigned pass = 0; pass < 2; ++pass) {
    fprintf(out, "%s[", pass == 0 ? "" : ",");
    for (unsigned endpoint = 0; endpoint < 2; ++endpoint) {
      if (endpoint != 0) fputc(',', out);
      PrintEndpoint(out, &record->passes[pass][endpoint], endpoint);
    }
    fputc(']', out);
  }
  fputs("]}\n", out);
}

#ifndef OS_DIAGNOSTIC_NEGOTIATION_TESTING
static AudioObjectPropertyAddress Address(AudioObjectPropertySelector selector) {
  return (AudioObjectPropertyAddress){selector,
      kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
}

static OSStatus ActualLookup(void *context, const char *uid, AudioDeviceID *id,
                            UInt32 *returned_size) {
  (void)context;
  CFStringRef qualifier = CFStringCreateWithCString(kCFAllocatorDefault, uid,
      kCFStringEncodingUTF8);
  if (qualifier == NULL) return kAudio_MemFullError;
  AudioObjectPropertyAddress address = Address(kAudioHardwarePropertyTranslateUIDToDevice);
  *returned_size = sizeof(*id);
  OSStatus status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &address,
      sizeof(qualifier), &qualifier, returned_size, id);
  CFRelease(qualifier);
  return status;
}

static UIDRead ActualUID(void *context, AudioDeviceID id, const char *expected_uid) {
  (void)context;
  UIDRead read = {0};
  CFStringRef actual = NULL;
  AudioObjectPropertyAddress address = Address(kAudioDevicePropertyDeviceUID);
  read.size = sizeof(actual);
  read.status = AudioObjectGetPropertyData(id, &address, 0, NULL, &read.size, &actual);
  if (read.status == noErr && read.size == sizeof(actual) && actual != NULL) {
    read.type_valid = CFGetTypeID(actual) == CFStringGetTypeID();
    if (read.type_valid) {
      CFStringRef expected = CFStringCreateWithCString(kCFAllocatorDefault,
          expected_uid, kCFStringEncodingUTF8);
      read.matched = expected != NULL && CFEqual(actual, expected);
      if (expected != NULL) CFRelease(expected);
    }
  }
  if (actual != NULL) CFRelease(actual);
  return read;
}

static bool ActualHas(void *context, AudioDeviceID id,
                      AudioObjectPropertySelector selector) {
  (void)context;
  AudioObjectPropertyAddress address = Address(selector);
  return AudioObjectHasProperty(id, &address);
}

static OSStatus ActualSize(void *context, AudioDeviceID id,
                           AudioObjectPropertySelector selector, UInt32 *size) {
  (void)context;
  AudioObjectPropertyAddress address = Address(selector);
  return AudioObjectGetPropertyDataSize(id, &address, 0, NULL, size);
}

static OSStatus ActualDeclarations(void *context, AudioDeviceID id,
    AudioServerPlugInCustomPropertyInfo *info, UInt32 *size) {
  (void)context;
  AudioObjectPropertyAddress address = Address(kAudioObjectPropertyCustomPropertyInfoList);
  return AudioObjectGetPropertyData(id, &address, 0, NULL, size, info);
}

static uint64_t ActualTicks(void *context) {
  (void)context;
  return mach_absolute_time();
}

int main(int argc, char **argv) {
  (void)argv;
  if (argc != 1) {
    fputs("usage: opensteamer-diagnostic-property-negotiation\n", stderr);
    return 64;
  }
  mach_timebase_info_data_t timebase = {0};
  if (mach_timebase_info(&timebase) != KERN_SUCCESS) return 70;
  const ProbeHAL hal = {NULL, ActualLookup, ActualUID, ActualHas, ActualSize,
      ActualDeclarations, ActualTicks};
  ProbeRecord record = Collect(&hal, timebase.numer, timebase.denom);
  PrintRecord(stdout, &record);
  if (ferror(stdout)) return 70;
  return record.result == kAmbiguous ? 69 : 0;
}
#endif
