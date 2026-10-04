# Exact-output WebRTC adapter — source qualification only

This directory is **not in the app dependency graph**. It does not enable Android
Connect, replace the installed app, or qualify Android playback. It contains an
opt-in Java source patch for the retained `webrtc-sdk/android v150.7871.01` SDK.
Do not append these classes beside an unchanged AAR: any future derived artifact
must replace the original `WebRtcAudioTrack` and its nested classes exactly once.
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

Still required: receiver composition and native-owner quarantine, a reproducible
single-definition derived artifact, dependency/license/security enrollment,
muted route bootstrap, focused actual-device/emulator lifecycle/media evidence,
foreground/background UI/service integration and public-network compatibility.
Do not use this directory as a shipping or runtime pass.
