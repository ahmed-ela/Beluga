# Beluga roadmap

This roadmap records current work, not private deployment history. Completed items describe code
foundations; they are not claims that every network, device, route, or distribution artifact has
passed the corresponding physical release gate.

## Paused client-upgrade checkpoint — 2026-10-05

**Paused at the user's request, not complete or deployment-ready.** Resume only when
the user asks. This dated checkpoint supersedes older status statements below for
the client-upgrade work; it does not mark the broader roadmap complete.

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

**The underlying relay-test root cause is not yet established.** The parent
`admitFixtureOutcome` in
`browser/beluga-audio/test/native-oracle/relay-parent-process.mjs` reduces the
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
