# Native Android client — format-check preview, pairing/media not implemented

Requested on 2026-10-02 as part of the active Mac menu-bar client goal. This
checkout now includes an independently packaged Kotlin/Compose preview under
`android/`: explicit QR/manual input with stale/duplicate/timeout fencing, strict
invitation parsing, and no app camera/microphone/Internet permission. Its UI only
checks format and explicitly reports **not paired**. Stable identity, saved Macs,
authenticated pairing/reconnect, media and controls are not implemented.
`android/protocol` is still independently JVM-testable. The browser `/v3/audio-share` receiver is a separate listen-only
bearer-link feature and must not be relabeled as a paired Android client.

## First vertical slice

1. A native client shell with explicit QR-camera use and manual invitation entry.
   Source/build tests pass; real scanner/device behavior remains unverified.
2. A stable device identity and encrypted device-local saved-Mac catalog; do not
   rotate identity or delete another Mac when adding/forgetting a record.
3. Crash-safe durable pairing, availability and authenticated reconnect to one
   selected Mac, with stale connection work retired before switching.
4. Real native Opus stereo downlink and H.264 screen reception, with acknowledged
   Show/Hide behavior and no implicit microphone or remote-input permission.
5. Add the clarified **Move media to phone** capability only with an implemented
   receiver and exact-session/source acknowledgement semantics.

Microphone uplink, remote keyboard/pointer, media transport controls, and any
other unfinished capability must remain unadvertised. A connect-only first
slice does not establish full iOS feature parity or complete this added scope.

## Preserve the deployed wire contract

Authoritative specifications are the existing implementations and their tests:

- `shared/Sources/RemoteSessionCore/RemotePairingQRCode.swift`: bounded non-URL
  `BELUGA-PAIRING-V1\n<canonical invitation>` envelope, maximum 128 UTF-8 bytes.
- `RemoteInvitationCode.swift`: invitation version, 160-bit secret, checksum,
  canonical Crockford Base32, expiry and one-use handling.
- `RemoteDeviceIdentity.swift`, `RemotePairing.swift`, `RemotePairedDevice.swift`:
  Ed25519 identities, ephemeral X25519, HKDF/HMAC, signed confirmation, durable
  commit/activation and persisted anti-replay reconnect counters.
- `PairingBootstrapSignalingClient.swift`, `PairedAvailabilitySignalingClient.swift`,
  `RendezvousSignalingClient.swift`: exact `/v1/rendezvous` and `/v2/availability`
  routes, role-specific bounded headers and deployed subprotocols. No capability
  query strings, credential logs, redirects, or incompatible rebranding.
- `RemoteSignalingCrypto.swift`: paired-phone signaling uses ChaCha20-Poly1305,
  not the browser audio-share AES-GCM protocol.
- `shared/Sources/WebRTCTransport`: exact media directions and stream IDs, ordered
  `audiostreamer.control`/`.v2` envelopes, stereo Opus negotiation and H.264 screen
  geometry/session-generation validation. Keep compatibility spellings such as
  `iphone-microphone`; platform labels are not permission or identity evidence.

Create shared deterministic interoperability fixtures before a transport port:
UUID casing/bytes, integer ranges/counters, sorted canonical JSON, absent versus
null fields, Base64 versus Base64URL, transcript lengths/domain separation,
signatures, derived keys, nonce/AEAD layout and reconnect replay rejection.
Use reviewed cryptographic implementations; do not invent cryptography to make
one happy-path pairing test pass.

Initial fixture coverage exists for the invitation secret, checksum, Crockford
encoding and strict QR envelope. The Swift fixture test generates the expected
codes from fixed secret bytes; the JVM parser consumes those same fixtures.
On 2026-10-02 the host-JVM run passed three vectors and 79 assertions, and the
Swift fixture test passed in `mac-phone-catalog-update-policy-3.log` within
`<private-release-evidence>`. The parser was compiled with
installed JDK 26.0.1, `--release 11 -Xlint:all -Werror`.
Handshake transcripts, identity/AEAD keys, commits and reconnect replay vectors
remain outstanding. Host-JVM results are not Android SDK or device proof.

## Mac-side prerequisite: preserve multiple phones

The host source now routes every pairing/reconnect checkpoint through the bounded
phone catalog. Startup migrates the original single-viewer item once without
rewriting its bytes or host identity; catalog presence then blocks legacy reads
and writes, including after every phone is forgotten. This is source integration,
not a migration of Ahmed's installed host or protected pairing service.

The Mac menu has explicit pair/select/forget actions. New pairing preserves
existing selection; forgetting clears only the exact requested record and never
chooses a replacement. One primary phone media owner remains the policy. Actions
require actual retained process ownership, a live service lifetime and a fresh
protocol-quiescent primary-session boundary, and drain the old transport before
mutation. An active viewer is not evicted. Independent browser shares retain
their separate lifetime; LAN and test-sidecar coexistence deny catalog actions.

The integrated focused run passes 89 XCTest cases plus 27 shared signaling tests,
including the 21 in-memory catalog and 19 menu cases. The signed Simulator audio
suites pass 429 tests with the same 22 explicit physical-only skips. Neither
result proves physical iPhone-plus-Android pairing or actual Android transport.
The updater source now requires signed candidate schema v2 and an exact sealed
integer catalog1 marker before binding/install authority; even a higher-build
v1 candidate is refused. Packaging checks original plist types before lossy JSON
conversion. Focused coverage passes 83 Swift tests and 35 producer tests with
602 assertions. This is not a signed native update trial or installed migration;
those and real-device compatibility remain release gates.

## Native preview evidence — 2026-10-02

- AGP9.1.1, built-in Kotlin/Compose compiler2.2.10, Gradle9.3.1, JDK17,
  API36/Build Tools36.0.0 are pinned. Existing SDK/JDK reused; no device or
  system SDK changes. Gradle distribution and wrapper official SHA-256 match.
- Debug APK builds; 19 model tests pass with zero skips/failures/errors and
  three shared protocol vectors pass 79 assertions. Strict offline forced-task
  repeat produces identical APK bytes. Repository-layout build also passes,
  using the one `shared/ProtocolFixtures` directory rather than copied fixtures.
- Application, protocol and plugin/buildscript graphs are locked. Independent
  provenance audit covers 786 exact files: all match declared SHA-256 and
  official repository sidecars (386 SHA-256, 400 explicitly weaker SHA-1 fallback).
  No dynamic/SNAPSHOT pins, missing hashes or verification bypasses were found.
- Actual debug APK signature verifies. Package permissions exclude CAMERA,
  RECORD_AUDIO and INTERNET; network-state and signature-scoped receiver
  permissions remain. Backup/transfer are disabled. No package installation,
  Android runtime/scanner proof, release signing or distribution is claimed.

## Evidence required before support/distribution claims

- Android project/toolchain and dependency provenance pinned; reproducible unit
  tests and signed package validation. The debug preview evidence above is not
  a signed release, dependency-license inventory for distribution, or device proof.
- Cross-language pairing/encryption vectors, bad payloads, interrupted commits,
  replay rejection, reconnect, Mac switching and per-device removal.
- Existing iPhone remains paired after adding/removing Android; no live-session
  eviction or default-route change during source/development tests.
- Native Android decoded-stereo proof, rendered-screen proof and real command
  acknowledgements, not merely SDP negotiation or a connected socket.
- Unrelated-network/forced-TURN coverage and bounded resources under churn.
- Explicit audio focus/background, interruption, route-loss, permission denial,
  microphone-off and complete teardown tests. Platform restrictions must remain
  visible; do not use fake audio or background keepalives to hide them.
- Signed artifact, installed-device identity and actual feature behavior remain
  separate stages. No Android support or release is currently claimed.
