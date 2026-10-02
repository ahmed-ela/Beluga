# Android protocol foundation — not an Android app

This dependency-free Java parser is the first JVM-compatible portion of the
native Android port. It preserves the existing invitation checksum domain,
Crockford encoding, human-entry aliases, and strict non-URL QR envelope. It does
**not** connect, authenticate a pairing, persist identities, play audio, or receive
video. Expiry and one-use enforcement belong to the authenticated pairing flow;
parsing an invitation does not establish either property.

`PairingInvitation.exportedCode()` deliberately exposes the capability. Never
log it. Descriptions and errors contain no supplied text. Manual entry has a
256-character input bound; QR payloads use the Swift 128-byte bound and require
the canonical grouped spelling. SHA-256 uses the platform implementation.

Both the JVM tests and Swift `PairingInvitationInteropTests` consume
`shared/ProtocolFixtures/pairing-invitations-v1.tsv`. Every fixture contains a
public deterministic **test-only** secret; never issue these as real invitations.
The Swift test also generates each code from the fixed secret, so the JVM and
Swift parsers do not merely agree on arbitrary unverified strings.

Run from the repository root with an installed JDK; keep class outputs outside
source. No SDK download, Gradle project, emulator, or connected device is needed:

```sh
build_dir=$(mktemp -d /private/tmp/beluga-android-protocol.XXXXXX)
javac --release 11 -Xlint:all -Werror -d "$build_dir" \
  android/protocol/src/main/java/com/elamin/beluga/protocol/PairingInvitation.java \
  android/protocol/src/test/java/com/elamin/beluga/protocol/PairingInvitationTest.java
java -cp "$build_dir" com.elamin.beluga.protocol.PairingInvitationTest \
  shared/ProtocolFixtures/pairing-invitations-v1.tsv
```

This verifies the host JVM parser only, not Android SDK compatibility, QR camera
behavior, Keystore storage, or the complete cryptographic/wire protocol. See
`ANDROID_CLIENT_PLAN.md` for the remaining scope and release evidence.
