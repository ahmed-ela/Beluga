# Beluga roadmap

This roadmap records current work, not private deployment history. Completed items describe code
foundations; they are not claims that every network, device, route, or distribution artifact has
passed the corresponding physical release gate.

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
- [ ] Investigate simulator notification reopening: fresh foreground-banner expansion and
  controls work, but after dismissal, pressing and holding the same delivered notification
  in Notification Center does not expand its controls panel. Determine whether the cause is
  simulator behavior, test input, or product code; current evidence does not establish which.
  Then verify reopened labels before any interaction and correct first-tap behavior across
  repeated reopen cycles, without rescheduling the notification or skipping assertions.

The isolated physical-iPhone test already demonstrated source switching, play/pause, and
±30-second embedded actions while genuinely locked on a cached notification. This simulator
failure does not invalidate that result; fresh combined-build and reopen validation remain
separate unfinished checks, not a claim of production integration.

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
