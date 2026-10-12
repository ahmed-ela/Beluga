# Android protocol core — preview UI is still not paired

This Java11 module now includes the invitation parser and the reviewed, bounded
pairing core: canonical v1 wire/transcripts, strict inbound decoding, the pinned
Foundation display-name profile, lightweight Bouncy Castle primitives, viewer
authentication, opaque identity-bound local record encoding, and the pure
bootstrap reducer/effect model, exact saved-pair reconnect authentication and
catalog/lifecycle helpers. Native encrypted identity/catalog composition is in
the app module; authenticated WSS and DNS adapters are in transport. The preview
UI calls their NEW-Mac pairing composition. Viewer-only availability routing,
exchange framing/crypto and guarded one-use reconnect response completion are
now implemented, but their selected-Mac session/media composition and a
physically validated paired Android client remain absent.

The reducer has only explicit trusted-adapter composition and fixture adapters.
Its callback receipts do not authenticate malicious in-process code or prove
physical storage durability. Close retires authorization synchronously; exact
old-transport cleanup is separate. A signed private record detects local
tampering and wrong identity, but it is not encryption, rollback/freshness
protection, or a storage-authorization proof. Public raw-seed handles are test/
composition material, not an Android Keystore implementation. Preview pairing
success requires actual authenticated completion and cleanup; a format-valid
invitation is still **not paired**. JVM adapter tests do not prove that runtime.

## Existing invitation contract

`PairingInvitation` retains the deployed checksum domain, Crockford encoding,
human-entry aliases, and strict non-URL QR envelope. Manual entry is bounded to
256 characters; QR input is bounded to 128 UTF-8 bytes. Parsing does not prove
expiry, one-use admission, or identity. `exportedCode()` exposes a capability;
never log it. Descriptions/errors contain no supplied text.

## Shared public fixtures and mandatory host tests

The existing invitation fixture remains unchanged. Retained public fixtures
live in `shared/ProtocolFixtures`, including:

- `public-swift-engine-v1.tsv`: 45 exact outputs from the actual Swift pairing
  engine using fixed public test seeds; SHA-256
  `7d8a58cd34400271d0c68ac1e263450c4ad4978337ae1bb87246362a6d0ec06a`.
- `public-foundation-unicode-name-v1.tsv`: 1198 exact observations from Foundation
  26.5.1 / 25F80, including 95 names, 12 malformed JSON cases, and the complete
  observed scalar range tables; SHA-256
  `f29705703eee4b18d32df294f0f3224a66f98c9e8d4f9e4300305667eafc92a6`.
- `public-swift-saved-pair-reconnect-v1.tsv`: 98 exact Swift reconnect outputs,
  including successive request counters and authenticated responses; SHA-256
  `3c8ef42139c81e4cff10fcc1957aa0460a7548792ce7e952498966eff51c629e`.
- `public-swift-bootstrap-envelopes-v1.tsv`: actual Swift bootstrap envelope
  capture, separately hash-pinned in its app tests.
- `public-swift-availability-v1.tsv`: 20 rows captured from the unchanged Swift
  availability client with synthetic socket boundaries, including retained
  activation, request and response wires plus directional keys; SHA-256
  `c204b3e755aacdc8e4563f448547e0e85d17ce5b081e103b53b54f26e530ed20`.
  The capture passed one XCTest case, then Android tests consume its exact
  bytes and captured production nonces. Neither fake sockets nor a derived
  session credential establish a real connection or native media behavior.

Every seed/key/name in these fixtures is public synthetic test material. Never
issue these as real invitations or treat them as real identities. Do not
regenerate the retained crypto fixture merely to change its signatures.
Hash, schema, bound, sorted-key and exact-inventory checks remain in the tests.
The Unicode table is an observed, source-bound compatibility profile, not a
claim about every Foundation OS release or Java's Unicode categories. There is
no normalization/trimming, and ill-formed UTF-16 remains refused.

Using the root-reviewed JDK17, SDK36, Gradle9.3.1 and private Gradle cache:

```sh
android/gradlew --project-dir android --gradle-user-home <private-gradle-cache> \
  --no-daemon --console=plain --dependency-verification strict :protocol:check
```

The existing invitation JavaExec task plus eight explicit JavaExec tasks run
the codec, decoder, Unicode, primitive interoperability, viewer authentication,
private-record, bootstrap and saved-pair reconnect fixtures. Gradle supplies repository-relative
fixture files as absolute arguments; the tests still authenticate exact bytes
with their pinned hashes. Mandatory tasks never export fixtures or write test
results into source. Compilation uses Java11, explicit UTF-8, all warnings as
errors and no annotation processors.

Only the default framework `test` task sets `failOnNoDiscoveredTests=false`:
there are no framework-discovered protocol tests. This does not skip or disable
the nine mandatory JavaExec suites, ignore their failures, or change app JUnit
discovery. The eight-suite run described below is historical; the added reconnect
suite passed separately against the exact retained Swift fixtures.

## Exact application-crypto dependency

`org.bouncycastle:bcprov-jdk15to18:1.86` is pinned as a protocol implementation
dependency. The adapter uses lightweight APIs without installing a global JCA
provider or selecting Android's built-in BC provider. Existing Gradle tooling's
1.79 graph is unchanged and is not this application dependency.

The provider JAR and POM have independently checked official provenance, with
their exact SHA-256 entries in Gradle verification metadata. The JAR also matches
the upstream 1.86 checksum CSV; both JAR/POM OpenPGP signatures were verified
against fingerprint `7B121B76A7ED6CE6E60AD51784E913A8E3A748C0`, anchored to
the upstream HTTPS-published public key. Gradle remains checksum-verifying;
its `verify-signatures=false` is not an OpenPGP verification claim.

The retained source JAR SHA-256 is
`434b5d4b25811177d950fb66640133950d749d4121c8ca49c2d89e9ffc5314db`.
The app asset `third-party/bouncycastle-1.86.txt` preserves the exact license text
from `org/bouncycastle/LICENSE.java` in that source JAR. The original mechanical
source export did not run Gradle or enroll locks. Root subsequently validated the
repository-layout integration on 2026-10-03: exact BC1.86-only protocol/app lock
additions, independently verified JAR/POM metadata, and 18 separately audited
lint-tool JAR/POM checksums. The plugin/buildscript graph is unchanged.

The forced strict offline run passed all 64 actionable tasks, all eight protocol
JavaExec suites, the app's 19 JUnit cases with zero failures/errors/skips, debug
assembly and lint (zero errors, four nonfatal warnings). The APK repeat is
byte-identical with SHA-256
`d14a30be82667ea03ab389e26f6a66cd40abc6b97f4a2954ee15ade0d6a96336`.
Its packaged manifest/native graphics payloads remain unchanged, and static
readback confirms the exact BC notice and six imported core class descriptors.
The camera-hardware lint suppression is limited to the CAMERA removal node;
it neither grants that permission nor suppresses other nodes/checks. This is
integrated-source/host/package evidence only, not Android runtime or device
validation. The three documentation files were refreshed afterward without
changing the tested code/configuration/fixture bytes.

See `ANDROID_CLIENT_PLAN.md` for remaining product and release gates. Host JVM
and D8/min23 checks do not establish Android runtime, real persistence/WSS,
pairing to a Mac, or media support.
