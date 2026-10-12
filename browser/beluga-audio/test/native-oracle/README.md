# Native Opus to browser stereo oracle

This opt-in test joins the real `BelugaAudioShareCoordinator` and native
`WebRTCAudioShareSender` to the production browser receiver. Only the input
source and signaling broker are fixtures: 48 kHz stereo PCM carries a 440 Hz
left tone and an 880 Hz right tone. There is no microphone or system-audio tap.

The runner owns an ephemeral loopback HTTPS/WSS broker, certificate, isolated
Chrome profile, and one XCTest process group. Native TLS trusts only the leaf
certificate digest; Chrome gets only that certificate's SPKI allowlist. It does
not change system trust, use the signed-in Chrome profile, install software, or
alter audio routes. Chrome input/output hardware are disabled. A real audio
element drives remote decoding just as in the product, while a parallel
AudioWorklet measures the decoded channels and outputs zero samples.

After building `CaptureServerTests` in an owned scratch directory, run from the
repository root (replace the bundle/result paths with that exact build):

```sh
DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer \
node browser/beluga-audio/test/native-oracle/run.mjs \
  --test-bundle /absolute/owned-scratch/arm64-apple-macosx/debug/BelugaPackageTests.xctest \
  --timeout-seconds 60 \
  --result /absolute/owned-evidence/native-browser.json
```

The result parent must already exist, and the result file must not exist. The
runner supports a 45–90 second bound, cleans up only its owned temporary directory
and process groups, and returns nonzero on any test or teardown failure.

Pass requires all three epochs to show decoded 48 kHz stereo, RMS above 0.01 in
each channel, and each intended tone exceeding the other by a ratio above 8.
It also requires receive-only topology, no sending tracks/microphone calls,
same-link rejoin, manual revocation, fresh-link absolute expiry, stopped native
sources, retired listeners, closed peers/tracks, no post-close decode progress,
successful XCTest completion, and no surviving owned process group.

Only bounded scalar diagnostics are recorded. Capabilities, private keys, ICE
credentials, SDP/candidates, and PCM are not logged. The native/browser child
logs are discarded; do not copy private signaling into a failure report.

The default invocation is **not** deployed-Worker proof, real system-audio capture
proof, phone coexistence proof, eight-listener performance proof, or internet/TURN proof.
The source-bound microphone gate and release/deployment gates remain separate.

## Opt-in temporary-credential forced relay mode

`run.mjs --relay-ice-stdin true` retains the same silent source, waveform limits,
three epochs, native XCTest and owned cleanup. Only the browser's injected peer
uses `iceTransportPolicy: "relay"`; the existing loopback broker supplies the same
temporary ICE servers to native and browser. Direct fixture and real-system-source
modes do not opt in. This is not a deployed Worker or unrelated-network test.

Execution requires a separately authorized parent issuer/revoker lifecycle. The
parent must mint short-lived ICE credentials, pass one canonical `JSON.stringify`
envelope `{iceServers,expiresAt}` through a private stdin pipe/socket and close it,
then revoke the issued credentials after runner cleanup on success, failure or
interruption. The operator entry point below supplies that lifecycle; possessing an
arbitrary stdin payload is not authorization to run. Never put secrets in arguments, environment, files or
logs; the runner never accepts master-key/API-token fields. `expiresAt` is Unix
milliseconds, at least the selected run bound plus 30 seconds ahead and no more
than 300 seconds ahead. Input is capped at 64 KiB and five seconds, normalized by
the production Cloudflare ICE validator, and cleared on cancellation. Opaque string
contents cannot prove issuance or distinguish a mislabelled credential; the trusted
parent owns that provenance and revocation. JavaScript strings cannot be zeroized;
references are dropped at cleanup and no credentials enter scalar reports.

Each epoch's decoded latch additionally waits for two good stereo windows at least
100 ms apart. Fresh inbound-audio stats must bind to the sole transport's selected
succeeded pair and its local relay candidate; both pair receive bytes and inbound
audio receive bytes must strictly advance with unchanged identities and advancing
timestamps. Missing, ambiguous, stale, frozen, regressed, replaced or non-relay proof
fails closed. Stats use the browser performance-origin clock. Startup silence stays
pending; a bad window after proof begins is terminal. The bounded scalar proof is
retained through peer closure; no candidate IDs, addresses, URLs or credentials are
reported. The first rejected proof predicate is retained as a fixed `relay_*`
error code at stage `relay_proof`, before intentional socket teardown can obscure
it. No raw stats or exception strings are added and acceptance is unchanged.
`SIGINT`/`SIGTERM` cancel pending input/setup and enter owned cleanup once,
permanently failing the result. The result path is checked before relay allocation.

Even a pass proves only this fixture's selected browser relay path and decoded
stereo/lifecycle. `systemAudioVerified`, `deployedWorkerVerified`,
`unrelatedNetworksVerified` and `physicalDeviceVerified` remain false. It proves
neither final acoustic output nor production enablement. Pure regressions are in
`test/relay-oracle.test.js` and ordinary `npm test`; they require no credentials,
browser, native media or network. Source preparation does not authorize execution.

### Parent-owned issuance and revocation

`run-credentialed-relay.mjs --execute-authorized-relay true` accepts the same
`--test-bundle`, optional `--chrome`, `--timeout-seconds` and `--result` arguments.
It requires a trusted, normally authorized credential reader to provide exactly
`{apiToken,keyId,name:"beluga-audio-share-v1"}` as canonical JSON over private stdin.
It does not access Keychain, change its permissions, create a relay app, enable
production sharing or accept the existing phone relay's credential namespace.
The exact account/item provenance is the operator's responsibility: a JSON name
is not independent evidence of an account or authorization.

The parent makes one issuance attempt for 180-second credentials, then runs the
existing relay fixture. Only temporary ICE reaches the child, never the master.
Following child cleanup it attempts every distinct known username's revocation
once, with separate five-second deadlines even after cancellation. These operations
use the [documented Cloudflare API](https://developers.cloudflare.com/realtime/turn/generate-credentials/).
Responses and input are size/time bounded. Error payloads and child output are
never copied to the parent report; that report contains fixed scalar status,
counts and proof-scope flags only. Its optional `fixtureDiagnostics` object
projects fixed failure/stage codes, bounded counters and booleans from the
existing child report. It excludes share IDs, credentials, URLs, candidate
identities, exception text and PCM. The first failed/incomplete epoch and last
native phase help locate the boundary; they do not recover a discarded XCTest
assertion or establish a root cause. Unknown enum values become `unknown` and
invalid scalar values become `null`, never raw strings. Diagnostics cannot grant
media success or cleanup. Normal report validation and all existing pass,
revocation and interruption rules still apply. No automatic retry occurs.

An uncertain issuance, failed revocation, cancelled run, missing child cleanup,
or invalid child proof cannot pass. Forced runner termination reports cleanup as
unverified: its separately owned child groups require operator reconciliation
before another attempt. Credential expiry is not process-cleanup evidence or a
substitute for a successful revocation acknowledgment. The entry point is not a
standalone recovery controller. Normal Keychain approval, current source/native
artifact bindings and an external owned-process supervisor must be established
before live execution. Neither source tests nor a local fixture pass enable
production sharing or qualify the deployed Worker, phones or Android release.
An external credential reader that validates the older exact report schema must
be updated and tested offline to admit the diagnostic object before using this
runner; do not bypass its report validator or authentication boundary.

`test/relay-lifecycle.test.js` uses injected HTTP/fixture responses;
`test/relay-parent-process.test.js` uses fake streams/processes. Neither calls the
network, reads credentials, launches a browser, or plays/captures audio.

## Separate real-system-source mode (execution requires fresh approval)

`run-system-source.mjs` is an additional explicit oracle, not a replacement for
the fixture command above. Its XCTest selects the **unchanged production source
factory**, so the challenge must travel through the real `SystemAudioCaptureSource`
and native tap before the existing sender/browser decoder. It does not launch the
host, acquire its runtime lock, load pairings, connect a phone, install a driver,
change a default/per-device route, or write a volume/format property. The silent
receiver still has hardware input and output disabled.

The separately owned `system-source-emitter.c` emits a bounded 48 kHz stereo
challenge on the existing default output only after real capture startup returns.
Each run selects fresh left/right frequencies and a public correlation nonce.
The emitter is a different process because production capture excludes its own
process. This **makes real sound** and can enter an existing phone's audio stream:
do not infer isolation merely from a private directory or unchanged routes.

Before execution the operator must freshly establish no active phone, or obtain
separate approval for the audible coexistence challenge. Unknown phone state is
refused. This gate is operator-provided evidence; the harness does not contact or
control a phone and never labels it independently verified phone coexistence.

The actual signed capture executable must have its own system-audio capture
authorization, or the user must approve **one ordinary permission request** for
that exact executable. The two states are distinct in the gate/report. There is
no public Core Audio tap permission preflight here. A hash or test bundle's Info
plist is not a TCC grant. This slice supports the existing signed `xctest` executable
only; it does not copy it into a new app, create a permission identity, change TCC,
impersonate the host, or retry a rejected/missing approval. If that execution identity
cannot obtain the normal grant, stop: a separately reviewed diagnostic app host is
required before running this mode.

Source preparation does not authorize these build or execution steps. Once the
operator approves them, compile the small output-only emitter into an owned new
path with the pinned toolchain (`clang -std=c11 -Wall -Wextra -Werror`, linking
AudioToolbox, CoreAudio and CoreFoundation). Compile the **unchanged**
`macOS/scripts/opensteamer-v91-coreaudio-route-monitor.swift` separately. No build,
signing or permission setup is performed by the runner. Main must bind the actual
built bytes to their reviewed sources before supplying their hashes.

Supply a fresh owner-only, non-symlink gate file with exactly these fields; the
placeholders below are documentation, not a ready-to-run authorization:

```json
{
  "schema": 1,
  "checkedAt": 0,
  "expiresAt": 0,
  "oracleExecutionApproved": true,
  "audioChallengeApproved": true,
  "capture": {
    "path": "/exact/canonical/path/to/xctest",
    "sha256": "EXACT_SHA256",
    "designatedRequirement": "EXACT_CODESIGN_DESIGNATED_REQUIREMENT",
    "permission": "confirmed"
  },
  "emitter": { "path": "/exact/owned/emitter", "sha256": "EXACT_SHA256" },
  "monitor": { "path": "/exact/owned/monitor", "sha256": "EXACT_SHA256" },
  "routes": { "input": "EXACT_UID", "output": "EXACT_UID", "system": "EXACT_UID" },
  "phone": { "state": "inactive", "coexistenceChallengeApproved": false }
}
```

`checkedAt`/`expiresAt` are Unix milliseconds: initial evidence must be at most
30 seconds old and the entire permit at most 120 seconds. Permission may instead
be `one-request-approved`; that is authorization to attempt once, not a claim
that permission exists. Phone state may be `absent` or `inactive`; `active`
requires its separate `coexistenceChallengeApproved=true`. The runner rechecks
expiry before capture and every emitter start. The gate does not monitor later
phone reconnects: the operator must supervise that boundary throughout the run.

```sh
node browser/beluga-audio/test/native-oracle/run-system-source.mjs \
  --gate /absolute/private/fresh-gate.json \
  --test-bundle /absolute/owned-scratch/BelugaPackageTests.xctest \
  --timeout-seconds 75 \
  --result /absolute/owned-evidence/system-source.json
```

The original fixture invocation/options are unchanged. This mode allows 60–90
seconds and uses a different XCTest method, which skips without its dedicated
opt-in variables. It keeps rejoin, manual revoke and absolute expiry and adds
owner-WSS-loss. The sticky read-only monitor must arm **before** audio resources,
then acknowledge clean listener removal, identical three default UIDs and zero
notifications **after** source/emitter teardown. Every source start/stop and
emitter stop/dispose must acknowledge completion. A killed source, emitter or
monitor, timeout, failed native stop, missing acknowledgement or residual owned
process makes the result fail; process death is not native teardown proof.
The expiry phase waits for automatic native retirement before any explicit stop;
it accepts `.ended`, or `.failed` from the expiry/socket-cancellation race, only
with both sources' stop acknowledgements and zero attached listeners. Owner loss
requires `.failed` plus all three sources' confirmed retirement. `SIGINT` and
`SIGTERM` enter the same single bounded cleanup path, including during setup or
teardown, and permanently fail the final report as `interrupted`.

The pure refusal/report regression is `test/system-source-oracle.test.js`, included
in ordinary `npm test`; it opens no browser, tap, output or route listener.
Even a real-system-source pass remains loopback signaling evidence: deployed
Worker, current-phone continuity, unrelated-network/forced-TURN operation and
eight-listener performance remain **unverified**. Production sharing stays disabled.

## 2026-10-02 findings

- A bare Window timer stored on a dependency object threw `TypeError` in Chrome;
  production timers now explicitly retain the global receiver.
- Omitting the answer's receive-only Opus `stereo=1` preference encoded mono
  despite `opus/48000/2` and a stereo native source. The explicit preference
  preserves unrelated negotiation parameters and is covered by regressions.
- An earlier zero-sample fixture lacked the product's audio-element playback.
  Adding that playback under the unchanged disabled-hardware-output flag fixed
  the harness, not the native capture implementation. The waveform thresholds
  and lifecycle assertions were not relaxed.
