# Beluga native Android pairing preview

Version `0.1.1-pairing-preview` (code 2) connects explicit Kotlin/Compose code
entry and QR confirmation to the durable one-use NEW-Mac pairing engine.
Initialize the encrypted local library explicitly on first use. Manual Pair or
Pair scanned Mac is then a separate foreground action; scanning alone never
opens a connection. Pairing uses the fixed broker over authenticated WSS, a
device-backed identity, exact catalog/selection revisions and the shared Swift
wire protocol. Only a clean authenticated terminal plus transport/storage
teardown can report pairing success. The UI then reloads the actual saved Macs.

This is source integration, not a distributed or physically validated Android
client. Android ART, real TLS/Keystore/filesystem behavior, QR UI, host pairing
and device lifecycle still need runtime validation. Native media, microphone,
remote control and Move media to phone are not available here. Selecting a
saved Mac does not connect. An interrupted pending/accepted pairing is not
silently resumed, overwritten or deleted. **Format valid, saved and connected
are different states.**

The minimum is now Android 8.1 (API 27), matching the secure-store contract and
the networking package's tested DEX floor. The earlier format-only API 23 APK
and the isolated API 27 packaging experiment are historical artifacts, not
this candidate. Media JSON decoding adds pinned Gson 2.11.0 and its Error Prone
annotations 2.27.0 dependency with exact locks, verification and license notices.
The sections explicitly labeled historical below describe those earlier runs;
they do not claim runtime validation for this candidate.

The source also reserves reconnect counters through the encrypted writer and
exact catalog readback, with cancellation and close-drain fencing. It now adds
the viewer-only availability WSS profile, exchange-bound encryption/parser and
one-use response completion. A package-private worker now composes retained
activation, durable reconnect reservation, authenticated response, exact availability
closure and media handoff. These pieces are not exposed as a native saved-Mac
connection: a compatible native receiver and runtime validation remain unfinished. The
previous storage checkpoint's 139 app JUnit cases, bootstrap-model assertions
and debug APK/static readback are historical evidence, not validation of these
new changes. Actual Android storage, TLS, pairing and media require runtime proof.

A reconnect is not an inert health check: the Mac prepares fresh media before
returning its response. Therefore this preview deliberately has no disposable
"check connection" action that would abandon an authorized media session.

## Selected-Mac media handoff — source checkpoint

- `ViewerLibraryController` now owns an explicit selected-ACTIVE Connect attempt
  against the exact displayed snapshot and private catalog/selection revisions.
  Pairing, selection, deletion and refresh stay blocked until actual connection
  cleanup completes; an observed native TERMINAL state is not release proof.
  Stop/close cancels the exact attempt, stale callbacks cannot affect a successor,
  and uncertain cleanup remains blocked. Operational status requires an explicit
  main-owner observation and does not claim decoded media. The public default
  factory remains connection-disabled; only the package-private receiver-injected
  factory composes this path. No Connect UI or native dependency is enabled yet.
- `AndroidViewerConnection` opens only already-enrolled storage and binds the exact
  selected ACTIVE Mac and catalog/selection revisions. Pairing and media share one
  process lease. An unproven close cannot admit a successor or library mutation.
- The child availability connection sends the retained activation before reserving
  the reconnect counter. Only an authenticated response followed by exact socket,
  storage-drain and committed-record readback can transfer the fresh credential.
  Closing that child does not revoke the longer-lived parent media session.
- Parent cancellation immediately closes the credential and revokes delivery. A
  late native factory result must still be owned and drained. Storage binding and
  process admission remain held through native teardown; unknown allocation/close
  does not become a successful cancellation.
- Media uses `/v1/rendezvous` with the three existing routing/role/admission headers,
  **no Mode header and no WebSocket subprotocol**. READY supplies bounded ephemeral
  STUN/TURN configuration. It does not establish authenticated or decoded media.
- `ViewerMediaSignalingCodec` uses the deployed direction-bound AEAD layout and
  replay window, not the availability domain framing. Strict bounded JSON parsing
  rejects duplicate keys, wrong roles/directions, malformed encodings and schema
  extensions. Exact duplicate READY cannot reset sequence/replay state.
- The public 40-row Swift capture is SHA-256
  `121c509e314c599ca9239715a3e1924513f29700f440d4bfe84bcb9b09b33510`.
  It contains synthetic actual Swift wire messages, not captured user sessions.
  JVM tests cover byte-exact ciphertext/wire interoperability, fault paths and fake
  media lifecycle. They do not establish Android Keystore, native WebRTC, PCM,
  screen rendering, physical pairing, release installation or distribution.

The retained M150 WebRTC library remains outside this APK: its 64-bit ELF RELRO
end alignment fails the documented 16 KB criterion. Private source compilation
against that API is not a compatible distributable dependency or runtime proof.
No new microphone permission, local capture, Connect button or production session
is introduced by this checkpoint.

## Screen-control v2 — source checkpoint

`ViewerScreenControlCodec` reads the existing Mac's JSON text protocol, with the
4,096-byte bound, strict UTF-8/schema/duplicate checks and full nonzero UInt64
request IDs. It validates then discards optional input capabilities; this
receive-only implementation grants no keyboard/pointer authority. Unrelated
host messages are bounded and ignored, not treated as media-control support.

`ViewerScreenSession` owns one exact peer/control/track lifetime. An explicit Show
requires foreground health, successful actual write and a matching Active ACK.
Hide/background revoke local presentation leases immediately; stale ACKs, queued
writes and scene generations cannot reopen them. Transient inactivity covers
an acknowledged Show without automatically sending another one. Hide failure,
health loss and expired operations close the lifetime. Keyframe requests do not
replace the Show lease. One write plus one required Hide bounds queued work.

A renderer that already holds its own exact post-swap receipt can request a fresh
lease for the **same acknowledged Show** after transient inactivity. The model
checks the original issuer, peer, control, track and Show-operation identity as
well as current scene, health and deadlines. It cannot revive a buffer after Hide,
backgrounding or a later Show. This permission is not a frame/draw receipt; a
native owner must separately prove the retained buffer belongs to that Show.

The public 49-row actual-Swift control capture is SHA-256
`515a9f854188a19203d5302da23e067d5afd856906534670857cdecc0c1eb8d1`.
Its deterministic sorted keys are fixture canonicalization, not a production
JSON ordering guarantee. The UInt64.max rows demonstrate wire capacity; the
session refuses issuing that final ID, matching the current Mac peer's bound.

These are protocol and lifecycle components, not a native Connect action. A
Show ACK proves host capture admission, **not Android decoded or rendered pixels**.
The native-library compatibility gate, actual DataChannel binding, foreground
privacy cover/rendering integration and Android runtime tests remain release
requirements. No live session or permission change is part of this checkpoint.

## Admission and privacy

- Only the user’s Scan button launches the scanner. Google Play services owns
  its camera UI. App camera/microphone permissions remain removed at manifest
  merge. INTERNET is enabled for explicit pairing, with cleartext disabled.
- Google Play services and its unbundled scanner module are required. First use
  can download the module through Play services. SDK failure shows a fixed
  unavailable message and manual entry stays available; no fallback fabricates
  a scan. Non-GMS devices can use manual entry only in this slice.
- QR input uses only the exact non-URL `BELUGA-PAIRING-V1\n<canonical code>`
  envelope. Manual input keeps the deployed ASCII aliases/separators/checksum.
  URL, null, Unicode look-alike, overlength, noncanonical and wrong-format
  payloads are refused before any network work.
- There is one SDK task owner at a time. Opaque attempt identity and a monotonic
  120-second result-admission window refuse duplicate, stale, cancelled or
  superseded callbacks. Expiry/clear revokes result admission but retains SDK
  ownership until the task ends, so another scanner is not launched over it.
- Entered text is memory-only, masked, bounded to 256 characters, cleared on
  consumption/clear/background/destruction, and never logged or saved in Bundle,
  preferences, clipboard, files or crash messages. A parsed QR invitation stays
  private only until explicit confirmation, the original scan deadline, clear,
  edit or lifecycle invalidation. It is consumed at most once; the UI state
  exposes no invitation. Managed-runtime erasure is not guaranteed.
- Leaving the foreground revokes an active pairing immediately. Cancellation
  is not completion: another pairing/library mutation remains blocked while
  cleanup is pending. Unknown cleanup remains fail-closed, never a retry loop.
  An external scanner's pending SDK task may finish after backgrounding, but
  its result can only stage a candidate for a new foreground confirmation.
- Android backups/transfers are disabled and the activity sets FLAG_SECURE.
  There is no automatic clipboard read and no invitation-bearing intent/deep link.

## Exact dependency selection

| Component | Pin | Rationale |
| --- | --- | --- |
| Gradle | 9.3.1 | AGP’s documented compatible version; ZIP SHA-256 pinned in wrapper properties. |
| AGP | 9.1.1 | API36 / Build Tools36.0.0 / JDK17 compatible; uses built-in KGP2.2.10. |
| Compose compiler | 2.2.10 | Must match that built-in Kotlin version; no old kotlin-android plugin. |
| Compose BOM | 2025.06.01 | Google Maven POM pins UI/Foundation1.8.3 and Material3 1.3.2; conservative stable API36-compatible graph instead of new SDK37+ requirements. |
| Activity Compose | 1.11.0 | Documented compiled API36, stable, minimum API23. |
| Google Code Scanner | 16.1.0 | Official Google scanner dependency; delegated explicit camera UI with no app camera permission. |
| JUnit | 4.13.2 | Stable host-unit-test runner. |
| Application crypto | org.bouncycastle:bcprov-jdk15to18:1.86 | Exact verified lightweight raw-protocol primitives; no global provider registration. Exact app/protocol rows are enrolled; tooling BC1.79 is unchanged. |
| Media JSON | com.google.code.gson:gson:2.11.0 | Strict streaming parser with closed, bounded application schemas; transitive annotations 2.27.0 are pinned and verified. |

Compile/target SDK36, Build Tools36.0.0, minimum API27, Java17 app and Java11
protocol bytecode are explicit. Direct versions are pinned; all configurations
use strict Gradle dependency locking for the resolved graph and artifact
checksum verification. Gradle rejects combining locking with its alternative
fail-on-dynamic-version mode, so those incompatible flags are not combined.
No SDK/JDK auto-download is authorized or configured.

Primary provenance:

- [AGP9.1 compatibility](https://developer.android.com/build/releases/agp-9-1-0-release-notes)
- [Built-in Kotlin](https://developer.android.com/build/migrate-to-built-in-kotlin)
- [Compose compiler setup](https://developer.android.com/develop/ui/compose/compiler)
- [Exact Google Maven BOM POM](https://dl.google.com/dl/android/maven2/androidx/compose/compose-bom/2025.06.01/compose-bom-2025.06.01.pom)
- [Activity1.11 release](https://developer.android.com/jetpack/androidx/releases/activity#1.11.0)
- [Google Code Scanner](https://developers.google.com/ml-kit/vision/barcode-scanning/code-scanner)
- [Gradle distribution/wrapper checksums](https://gradle.org/release-checksums/)
- [Dependency verification](https://docs.gradle.org/9.3.1/userguide/dependency_verification.html)

## Historical preview bootstrap — 2026-10-02

Supply the already verified JDK17 and SDK36 via JAVA_HOME and ANDROID_HOME.
Use an isolated GRADLE_USER_HOME outside any production checkout. Root generated
the wrapper using the verified Gradle9.3.1 distribution and checked its JAR
against the separately retrieved official checksum below. Dependency locks and
verification metadata have been bootstrapped. A strict offline repeat with all
47 tasks forced to execute also passes, including all 19 model tests and 79
protocol assertions. Its APK hash matches the first successful build. The
independent provenance audit compared all 786 exact cached files to their declared
SHA-256 and official repository sidecars: 386 published SHA-256 matches and 400
explicit SHA-1 fallback matches, with no missing or mismatched file. SHA-1 is
weaker provenance; this is not publisher-signature or malware-free evidence.
The 115-component plugin/buildscript graph is locked separately from app/protocol
graphs. Never regenerate verification metadata automatically in CI.

Using the independently verified Gradle9.3.1 executable:

```sh
gradle --project-dir <scratch-project> --gradle-user-home <private-gradle-cache> \
  --no-daemon --console=plain --write-locks --write-verification-metadata sha256 \
  :protocol:invitationInteropTest :app:testDebugUnitTest :app:assembleDebug
```

This is a **bootstrap observation**, not trusted dependency verification:
review every generated checksum/lock against primary artifact provenance before
accepting `gradle/verification-metadata.xml` and `gradle.lockfile` files. Then run
the same tasks using `--dependency-verification strict` and no write flags.
Do not turn verification off or silently approve changed hashes.

Generate wrapper scripts/JAR only with the verified local Gradle9.3.1:

```sh
gradle --project-dir <scratch-project> --gradle-user-home <private-gradle-cache> \
  --no-daemon wrapper --gradle-version 9.3.1 --distribution-type bin \
  --gradle-distribution-sha256-sum b266d5ff6b90eada6dc3b20cb090e3731302e553a27c5d3e4df1f0d76beaff06
```

Verify generated wrapper JAR SHA-256 equals the official9.3.1 value
`b3a875ddc1f044746e1b1a55f645584505f4a10438c1afea9f15e92a7c42ec13`.
Inspect the merged manifest/APK for permission, backup and capability boundaries.
Root's initial APK readback has no CAMERA, RECORD_AUDIO or INTERNET permission;
transitive ACCESS_NETWORK_STATE and the signature-scoped dynamic-receiver
permission remain. The standard profile-installer receiver is exported behind
android.permission.DUMP; the launcher is the only unprotected exported component.
Debug v1/v2 APK signature verification passes. This is not release signing.
The 19 model unit tests and shared 3-vector/79-assertion parser test are host
proof only. Physical QR UI, Play-service availability, lifecycle and package
behavior still require independent Android validation.

## Historical integrated protocol validation — 2026-10-03

Root's isolated repository-layout run passed `:protocol:check`,
`:app:testDebugUnitTest`, `:app:assembleDebug` and `:app:lintDebug` using strict
dependency verification, `--offline --rerun-tasks`, no build/configuration cache,
and the already reviewed toolchain/cache. All 64 actionable tasks executed.
All eight protocol JavaExec suites passed; the app's 19 JUnit cases had zero
failures, errors or skips. Lint reports zero errors and four nonfatal warnings:
three newer-tool/dependency notices and the preview's missing application icon.
This is not a claim that every Gradle task ran or that lint is warning-free.

Only `:protocol:test` sets `failOnNoDiscoveredTests=false` because this module's
tests are standalone JavaExec mains, not framework-discovered tests. All eight
named JavaExec suites remain mandatory `check` dependencies; none are disabled
and test failures are not ignored. App JUnit discovery is unchanged.

The protocol/app lock delta adds only exact BC1.86; the plugin/buildscript lock
is unchanged. Its JAR/POM provenance and the 18 additional lint JAR/POM SHA-256
checksums were independently matched to official repository sidecars before
strict verification. The CAMERA removal node alone has
`tools:ignore="PermissionImpliesUnsupportedChromeOsHardware"`; this is not a
global suppression, camera permission grant, or new hardware requirement.

The forced offline repeat produces the identical APK SHA-256
`d14a30be82667ea03ab389e26f6a66cd40abc6b97f4a2954ee15ade0d6a96336`.
Static readback confirms the packaged manifest and all four existing native
graphics libraries are byte-identical to the preview baseline, the exact BC
notice asset is present, and the six imported core classes are in DEX. Debug
v1/v2 signature verification passes. Separate private JVM and D8/min23 gates
remain host/compiler evidence, not API23 runtime proof. No APK installation,
scanner/device test, real identity/storage/WSS, Mac pairing or media validation
has occurred. Documentation was refreshed after this run; the tested code,
configuration and fixture bytes are unchanged.

That historical preview did not wire storage or WSS. The current source adds
that composition and UI admission, but a paired Android runtime still requires
device evidence. Do not replace an existing iPhone binding or infer pairing
from a format-valid status, JVM tests or an APK build.
