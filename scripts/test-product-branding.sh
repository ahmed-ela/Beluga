#!/bin/zsh
# Deterministic regression tests for the current-tree product-branding allowlist.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMPORARY_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/opensteamer-branding-tests.XXXXXX")
trap 'rm -rf "$TEMPORARY_ROOT"' EXIT

initialize_repository() {
  local repository=$1
  mkdir -p "$repository/scripts"
  cp "$ROOT_DIR/scripts/check-product-branding.sh" "$repository/scripts/"
  git -C "$repository" init -q -b main
  git -C "$repository" config user.name "opensteamer contributors"
  git -C "$repository" config user.email "opensteamer@users.noreply.github.com"
}

commit_all() {
  local repository=$1
  git -C "$repository" add -A
  git -C "$repository" commit -q -m "branding fixture"
}

require_failure() {
  local repository=$1
  local expected=$2
  local output="$TEMPORARY_ROOT/rejection-$RANDOM.log"
  if "$repository/scripts/check-product-branding.sh" "$repository" >"$output" 2>&1; then
    print -u2 -- "branding fixture unexpectedly passed"
    exit 1
  fi
  grep -Fq -- "$expected" "$output"
}

PRODUCTION_HOST='audiostreamer-rendezvous.elaminahmed03.workers.dev'
PRODUCTION_URL="wss://${PRODUCTION_HOST}"
PRODUCTION_BUNDLE_ID='com.elamin.AudioStreamer'
DEBUG_BUNDLE_ID='org.example.AudioStreamer.dev'

write_current_automatic_signing_fixture() {
  local repository=$1

  mkdir -p "$repository/iOS/opensteamer/opensteamer.xcodeproj"

  cat >"$repository/iOS/opensteamer/project.yml" <<EOF
name: opensteamer
targets:
  opensteamer:
    type: application
    attributes:
      ProvisioningStyle: Automatic
    settings:
      base:
        MARKETING_VERSION: 0.1.0
        CURRENT_PROJECT_VERSION: 1
        OPENSTEAMER_RENDEZVOUS_URL: ""
      configs:
        Debug:
          PRODUCT_BUNDLE_IDENTIFIER: ${DEBUG_BUNDLE_ID}
          CODE_SIGN_STYLE: Automatic
        Release:
          PRODUCT_BUNDLE_IDENTIFIER: ${PRODUCTION_BUNDLE_ID}
          DEVELOPMENT_TEAM: MSMG8CJLB3
          CURRENT_PROJECT_VERSION: 34
          CODE_SIGN_STYLE: Automatic
          OPENSTEAMER_RENDEZVOUS_URL: "${PRODUCTION_URL}"
EOF

  cat >"$repository/iOS/opensteamer/opensteamer.xcodeproj/project.pbxproj" <<EOF
// opensteamer automatic-signing fixture
{
	objects = {
		0240299FE56B5D6503940318 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_STYLE = Automatic;
				OPENSTEAMER_RENDEZVOUS_URL = "";
				PRODUCT_BUNDLE_IDENTIFIER = ${DEBUG_BUNDLE_ID};
			};
			name = Debug;
		};
		5ADF15167753B5B287DCA772 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 34;
				DEVELOPMENT_TEAM = MSMG8CJLB3;
				MARKETING_VERSION = 0.1.0;
				OPENSTEAMER_RENDEZVOUS_URL = "${PRODUCTION_URL}";
				PRODUCT_BUNDLE_IDENTIFIER = ${PRODUCTION_BUNDLE_ID};
			};
			name = Release;
		};
	};
}
EOF

  cat >"$repository/README.md" <<EOF
# Beluga

| Configuration field | Checked-in value |
| --- | --- |
| Production bundle | <code>${PRODUCTION_BUNDLE_ID}</code> |
| Debug bundle | <code>${DEBUG_BUNDLE_ID}</code> |
EOF
}

write_project_scope_fixture() {
  local repository=$1
  local target=$2
  local configuration=$3
  local setting=$4
  local url=$5

  cat >"$repository/iOS/opensteamer/project.yml" <<EOF
targets:
  ${target}:
    settings:
      configs:
        ${configuration}:
          ${setting}: "${url}"
EOF
}

write_pbxproj_scope_fixture() {
  local repository=$1
  local configuration=$2
  local bundle_identifier=$3
  local setting=$4
  local url=$5

  cat >"$repository/iOS/opensteamer/opensteamer.xcodeproj/project.pbxproj" <<EOF
// opensteamer branding mutation fixture
{
	objects = {
		AAAAAAAAAAAAAAAAAAAAAAAA /* ${configuration} */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_STYLE = Automatic;
				${setting} = "${url}";
				PRODUCT_BUNDLE_IDENTIFIER = ${bundle_identifier};
			};
			name = ${configuration};
		};
	};
}
EOF
}

ALLOWED="$TEMPORARY_ROOT/allowed"
initialize_repository "$ALLOWED"
mkdir -p \
  "$ALLOWED/services/Rendezvous/src" \
  "$ALLOWED/iOS/opensteamer/Sources/Security" \
  "$ALLOWED/iOS/opensteamer/Sources/Support" \
  "$ALLOWED/iOS/opensteamer/Tests" \
  "$ALLOWED/macOS/Sources/CaptureServer" \
  "$ALLOWED/shared/Sources/RemoteSessionCore"
print -r -- "# Beluga" >"$ALLOWED/README.md"
print -r -- 'export const CHANNEL_HEADER = "x-audiostreamer-channel";' \
  >"$ALLOWED/services/Rendezvous/src/protocol.mjs"
print -r -- 'let service = "org.example.AudioStreamer"' \
  >"$ALLOWED/iOS/opensteamer/Sources/Security/KeychainStore.swift"
print -r -- '<key>OpensteamerRendezvousURL</key>' \
  >"$ALLOWED/iOS/opensteamer/Sources/Support/Info.plist"
print -r -- 'XCTAssertEqual(Bundle.main.bundleIdentifier, "org.example.AudioStreamer.dev")' \
  >"$ALLOWED/iOS/opensteamer/Tests/AppArtifactContractTests.swift"
print -r -- 'let rendezvous = environment["OPENSTEAMER_RENDEZVOUS_URL"]' \
  >"$ALLOWED/macOS/Sources/CaptureServer/CaptureServerOptions.swift"
print -r -- 'let salt = "AudioStreamer.RemoteSession.HKDF-SHA256.v1"' \
  >"$ALLOWED/shared/Sources/RemoteSessionCore/RemoteSignalingCrypto.swift"
commit_all "$ALLOWED"
"$ALLOWED/scripts/check-product-branding.sh" "$ALLOWED" >/dev/null

AUTOMATIC_SIGNING="$TEMPORARY_ROOT/automatic-signing"
initialize_repository "$AUTOMATIC_SIGNING"
write_current_automatic_signing_fixture "$AUTOMATIC_SIGNING"
commit_all "$AUTOMATIC_SIGNING"
"$AUTOMATIC_SIGNING/scripts/check-product-branding.sh" "$AUTOMATIC_SIGNING" >/dev/null

MAC_RENDEZVOUS="$TEMPORARY_ROOT/mac-rendezvous"
initialize_repository "$MAC_RENDEZVOUS"
mkdir -p "$MAC_RENDEZVOUS/macOS/BelugaHost"
print -rl -- '<key>BelugaRendezvousURL</key>' "<string>${PRODUCTION_URL}</string>" \
  >"$MAC_RENDEZVOUS/macOS/BelugaHost/Info.plist"
commit_all "$MAC_RENDEZVOUS"
"$MAC_RENDEZVOUS/scripts/check-product-branding.sh" "$MAC_RENDEZVOUS" >/dev/null

print -rl -- '<key>CFBundleDisplayName</key>' "<string>${PRODUCTION_URL}</string>" \
  >"$MAC_RENDEZVOUS/macOS/BelugaHost/Info.plist"
require_failure "$MAC_RENDEZVOUS" 'macOS/BelugaHost/Info.plist:2:'
print -rl -- '<key>BelugaRendezvousURL</key>' "<string>http://${PRODUCTION_HOST}</string>" \
  >"$MAC_RENDEZVOUS/macOS/BelugaHost/Info.plist"
require_failure "$MAC_RENDEZVOUS" 'macOS/BelugaHost/Info.plist:2:'
print -rl -- '<key>BelugaRendezvousURL</key>' "<string>Beluga at ${PRODUCTION_URL}</string>" \
  >"$MAC_RENDEZVOUS/macOS/BelugaHost/Info.plist"
require_failure "$MAC_RENDEZVOUS" 'macOS/BelugaHost/Info.plist:2:'
print -rl -- '<key>BelugaRendezvousURL</key>' "<string>${PRODUCTION_URL}</string>" \
  >"$MAC_RENDEZVOUS/macOS/BelugaHost/Info.plist"
mkdir -p "$MAC_RENDEZVOUS/macOS/OtherApp"
cp "$MAC_RENDEZVOUS/macOS/BelugaHost/Info.plist" "$MAC_RENDEZVOUS/macOS/OtherApp/Info.plist"
commit_all "$MAC_RENDEZVOUS"
require_failure "$MAC_RENDEZVOUS" 'macOS/OtherApp/Info.plist:2:'

HOST_CONTRACTS="$TEMPORARY_ROOT/host-contracts"
initialize_repository "$HOST_CONTRACTS"
mkdir -p \
  "$HOST_CONTRACTS/macOS/LaunchAgents" \
  "$HOST_CONTRACTS/macOS/Tests/CaptureServerTests" \
  "$HOST_CONTRACTS/macOS/scripts"
print -r -- "8. \`${PRODUCTION_URL}\`" >"$HOST_CONTRACTS/HOST_MIGRATION.md"
print -r -- "<string>${PRODUCTION_URL}</string>" \
  >"$HOST_CONTRACTS/macOS/LaunchAgents/org.example.opensteamer.worldwide.plist"
print -r -- "\"${PRODUCTION_URL}\"," \
  >"$HOST_CONTRACTS/macOS/Tests/CaptureServerTests/MacHostDeploymentContractTests.swift"
print -r -- "readonly REVIEWED_RENDEZVOUS_URL=\"${PRODUCTION_URL}\"" \
  >"$HOST_CONTRACTS/macOS/scripts/verify-mac-host-launch-state.sh"
print -r -- 'forbidden_override="AUDIOSTREAMER_RENDEZVOUS_URL"' \
  >>"$HOST_CONTRACTS/macOS/scripts/verify-mac-host-launch-state.sh"
print -r -- "        \"${PRODUCTION_URL}\".to_owned()," \
  >"$HOST_CONTRACTS/macOS/scripts/opensteamer-host-migration-controller.rs"
print -r -- "        \"${PRODUCTION_URL}\".to_owned()," \
  >"$HOST_CONTRACTS/macOS/scripts/opensteamer-host-paired-v2-update-controller.rs"
print -r -- 'const HOST_IDENTITY: &str = "com.elamin.AudioStreamer.CaptureServer";' \
  >>"$HOST_CONTRACTS/macOS/scripts/opensteamer-host-paired-v2-update-controller.rs"
print -r -- 'const LEGACY_LABEL: &str = "com.elamin.audiostreamer.worldwide";' \
  >>"$HOST_CONTRACTS/macOS/scripts/opensteamer-host-paired-v2-update-controller.rs"
print -r -- "        \"${PRODUCTION_URL}\".to_owned()," \
  >"$HOST_CONTRACTS/macOS/scripts/opensteamer-host-paired-v6-update-controller.rs"
print -r -- 'const HOST_IDENTITY: &str = "com.elamin.AudioStreamer.CaptureServer";' \
  >>"$HOST_CONTRACTS/macOS/scripts/opensteamer-host-paired-v6-update-controller.rs"
print -r -- 'const LEGACY_LABEL: &str = "com.elamin.audiostreamer.worldwide";' \
  >>"$HOST_CONTRACTS/macOS/scripts/opensteamer-host-paired-v6-update-controller.rs"
print -r -- 'XCTAssertEqual(label, "com.elamin.audiostreamer.worldwide")' \
  >"$HOST_CONTRACTS/macOS/Tests/CaptureServerTests/MacHostMigrationContractTests.swift"
print -r -- 'XCTAssertEqual(service, "com.elamin.AudioStreamer.CaptureServer.WorldwidePairing.v1")' \
  >>"$HOST_CONTRACTS/macOS/Tests/CaptureServerTests/MacHostMigrationContractTests.swift"
commit_all "$HOST_CONTRACTS"
"$HOST_CONTRACTS/scripts/check-product-branding.sh" "$HOST_CONTRACTS" >/dev/null

CURRENT_COMPATIBILITY_CONTRACTS="$TEMPORARY_ROOT/current-compatibility-contracts"
initialize_repository "$CURRENT_COMPATIBILITY_CONTRACTS"
mkdir -p \
  "$CURRENT_COMPATIBILITY_CONTRACTS/iOS/opensteamer/scripts" \
  "$CURRENT_COMPATIBILITY_CONTRACTS/macOS/Sources/CaptureCore" \
  "$CURRENT_COMPATIBILITY_CONTRACTS/macOS/Tests/CaptureCoreTests" \
  "$CURRENT_COMPATIBILITY_CONTRACTS/macOS/Tests/CaptureServerTests"
print -r -- 'PROTECTED_LAUNCH_AGENT="com.elamin.audiostreamer.worldwide.plist"' \
  >"$CURRENT_COMPATIBILITY_CONTRACTS/iOS/opensteamer/scripts/archive-upload-side-by-side-testflight.sh"
print -r -- 'PROTECTED_LAUNCH_AGENT="com.elamin.audiostreamer.worldwide"' \
  >"$CURRENT_COMPATIBILITY_CONTRACTS/iOS/opensteamer/scripts/validate-testflight-paired-reconnect.sh"
print -r -- 'let host = "com.elamin.AudioStreamer.CaptureServer"' \
  >"$CURRENT_COMPATIBILITY_CONTRACTS/macOS/Sources/CaptureCore/SystemAudioCaptureSource.swift"
print -r -- 'XCTAssertEqual(host, "com.elamin.AudioStreamer.CaptureServer")' \
  >"$CURRENT_COMPATIBILITY_CONTRACTS/macOS/Tests/CaptureCoreTests/SystemAudioCaptureSourceTests.swift"
print -r -- 'let protected = "com.elamin.audiostreamer.worldwide"' \
  >"$CURRENT_COMPATIBILITY_CONTRACTS/macOS/Tests/CaptureServerTests/PhysicalValidationScriptTests.swift"
commit_all "$CURRENT_COMPATIBILITY_CONTRACTS"
"$CURRENT_COMPATIBILITY_CONTRACTS/scripts/check-product-branding.sh" \
  "$CURRENT_COMPATIBILITY_CONTRACTS" >/dev/null

FROZEN_LOCAL_MONO_CONTRACTS="$TEMPORARY_ROOT/frozen-local-mono-contracts"
initialize_repository "$FROZEN_LOCAL_MONO_CONTRACTS"
mkdir -p "$FROZEN_LOCAL_MONO_CONTRACTS/macOS/scripts"
print -r -- 'const LEGACY_APP: &str = "/Applications/AudioStreamer Host.app";
const LEGACY_PLIST: &str = "/Users/example/Library/LaunchAgents/com.elamin.audiostreamer.worldwide.plist";
const SHARED_LOCK: &str = "/Users/example/Library/Application Support/com.elamin.AudioStreamer.CaptureServer.runtime/worldwide-host.lock";
"wss://audiostreamer-rendezvous.elaminahmed03.workers.dev",' \
  >"$FROZEN_LOCAL_MONO_CONTRACTS/macOS/scripts/opensteamer-host-local-mono-trial-controller.rs"
print -r -- 'Identifier=com.elamin.AudioStreamer.CaptureServer' \
  >"$FROZEN_LOCAL_MONO_CONTRACTS/macOS/scripts/run-opensteamer-host-local-mono-trial.sh"
print -r -- 'LEGACY_APP="/Applications/AudioStreamer Host.app"
LEGACY_LABEL="com.elamin.audiostreamer.worldwide"
LEGACY_PLIST="com.elamin.audiostreamer.worldwide.plist"
grep "AudioStreamer Host|com.elamin.audiostreamer"' \
  >"$FROZEN_LOCAL_MONO_CONTRACTS/macOS/scripts/rescue-opensteamer-host-local-mono-trial-coreaudio-sip.sh"
print -r -- '- `/Applications/AudioStreamer Host.app`
- `/Users/example/Library/LaunchAgents/com.elamin.audiostreamer.worldwide.plist`' \
  >"$FROZEN_LOCAL_MONO_CONTRACTS/MAINTENANCE.md"
commit_all "$FROZEN_LOCAL_MONO_CONTRACTS"
"$FROZEN_LOCAL_MONO_CONTRACTS/scripts/check-product-branding.sh" \
  "$FROZEN_LOCAL_MONO_CONTRACTS" >/dev/null

SCOPED_COMPATIBILITY="$TEMPORARY_ROOT/scoped-compatibility"
initialize_repository "$SCOPED_COMPATIBILITY"
PHYSICAL_TEST_PATH="iOS/opensteamer/Tests/WebRTCAudioPlaybackSessionTests.swift"
DIAGNOSTIC_TEST_PATH="macOS/Tests/CaptureServerTests/DiagnosticDriverV2ResumeContractTests.swift"
DIAGNOSTIC_RUST_PATHS=(
  macOS/scripts/opensteamer-diagnostic-driver-v1-update-controller.rs
  macOS/scripts/opensteamer-diagnostic-driver-v2-resume-stager.rs
  macOS/scripts/opensteamer-diagnostic-driver-v2-update-controller.rs
)
mkdir -p "$SCOPED_COMPATIBILITY/${PHYSICAL_TEST_PATH:h}" \
  "$SCOPED_COMPATIBILITY/${DIAGNOSTIC_TEST_PATH:h}" "$SCOPED_COMPATIBILITY/macOS/scripts"
print -r -- '        guard Bundle.main.bundleIdentifier == "org.example.AudioStreamer.dev" else {
        try require(Bundle.main.bundleIdentifier == "org.example.AudioStreamer.dev", "The distinct spare development app is required.")' \
  >"$SCOPED_COMPATIBILITY/$PHYSICAL_TEST_PATH"
print -r -- '                "/Applications/AudioStreamer Host.app/Contents/MacOS/CaptureServer",
                "com.elamin.audiostreamer.worldwide",
            "com.elamin.AudioStreamer.CaptureServer.WorldwidePairing", ".v1",
            "AudioStreamer Host.app",' >"$SCOPED_COMPATIBILITY/$DIAGNOSTIC_TEST_PATH"
for relative_path in "${DIAGNOSTIC_RUST_PATHS[@]}"; do
  print -r -- 'const HOST_IDENTIFIER: &str = "com.elamin.AudioStreamer.CaptureServer";
const HOST_RENDEZVOUS_URL: &str = "wss://audiostreamer-rendezvous.elaminahmed03.workers.dev";
const HOST_LOCK: &str = "/Users/ahmed/Library/Application Support/com.elamin.AudioStreamer.CaptureServer.runtime/worldwide-host.lock";
const LEGACY_EXECUTABLE: &str = "/Applications/AudioStreamer Host.app/Contents/MacOS/CaptureServer";
    "/Users/ahmed/Library/LaunchAgents/com.elamin.audiostreamer.worldwide.plist";
const LEGACY_LABEL: &str = "com.elamin.audiostreamer.worldwide";' \
    >"$SCOPED_COMPATIBILITY/$relative_path"
done
print -r -- '        "com.elamin.AudioStreamer.CaptureServer.WorldwidePairing",
        "streamer-failed-20260720-102747-44276/AudioStreamer Host.app",' \
  >>"$SCOPED_COMPATIBILITY/${DIAGNOSTIC_RUST_PATHS[2]}"
commit_all "$SCOPED_COMPATIBILITY"
"$SCOPED_COMPATIBILITY/scripts/check-product-branding.sh" "$SCOPED_COMPATIBILITY" >/dev/null

require_scoped_content_rejected() {
  local name=$1 relative_path=$2 content=$3 token=$4
  local repository="$TEMPORARY_ROOT/$name"
  initialize_repository "$repository"
  mkdir -p "$repository/${relative_path:h}"
  print -r -- "$content" >"$repository/$relative_path"
  commit_all "$repository"
  require_failure "$repository" "$relative_path:1:$token"
}

MAC_CLIENT_COMPATIBILITY="$TEMPORARY_ROOT/mac-client-compatibility"
initialize_repository "$MAC_CLIENT_COMPATIBILITY"
MAC_CLIENT_COMPATIBILITY_PATHS=(
  iOS/opensteamer/Sources/Security/ViewerPairedMacCatalogStore.swift
  macOS/Sources/BelugaUpdateCore/BelugaUpdateOperation.swift
  macOS/Sources/BelugaUpdateCore/BelugaUpdateInstalledArtifact.swift
  macOS/Sources/CaptureServer/BelugaHostPresentation.swift
  macOS/Tests/CaptureServerTests/BelugaUpdatePeerIdentityTests.swift
  macOS/Tests/CaptureServerTests/BelugaUpdateInstalledArtifactTests.swift
  macOS/Tests/CaptureServerTests/BelugaMenuBarTests.swift
  macOS/scripts/build-beluga-mac-client-contract.rb
  macOS/scripts/verify-beluga-mac-client-tests.rb
  macOS/BelugaHost/Release.json
  android/protocol/src/main/java/com/elamin/beluga/protocol/PairingInvitation.java
  ANDROID_CLIENT_PLAN.md
  shared/Sources/WebRTCTransport/WebRTCAudioShareSender.swift
)
for relative_path in "${MAC_CLIENT_COMPATIBILITY_PATHS[@]}"; do
  mkdir -p "$MAC_CLIENT_COMPATIBILITY/${relative_path:h}"
done
print -r -- 'service: "org.example.AudioStreamer", account: "worldwide-paired-macs-catalog"' \
  >"$MAC_CLIENT_COMPATIBILITY/${MAC_CLIENT_COMPATIBILITY_PATHS[1]}"
print -r -- 'package static let expectedBundleIdentifier = "com.elamin.AudioStreamer.CaptureServer"' \
  >"$MAC_CLIENT_COMPATIBILITY/${MAC_CLIENT_COMPATIBILITY_PATHS[2]}"
print -r -- 'static let signingRequirement = "anchor apple generic and identifier \"com.elamin.AudioStreamer.CaptureServer\" and certificate leaf[subject.OU] = \"MSMG8CJLB3\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"' \
  >"$MAC_CLIENT_COMPATIBILITY/${MAC_CLIENT_COMPATIBILITY_PATHS[3]}"
print -r -- '&& bundleIdentifier == "com.elamin.AudioStreamer.CaptureServer"' \
  >"$MAC_CLIENT_COMPATIBILITY/${MAC_CLIENT_COMPATIBILITY_PATHS[4]}"
print -r -- 'XCTAssertTrue(source.contains("identifier \"\(role == .main ? "com.elamin.AudioStreamer.CaptureServer" : "com.elamin.beluga.Updater")\""))' \
  >"$MAC_CLIENT_COMPATIBILITY/${MAC_CLIENT_COMPATIBILITY_PATHS[5]}"
print -r -- 'XCTAssertTrue(Reader.signingRequirement.contains("identifier \"com.elamin.AudioStreamer.CaptureServer\""))' \
  >"$MAC_CLIENT_COMPATIBILITY/${MAC_CLIENT_COMPATIBILITY_PATHS[6]}"
print -rl -- "let endpoint = \"${PRODUCTION_URL}\"" \
  'bundleIdentifier: "com.elamin.AudioStreamer.CaptureServer",' \
  'arguments: arguments, bundleIdentifier: "com.elamin.AudioStreamer.CaptureServer",' \
  >"$MAC_CLIENT_COMPATIBILITY/${MAC_CLIENT_COMPATIBILITY_PATHS[7]}"
print -r -- "BUNDLE_ID = 'com.elamin.AudioStreamer.CaptureServer'" \
  >"$MAC_CLIENT_COMPATIBILITY/${MAC_CLIENT_COMPATIBILITY_PATHS[8]}"
print -r -- "value = '${PRODUCTION_URL}'" \
  >"$MAC_CLIENT_COMPATIBILITY/${MAC_CLIENT_COMPATIBILITY_PATHS[9]}"
print -r -- '"bundleIdentifier": "com.elamin.AudioStreamer.CaptureServer",' \
  >"$MAC_CLIENT_COMPATIBILITY/${MAC_CLIENT_COMPATIBILITY_PATHS[10]}"
print -r -- '"AudioStreamer.RemoteInvitation.Checksum.v1\0".getBytes(StandardCharsets.US_ASCII);' \
  >"$MAC_CLIENT_COMPATIBILITY/${MAC_CLIENT_COMPATIBILITY_PATHS[11]}"
print -r -- '`audiostreamer.control`/`.v2` envelopes, stereo Opus negotiation and H.264 screen' \
  >"$MAC_CLIENT_COMPATIBILITY/${MAC_CLIENT_COMPATIBILITY_PATHS[12]}"
print -r -- '|| $0.hasPrefix("a=audiostreamer") || $0.hasPrefix("a=opensteamer")' \
  >"$MAC_CLIENT_COMPATIBILITY/${MAC_CLIENT_COMPATIBILITY_PATHS[13]}"
commit_all "$MAC_CLIENT_COMPATIBILITY"
"$MAC_CLIENT_COMPATIBILITY/scripts/check-product-branding.sh" "$MAC_CLIENT_COMPATIBILITY" >/dev/null

# Every newly permitted path still rejects former-brand presentation. Separate
# fixtures avoid a first failure hiding a later path's accidental broad allowance.
for relative_path in "${MAC_CLIENT_COMPATIBILITY_PATHS[@]}"; do
  require_scoped_content_rejected "mac-client-display-${relative_path:t}" "$relative_path" \
    'Text("AudioStreamer")' AudioStreamer
done
require_scoped_content_rejected mac-client-identity-wrong-path \
  macOS/Sources/BelugaUpdateCore/Unreviewed.swift \
  'package static let expectedBundleIdentifier = "com.elamin.AudioStreamer.CaptureServer"' \
  AudioStreamer.CaptureServer
require_scoped_content_rejected mac-client-identity-wrong-token "${MAC_CLIENT_COMPATIBILITY_PATHS[2]}" \
  'package static let expectedBundleIdentifier = "com.elamin.AudioStreamer.CaptureServer.preview"' \
  AudioStreamer.CaptureServer.preview
require_scoped_content_rejected mac-client-identity-trailing-brand "${MAC_CLIENT_COMPATIBILITY_PATHS[2]}" \
  'package static let expectedBundleIdentifier = "com.elamin.AudioStreamer.CaptureServer" // AudioStreamer' \
  AudioStreamer.CaptureServer
require_scoped_content_rejected mac-client-keychain-wrong-account "${MAC_CLIENT_COMPATIBILITY_PATHS[1]}" \
  'service: "org.example.AudioStreamer", account: "unreviewed-catalog"' AudioStreamer
require_scoped_content_rejected mac-client-release-display-field "${MAC_CLIENT_COMPATIBILITY_PATHS[10]}" \
  '"displayName": "com.elamin.AudioStreamer.CaptureServer",' AudioStreamer.CaptureServer
require_scoped_content_rejected mac-client-rendezvous-wrong-token "${MAC_CLIENT_COMPATIBILITY_PATHS[9]}" \
  "value = 'wss://audiostreamer-rendezvous.elaminahmed04.workers.dev'" \
  audiostreamer-rendezvous.elaminahmed04.workers.dev
require_scoped_content_rejected android-checksum-wrong-domain "${MAC_CLIENT_COMPATIBILITY_PATHS[11]}" \
  '"AudioStreamer.RemoteInvitation.Checksum.v2\0".getBytes(StandardCharsets.US_ASCII);' \
  AudioStreamer.RemoteInvitation.Checksum.v2
require_scoped_content_rejected audio-share-negative-prefix-wrong-context "${MAC_CLIENT_COMPATIBILITY_PATHS[13]}" \
  'Text("a=audiostreamer")' audiostreamer
require_scoped_content_rejected android-plan-wire-wrong-context "${MAC_CLIENT_COMPATIBILITY_PATHS[12]}" \
  '# audiostreamer.control' audiostreamer.control

# Exercise every imported Android compatibility line, rather than a reduced sample.
# The policy has fixed literal matches; these current-source inputs cannot grant permission.
ANDROID_CLIENT_COMPATIBILITY="$TEMPORARY_ROOT/android-client-compatibility"
initialize_repository "$ANDROID_CLIENT_COMPATIBILITY"
ANDROID_CLIENT_COMPATIBILITY_PATHS=(
  android/protocol/src/main/java/com/elamin/beluga/protocol/PairingInvitation.java
  android/protocol/src/main/java/com/elamin/beluga/protocol/PairingCanonicalCodec.java
  android/protocol/src/main/java/com/elamin/beluga/protocol/PairingBootstrapEnvelopeCodec.java
  android/protocol/src/main/java/com/elamin/beluga/protocol/ViewerPairingAuthenticator.java
  android/protocol/src/main/java/com/elamin/beluga/protocol/ReconnectMessages.java
  android/transport/src/main/java/com/elamin/beluga/protocol/ProcessPairingDnsResolver.java
  android/protocol/src/test/java/com/elamin/beluga/protocol/PairingCanonicalCodecTest.java
  android/protocol/src/test/java/com/elamin/beluga/protocol/BouncyCastlePairingCryptoTest.java
  android/transport/src/main/java/com/elamin/beluga/protocol/NettyPairingWssTransport.java
  android/transport/src/test/java/com/elamin/beluga/protocol/NettyPairingWssTransportTest.java
  android/transport/src/test/java/com/elamin/beluga/protocol/ViewerPairingSessionTest.java
  android/app/src/test/java/com/elamin/beluga/protocol/PairingBootstrapEnvelopeCodecTest.java
  android/app/src/test/java/com/elamin/beluga/protocol/PairingBootstrapBrokerEventParserTest.java
  android/app/src/test/java/com/elamin/beluga/protocol/ViewerStorageCatalogTest.java
)
# These exact files are absent in the prior Android checkpoint. When present,
# their actual ABI lines must pass the same fixed policy, not a fixture exemption.
for relative_path in \
  android/protocol/src/main/java/com/elamin/beluga/protocol/ViewerAvailabilityLocator.java \
  android/protocol/src/main/java/com/elamin/beluga/protocol/ViewerAvailabilityEnvelopeCodec.java \
  android/app/src/test/java/com/elamin/beluga/protocol/ViewerAvailabilityEnvelopeCodecTest.java \
  android/protocol/src/main/java/com/elamin/beluga/protocol/ViewerMediaSignalingCodec.java \
  android/app/src/test/java/com/elamin/beluga/protocol/ViewerMediaSignalingCodecTest.java \
  android/app/src/test/java/com/elamin/beluga/protocol/ViewerConnectionSessionTest.java; do
  if [[ -f "$ROOT_DIR/$relative_path" ]] && \
      rg -q 'AudioStreamer|audiostreamer' "$ROOT_DIR/$relative_path"; then
    ANDROID_CLIENT_COMPATIBILITY_PATHS+=("$relative_path")
  fi
done
for relative_path in "${ANDROID_CLIENT_COMPATIBILITY_PATHS[@]}"; do
  mkdir -p "$ANDROID_CLIENT_COMPATIBILITY/${relative_path:h}"
  rg 'AudioStreamer|audiostreamer' "$ROOT_DIR/$relative_path" \
    >"$ANDROID_CLIENT_COMPATIBILITY/$relative_path"
done
commit_all "$ANDROID_CLIENT_COMPATIBILITY"
"$ANDROID_CLIENT_COMPATIBILITY/scripts/check-product-branding.sh" \
  "$ANDROID_CLIENT_COMPATIBILITY" >/dev/null

for relative_path in "${ANDROID_CLIENT_COMPATIBILITY_PATHS[@]}"; do
  # Every admitted source/test path still refuses presentation, including a real ABI token.
  require_scoped_content_rejected "android-client-display-${relative_path:t}" "$relative_path" \
    'String displayName = "AudioStreamer";' AudioStreamer
  require_scoped_content_rejected "android-client-domain-display-${relative_path:t}" "$relative_path" \
    'String displayName = "AudioStreamer.Pairing.Root.v1";' AudioStreamer.Pairing.Root.v1

  # Moving an otherwise exact imported definition/assertion to a new file must not pass.
  content=$(rg -m 1 'AudioStreamer|audiostreamer' "$ROOT_DIR/$relative_path" \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  wrong_path="android/unreviewed/${relative_path:t}"
  repository="$TEMPORARY_ROOT/android-client-wrong-path-${relative_path:t}"
  initialize_repository "$repository"
  mkdir -p "$repository/${wrong_path:h}"
  print -r -- "$content" >"$repository/$wrong_path"
  commit_all "$repository"
  require_failure "$repository" "$wrong_path:1:"
done

require_scoped_content_rejected android-client-admission-domain-version "${ANDROID_CLIENT_COMPATIBILITY_PATHS[1]}" \
  'digest.update("AudioStreamer.WorldwideInvitation.Admitted.v2\0".getBytes(StandardCharsets.UTF_8));' \
  AudioStreamer.WorldwideInvitation.Admitted.v2
require_scoped_content_rejected android-client-canonical-frame-version "${ANDROID_CLIENT_COMPATIBILITY_PATHS[2]}" \
  'byte[] domain = ("AudioStreamer.Pairing." + fixedSuffix + ".v2").getBytes(StandardCharsets.US_ASCII);' \
  AudioStreamer.Pairing.
require_scoped_content_rejected android-client-canonical-frame-variable "${ANDROID_CLIENT_COMPATIBILITY_PATHS[2]}" \
  'byte[] domain = ("AudioStreamer.Pairing." + displayName + ".v1").getBytes(StandardCharsets.US_ASCII);' \
  AudioStreamer.Pairing.
require_scoped_content_rejected android-client-envelope-domain-version "${ANDROID_CLIENT_COMPATIBILITY_PATHS[3]}" \
  'private static final byte[] AAD_DOMAIN = ascii("AudioStreamer.Signaling.Envelope.AAD.v2\0");' \
  AudioStreamer.Signaling.Envelope.AAD.v2
require_scoped_content_rejected android-client-durable-label-version "${ANDROID_CLIENT_COMPATIBILITY_PATHS[4]}" \
  'channel = derive(root, salt, "AudioStreamer.DurableRendezvous.session.channel.v2");' \
  AudioStreamer.DurableRendezvous.session.channel.v2
require_scoped_content_rejected android-client-role-label-swap "${ANDROID_CLIENT_COMPATIBILITY_PATHS[4]}" \
  'key = derive(root, transcript, "AudioStreamer.Pairing.Confirmation.viewer.v2");' \
  AudioStreamer.Pairing.Confirmation.viewer.v2
require_scoped_content_rejected android-client-commit-role-variable "${ANDROID_CLIENT_COMPATIBILITY_PATHS[4]}" \
  'return "AudioStreamer.Pairing.Commit." + displayName + "." + name + ".v1";' \
  AudioStreamer.Pairing.Commit.
require_scoped_content_rejected android-client-reconnect-label-version "${ANDROID_CLIENT_COMPATIBILITY_PATHS[5]}" \
  'return domain("AudioStreamer.Reconnect.Request.Signature.v2", unsignedRequest(request));' \
  AudioStreamer.Reconnect.Request.Signature.v2
require_scoped_content_rejected android-client-dns-host-mutation "${ANDROID_CLIENT_COMPATIBILITY_PATHS[6]}" \
  'private static final String HOST = "audiostreamer-rendezvous.elaminahmed04.workers.dev";' \
  audiostreamer-rendezvous.elaminahmed04.workers.dev
require_scoped_content_rejected android-client-test-frame-version "${ANDROID_CLIENT_COMPATIBILITY_PATHS[7]}" \
  'byte[] label = ("AudioStreamer.Pairing." + suffix + ".v2").getBytes(StandardCharsets.US_ASCII);' \
  AudioStreamer.Pairing.
require_scoped_content_rejected android-client-test-commit-variable "${ANDROID_CLIENT_COMPATIBILITY_PATHS[8]}" \
  'byte[] key = BouncyCastlePairingCrypto.hkdfSha256(root, transcript, utf8("AudioStreamer.Pairing.Commit." + displayName + "." + phase + ".v1"), 32);' \
  AudioStreamer.Pairing.Commit.
require_scoped_content_rejected android-client-origin-wrong-scheme "${ANDROID_CLIENT_COMPATIBILITY_PATHS[9]}" \
  'public static final String PRODUCTION_ORIGIN = "ws://audiostreamer-rendezvous.elaminahmed03.workers.dev";' \
  audiostreamer-rendezvous.elaminahmed03.workers.dev
require_scoped_content_rejected android-client-subprotocol-version "${ANDROID_CLIENT_COMPATIBILITY_PATHS[9]}" \
  'public static final String SUBPROTOCOL = "audiostreamer.pairing.v2";' audiostreamer.pairing.v2
require_scoped_content_rejected android-client-header-role-swap "${ANDROID_CLIENT_COMPATIBILITY_PATHS[9]}" \
  '.set("X-AudioStreamer-Role", "host")' AudioStreamer-Role
require_scoped_content_rejected android-client-header-trailing-brand "${ANDROID_CLIENT_COMPATIBILITY_PATHS[9]}" \
  '.set("X-AudioStreamer-Channel", join.channelID()) // AudioStreamer' AudioStreamer-Channel
require_scoped_content_rejected android-client-test-forbidden-header-inversion "${ANDROID_CLIENT_COMPATIBILITY_PATHS[10]}" \
  'assertTrue(headers.contains("X-AudioStreamer-Viewer-Admission"));' AudioStreamer-Viewer-Admission

require_scoped_content_rejected android-client-availability-subprotocol-version "${ANDROID_CLIENT_COMPATIBILITY_PATHS[9]}" \
  'public static final String AVAILABILITY_SUBPROTOCOL = "audiostreamer.availability.v2";' audiostreamer.availability.v2
require_scoped_content_rejected android-client-availability-subprotocol-wrong-path \
  android/transport/src/main/java/com/elamin/beluga/protocol/UnreviewedAvailabilityTransport.java \
  'public static final String AVAILABILITY_SUBPROTOCOL = "audiostreamer.availability.v1";' audiostreamer.availability.v1
require_scoped_content_rejected android-client-availability-mode-swap "${ANDROID_CLIENT_COMPATIBILITY_PATHS[9]}" \
  '.set("X-AudioStreamer-Mode", "pairing");' AudioStreamer-Mode
require_scoped_content_rejected android-client-availability-host-registration "${ANDROID_CLIENT_COMPATIBILITY_PATHS[9]}" \
  '.set("X-AudioStreamer-Viewer-Admission", join.admissionProofForUpgradeHeader());' AudioStreamer-Viewer-Admission
require_scoped_content_rejected android-client-availability-test-host-header-inversion "${ANDROID_CLIENT_COMPATIBILITY_PATHS[10]}" \
  'assertTrue(headers.contains("X-AudioStreamer-Host-Admission"));' AudioStreamer-Host-Admission
require_scoped_content_rejected android-client-availability-test-mode-swap "${ANDROID_CLIENT_COMPATIBILITY_PATHS[10]}" \
  'assertEquals("pairing", headers.get("X-AudioStreamer-Mode"));' AudioStreamer-Mode
require_scoped_content_rejected android-client-availability-subprotocol-display "${ANDROID_CLIENT_COMPATIBILITY_PATHS[9]}" \
  'String displayName = "audiostreamer.availability.v1";' audiostreamer.availability.v1
require_scoped_content_rejected android-client-availability-route-version \
  android/protocol/src/main/java/com/elamin/beluga/protocol/ViewerAvailabilityLocator.java \
  'route = derive(root, routeSalt, "AudioStreamer.Availability.Route.v2");' AudioStreamer.Availability.Route.v2
require_scoped_content_rejected android-client-availability-admission-role-swap \
  android/protocol/src/main/java/com/elamin/beluga/protocol/ViewerAvailabilityLocator.java \
  'admission = derive(route, transcript, "AudioStreamer.Availability.Admission.Host.v2");' AudioStreamer.Availability.Admission.Host.v2
require_scoped_content_rejected android-client-availability-seed-label-change \
  android/protocol/src/main/java/com/elamin/beluga/protocol/ViewerAvailabilityLocator.java \
  'seed = derive(root, seedSalt, "AudioStreamer.Availability.ExchangeSeed.v2");' AudioStreamer.Availability.ExchangeSeed.v2
require_scoped_content_rejected android-client-availability-label-display \
  android/protocol/src/main/java/com/elamin/beluga/protocol/ViewerAvailabilityLocator.java \
  'String displayName = "AudioStreamer.Availability.Route.v1";' AudioStreamer.Availability.Route.v1
require_scoped_content_rejected android-client-availability-domain-wrong-path \
  android/protocol/src/main/java/com/elamin/beluga/protocol/UnreviewedAvailabilityLocator.java \
  'route = derive(root, routeSalt, "AudioStreamer.Availability.Route.v1");' AudioStreamer.Availability.Route.v1
require_scoped_content_rejected android-client-availability-exchange-salt-input-change \
  android/protocol/src/main/java/com/elamin/beluga/protocol/ViewerAvailabilityEnvelopeCodec.java \
  'salt = ReconnectMessages.domain("AudioStreamer.Availability.Exchange.Salt.v1", raw);' AudioStreamer.Availability.Exchange.Salt.v1
require_scoped_content_rejected android-client-availability-send-direction-swap \
  android/protocol/src/main/java/com/elamin/beluga/protocol/ViewerAvailabilityEnvelopeCodec.java \
  'send = ViewerAvailabilityLocator.derive(seed, salt, "AudioStreamer.Availability.Exchange.Signaling.HostToViewer.v1");' AudioStreamer.Availability.Exchange.Signaling.HostToViewer.v1
require_scoped_content_rejected android-client-availability-aad-version \
  android/protocol/src/main/java/com/elamin/beluga/protocol/ViewerAvailabilityEnvelopeCodec.java \
  'return ReconnectMessages.domain("AudioStreamer.Availability.Envelope.AAD.v2", new byte[] {1}, ascii(channel),' AudioStreamer.Availability.Envelope.AAD.v2
require_scoped_content_rejected android-client-availability-envelope-label-display \
  android/protocol/src/main/java/com/elamin/beluga/protocol/ViewerAvailabilityEnvelopeCodec.java \
  'String displayName = "AudioStreamer.Availability.Envelope.AAD.v1";' AudioStreamer.Availability.Envelope.AAD.v1
require_scoped_content_rejected android-client-availability-test-aad-version \
  android/app/src/test/java/com/elamin/beluga/protocol/ViewerAvailabilityEnvelopeCodecTest.java \
  'return ReconnectMessages.domain("AudioStreamer.Availability.Envelope.AAD.v2", new byte[] {1}, value("derived.channel"),' AudioStreamer.Availability.Envelope.AAD.v2
require_scoped_content_rejected android-client-availability-test-aad-input-change \
  android/app/src/test/java/com/elamin/beluga/protocol/ViewerAvailabilityEnvelopeCodecTest.java \
  'return ReconnectMessages.domain("AudioStreamer.Availability.Envelope.AAD.v1", new byte[] {2}, value("derived.channel"),' AudioStreamer.Availability.Envelope.AAD.v1
require_scoped_content_rejected android-client-availability-test-aad-wrong-path \
  android/app/src/test/java/com/elamin/beluga/protocol/UnreviewedAvailabilityEnvelopeTest.java \
  'return ReconnectMessages.domain("AudioStreamer.Availability.Envelope.AAD.v1", new byte[] {1}, value("derived.channel"),' AudioStreamer.Availability.Envelope.AAD.v1
require_scoped_content_rejected android-client-availability-test-label-display \
  android/app/src/test/java/com/elamin/beluga/protocol/ViewerAvailabilityEnvelopeCodecTest.java \
  'String displayName = "AudioStreamer.Availability.Envelope.AAD.v1";' AudioStreamer.Availability.Envelope.AAD.v1
require_scoped_content_rejected android-client-media-aad-version \
  android/protocol/src/main/java/com/elamin/beluga/protocol/ViewerMediaSignalingCodec.java \
  'byte[] prefix = ascii("AudioStreamer.Signaling.Envelope.AAD.v2\0");' AudioStreamer.Signaling.Envelope.AAD.v2
require_scoped_content_rejected android-client-media-aad-display \
  android/protocol/src/main/java/com/elamin/beluga/protocol/ViewerMediaSignalingCodec.java \
  'String displayName = "AudioStreamer.Signaling.Envelope.AAD.v1";' AudioStreamer.Signaling.Envelope.AAD.v1
require_scoped_content_rejected android-client-media-aad-wrong-path \
  android/protocol/src/main/java/com/elamin/beluga/protocol/UnreviewedMediaCodec.java \
  'byte[] prefix = ascii("AudioStreamer.Signaling.Envelope.AAD.v1\0");' AudioStreamer.Signaling.Envelope.AAD.v1
require_scoped_content_rejected android-client-connection-test-aad-direction \
  android/app/src/test/java/com/elamin/beluga/protocol/ViewerConnectionSessionTest.java \
  'byte[] aad = ReconnectMessages.domain("AudioStreamer.Availability.Envelope.AAD.v1", new byte[] {2},' AudioStreamer.Availability.Envelope.AAD.v1

require_scoped_content_rejected physical-identity-wrong-path \
  iOS/opensteamer/Tests/UnreviewedTests.swift \
  'guard Bundle.main.bundleIdentifier == "org.example.AudioStreamer.dev" else {' AudioStreamer.dev
require_scoped_content_rejected physical-identity-wrong-token "$PHYSICAL_TEST_PATH" \
  'guard Bundle.main.bundleIdentifier == "org.example.AudioStreamer.dev.preview" else {' AudioStreamer.dev.preview
require_scoped_content_rejected physical-identity-wrong-context "$PHYSICAL_TEST_PATH" \
  'Text("org.example.AudioStreamer.dev")' AudioStreamer.dev
require_scoped_content_rejected physical-identity-trailing-brand "$PHYSICAL_TEST_PATH" \
  'guard Bundle.main.bundleIdentifier == "org.example.AudioStreamer.dev" else { // AudioStreamer' AudioStreamer.dev
require_scoped_content_rejected physical-brand-display "$PHYSICAL_TEST_PATH" \
  'Text("AudioStreamer")' AudioStreamer
for relative_path in "${DIAGNOSTIC_RUST_PATHS[@]}"; do
  require_scoped_content_rejected "diagnostic-wrong-context-${relative_path:t}" "$relative_path" \
    'println!("com.elamin.AudioStreamer.CaptureServer");' AudioStreamer.CaptureServer
  require_scoped_content_rejected "diagnostic-brand-display-${relative_path:t}" "$relative_path" \
    'println!("AudioStreamer");' AudioStreamer
done
require_scoped_content_rejected diagnostic-unreviewed-version \
  macOS/scripts/opensteamer-diagnostic-driver-v3-update-controller.rs \
  'const HOST_IDENTIFIER: &str = "com.elamin.AudioStreamer.CaptureServer";' AudioStreamer.CaptureServer
require_scoped_content_rejected diagnostic-identity-wrong-token "${DIAGNOSTIC_RUST_PATHS[1]}" \
  'const HOST_IDENTIFIER: &str = "com.elamin.AudioStreamer.CaptureServer.v2";' AudioStreamer.CaptureServer.v2
require_scoped_content_rejected diagnostic-host-wrong-token "${DIAGNOSTIC_RUST_PATHS[1]}" \
  'const HOST_RENDEZVOUS_URL: &str = "wss://audiostreamer-rendezvous.elaminahmed04.workers.dev";' \
  audiostreamer-rendezvous.elaminahmed04.workers.dev
require_scoped_content_rejected diagnostic-lock-wrong-path "${DIAGNOSTIC_RUST_PATHS[1]}" \
  'const HOST_LOCK: &str = "/Users/other/Library/Application Support/com.elamin.AudioStreamer.CaptureServer.runtime/worldwide-host.lock";' \
  AudioStreamer.CaptureServer.runtime
require_scoped_content_rejected diagnostic-resume-only-fragment "${DIAGNOSTIC_RUST_PATHS[1]}" \
  '"com.elamin.AudioStreamer.CaptureServer.WorldwidePairing",' AudioStreamer.CaptureServer.WorldwidePairing
require_scoped_content_rejected diagnostic-test-wrong-context "$DIAGNOSTIC_TEST_PATH" \
  'Text("AudioStreamer Host.app")' AudioStreamer
require_scoped_content_rejected diagnostic-test-wrong-token "$DIAGNOSTIC_TEST_PATH" \
  '"com.elamin.AudioStreamer.CaptureServer.WorldwidePairing.v2", ".v1",' AudioStreamer.CaptureServer.WorldwidePairing.v2

PAIRED_V7_WRONG_PATH="$TEMPORARY_ROOT/paired-v7-wrong-path"
initialize_repository "$PAIRED_V7_WRONG_PATH"
mkdir -p "$PAIRED_V7_WRONG_PATH/macOS/scripts"
print -r -- "        \"${PRODUCTION_URL}\".to_owned()," \
  >"$PAIRED_V7_WRONG_PATH/macOS/scripts/opensteamer-host-paired-v7-update-controller.rs"
commit_all "$PAIRED_V7_WRONG_PATH"
require_failure "$PAIRED_V7_WRONG_PATH" \
  "macOS/scripts/opensteamer-host-paired-v7-update-controller.rs:1:${PRODUCTION_HOST}"

LOCAL_MONO_WRONG_HOST="$TEMPORARY_ROOT/local-mono-wrong-host"
initialize_repository "$LOCAL_MONO_WRONG_HOST"
mkdir -p "$LOCAL_MONO_WRONG_HOST/macOS/scripts"
print -r -- '"wss://audiostreamer-rendezvous.elaminahmed04.workers.dev",' \
  >"$LOCAL_MONO_WRONG_HOST/macOS/scripts/opensteamer-host-local-mono-trial-controller.rs"
commit_all "$LOCAL_MONO_WRONG_HOST"
require_failure "$LOCAL_MONO_WRONG_HOST" \
  'macOS/scripts/opensteamer-host-local-mono-trial-controller.rs:1:audiostreamer-rendezvous.elaminahmed04.workers.dev'

STALE_ACTIVE_RENDEZVOUS_ENV="$TEMPORARY_ROOT/stale-active-rendezvous-env"
initialize_repository "$STALE_ACTIVE_RENDEZVOUS_ENV"
mkdir -p "$STALE_ACTIVE_RENDEZVOUS_ENV/macOS/Sources/CaptureServer"
print -r -- 'let endpoint = environment["AUDIOSTREAMER_RENDEZVOUS_URL"]' \
  >"$STALE_ACTIVE_RENDEZVOUS_ENV/macOS/Sources/CaptureServer/CaptureServerOptions.swift"
commit_all "$STALE_ACTIVE_RENDEZVOUS_ENV"
require_failure "$STALE_ACTIVE_RENDEZVOUS_ENV" \
  'macOS/Sources/CaptureServer/CaptureServerOptions.swift:1:AUDIOSTREAMER_RENDEZVOUS_URL'

STALE_ACTIVE_RENDEZVOUS_PLIST="$TEMPORARY_ROOT/stale-active-rendezvous-plist"
initialize_repository "$STALE_ACTIVE_RENDEZVOUS_PLIST"
mkdir -p "$STALE_ACTIVE_RENDEZVOUS_PLIST/iOS/opensteamer/Sources/Support"
print -r -- '<key>AudioStreamerRendezvousURL</key>' \
  >"$STALE_ACTIVE_RENDEZVOUS_PLIST/iOS/opensteamer/Sources/Support/Info.plist"
commit_all "$STALE_ACTIVE_RENDEZVOUS_PLIST"
require_failure "$STALE_ACTIVE_RENDEZVOUS_PLIST" \
  'iOS/opensteamer/Sources/Support/Info.plist:1:AudioStreamerRendezvousURL'

STALE_SMOKE_RENDEZVOUS_ENV="$TEMPORARY_ROOT/stale-smoke-rendezvous-env"
initialize_repository "$STALE_SMOKE_RENDEZVOUS_ENV"
mkdir -p "$STALE_SMOKE_RENDEZVOUS_ENV/services/RendezvousWorker/scripts"
print -r -- 'const endpoint = process.env.AUDIOSTREAMER_RENDEZVOUS_URL;' \
  >"$STALE_SMOKE_RENDEZVOUS_ENV/services/RendezvousWorker/scripts/smoke-public.mjs"
commit_all "$STALE_SMOKE_RENDEZVOUS_ENV"
require_failure "$STALE_SMOKE_RENDEZVOUS_ENV" \
  'services/RendezvousWorker/scripts/smoke-public.mjs:1:AUDIOSTREAMER_RENDEZVOUS_URL'

HOST_CONTRACT_WRONG_CONTEXT="$TEMPORARY_ROOT/host-contract-wrong-context"
initialize_repository "$HOST_CONTRACT_WRONG_CONTEXT"
print -r -- "9. \`${PRODUCTION_URL}\`" \
  >"$HOST_CONTRACT_WRONG_CONTEXT/HOST_MIGRATION.md"
commit_all "$HOST_CONTRACT_WRONG_CONTEXT"
require_failure "$HOST_CONTRACT_WRONG_CONTEXT" \
  "HOST_MIGRATION.md:1:${PRODUCTION_HOST}"

RENDEZVOUS_WRONG_PATH="$TEMPORARY_ROOT/rendezvous-wrong-path"
initialize_repository "$RENDEZVOUS_WRONG_PATH"
write_current_automatic_signing_fixture "$RENDEZVOUS_WRONG_PATH"
print -r -- "$PRODUCTION_URL" >"$RENDEZVOUS_WRONG_PATH/README.md"
commit_all "$RENDEZVOUS_WRONG_PATH"
require_failure "$RENDEZVOUS_WRONG_PATH" \
  "README.md:1:${PRODUCTION_HOST}"

MUTATED_PRODUCTION_HOST='audiostreamer-rendezvous.elaminahmed04.workers.dev'
RENDEZVOUS_WRONG_TOKEN="$TEMPORARY_ROOT/rendezvous-wrong-token"
initialize_repository "$RENDEZVOUS_WRONG_TOKEN"
write_current_automatic_signing_fixture "$RENDEZVOUS_WRONG_TOKEN"
write_project_scope_fixture "$RENDEZVOUS_WRONG_TOKEN" \
  opensteamer Release OPENSTEAMER_RENDEZVOUS_URL \
  "wss://${MUTATED_PRODUCTION_HOST}"
commit_all "$RENDEZVOUS_WRONG_TOKEN"
require_failure "$RENDEZVOUS_WRONG_TOKEN" \
  "iOS/opensteamer/project.yml:6:${MUTATED_PRODUCTION_HOST}"

RENDEZVOUS_WRONG_CONFIGURATION="$TEMPORARY_ROOT/rendezvous-wrong-configuration"
initialize_repository "$RENDEZVOUS_WRONG_CONFIGURATION"
write_current_automatic_signing_fixture "$RENDEZVOUS_WRONG_CONFIGURATION"
write_project_scope_fixture "$RENDEZVOUS_WRONG_CONFIGURATION" \
  opensteamer Debug OPENSTEAMER_RENDEZVOUS_URL "$PRODUCTION_URL"
commit_all "$RENDEZVOUS_WRONG_CONFIGURATION"
require_failure "$RENDEZVOUS_WRONG_CONFIGURATION" \
  "iOS/opensteamer/project.yml:6:${PRODUCTION_HOST}"

RENDEZVOUS_WRONG_SETTING="$TEMPORARY_ROOT/rendezvous-wrong-setting"
initialize_repository "$RENDEZVOUS_WRONG_SETTING"
write_current_automatic_signing_fixture "$RENDEZVOUS_WRONG_SETTING"
write_project_scope_fixture "$RENDEZVOUS_WRONG_SETTING" \
  opensteamer Release RENDEZVOUS_URL "$PRODUCTION_URL"
commit_all "$RENDEZVOUS_WRONG_SETTING"
require_failure "$RENDEZVOUS_WRONG_SETTING" \
  "iOS/opensteamer/project.yml:6:${PRODUCTION_HOST}"

RENDEZVOUS_WRONG_TARGET="$TEMPORARY_ROOT/rendezvous-wrong-target"
initialize_repository "$RENDEZVOUS_WRONG_TARGET"
write_current_automatic_signing_fixture "$RENDEZVOUS_WRONG_TARGET"
write_project_scope_fixture "$RENDEZVOUS_WRONG_TARGET" \
  opensteamerTests Release OPENSTEAMER_RENDEZVOUS_URL "$PRODUCTION_URL"
commit_all "$RENDEZVOUS_WRONG_TARGET"
require_failure "$RENDEZVOUS_WRONG_TARGET" \
  "iOS/opensteamer/project.yml:6:${PRODUCTION_HOST}"

PBX_RENDEZVOUS_WRONG_CONFIGURATION="$TEMPORARY_ROOT/pbx-rendezvous-wrong-configuration"
initialize_repository "$PBX_RENDEZVOUS_WRONG_CONFIGURATION"
write_current_automatic_signing_fixture "$PBX_RENDEZVOUS_WRONG_CONFIGURATION"
write_pbxproj_scope_fixture "$PBX_RENDEZVOUS_WRONG_CONFIGURATION" \
  Debug "$PRODUCTION_BUNDLE_ID" OPENSTEAMER_RENDEZVOUS_URL "$PRODUCTION_URL"
commit_all "$PBX_RENDEZVOUS_WRONG_CONFIGURATION"
require_failure "$PBX_RENDEZVOUS_WRONG_CONFIGURATION" \
  "iOS/opensteamer/opensteamer.xcodeproj/project.pbxproj:8:${PRODUCTION_HOST}"

PBX_RENDEZVOUS_WRONG_BUNDLE="$TEMPORARY_ROOT/pbx-rendezvous-wrong-bundle"
initialize_repository "$PBX_RENDEZVOUS_WRONG_BUNDLE"
write_current_automatic_signing_fixture "$PBX_RENDEZVOUS_WRONG_BUNDLE"
write_pbxproj_scope_fixture "$PBX_RENDEZVOUS_WRONG_BUNDLE" \
  Release "$DEBUG_BUNDLE_ID" OPENSTEAMER_RENDEZVOUS_URL "$PRODUCTION_URL"
commit_all "$PBX_RENDEZVOUS_WRONG_BUNDLE"
require_failure "$PBX_RENDEZVOUS_WRONG_BUNDLE" \
  "iOS/opensteamer/opensteamer.xcodeproj/project.pbxproj:8:${PRODUCTION_HOST}"

PBX_RENDEZVOUS_WRONG_SETTING="$TEMPORARY_ROOT/pbx-rendezvous-wrong-setting"
initialize_repository "$PBX_RENDEZVOUS_WRONG_SETTING"
write_current_automatic_signing_fixture "$PBX_RENDEZVOUS_WRONG_SETTING"
write_pbxproj_scope_fixture "$PBX_RENDEZVOUS_WRONG_SETTING" \
  Release "$PRODUCTION_BUNDLE_ID" RENDEZVOUS_URL "$PRODUCTION_URL"
commit_all "$PBX_RENDEZVOUS_WRONG_SETTING"
require_failure "$PBX_RENDEZVOUS_WRONG_SETTING" \
  "iOS/opensteamer/opensteamer.xcodeproj/project.pbxproj:8:${PRODUCTION_HOST}"

STALE_CONTENT="$TEMPORARY_ROOT/stale-content"
initialize_repository "$STALE_CONTENT"
print -r -- "# AudioStreamer" >"$STALE_CONTENT/README.md"
commit_all "$STALE_CONTENT"
require_failure "$STALE_CONTENT" \
  "former product branding remains outside the compatibility allowlist"

STALE_COMPONENT="$TEMPORARY_ROOT/stale-component"
initialize_repository "$STALE_COMPONENT"
print -r -- "obsolete MacCaptureHost.app" >"$STALE_COMPONENT/README.md"
commit_all "$STALE_COMPONENT"
require_failure "$STALE_COMPONENT" \
  "former product branding remains outside the compatibility allowlist"

STALE_BUILD_ENV="$TEMPORARY_ROOT/stale-build-environment"
initialize_repository "$STALE_BUILD_ENV"
print -r -- 'MAC_CAPTURE_CODESIGN_IDENTITY="-"' >"$STALE_BUILD_ENV/build.sh"
commit_all "$STALE_BUILD_ENV"
require_failure "$STALE_BUILD_ENV" \
  "former product branding remains outside the compatibility allowlist"

MUTATED_CRYPTO="$TEMPORARY_ROOT/mutated-crypto"
initialize_repository "$MUTATED_CRYPTO"
mkdir -p "$MUTATED_CRYPTO/shared/Sources/RemoteSessionCore"
print -r -- 'let salt = "AudioStreamer.RemoteSession.HKDF-SHA256.v2"' \
  >"$MUTATED_CRYPTO/shared/Sources/RemoteSessionCore/RemoteSignalingCrypto.swift"
commit_all "$MUTATED_CRYPTO"
require_failure "$MUTATED_CRYPTO" \
  "former product branding remains outside the compatibility allowlist"

STALE_PATH="$TEMPORARY_ROOT/stale-path"
initialize_repository "$STALE_PATH"
print -r -- "stale path" >"$STALE_PATH/AudioStreamer-notes.md"
commit_all "$STALE_PATH"
require_failure "$STALE_PATH" "former product branding remains in a tracked path"

STALE_BELUGA_DISPLAY="$TEMPORARY_ROOT/stale-beluga-display"
initialize_repository "$STALE_BELUGA_DISPLAY"
mkdir -p "$STALE_BELUGA_DISPLAY/iOS/opensteamer/Sources/Views"
print -r -- '.navigationTitle("opensteamer")' \
  >"$STALE_BELUGA_DISPLAY/iOS/opensteamer/Sources/Views/BrowserView.swift"
commit_all "$STALE_BELUGA_DISPLAY"
require_failure "$STALE_BELUGA_DISPLAY" "superseded app display branding remains"

CAPTURE_USAGE_DISPLAY="$TEMPORARY_ROOT/capture-usage-display"
initialize_repository "$CAPTURE_USAGE_DISPLAY"
mkdir -p "$CAPTURE_USAGE_DISPLAY/macOS/Sources/CaptureServer"
print -r -- '<key>NSAppleEventsUsageDescription</key>
<string>Beluga reads playback information and controls Chrome and Music when you enable media integration.</string>' \
  >"$CAPTURE_USAGE_DISPLAY/macOS/Sources/CaptureServer/Info.plist"
commit_all "$CAPTURE_USAGE_DISPLAY"
"$CAPTURE_USAGE_DISPLAY/scripts/check-product-branding.sh" "$CAPTURE_USAGE_DISPLAY" >/dev/null
print -r -- '<key>NSAppleEventsUsageDescription</key>
<string>opensteamer reads playback information and controls Chrome and Music when you enable media integration.</string>' \
  >"$CAPTURE_USAGE_DISPLAY/macOS/Sources/CaptureServer/Info.plist"
commit_all "$CAPTURE_USAGE_DISPLAY"
require_failure "$CAPTURE_USAGE_DISPLAY" "superseded app display branding remains"

print -- "Beluga branding regression tests passed"
