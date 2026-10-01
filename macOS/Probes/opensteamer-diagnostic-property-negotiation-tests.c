#define OS_DIAGNOSTIC_NEGOTIATION_TESTING 1
#include "opensteamer-diagnostic-property-negotiation.c"
#include <stdlib.h>

static unsigned assertions, tests;
#define CHECK(condition) do { ++assertions; if (!(condition)) { \
  fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #condition); \
  exit(1); } } while (0)

typedef struct Fixture {
  EndpointRead reads[2][2];
  uint64_t tick_values[3];
  unsigned lookups, pass, uid_calls[2][2], has_calls, size_calls, data_calls, ticks;
} Fixture;

static Fixture Fresh(bool v2) {
  Fixture fixture = {0};
  fixture.tick_values[0] = 100;
  fixture.tick_values[1] = 200;
  fixture.tick_values[2] = 300;
  for (unsigned pass = 0; pass < 2; ++pass) {
    for (unsigned endpoint = 0; endpoint < 2; ++endpoint) {
      EndpointRead *read = &fixture.reads[pass][endpoint];
      read->id = endpoint == 0 ? 100 : 200;
      read->lookup_size = sizeof(AudioDeviceID);
      read->final_id = read->id;
      read->final_lookup_size = sizeof(AudioDeviceID);
      read->uid_before = (UIDRead){noErr, sizeof(CFStringRef), true, true};
      read->uid_after = read->uid_before;
      read->declarations_have_property = true;
      read->declaration_count = v2 ? 2 : 1;
      read->declarations_size = read->declaration_count *
          sizeof(AudioServerPlugInCustomPropertyInfo);
      read->declarations_returned_size = read->declarations_size;
      read->declarations[0] = (AudioServerPlugInCustomPropertyInfo){kV1Selector,
          kAudioServerPlugInCustomPropertyDataTypeCFPropertyList,
          kAudioServerPlugInCustomPropertyDataTypeNone};
      if (v2) read->declarations[1] = (AudioServerPlugInCustomPropertyInfo){
          kV2Selector, kAudioServerPlugInCustomPropertyDataTypeCFPropertyList,
          kAudioServerPlugInCustomPropertyDataTypeNone};
      read->v1 = (PropertyRead){true, true, noErr, sizeof(CFPropertyListRef)};
      read->v2 = v2 ? read->v1 : (PropertyRead){false, false,
          kAudioHardwareUnknownPropertyError, 0};
    }
  }
  return fixture;
}

static unsigned Endpoint(const char *uid) {
  CHECK(strcmp(uid, kUIDs[0]) == 0 || strcmp(uid, kUIDs[1]) == 0);
  return strcmp(uid, kUIDs[0]) == 0 ? 0 : 1;
}

static EndpointRead *ReadForID(Fixture *fixture, AudioDeviceID id) {
  for (unsigned endpoint = 0; endpoint < 2; ++endpoint)
    if (fixture->reads[fixture->pass][endpoint].id == id)
      return &fixture->reads[fixture->pass][endpoint];
  CHECK(false);
  return NULL;
}

static OSStatus Lookup(void *context, const char *uid, AudioDeviceID *id,
                       UInt32 *size) {
  Fixture *fixture = context;
  unsigned call = fixture->lookups++;
  CHECK(call < 8);
  fixture->pass = call / 4;
  EndpointRead *read = &fixture->reads[fixture->pass][Endpoint(uid)];
  if (call % 4 < 2) {
    *id = read->id; *size = read->lookup_size; return read->lookup_status;
  }
  *id = read->final_id; *size = read->final_lookup_size;
  return read->final_lookup_status;
}

static UIDRead UID(void *context, AudioDeviceID id, const char *uid) {
  Fixture *fixture = context;
  unsigned endpoint = Endpoint(uid);
  EndpointRead *read = ReadForID(fixture, id);
  unsigned call = fixture->uid_calls[fixture->pass][endpoint]++;
  CHECK(call < 2);
  return call == 0 ? read->uid_before : read->uid_after;
}

static bool Has(void *context, AudioDeviceID id,
                AudioObjectPropertySelector selector) {
  Fixture *fixture = context;
  ++fixture->has_calls;
  EndpointRead *read = ReadForID(fixture, id);
  if (selector == kAudioObjectPropertyCustomPropertyInfoList)
    return read->declarations_have_property;
  CHECK(selector == kV1Selector || selector == kV2Selector);
  return selector == kV1Selector ? read->v1.has_property : read->v2.has_property;
}

static OSStatus FixtureSize(void *context, AudioDeviceID id,
    AudioObjectPropertySelector selector, UInt32 *size) {
  Fixture *fixture = context;
  ++fixture->size_calls;
  EndpointRead *read = ReadForID(fixture, id);
  if (selector == kAudioObjectPropertyCustomPropertyInfoList) {
    *size = read->declarations_size; return read->declarations_size_status;
  }
  CHECK(selector == kV1Selector || selector == kV2Selector);
  PropertyRead *property = selector == kV1Selector ? &read->v1 : &read->v2;
  *size = property->size; return property->size_status;
}

static OSStatus Declarations(void *context, AudioDeviceID id,
    AudioServerPlugInCustomPropertyInfo *items, UInt32 *size) {
  Fixture *fixture = context;
  ++fixture->data_calls;
  EndpointRead *read = ReadForID(fixture, id);
  CHECK(*size <= kMaximumDeclarations * sizeof(*items));
  UInt32 available = *size / sizeof(*items);
  UInt32 count = read->declaration_count < available ?
      read->declaration_count : available;
  memcpy(items, read->declarations, count * sizeof(*items));
  *size = read->declarations_returned_size;
  return read->declarations_data_status;
}

static uint64_t Ticks(void *context) {
  Fixture *fixture = context;
  CHECK(fixture->ticks < 3);
  return fixture->tick_values[fixture->ticks++];
}

static ProbeRecord RunTimebase(Fixture *fixture, UInt32 numer, UInt32 denom) {
  const ProbeHAL hal = {fixture, Lookup, UID, Has, FixtureSize, Declarations, Ticks};
  return Collect(&hal, numer, denom);
}
static ProbeRecord Run(Fixture *fixture) { return RunTimebase(fixture, 1, 1); }

static void Legacy(void) {
  Fixture fixture = Fresh(false); ProbeRecord record = Run(&fixture);
  CHECK(record.result == kLegacyV1);
  CHECK(strcmp(record.reason, "exact-stable-metadata") == 0);
  CHECK(fixture.lookups == 8 && fixture.has_calls == 12 &&
        fixture.size_calls == 12 && fixture.data_calls == 4);
  CHECK(record.ticks_before == 100 && record.ticks_after == 300);
  CHECK(record.passes[1][1].v2.size_status == kAudioHardwareUnknownPropertyError);
}

static void V2(void) {
  Fixture fixture = Fresh(true); ProbeRecord record = Run(&fixture);
  CHECK(record.result == kV2Present);
  CHECK(record.passes[0][0].declaration_count == 2);
}

static void GenericErrors(void) {
  const OSStatus errors[] = {kAudioHardwareUnspecifiedError,
      kAudioHardwareIllegalOperationError, kAudioHardwareBadObjectError,
      kAudioHardwareNotReadyError, kAudio_MemFullError};
  for (unsigned error = 0; error < sizeof(errors)/sizeof(errors[0]); ++error) {
    Fixture fixture = Fresh(false);
    for (unsigned pass = 0; pass < 2; ++pass)
      for (unsigned endpoint = 0; endpoint < 2; ++endpoint)
        fixture.reads[pass][endpoint].v2.size_status = errors[error];
    CHECK(Run(&fixture).result == kAmbiguous);
  }
}

static void AdvertisedUnavailable(void) {
  Fixture fixture = Fresh(true);
  for (unsigned pass = 0; pass < 2; ++pass)
    for (unsigned endpoint = 0; endpoint < 2; ++endpoint) {
      fixture.reads[pass][endpoint].v2.has_property = false;
      fixture.reads[pass][endpoint].v2.size_status = kAudioHardwareUnknownPropertyError;
    }
  CHECK(Run(&fixture).result == kAmbiguous);
}

static void UndeclaredPresent(void) {
  Fixture fixture = Fresh(false);
  for (unsigned pass = 0; pass < 2; ++pass)
    for (unsigned endpoint = 0; endpoint < 2; ++endpoint)
      fixture.reads[pass][endpoint].v2 = fixture.reads[pass][endpoint].v1;
  CHECK(Run(&fixture).result == kAmbiguous);
}

static void OneFieldMutations(void) {
  for (unsigned pass = 0; pass < 2; ++pass) {
    for (unsigned endpoint = 0; endpoint < 2; ++endpoint) {
      for (unsigned mutation = 0; mutation < 21; ++mutation) {
        Fixture fixture = Fresh(true);
        EndpointRead *read = &fixture.reads[pass][endpoint];
        switch (mutation) {
        case 0: read->v1.has_property = false; break;
        case 1: read->v1.size_status = kAudioHardwareUnknownPropertyError; break;
        case 2: read->v1.size = 4; break;
        case 3: read->v2.has_property = false; break;
        case 4: read->v2.size_status = kAudioHardwareUnspecifiedError; break;
        case 5: read->v2.size = 4; break;
        case 6: read->declarations[1] = read->declarations[0]; break;
        case 7: read->declarations[1].mPropertyDataType =
                    kAudioServerPlugInCustomPropertyDataTypeCFString; break;
        case 8: read->declarations[1].mQualifierDataType =
                    kAudioServerPlugInCustomPropertyDataTypeCFString; break;
        case 9: read->declarations_size = 0; break;
        case 10: read->declarations_size = UINT32_MAX; break;
        case 11: read->declarations_size = 13; break;
        case 12: read->declarations_size_status = kAudioHardwareUnknownPropertyError; break;
        case 13: read->declarations_returned_size -= 1; break;
        case 14: read->declarations_data_status = kAudioHardwareUnspecifiedError; break;
        case 15: read->uid_before.matched = false; break;
        case 16: read->uid_after.matched = false; break;
        case 17: read->uid_after.type_valid = false; break;
        case 18: read->uid_after.size = 4; break;
        case 19: read->uid_after.status = kAudioHardwareBadObjectError; break;
        case 20: read->declarations_have_property = false; break;
        }
        CHECK(Run(&fixture).result == kAmbiguous);
        CHECK(fixture.data_calls <= 4);
      }
    }
  }
}

static void IdentityDrift(void) {
  for (unsigned pass = 0; pass < 2; ++pass)
    for (unsigned endpoint = 0; endpoint < 2; ++endpoint)
      for (unsigned mutation = 0; mutation < 6; ++mutation) {
        Fixture fixture = Fresh(false);
        EndpointRead *read = &fixture.reads[pass][endpoint];
        switch (mutation) {
        case 0: read->lookup_status = kAudioHardwareBadDeviceError; break;
        case 1: read->lookup_size = 3; break;
        case 2: read->id = kAudioObjectUnknown; break;
        case 3: read->final_id += 1; break;
        case 4: read->final_lookup_status = kAudioHardwareUnspecifiedError; break;
        case 5: read->final_lookup_size = 3; break;
        }
        CHECK(Run(&fixture).result == kAmbiguous);
      }
  Fixture fixture = Fresh(false);
  fixture.reads[1][1].id += 1; fixture.reads[1][1].final_id += 1;
  CHECK(Run(&fixture).result == kAmbiguous);
}

static void DuplicateIDs(void) {
  Fixture fixture = Fresh(false);
  for (unsigned pass = 0; pass < 2; ++pass) {
    fixture.reads[pass][1].id = fixture.reads[pass][0].id;
    fixture.reads[pass][1].final_id = fixture.reads[pass][0].id;
  }
  CHECK(Run(&fixture).result == kAmbiguous);
}

static void MixedEndpoints(void) {
  Fixture legacy = Fresh(false), v2 = Fresh(true);
  for (unsigned pass = 0; pass < 2; ++pass)
    legacy.reads[pass][1] = v2.reads[pass][1];
  CHECK(Run(&legacy).result == kAmbiguous);
}

static void MixedPasses(void) {
  Fixture legacy = Fresh(false), v2 = Fresh(true);
  legacy.reads[1][0] = v2.reads[1][0]; legacy.reads[1][1] = v2.reads[1][1];
  ProbeRecord record = Run(&legacy);
  CHECK(record.result == kAmbiguous);
  CHECK(strcmp(record.reason, "metadata-changed") == 0);
}

static void DeclarationChurn(void) {
  Fixture fixture = Fresh(true);
  AudioServerPlugInCustomPropertyInfo saved = fixture.reads[1][0].declarations[0];
  fixture.reads[1][0].declarations[0] = fixture.reads[1][0].declarations[1];
  fixture.reads[1][0].declarations[1] = saved;
  CHECK(Run(&fixture).result == kAmbiguous);
}

static void BoundedDeclarations(void) {
  Fixture fixture = Fresh(false);
  for (unsigned pass = 0; pass < 2; ++pass)
    for (unsigned endpoint = 0; endpoint < 2; ++endpoint) {
      EndpointRead *read = &fixture.reads[pass][endpoint];
      read->declaration_count = kMaximumDeclarations;
      read->declarations_size = read->declarations_returned_size =
          sizeof(read->declarations);
      for (unsigned index = 1; index < kMaximumDeclarations; ++index)
        read->declarations[index] = (AudioServerPlugInCustomPropertyInfo){
            1000 + index, kAudioServerPlugInCustomPropertyDataTypeCFString, 0};
    }
  CHECK(Run(&fixture).result == kLegacyV1);
  fixture = Fresh(false);
  fixture.reads[0][0].declarations_size =
      (kMaximumDeclarations + 1) * sizeof(AudioServerPlugInCustomPropertyInfo);
  CHECK(Run(&fixture).result == kAmbiguous);
  CHECK(fixture.data_calls == 3);
}

static void InvalidUnrelatedDeclaration(void) {
  for (unsigned mutation = 0; mutation < 4; ++mutation) {
    Fixture fixture = Fresh(false);
    EndpointRead *read = &fixture.reads[0][0];
    read->declaration_count = 2;
    read->declarations_size = read->declarations_returned_size =
        2 * sizeof(AudioServerPlugInCustomPropertyInfo);
    read->declarations[1] = (AudioServerPlugInCustomPropertyInfo){1000,
        kAudioServerPlugInCustomPropertyDataTypeCFString, 0};
    switch (mutation) {
    case 0: read->declarations[1].mSelector = 0; break;
    case 1: read->declarations[1].mPropertyDataType = UINT32_MAX; break;
    case 2: read->declarations[1].mQualifierDataType = UINT32_MAX; break;
    case 3: read->declarations[1] = read->declarations[0]; break;
    }
    CHECK(Run(&fixture).result == kAmbiguous);
  }
}

static void WindowFailures(void) {
  for (unsigned mutation = 0; mutation < 5; ++mutation) {
    Fixture fixture = Fresh(false);
    switch (mutation) {
    case 0: fixture.tick_values[2] = 100; break;
    case 1: fixture.tick_values[2] = 99; break;
    case 2: fixture.tick_values[2] = 2000000101; break;
    case 3: fixture.tick_values[1] = 2000000101; break;
    case 4: fixture.tick_values[2] = UINT64_MAX; break;
    }
    CHECK(Run(&fixture).result == kAmbiguous);
    CHECK(fixture.lookups <= 8);
    if (mutation == 3) CHECK(fixture.lookups == 4);
  }
  Fixture fixture = Fresh(false);
  CHECK(RunTimebase(&fixture, 0, 1).result == kAmbiguous);
  fixture = Fresh(false);
  CHECK(RunTimebase(&fixture, 1, 0).result == kAmbiguous);
  fixture = Fresh(false);
  CHECK(RunTimebase(&fixture, UINT32_MAX, UINT32_MAX).result == kLegacyV1);
}

static void StatusEvidence(void) {
  Fixture fixture = Fresh(false);
  fixture.reads[1][0].v2.size_status = kAudioHardwareUnspecifiedError;
  ProbeRecord record = Run(&fixture);
  CHECK(record.result == kAmbiguous);
  CHECK(record.passes[0][0].v2.size_status == kAudioHardwareUnknownPropertyError);
  CHECK(record.passes[1][0].v2.size_status == kAudioHardwareUnspecifiedError);
  FILE *out = tmpfile(); CHECK(out != NULL);
  PrintRecord(out, &record); CHECK(!ferror(out));
  CHECK(ftell(out) > 0 && ftell(out) < 32768);
  rewind(out); char bytes[32768] = {0};
  CHECK(fread(bytes, 1, sizeof(bytes) - 1, out) > 0);
  CHECK(strstr(bytes, "\"sizeStatus\":2003332927") != NULL);
  CHECK(strstr(bytes, "\"sizeStatus\":2003329396") != NULL);
  CHECK(strstr(bytes, "\"classification\":\"ambiguous\"") != NULL);
  CHECK(fclose(out) == 0);
}

static void RunTest(const char *name, void (*test)(void)) {
  test(); ++tests; printf("ok - %s\n", name);
}

int main(int argc, char **argv) {
  if (argc == 3 && strcmp(argv[1], "--fixture-json") == 0) {
    CHECK(strcmp(argv[2], "legacy") == 0 || strcmp(argv[2], "v2") == 0);
    Fixture fixture = Fresh(strcmp(argv[2], "v2") == 0);
    ProbeRecord record = Run(&fixture); PrintRecord(stdout, &record); return 0;
  }
  CHECK(argc == 1);
  RunTest("legacy requires exact mirrored absence", Legacy);
  RunTest("v2 requires exact mirrored presence", V2);
  RunTest("generic errors never authorize fallback", GenericErrors);
  RunTest("advertised unavailable v2 never authorizes fallback", AdvertisedUnavailable);
  RunTest("undeclared present v2 is ambiguous", UndeclaredPresent);
  RunTest("every endpoint and pass rejects one-field ambiguity", OneFieldMutations);
  RunTest("UID lookup and final ID drift fail closed", IdentityDrift);
  RunTest("duplicate endpoint IDs fail closed", DuplicateIDs);
  RunTest("mixed endpoint versions fail closed", MixedEndpoints);
  RunTest("mixed pass versions fail closed", MixedPasses);
  RunTest("declaration churn fails closed", DeclarationChurn);
  RunTest("complete bounded declaration inventory", BoundedDeclarations);
  RunTest("malformed unrelated declarations fail closed", InvalidUnrelatedDeclaration);
  RunTest("invalid and oversized windows fail closed", WindowFailures);
  RunTest("raw before and after failure status evidence retained", StatusEvidence);
  printf("%u tests, %u assertions, 0 failures\n", tests, assertions);
  puts("diagnostic property negotiation offline tests passed");
  return 0;
}
