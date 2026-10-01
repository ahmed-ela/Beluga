# opensteamer Virtual Microphone driver

This directory contains the test-first replacement for the incompatible
BlackHole 2ch route. It is a separate Core Audio `AudioServerPlugIn`; it does
not replace, modify, or reuse the installed BlackHole bundle.

The production topology is fixed:

- `opensteamer Virtual Microphone` is visible, input-only, mono Float32 at
  48 kHz, and may be selected only as the default input.
- `opensteamer Virtual Microphone Writer` is hidden, output-only, mono Float32
  at 48 kHz, and cannot be any default device.
- Both endpoints share one lock-free PCM ring and one clock domain.
- Every transition from zero global I/O clients to the first client starts a
  fresh timeline, clears stale PCM by generation, and increments a nonzero
  zero-timestamp seed. A client joining an active timeline preserves that seed.
- Non-real-time client registrations are separate from the fixed 64 active PCM
  leases. Idle applications can register both endpoints without starving a new
  microphone reader. Registry allocation failure and active-stream capacity
  rejection leave the current writer and timeline intact.

The driver must pass its direct production-core and plug-in-interface tests in
both endpoint start orders and across repeated complete stops before it is
eligible for installation. A public installed-driver loopback and VPIO
compatibility probe are additional gates; neither substitutes for the final
FaceTime/far-end acceptance call.

The plug-in wrapper is based on Apple's MIT-licensed “Creating an Audio Server
Driver Plug-in” sample. `APPLE_SAMPLE_LICENSE.txt` preserves that notice. No
BlackHole source is incorporated.

## Local verification

Run the core, direct plug-in-interface, and sanitizer suites without loading a
driver:

```sh
make -C macOS/VirtualAudioDriver test test-sanitizers
```

Build the passive diagnostic reader without loading or starting a device:

```sh
mkdir -p /private/tmp/opensteamer-diagnostic-reader
macOS/VirtualAudioDriver/scripts/build-diagnostic-snapshot-reader.sh \
  /private/tmp/opensteamer-diagnostic-reader/opensteamer-diagnostic-snapshot-reader
```

Its `--read-once` mode resolves only the two exact opensteamer device UIDs,
revalidates the returned UID, and reads the versioned `osDS` property. It does
not enumerate devices, set defaults, change routes, or start I/O. A read can
return “snapshot unavailable” during a lifecycle transition; the reader never
blocks the driver waiting for one. The fixed POD capture and all real-time
recording are allocation-free. Core Audio custom-property IPC requires a
marshalled Core Foundation value, so the non-real-time property getter creates
one immutable `CFData` only after releasing the lifecycle locks.

The frozen v1 `osDS` snapshot contains 64 registration records. It is explicitly
unavailable while overflow registrations cannot be represented; it never truncates
the registry and reports a misleading green invariant. `--read-v2-once` reads the
separate `osD2` property with an exact complete variable-size registration inventory,
all 64 active-core records, and the last admission-failure operation/client/PID/status.
Its bounded non-real-time getter allocates outside lifecycle locks and revalidates
the registry revision under trylocks. A transition, allocation/size failure, or
inconsistent byte/count contract returns unavailable, not partial success. Neither
passive mode starts I/O or grants admission.

The normal host idle proof supports the complete v2 inventory and falls back to
frozen v1 only when the new property is genuinely absent on an older driver. An
unavailable or malformed v2 observation never grants a partial legacy proof.
Before installing this registration change, the historical strict-v1 guarded
driver cutover consumers still need a reviewed compatible successor: they cannot
prove idle while overflow registrations exist, even after all audio streams stop.
Do not weaken that proof, truncate v1, or treat offline tests as authorization to
replace the installed driver.

Build and verify a reproducible universal local bundle at a new temporary
path:

```sh
mkdir -p /private/tmp/opensteamer-driver-check
macOS/VirtualAudioDriver/scripts/build-driver.sh \
  /private/tmp/opensteamer-driver-check/OpensteamerVirtualMicrophone.driver
macOS/VirtualAudioDriver/scripts/verify-driver-bundle.sh \
  /private/tmp/opensteamer-driver-check/OpensteamerVirtualMicrophone.driver
```

The local build is deliberately ad hoc signed and is not an installable
production release. Production distribution requires a Developer ID
Application signature for the driver, a Developer ID Installer signature for
its package, notarization, stapling, and the separate journaled host/driver
migration. Do not copy this bundle into `/Library/Audio/Plug-Ins/HAL`, reload
Core Audio, or replace the running host outside that authorized transaction.
