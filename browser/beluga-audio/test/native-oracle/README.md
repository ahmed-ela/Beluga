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

This is **not** deployed-Worker proof, real system-audio capture proof, phone
coexistence proof, eight-listener performance proof, or internet/TURN proof.
The source-bound microphone gate and release/deployment gates remain separate.

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
