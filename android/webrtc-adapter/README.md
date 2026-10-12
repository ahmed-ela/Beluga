# Exact-output WebRTC adapter — receiver preview integration

The preview app graph now includes `receiver/` and one exact local derived AAR.
This source enrollment does not install an app or qualify Android playback.
This directory contains an opt-in Java source patch, an offline derived-artifact
builder, and the receive-only receiver integration for the retained
`webrtc-sdk/android v150.7871.01` SDK. Do not append these classes beside an
unchanged AAR: the derived artifact replaces the original `WebRtcAudioTrack`
and its nested classes exactly once. `src/` is deliberately not an app source
directory; its `PlaybackOutputObserver` is already in the derived AAR.
No native library, ELF header, or Java class-version header is modified.

## Pinned input

- [Upstream WebRtcAudioTrack.java](https://raw.githubusercontent.com/webrtc-sdk/webrtc/73cb8180f7258ee292878d6edd05177f41883962/sdk/android/src/java/org/webrtc/audio/WebRtcAudioTrack.java)
  at revision `73cb8180f7258ee292878d6edd05177f41883962`.
- Original source SHA-256:
  `96c77cbea46cb507e22c39118cbcff6989d7473d1061e3a5a09b46a631d8560b`.
- Original `classes.jar` SHA-256:
  `737a44bde15d6bd7108bfb756c4772985dea77d8f87e27e2f70ff4b3b1921a10`.
- Original AAR SHA-256:
  `8ad5e5fd02f0177743ddb566bea329006bef7689b944f6351717cd1d018958c0`.

Apply `WebRtcAudioTrack.patch` only to that exact source (zero fuzz). Preserve
the upstream copyright header and the accompanying LICENSE/PATENTS notices.
This is not complete licensing/security or native-dependency admission.

## Receiver contract

Supply `PlaybackOutputObserver` through the existing ADM state-callback builder.
Opted-in callers receive only the exact-output methods, not inherited no-argument
start/stop callbacks. Non-opted-in state callbacks retain their existing delivery.
It receives the actual Android output after playback starts; until the caller
proves its route and owns media focus, the per-write callback must return false.
False substitutes the SDK's existing zero buffer. A callback exception stops the
thread's write loop and leaves a sticky failure. No route changes, second output,
reflection, microphone permission or local recording are introduced.

The observer must be nonblocking. Dispatch platform ownership to main and keep
per-write authorization atomic. One opted-in ADM owns one output lifetime. Late
gain must not reopen it; a new attempt needs a fresh factory/peer/ADM. Already
accepted platform buffers cannot be retracted by this logical gate.

Stopped is delivered only after the actual thread joins and output stop/release
succeed. A failed join retains references and emits no stopped receipt. The
caller **must quarantine before `peer.close()`, disposal or ADM release** when
cleanup is unproved: native destruction ignores a failed StopPlayout return.
Missing stopped receipt (including a throwing failure observer) is unproved;
never rely solely on the cleanup boolean delivered to a callback that can throw.
This patch alone does not establish complete native lifetime safety. Do not retry
or reuse an unproved lifetime. Native thread failure cannot promise bounded,
leak-free recovery.

Keep the exact Java output reference through asynchronous routing-listener/focus
cleanup. Drive that cleanup from the exact output's terminal receipt, separately
from the final receiver receipt. Parent close must await both without a circular
future or a synchronous native-to-main wait. An OEM platform exception remains
unproved cleanup, never success. The default non-opted-in stop/mute/callback path
is retained; exact-output pinning is shared, while the new post-pull stop check
is opt-in only.

## Tests and remaining integration

`PlaybackOutputObserverTest` exercises the actual patched `OutputLease` helper.
Test-only Unsafe allocates identity-only Android objects without constructors,
platform calls or JNI. These tests prove decisions, not thread joins, device
audio, focus, routing, final PCM or final pixels. Compilation and original-method
descriptor comparison must use the pinned SDK and real Android compile SDK.

The `receiver/` source now connects the actual output callbacks to bounded muted
route discovery, exact route/focus ownership, and receipt-gated native destruction.
The corresponding pure `ViewerPlaybackOutputLifetime` lives in the app sources.
It keeps output-stop and main-thread cleanup receipts separate. An explicit
retirement and a failed admission read race at an atomic retirement commit, so
a late read cannot convert an already-requested disconnect into a new failure.
Missing cleanup proof strongly retains the receiver graph in a process quarantine
before the session parent drops its reference; it blocks later native starts.
Quarantine is containment, not leak-free recovery.

The receiver uses the existing production rendezvous origin, stored identities,
fresh session credentials, and broker-provided ICE configuration. It includes no
private-oracle connector, candidate restrictions, PCM collector or diagnostic
artifact writer. App/UI composition and its validation are separate from this
dependency enrollment. The retained native
API makes SetAudioPlayout(false) a synchronous worker call to StopPlayout, but
discards its return value; the exact Java stop receipt is therefore required
before peer.close as well as disposal. See the pinned upstream
[PeerConnection implementation](https://github.com/webrtc-sdk/webrtc/blob/73cb8180f7258ee292878d6edd05177f41883962/pc/peer_connection.cc#L1576)
and [AudioState implementation](https://github.com/webrtc-sdk/webrtc/blob/73cb8180f7258ee292878d6edd05177f41883962/audio/audio_state.cc#L56).

Still required: complete license/security review, app receiver/UI validation,
focused actual-device/emulator lifecycle/media evidence for this derived artifact,
foreground/background UI/service integration and public-network compatibility.
Do not use this directory as a shipping or runtime pass.

## Reproducing the receiver preview dependency

The app requires `-PbelugaDerivedWebrtcAar=/absolute/canonical/libwebrtc-derived.aar`.
The path must be an existing regular file with no symlink/path aliases, and its
SHA-256 must be exactly
`e98a90d72fa186d9feb92ea3cde3a6dda06e68361c061bce9f72bf854c92bf6d`.
The Gradle configuration and `preBuild` recheck it. There is no fallback to the
raw SDK, download, checked-in binary or artifact search. An absent/mismatched
input fails instead of silently building a different receiver.

Run Gradle under an explicitly supplied local JDK21 `JAVA_HOME`; the retained
upstream classes require that compiler. Java/Kotlin app output stays at17 and
AGP's Android platform wiring is unchanged. No toolchain or SDK download is
enabled. Continue using the repository's offline strict dependency-verification
and lock settings. This file dependency is pinned above rather than by Maven
coordinates. The existing ABI set is retained; it is not an all-ABI runtime pass.
Native stripping is disabled for this exact library so packaging must retain its
reviewed bytes; inspect the built APK independently before runtime use.

## Packaged notices and provenance

The per-variant `prepare…WebRtcNotices` task copies `LICENSE.webrtc`,
`PATENTS.webrtc`, `NOTICE.beluga`, `NOTICE.native.webrtc`, `VERSIONS.webrtc`,
`NOTICE.fork.webrtc`, `LICENSE.Apache-2.0` and `PROVENANCE.notices.json` into APK
assets at `third-party/webrtc-sdk-150.7871.01/`. Explicit APK delivery is necessary:
notices in the outer AAR alone do not guarantee their delivery in the APK.

`NOTICE.native.webrtc` and `VERSIONS.webrtc` are unchanged copies of `webrtc/NOTICE`
and `webrtc/VERSIONS` from the unprefixed `webrtc.android.tar.gz` Actions artifact
`9744480229` in [upstream build #479](https://github.com/webrtc-sdk/webrtc-build/actions/runs/33350496482).
The retained artifact ZIP digest, member paths and individual notice hashes are
recorded in `PROVENANCE.notices.json`. Its embedded `webrtc/aar/libwebrtc.aar`
matches the original AAR digest above; all four embedded native payloads match
the unchanged payloads retained by the derived AAR. `VERSIONS.webrtc` pins the
source revision and dependency revisions. The upstream
[packager](https://github.com/webrtc-sdk/webrtc-build/blob/06e3410d8f67d08202e26f55225705596b60778e/build/run.py#L850)
generates a dependency-license union across Android build targets/architectures
and renames it `NOTICE`. Its original Markdown and escaped text are preserved.
Do not substitute the release's generic `webrtc.tar.gz`: the release workflow
selects prefixed variants, not this unprefixed artifact.

`NOTICE.fork.webrtc` separately preserves the pinned source's Shiguredo/Wandbox
attribution; it is not the generated dependency inventory. The pinned upstream
[README](https://github.com/webrtc-sdk/webrtc/blob/73cb8180f7258ee292878d6edd05177f41883962/README.md#license)
identifies Shiguredo patches and LiveKit changes as Apache-2.0.
`LICENSE.Apache-2.0` is the unchanged full license text from Apache's primary site.

This establishes the generated notice inventory's provenance and byte binding,
not an independent completeness, legal, patent, security or runtime clearance.
Review of license obligations/security and readback of the actual built APK's
notice assets remain release requirements. No native rebuild or derived-AAR
change was needed to collect these notices; raw-SDK emulator evidence does not
qualify the app's derived receiver.

## Offline derived-AAR builder

`build-derived-aar.rb` consumes explicit local inputs; it never downloads, signs,
installs, enrolls a Gradle dependency or loads JNI. An existing output directory
is refused. Failed work stays in its one-shot directory and must not be reused.
Only a terminal `receipt.json` with `DERIVED_AAR_BUILT_NOT_ADMITTED` identifies
completed static packaging; an AAR left without that receipt is not success.

```sh
ruby android/webrtc-adapter/build-derived-aar-test.rb
ruby android/webrtc-adapter/build-derived-aar.rb \
  --inputs /absolute/reviewed-inputs.json \
  --output /absolute/new-derived-aar-directory
```

The exact JSON object has these fields (no extra or duplicate keys):

- `schema`: `beluga.webrtc-derived-aar.inputs.v1`.
- `rawAar`, `upstreamSource`: canonical absolute paths to the unchanged pinned
  AAR and upstream `WebRtcAudioTrack.java` above.
- `jdkHome`: canonical local JDK21 home. Only its `javac` and `javap` are invoked;
  the build produces non-preview Java17 classes, never rewritten class headers.
- `androidJar`: the actual Android36 platform jar, SHA-256
  `d9eb9da824d9e247a352f570f01e1169e725b2954bca9e283a71786c59b59f9a`.
- `annotationsJar`: AndroidX annotation-jvm1.9.1, SHA-256
  `1e343917ebf27ba96fe4dc52b1cad7fd32b738fbc6355bb6cd5b3b305d7212d0`.
- `inputPins`: an exact absolute-path-to-SHA256 map containing those four input
  files; `jdkHome/bin/javac`, `jdkHome/bin/javap`, `jdkHome/release`; `/bin/ps`;
  and this directory's `build-derived-aar.rb`, `build-command.rb`,
  `WebRtcAudioTrack.patch`, `LICENSE.webrtc`, `PATENTS.webrtc`, and
  `src/org/webrtc/audio/PlaybackOutputObserver.java`. Root must prepare and review
  these pins before execution. The bounded command supervisor is currently
  qualified for the pinned macOS `/bin/ps`, not arbitrary hosts.

The builder applies the unified patch at exact original line positions and
context, with no fuzz or offset. It checks original method descriptors for both
`WebRtcAudioTrack` and its original `AudioTrackThread`, replaces those two classes
once, and adds only `OutputLease` and `PlaybackOutputObserver`. Every other JAR
entry and every original outer AAR payload, including all four native libraries,
must remain byte-identical. Duplicate/path-aliased archive members are refused.

Archives use sorted names, stored payloads, fixed timestamps and regular-file
metadata. Compression metadata is deliberately regenerated, not preserved.
LICENSE/PATENTS and canonical provenance are added under
`META-INF/beluga-webrtc-adapter/`; no existing notice is removed. Embedded
provenance is independent of output paths and records exact compiler/source/tool
and output-class hashes. Input hashes are rechecked before and after publication.
Whole-JDK provenance, complete licensing/security review, R8 qualification and
native/device/runtime compatibility remain separate gates. The focused Ruby tests
use pure archive/patch fixtures and a command double, not an actual compiler.
