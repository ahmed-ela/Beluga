# Beluga roadmap

This roadmap records current work, not private deployment history. Completed items describe code
foundations; they are not claims that every network, device, route, or distribution artifact has
passed the corresponding physical release gate.

## Resumed client-upgrade checkpoint — 2026-10-05

### Stopped at the user's checkpoint request — 2026-10-05

The user clarified that the requested action is to commit, push and preserve
progress, not continue release work. Further implementation, live relay attempts
and deployment are stopped here. The goal is incomplete.

- All existing product progress is preserved on `feat/phone-media-handoff`.
  Latest diagnostic source `dc23be4730d2d73b4704942ae20e5c7732c1d884`
  was committed, pushed and independently matched against the remote branch.
- The approved prior relay attempt connected and received a good stereo waveform
  but failed relay-proof validation. Temporary credentials were revoked; owned
  process cleanup and the zero-notification sticky route monitor passed. This
  does not prove a product defect or a passing relay path.
- Fixed first-rejection diagnostics are saved; 45 focused cases pass. Independent
  review passed after correcting failure-report ordering. No media, credential,
  revocation, route or teardown acceptance criterion was weakened.
- A fresh private reader/supervisor was prepared, offline-tested and reviewed,
  **but never executed**. Its pins refer to the diagnostic commit above and must
  be revalidated/rebound after this documentation-only checkpoint before any
  future explicitly resumed run. Private evidence remains outside Git.
- No new full-feature DMG, update feed or TestFlight release was published. The
  running host, phones and audio routes were not changed.

Remaining on explicit resumption: obtain the exact relay rejection with the
prepared guarded diagnostic, resolve it from evidence, qualify deployed sharing
and actual Android app pairing/reconnect/media, then complete release validation
and publish the signed DMG/update feed and matching TestFlight. Android actual-
media handoff is not implemented. Live YouTube and real upgrade rehearsal remain
explicitly deferred, not passed.

The earlier resumption record below is retained as history, not an instruction
to continue while this checkpoint is stopped.

The user resumed both the original Mac-client request and the phone handoff/
Android additions. One goal is active again; the release is still incomplete.
All previous product progress and the pause checkpoint were remote-confirmed at
`2510c0aab37bc7ed2ded8e5c3ebd1a439296f6de` before resumption.

- Relay diagnostics (`9b20fdf`) are now preserved through the parent/lifecycle report using
  a fixed, exact scalar schema. No share IDs, credentials, URLs, signaling,
  exception text or PCM are copied. The existing media, cleanup, revocation and
  cancellation acceptance rules remain unchanged.
- 39 focused diagnostic/parent/lifecycle/relay cases passed, with zero failures
  or skips. Independent integration review caught a child-exit/native-exit
  diagnostic distinction; that was corrected and the seven affected parent
  cases passed again. The staged diff secret scan was clean. This is diagnostic
  tooling evidence, not a passing live relay test or a product root cause.
- Android source and retained evidence were reviewed without another build or
  runtime attempt. Actual app pairing/reconnect/media qualification remains
  missing; the variable first-Show result still does not establish a deterministic
  product defect. Android currently supports the receiver path, not actual-media
  handoff, background playback, microphone forwarding or remote input.
- After the phone naturally disconnected, one approved guarded relay attempt
  connected and received a good stereo waveform, but failed its relay proof.
  Temporary credentials were revoked and all owned processes/scratch cleaned up;
  the sticky route monitor reported zero notifications and clean teardown. The
  production host and routes remained unchanged. This is not relay success.
- The existing diagnostics did not identify which proof predicate failed. Added
  fixed first-rejection codes that survive intentional socket teardown without
  changing the five-field proof, thresholds, media or cleanup acceptance. All
  45 focused proof/browser/parent/lifecycle/diagnostic cases pass with no skips.
  A separate bounded local no-TURN browser probe found valid stats bindings and
  timestamps; it neither identifies the relay defect nor qualifies deployment.

Next: admit the fixed predicate codes in a fresh offline-tested private reader,
bind the reviewed supervisor to the new source, then make one bounded changed
diagnostic relay attempt when the existing quiet-session/route gate permits it.
Do not weaken the gate or repeat the old opaque failure. Sharing service, Android app qualification, final
release validation, signed DMG/update feed and matching TestFlight publication
remain open. The previous YouTube and real upgrade rehearsal deferrals remain.

## Historical pause checkpoint — 2026-10-05

**The earlier pause was not completion or deployment readiness.** This section
preserves that stopping point and is superseded by the resumption above; it does
not mark the broader roadmap complete.

The implementation baseline is `ac30e456e1ef10b4da2c7de1be52fe81917d55f0`
on `feat/phone-media-handoff`. This checkpoint changes documentation only. Detailed
private execution evidence and failed attempts are retained outside the repository.
Keep credentials only in their authorized memory/Keychain scopes; do not commit
credentials, account configuration or raw signaling to this document or Git.

### Requested scope and completed work

- One-use QR pairing, durable saved-Mac selection, menu-bar controls, timed private
  browser audio sharing, versioned DMG packaging and secure updater foundations
  exist in source. Their source/fixture evidence is not a complete installed-release
  or public-service result.
- "Move media to phone" means continue the actual media at the same position, then
  pause the exact Mac source only after phone success. The implementation and focused
  Mac/Simulator checks are retained. Preserve the already-shipped video screen-awake
  behavior; do not replace this handoff with simple Mac-audio forwarding.
- Android's selected-Mac controller, receiver and Connect/Disconnect/Show/Hide UI
  are wired. Local-library initialization/reopen and scoped private native/media
  checks passed. A previous first-Show black-frame result remains unexplained; a
  later instrumented pass is not proof of a functional fix.
- Browser sharing passed the local real-system-source stereo fixture, including
  rejoin, revocation, expiry and owner loss. The separate relay lifecycle has
  20 focused offline tests passing; these do not establish live relay success.
- The private credential reader's ordinary approval window was extended from one
  to five minutes after repeated pre-network timeouts. Its six offline validation/
  refusal test groups passed. Credential scope, media-test deadlines, temporary
  credential lifetime and cleanup rules were unchanged. Those operator helpers
  remain private and are not product changes in this commit.

### Exact stopping point

The latest supervised live relay attempt got past Keychain and validated issuance
of one temporary credential. The fixture started but returned `fixture_failed`.
Fixture cleanup was verified, the one credential was revoked, and there was no
issuance uncertainty, revocation failure or interruption. All observed owned
processes exited, the scratch directory was removed, and the sticky CoreAudio
monitor finished with zero notifications and clean teardown. The existing host
and default audio routes were unchanged.

**The underlying relay-test root cause was not established at pause.** The parent
`admitFixtureOutcome` in
`browser/beluga-audio/test/native-oracle/relay-parent-process.mjs` then reduced the
child's detailed report to `passed` and `cleanupVerified`; the retained lifecycle
report therefore does not identify the failed assertion. Neither a TURN outage,
a streaming defect, nor an oracle defect has been proved. Root-cause investigation
was interrupted by this pause before any diagnostic patch or new test.

### Remaining work, in order

1. Preserve bounded, allowlisted, nonsecret failure diagnostics through the relay
   report path. Retain the failed phase/assertion and useful scalar counters, not
   credentials, capabilities, SDP, ICE addresses, PCM or raw child logs. On explicit
   resumption, use one supervised diagnostic attempt; do not repeat unchanged tests
   or assume another approval prompt is necessary.
2. Diagnose the actual failed boundary, fix only a demonstrated defect, add focused
   regression coverage and obtain a fresh passing relay result with complete
   revocation/process/route cleanup. Do not weaken the oracle to obtain a pass.
3. Finish live sharing-service integration and qualification: expiry/revocation,
   existing-phone coexistence, relay behavior and resource/cost limits. Production
   sharing remains disabled. Preserve the existing deployed origin and separate
   sharing credentials from existing phone credentials.
4. Qualify the actual Android app's pairing, saved-Mac reconnect, decoded audio and
   Show/Hide path against the intended Mac/service, including the unresolved startup
   variability. Private emulator/local fixtures do not prove unrelated-network or
   physical-device behavior.
5. Run the final release gate against the settled source and exact candidate inputs.
   Prior source-bound receipts are historical; reuse unaffected evidence without
   presenting it as a fresh full-release receipt.
6. Prepare and verify the versioned signed/notarized Mac DMG and signed update feed,
   publish the repository release, and complete the matching internal TestFlight
   workflow. Distinguish packaging, upload, availability, installation and live
   behavior. No new client-upgrade DMG/feed or TestFlight candidate was deployed by
   the latest work.

### Decisions and boundaries to preserve on resumption

- The user chose to hold deployment until browser sharing and Android streaming
  are ready; do not silently publish a narrower preview.
- Live YouTube handoff testing is deferred while YouTube is blocked. Do not bypass
  that restriction or claim the deferred test passed.
- The real old-to-new updater rehearsal is deferred to the user's Mac after
  deployment. Do not request a disposable VM again; keep that test explicitly open.
- The historical V9 microphone-recovery clause in the goal text is superseded.
  Do not restart that work, alter protected legacy runtimes, disturb phone sessions
  or change audio routes as a release convenience.
- At pause, no owned relay/release test was running. No more authentication requests,
  diagnostic runs, builds or deployments are authorized by saving this checkpoint.

## Publication

- [x] Select and add the GPL-2.0-only project license.
- [x] Remove production endpoints, signing identities, personal metadata, and real capabilities
  from the publishable tree and reachable Git history.
- [x] Add full-history Gitleaks and project-specific external-blocklist release gates.
- [x] Add third-party notices for direct runtime dependencies.
- [ ] Add CI for Swift, iOS generation/build/tests, both Node services, secret scanning, and
  generated-project consistency.
- [ ] Assess required-reason APIs and add an accurate iOS privacy manifest if the shipped binary
  needs one; do not add declarations for APIs the app does not use.
- [ ] Configure unique bundle, Keychain, telemetry, LaunchAgent, and process namespaces before the
  first public binary distribution.

## Worldwide reliability

- [ ] Deploy and validate TURN for the intended service account.
- [ ] Pass unrelated-network direct and forced-TURN physical tests.
- [ ] Exercise restrictive NAT/firewall failure and bounded ICE recovery.
- [ ] Document provider quotas, cost, credential rotation, and outage behavior.
- [ ] Add release-safe endpoint injection without committing operator configuration.

## Pairing and security

- [ ] Add a first-run host surface that presents invitations without persistent logs.
- [ ] Add explicit per-device revocation UX on both endpoints.
- [ ] Perform an external threat-model and implementation review.
- [ ] Add Worker abuse, rate-limit, hibernation, and load validation at deployment scale.
- [ ] Enable GitHub secret scanning and push protection on the public repository.

## Audio

- [ ] Add wired/external, source-correlated acoustic capture for final-output fidelity claims.
- [ ] Validate built-in speaker, wired, USB, and supported wireless routes.
- [ ] Complete background, lock, interruption, and real-call physical matrices.
- [x] Keep full-band, clipping, silence, half-stereo, gain-pumping, and phase-reset mutations in
  the automated waveform suite.

## Notification controls

- [x] Integrate the bounded browser/Music catalog, shared source-specific Play/Pause
  and ±30-second commands, and the App Group notification extension in source.
  See [notification media controls](docs/notification-media-controls.md) for authority,
  packaging and evidence boundaries; this is not an installed-release claim.
- [ ] Validate the integrated release on a physical locked iPhone against real Mac
  sources, including recovery and repeated reopening of the same delivered card.
- [ ] Diagnose the reported stale Play/Pause state in the expanded ±30-second
  notification after pausing directly on the Mac. The isolated unsolicited-host-pause
  simulator regression passes. A Mac observer deadline-starvation defect is now
  reproduced and patched with 121 focused tests passing; that host repair committed
  on September 30. The user still reports the failure. A production iOS consumer
  regression reproduces a queued pause blocked behind a native audio read. The
  bounded-worker repair passes the signed Simulator audio/notification suites and
  expanded-card check; build 91 still requires distribution and a fresh phone check.
  See [external-pause evidence](docs/notification-media-controls.md#external-pause-follow-up-2026-09-30).
- [x] Verify simulator same-card reopening through Notification Center's actual
  swipe-left → View action. Three cycles pass with fresh labels before source selection,
  exact first-command receipts, and unchanged OS-delivered identifier/date/session/category;
  no notification rescheduling or skipped assertions. The earlier long-press path still
  fails in this simulator, including for a plain system notification; its cause and
  physical locked behavior are not established. See the
  [dated evidence](docs/notification-media-controls.md#notification-center-follow-up-2026-09-30).

The isolated physical-iPhone test already demonstrated source switching, play/pause, and
±30-second embedded actions while genuinely locked on a cached notification. The simulator
results do not replace that physical evidence; fresh combined-build locked-device and
reopen validation remain separate unfinished checks, not a claim of production integration.

## Screen and input

- [ ] Cryptographically bind physical screen challenges to their source session.
- [ ] Add GPU-presentation and confirmed native-stop oracles.
- [ ] Drive a disposable Mac target and verify actual pointer/text mutations.
- [ ] Complete multi-display selection and behavior.
- [x] Keep remote input explicit, screen-generation-bound, and revocable.

## Packaging and operations

- [ ] Add a Mac installer/menu-bar host and safe LaunchAgent management.
- [ ] Add update and rollback handling without changing signing, Keychain, or TCC identity.
- [ ] Add structured, redacted operational diagnostics.
- [ ] Document sleep/wake limitations without promising unsupported remote wake-up.
- [ ] Generalize the physical-device harness so model, OS, team, bundle, and installed build are
  explicit operator inputs rather than repository defaults.

## Completed foundations

- [x] One-use invitation pairing with durable device binding.
- [x] Distinct WSS coordination for pairing and paired-device availability.
- [x] Direct-preferred WebRTC with configurable TURN fallback.
- [x] 48 kHz stereo Opus audio and H.264 screen transport.
- [x] Output-only iOS playback architecture with background-audio policy.
- [x] Independent screen Show/Hide and capability-gated remote input.
- [x] Connection telemetry that excludes secrets and user-entered input.
- [x] Mutation-resistant protocol, waveform, lifecycle, artifact, and shell-driver oracles.
