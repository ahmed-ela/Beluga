# Beluga Mac client 0.2

Status: implementation in progress; no DMG, updater, browser share, or new phone build deployed.
This feature work does not modify a separately prepared driver recovery or any
installed host. Keep its frozen product/tooling inputs and protected runtime intact.

## Added goal scope — connected-phone media action and Android

The user added both requirements on 2026-10-02. They extend this active Mac-client
goal; they are not completed features or a second duplicate goal.

- Add **Move media to phone** to the logo's menu for the currently authenticated,
  live connected phone. Saved pairing or completed negotiation alone does not
  enable it. Bind each request/result to that exact phone and media-session
  generation; disconnect, reconnect, or switching phones invalidates old work.
- Product choice resolved on 2026-10-03: **option 2**, continue the selected
  source in a phone player at its current position, then pause that exact source
  on the Mac only after confirmed phone playback. Existing Mac-audio downlink
  is not this feature. Opening an app or link is not playback confirmation.
  Start with a finite, seekable YouTube video; unsupported providers remain
  explicitly unavailable rather than silently changing the action into streaming.
- Preserve the existing selected-source ownership rule. A newly playing tab
  must not steal the source chosen for a move. An action must not pause unrelated
  Mac media or report success from merely sending a command/opening a URL.
- Add a native **Android paired client**, not just Android access to browser
  audio links. Reuse the same one-use QR and durable pairing protocol, retain
  multiple saved Macs, and connect one selected Mac with explicit capabilities.
- Preserve existing iPhone trust when Android is paired. The host source now
  migrates its single saved-viewer slot to a bounded multi-phone catalog; its
  installed-runtime and compatibility proof remain outstanding. Keep
  **one active phone session**; this
  request does not authorize eviction of a current viewer or promise simultaneous
  iPhone/Android sessions. Forgetting one phone must not erase another.
- Android audio, screen, microphone, control, background behavior, and the new
  media action each require implementation and independent verification before
  advertising support. Native Android first-slice and compatibility gates are
  recorded in `ANDROID_CLIENT_PLAN.md`.

Added delivery gates:

- [x] Confirm media-move semantics and define receiver acknowledgement/failure behavior.
- [ ] Connected-phone menu action, exact-session fencing, source continuity and real effect.
- [ ] Host multi-phone migration/revocation without losing the existing iPhone pairing.
- [ ] Android QR, secure identity/catalog, durable reconnect and saved-Mac selection.
- [ ] Android native audio/screen and advertised-control interoperability proofs.
- [ ] Signed Android artifact and explicit device/network/runtime verification.

Discovery notes: current remote-media commands run phone-to-Mac, not backwards;
the menu's `sessionPrepared` phase is signaling-only. A new action needs actual
peer/ICE/control health, current paired-device identity, a negotiated receiver
capability and a bounded acknowledgement. Streaming playback must use the
existing phone lifecycle without implicitly enabling its microphone or overriding
interruption/private-route gates. For a real source handoff, the existing selected
YouTube item provides a bounded video ID and position, but external app opening
does not prove playback. Apple Music has no established portable handoff link in
the current metadata. Unsupported/needs-user-action must remain explicit.

### Media-transfer acceptance contract

This contract is not an implementation or deployment claim. The first source
slice keeps the new optional capability **off by default** until its complete
host-menu, phone-player and audio-lifecycle integration passes the gates below.

- The offer names the selected primary source, exact authenticated negotiation,
  one-use operation, provider video ID, bounded position/rate/duration and a fixed
  deadline. A replay, duplicate delivery or later snapshot cannot renew it.
- The phone must observe the exact video playing with advancing time near the
  requested position in its visible, current player. Ready, URL-open, a Mac state
  update, a paused frame and a sent command do not establish phone playback.
- Autoplay refusal offers a visible Play action. Failure, timeout, dismissal,
  backgrounding, disconnection or source replacement leaves the Mac untouched.
  Position/rate changes while loading must cancel or explicitly re-anchor the
  transfer, not pause a source that has since moved elsewhere in its timeline.
- The pause must be correlated to the still-current offer at the host, then use
  the existing exact Chrome process/tab/document/item native authorization and
  actual pause readback. An ordinary Pause acknowledgement alone is not a
  correlated handoff completion receipt.
- Local playback and the existing Mac-audio downlink must have an explicit,
  owner-scoped coexistence policy. Do not change AVAudioSession, default routes,
  microphone intent, interruption admission or screen-presentation authority as
  a shortcut. Direct track muting is not sufficient because the lifecycle owner
  reapplies its gate. Cancellation must restore only the same session's state.
- Model/transport tests, actual WebView playback, Simulator integration, physical
  phone playback and a released artifact are distinct proof levels. Do not enable
  a menu item or advertise Android support from an unwired player/protocol alone.

Use the supported [YouTube IFrame API](https://developers.google.com/youtube/iframe_api_reference)
and the app's actual [embedded-player identity](https://developers.google.com/youtube/terms/required-minimum-functionality#embedded-player-api-client-identity).
Keep its controls visible, do not bypass autoplay restrictions, and leave the
Mac playing when embedding or position confirmation fails.

Component checkpoint (2026-10-03): source now contains default-off negotiated
offers, exact one-use receiver receipts, and a SwiftUI/WKWebView YouTube player
with revocable, advancing-time playback observations. The actual native local
WebView bridge and lifecycle tests pass in Simulator. Neither frontend enables
the capability, no menu action is wired, and consuming an offer sends no Pause.
The player has not been verified against a real YouTube stream; unsupported
embedding/autoplay, source re-anchoring while loading, post-commit local player
controls and audio coexistence remain integration work. This is not a transfer
or deployment claim. See the handoff component section in `TESTING_ORACLES.md`.

Native source checkpoint (2026-10-03): the host now creates opaque, one-use
descriptors from exact native Chrome observations, not artwork metadata. A
specialized Pause path revalidates original source/timeline/phone position at
the final renderer operation and requires paused-position readback. Stop,
timeout, controller invalidation and revoked caller authority cancel queued work.
Separate playback-continuity identifiers retire pause/resume, seek, buffering and
rate-change ABA without changing normal source-selection or command identity.
The actual controller/composite/backend and extracted script tests use explicit
boundary doubles. No wire transaction, menu action or phone audio lifecycle is
wired to this path yet; the product capability stays disabled. This is not a
completed transfer, live-runtime verification or deployment.

## Product contract

- One Mac app/process with the existing exclusive host lock and preserved Keychain/signing IDs.
  Finder launch uses the physical display; headless virtual-display options remain explicit.
- A persistent Beluga menu-bar item presents status, QR pairing, audio sharing, and updates.
- The QR carries a bounded non-URL envelope around the existing one-use invitation. The existing
  authenticated handshake, not scanning alone, creates the durable Keychain trust relationship.
- The phone retains multiple independent Mac records under its existing stable viewer identity.
  Selecting a Mac retires the previous connection before admitting another. Adding or forgetting
  one Mac must not erase another or rotate the iPhone identity.
- Browser links grant live Mac audio only. They grant no microphone, screen, remote input,
  persistent pairing, or administrative authority. Unlisted, cryptographically random bearer
  links may be forwarded by recipients; expiration and host revocation close current listeners
  as well as rejecting new ones. A countdown is presentation, not the expiry authority.
- Sharing must not replace the phone peer or alter default audio routes. Resource limits and
  disconnect cleanup are required; a slow listener must not stall the source callback.
- SemVer identifies releases; a monotonically increasing Mac build identifies Sparkle updates.
  The first new-client candidate is planned as 0.2.0/build100. Do not relabel prior artifacts.
- Publish a Developer ID-signed, notarized and stapled DMG as a repository Release asset.
  Sparkle 2.10.0 verifies a signed HTTPS feed and Ed25519-signed archive before extraction.
  Keep signing keys in Keychain, never source, logs, arguments, or feed URLs.
- Updating must respect active pairing/listeners/media and drain the existing host before quit.
  No updater auto-install during sessions and no privileged driver update as an app-update side effect.

## Delivery gates

- [ ] QR round trip and hostile-payload rejection; physical camera proof remains distinct.
- [ ] Multiple-Mac persistence, migration, per-Mac deletion, selection and stale-task fencing.
- [ ] Real menu-bar lifecycle, current invitation expiry, one host runtime, graceful shutdown.
- [ ] Additive browser signaling namespace with separate owner/listener capabilities, bounded
      admissions, expiry/revocation of active peers, restart failure behavior and no secret logs.
- [ ] Non-interfering real Opus/WebRTC audio fan-out, no microphone/screen/control grants.
- [ ] Browser final decoded waveform and forced-TURN/unrelated-network checks.
- [ ] Versioned artifact verifier including Sparkle's complete nested code/signature closure.
- [ ] Signed/notarized DMG, clean-Mac onboarding/permission checks and repository Release asset.
- [ ] Genuine old-to-new signed update test, busy-session rejection and safe host termination.
- [ ] Compatible iOS build distributed and actual two-Mac selection verified.

The existing product, microphone, screen, and protected-legacy regression gates remain in force.
The browser protocol must not change deployed /v1/rendezvous or /v2/availability ABI.

## Implementation evidence — 2026-10-02

- Distribution readback uses a fresh private internal mountpoint independently
  of the chosen output volume. An external-backed mountpoint can be refused by
  DiskImages even when the image and directory permissions are valid. The
  packager's explicit notarized-DMG resume trio copies an independently
  digest-bound image into fresh empty output; it never rebuilds the app,
  re-signs/re-staples the image or repeats a notary submission. Current release
  receipt, source/retained-product authority, updater tool/key checks, exact DMG
  signing identity, Accepted notary ID/name, staple/Gatekeeper/image validation
  and mounted app/candidate readback all remain mandatory before archive/feed
  signing. The report retains original product provenance and records recovery
  separately; it does not claim the interrupted original package completed or
  equate Apple's pre-staple submission digest with the copied stapled image.
  This source change alone is not successful packaging or deployment.
- Actual retained-artifact admission passed the evidence collector, then native
  verification exposed a second metadata-parser defect: vtool's linker/compiler
  `version` lines were counted as macOS deployment targets alongside `minos`.
  The corrected parser binds each exact binary path and architecture to one
  macOS build/minimum command and validates its tool records separately. Missing,
  duplicate, foreign-platform and malformed slices fail closed; the existing
  macOS14 ceiling and exact14 target for our three executables are unchanged.
  The 69-case producer suite passes 1035 assertions, and read-only diagnostics
  pass for all14 retained code members' targets, loading contracts and signatures.
  These are not a fresh full release receipt, successful packaging or deployment.
- Retained-artifact recovery is an explicit alternative in the existing client
  verifier/packager, not a fabricated successful `build.json`. A reviewed private
  manifest and independent digest bind the failed official invocation, exact
  original product, current tooling, both receipts, signed app tree, three product
  logs and an explicitly retrospective trusted-root observation. The original
  final checks remain recorded as incomplete. The current full offline receipt
  stays mandatory; the historical receipt is never treated as current authority.
  The collector compares exact reviewed Git blobs and actual receipt permission
  tuples, refuses every non-tooling/product or ignored-dependency difference,
  and fences evidence identities, source inputs and tested tools at verification
  and packaging boundaries. All native artifact/signature/layout checks remain.
  Package inputs are successful build report **or** retained admission, never both.
  No old product bytes or sealed source identifiers are changed or re-signed.
  Focused tests exercise malformed/ambiguous evidence, source confusion, ignored
  drift, filesystem replacement, immutable provenance and exact success terminals.
  Actual retained-artifact admission, notarization and deployment remain pending.
  For artifact-only readback, the existing verifier accepts the app plus
  `--retained-admission`, `--retained-sha256` and `--identity`; it requires the
  ordinary current-receipt environment. Packaging accepts the first two optional
  arguments alongside its existing six required options. Keep the manifest,
  retrospective observation and verification reports private and independently
  reviewed; do not generate claims of original build success from these inputs.
- The first source-bound release build exposed a packaging-parser defect: real
  codesign emits `CodeDirectory v=...`, not the fixture's `CodeDirectory=...`.
  The corrected UTF-8 parser preserves singleton-field checks and requires the
  numeric runtime bit, exact runtime label, no ad-hoc flag, and a nonblank secure
  timestamp. Its new actual-format/ambiguous-record tests fail against the old
  parser; the corrected producer suite passes 39 cases/654 assertions under C
  locale. Read-only checks also pass for all 14 real candidate code members and
  its app signature. Native strict signature and Developer-ID checks are unchanged.
  The preceding `e98e6c5` checkpoint passed all 26 offline stages (413 Mac,
  27 shared signaling, 429 Simulator passes/22 physical-only exclusions, Rust and
  driver checks), but that receipt is not release authority for the parser edit.
  The failed candidate is retained, not deployed or relabeled as verified.
- The existing mandatory release runner now includes the catalog/menu/lock and
  updater suites plus named packaging-contract and shared-signaling phases; no
  second release pipeline was added. All 27 current shared tests are required,
  including when both discovery and result logs omit the same case. Gate
  self-tests pass 53 cases/763 assertions. The actual selected Mac run passes
  413 cases with no skips/failures, and replay validates the real 27 shared and
  35 packaging cases. Both release hooks and product identity checks pass.
  These focused results are not the final 26-phase source-bound receipt.
- Catalog-aware updates require candidate schema v2 and a sealed exact-integer
  catalog1 marker, bound by the signed full-app tree. A signature-positive v1
  candidate is rejected before binding/install even with the maximum build number.
  83 focused Swift cases and 35 producer cases/602 assertions pass. A negative
  fixture caught plist-to-JSON coercion of real1 to integer1; original plist type
  checks now reject it in both XML and binary form. No signed native update trial
  has been performed. An old binary installed outside this updater is not made
  catalog-safe by this change.
- The host catalog is now wired through bootstrap, reconnect and the menu's
  explicit pair/select/confirmed-forget actions. The menu receives bounded labels,
  phone IDs and exact revision/selection tickets, not trust keys. Stale dialogs,
  capacity exhaustion, late completion and missing owner authority cannot replace
  a current pairing. Existing SwiftUI content and the narrow AppKit shell remain.
  Phone changes wait for primary-session quiescence and exact old transport close;
  independent audio shares are not stopped. No installed pairing has been changed.
- `mac-phone-catalog-integration-4-restored.log`: 89 XCTest and 27 shared signaling
  tests pass. Removing the concurrent-close joins made five exact delayed-close
  regressions fail; the corrected files were restored to their original hashes
  and the affected integrated suite passed again. The first attempt's two test
  calls to an internal cross-module initializer failed compilation and were fixed
  to use the public canonical wire initializer; that failure log is preserved.
- Fresh signed Simulator audio run `beluga-catalog-simulator.gaZ7Pu`: 429 passes,
  zero failures, and the exact same 22 enumerated physical-only skips. Independent
  xcresult and app signature checks pass. This is not physical microphone, pairing,
  two-Mac behavior, or the complete source-bound release receipt.
- Native Android format-check preview is committed separately: 19 model tests and
  79 shared protocol assertions pass, including a strict offline repeat. This is
  not authenticated Android pairing/media; see `ANDROID_CLIENT_PLAN.md`.
- Fresh initial feed-fetch/parse failure now has a guarded completion path after
  the exact one-shot native error acknowledgement, matching abort/idle-finish
  callbacks, no candidate admission or installation activity, continuous
  ownership, and unchanged predecessor. Standard Sparkle error UI is retained.
  A rejected candidate reentry invalidates even an already minted completion;
  Core rechecks immediately before removing the prepared marker.
  `mac-failed-initial-check-2.log` passes 348 focused tests, including 13 new
  cases. The first run's throwing-test-closure compilation failure is retained;
  the explicit do/catch regression now counts only actual rejection. No signed
  native update or error dialog has been exercised.
- The preceding clean `e2e3766` checkpoint passed all 24 phases of the full
  offline microphone gate: 241 Mac tests, 429 Simulator passes with 22 explicitly
  enumerated physical-only exclusions, Rust and native driver checks. Receipt
  verification passed before the next source edit. That receipt is historical,
  not release authority for the later updater or Android changes; a fresh final
  source-bound gate remains required. No physical-device/runtime proof is implied.
- Release-preparation checkpoint: fresh initial-check Cancel and exact
  notDownloaded Skip/dismiss now have a reason-bound unarmed completion path.
  The actual protected UI intent, native manual-cycle callbacks, unchanged
  predecessor and exact prepared record must all agree. Interrupted/resumed,
  armed, failed and restored attempts cannot use it. The later feed-error source
  checkpoint above supersedes this gap; native validation is still outstanding.
  No install or release is claimed.
- `mac-unarmed-decisions-2.log`: 335 focused Swift tests pass and the executable
  links. The first run retained two failing tests: a singleton masquerading as a
  different item and an unintended repeated-admission rejection. The fixture now
  proves distinct identity; safe same-item admission stays idempotent but cannot
  supply fresh unarmed-retirement evidence. Branding fixtures pass, including
  exact new compatibility contexts and rejection mutants. Staged secret scanning
  passes with only exact public-key/tool-checksum exceptions; changed values and
  a wrong-path copy are rejected. Detailed paths remain in the private ledger.
- Latest checkpoint: the menu's in-process Sparkle controller has been replaced
  by an authenticated client and the separate `BelugaUpdater` product/entrypoint
  now compiles and links. Private control/readiness endpoints, verified outside-app
  staging, ordinary-lock reacquisition, exact predecessor-broker persistence,
  actual installed callback/readback and new-menu process-generation/readiness
  are connected in source. No signed update operation has yet been run.
- Normal no-update retirement is separate from installed completion: only explicit
  controlled-history admission, one fresh exact paired native SDK completion,
  no arm/resume/candidate path, unchanged signed predecessor and exact prepared
  snapshot under continuous ownership qualify. Signed ownership-protocol1 is a
  broker-only producer contract beginning at build100, not a high-build or absent-
  marker inference. The checked repository release inventory was empty; tracked
  pre-updater source `168036d` contains no Sparkle. Unknown distributions refuse
  enrollment. The clean release producer now guards the source lineage and forbids
  in-process Sparkle imports/startup, with an explicit mutation regression.
- `mac-broker-composition-4.log`: 320/320 focused Swift tests pass, including the
  new controller, endpoint/bootstrap/drain, persisted broker identity, native
  readback and controlled no-update paths. The actual broker executable linked;
  its help-only smoke exited0 without an update operation. Dependency readback
  confirms broker Sparkle and no LiveKit. Review fixed the terminal acknowledgment
  race by waiting for bounded EOF after authenticated receipt, not a sleep or
  another ack cycle. A post-clear receipt failure cannot reverse verified clearance.
- `mac-broker-composition-producer-1.log`: 31 Ruby cases/548 assertions pass.
  Product identity passes in `product-identity-broker-composition-2.log`; the first
  invocation used the wrong shell and is retained as failure, not pass. Fifteen
  package-input cases pass in `testflight-package-broker-composition.log` after
  exact current-manifest repinning. Historical cache provenance remains unchanged.
  Composition runs1–3 retain, respectively, a C-name import error, a test-expression
  compiler diagnostic, and a mutation fixture that accidentally supplied unchanged
  bytes. None is counted as passing evidence. No signing, installer/host launch,
  phone, audio route, production deployment or release publication occurred.
- Earlier component checkpoints below are historical; their then-missing executable,
  endpoint and menu wiring are superseded by the latest checkpoint above. Positive
  signed native replacement and recovery gates remain open.
- External-updater packaging, private staging and authenticated communication are
  now source-tested components, not a launched updater. Packaging defines the
  distinct nested `BelugaUpdater.app`, its own complete Sparkle closure, fixed
  code/alias/dependency inventory, sealed matching release configuration, empty
  entitlements and inside-out signing. `mac-broker-producer-1.log` passes 30 Ruby
  cases/540 assertions. The builder now expects the `BelugaUpdater` product;
  its executable target/entrypoint and menu integration still must be supplied
  before running a release build. The old in-process menu controller remains.
- `BelugaUpdateBrokerArtifact` verifies/copies/re-verifies the exact signed broker
  into a fresh private operation directory outside the app. Root/parent identity,
  bounded no-follow copying, full tree/executable/native CDHash and sealed config
  are checked. Failed copies remain retained, never reused. Positive policy tests
  use unsigned private fixtures with explicitly injected signature evidence; no
  signed staging or launch was performed. Extended metadata, Gatekeeper and
  notarization are not inferred from this copy.
- `BelugaUpdatePeerIdentity` binds public kernel audit tokens, exact process
  generation/path, UID and dynamic Developer-ID role/team/CDHash. The canonical
  operation/channel-bound protocol rejects replay, role confusion and malformed
  frames. The real local-socket channel bounds I/O, refuses concurrent calls,
  supports cancellation without recycling another owner's fd and reauthenticates
  around each frame. `close()` requests cancellation, not worker completion; native
  Security calls remain synchronous. A wire readiness value is not authority.
  Integration still needs private endpoint discovery and exact new-menu readiness.
- `mac-broker-staging-ipc-3.log` passes 170/170 affected Swift tests, including
  22 real private-socket cases, 16 peer-identity cases and 14 staging cases. Native
  wrong-executable rejection and Security requirement syntax are exercised; this
  is not a positive signed cross-process handshake or old-to-new update. Review
  fixed native/wire role confusion and unbounded lock queueing. The earlier C-macro
  compile failure and Foundation `/private/tmp` canonicalization fixture failure
  remain separately recorded in runs 1 and 2, not reported as passes.
- `mac-broker-staging-core-build.log` passes the independent core build. The new
  public BSM dependency has an exact current package-manifest pin; product identity
  and 15 TestFlight package-input cases pass in `product-identity-broker-ipc.log`
  and `testflight-package-broker-ipc.log`. Historical cache-enrollment pins are
  unchanged. Logs remain under `<private-release-evidence>`.
- Installed-byte readback is now implemented as an unwired core component.
  `BelugaUpdateBundleTree` reproduces the package producer's full-tree format with
  bounded descriptor-relative reads, no symlink traversal and mutation checks.
  Ruby and Swift share a literal Unicode/escaping golden vector.
  `BelugaUpdateInstalledArtifact` uses local native Security verification, exact
  Developer ID Application/team/bundle identity, hardened-runtime flags and sealed
  metadata, bracketing it with equal tree observations and context revalidation.
  Exact expected version/build/executable/tree are checked independently of SDK
  completion. `mac-update-installed-readback-3.log` passes 105/105 affected Swift
  tests; `mac-candidate-producer-2.log` passes 25 cases/468 assertions. Initial
  imported-flag compiler failures remain preserved. Review corrected the leaf
  certificate class to match the distribution policy. Native unsigned-fixture
  rejection is proven; positive signed replacement/live readiness is not.
- Signed-candidate metadata now connects the distribution producer to the updater
  session. The producer derives executable/full signed app-tree hashes from the
  verified app, compares the final mounted DMG, and emits strict versioned metadata
  before whole-feed signing. The session requires positive signature status and
  the exact fresh manual-admission object; cached/resumed items and premature
  ready/retry cannot authorize installation. `mac-update-candidate-integration-2.log`
  passes 77/77 affected Swift tests; `mac-candidate-producer-1.log` passes 24 Ruby
  cases/467 assertions. The initial singleton-fixture failure is retained separately.
  Independent source review found no blocker in this slice. These checks did not
  start an updater or sign, install or publish an artifact. Production wiring,
  signed broker staging, authenticated readiness and native replacement remain.
- Broker lifetime and namespace are implemented as unlaunched shared components.
  The core builds independently in `mac-update-broker-core-build.log`.
  `mac-update-broker-driver-3.log` passes 148/148 focused tests, including 18 broker
  and 15 namespace tests. A separate run of the registered session suite passes
  18/18 in `mac-update-sparkle-session-2.log`: real private lock/store composition
  proves publication before fake SDK startup and durable arming before an install
  reply. No-update/cancellation do not clear the record. Review caught and fixed
  a cross-thread status-read deadlock and a post-clear result regression; both have
  bounded regressions. The adapter's reentrant tests now use weak actor-isolated
  references rather than mutable captured variables.
- `BelugaUpdateDriver` owns the supported, inert-until-start Sparkle composition.
  It binds callbacks and the verified target feed to the exact updater instance,
  disables automatic checks/downloads, gates installation and target termination,
  and reports completion only as an observation. Tests also assert the actual
  public Objective-C selectors without constructing an updater. Its initial test
  file was outside a registered target; it was moved into `CaptureServerTests`
  and the separate 18-test result above confirms execution. Earlier compiler-error
  logs are retained, not reported as passes. This is not a native SDK, signed
  replacement, installed-app or deployment result. Production broker executable,
  signing/staging, installed verification and authenticated readiness remain unwired.
- The Driver-target extraction has a new exact package-manifest pin. The product
  identity check and all 15 actual TestFlight package-input behavior cases pass in
  `product-identity-driver-extraction.log` and
  `testflight-package-driver-extraction.log` under the same private test directory.
  Historical encrypted-cache enrollment pins remain unchanged. The earlier broad
  381-case product-identity fixture run was deliberately stopped (exit 143) before
  changing its inputs; its partial `product-identity-core-fixtures.log` is retained
  and is **not a passing suite**. The scoped Swift results above cover this checkpoint.
- The follow-on shared-core extraction and guarded user-driver changes passed
  115/115 focused tests in
  `<private-release-evidence>/mac-update-core-adapter-1.log`.
  This includes 19 fake update-dialog callback tests, the real shared-lock tests,
  private diagnostics ACL regressions and the migration source contract. The core
  builds without CaptureServer/Sparkle/WebRTC. Install choices and termination
  retries now require an explicit synchronous authorization callback; stale,
  duplicate, reentrant or post-cancellation replies cannot start installation.
  The future broker still must supply real durable publication to that callback.
  No native updater or replacement was launched.
- Product identity and 15 current TestFlight package-input cases passed after
  binding the extracted package manifest; old cache-enrollment provenance was not
  repinned. Branding fixtures pass with an exact Mac rendezvous-key/value allowance.
  The broad tracked-tree branding audit is **not green**: its initial run reported
  96 unmatched compatibility tokens, 95 already present in HEAD at those paths.
  The one new Mac configuration-address match is now narrowly covered; the older
  matches still need review before release, not a blanket exception or renaming
  shipped compatibility IDs. Logs are under the same private test directory.
- Durable updater storage, canonical app/account binding, lock-before-read runtime
  admission and public installed-callback adapter: 58/58 focused tests passed in
  `<private-release-evidence>/mac-update-durable-fence-5.log`.
  The new app's direct CLI and normal runtime now honor unresolved-update records
  under the same retained host lock. Menu SDK startup is deferred until an explicit
  owned check. These are private-fixture tests, not a signed native update; the
  external broker, durable publication before SDK startup, unarmed retirement and
  authenticated post-replacement readiness remain release blockers.
- Added-scope foundations: 35 focused Swift tests passed in
  `<private-release-evidence>/mac-phone-catalog-update-policy-3.log`:
  21 in-memory host phone-catalog tests, 13 pure updater-operation policy tests,
  and one shared invitation-fixture test. The catalog preserves original bytes,
  has explicit selection, rejects stale writes/counter regression and retains an
  authoritative empty catalog. It is **not wired to production callers**;
  `macOS/BelugaHost/PAIRED_PHONE_CATALOG_INTEGRATION.md` records migration ordering,
  async fences and catalog-unaware downgrade restrictions.
- Android protocol foundation: dependency-free JVM invitation/QR parser compiled
  with installed `javac 26.0.1 --release 11 -Xlint:all -Werror`; three shared fixed
  vectors and 79 assertions passed. Swift independently generated those codes
  from the same fixed test-only secret bytes. This is not an Android app, SDK
  build, connected-phone test, full pairing handshake or media proof.
- Signed Simulator QR/catalog/pairing-persistence suites: 66 tests passed in
  `<private-release-evidence>/ios-pairing-bound-recovery.xcresult`.
  This is not a physical camera or two-Mac connection result.
- Integrated Mac menu/update/QR/sharing/lifetime suites: 99 tests passed in
  `<private-release-evidence>/mac-share-integrated-6.log`, including
  the real native send-only offer and bounded fake-source/fake-recipient lifecycle tests.
  The UI regression waits for committed actor state instead of XCTest's nested asynchronous
  waiter path, which reproducibly crashed the test runner; all three UI tests now pass.
  After the sticky installer fence added four more regressions, all 20 focused update
  policy/ownership tests passed in `mac-update-armed.log`. The coordinator's 21 tests passed
  with the final native-oracle build in `mac-share-oracle-rebuild.log`.
- Additive Worker/browser suites: 67 and 23 tests passed respectively, including global
  creation/active grants, cumulative issuance, bounded queues, expiry, targeted retirement,
  and actual-playback versus connected-transport presentation. The two changed sharing
  Worker suites were rerun after the browser protocol correction: 33/33 passed in
  `worker-stereo-protocol.log`; browser evidence is `browser-stereo-negotiation.log`.
  Production sharing is disabled.
- Native-to-Chrome final-sample oracle: PASS twice, including final harness version in
  `<private-release-evidence>/native-browser-8.json`. Three epochs proved
  real native Opus encoding and browser stereo decoding at 48 kHz, same-link rejoin,
  revoke and fresh-link expiry; native source listeners retired and both sources stopped.
  Browser microphone requests were zero; owned child processes/groups were reaped.
  This uses explicitly synthetic fixture PCM and a loopback broker, not the deployed
  Worker, system-audio tap, a physical phone, TURN, or unrelated-network connectivity.
  It exposed and fixed a real Window-timer receiver error and a missing `stereo=1`
  receive preference; `opus/48000/2` alone had produced mono. The earlier zero-sample
  failure was a harness mismatch: the probe now plays an audio element like the product,
  under the same no-hardware-output browser flag, beside its zero-output waveform probe.
- Offline packaging contract tests: 19 tests, 398 assertions passed for the dedicated Mac
  feed and receipt-bound compiler/environment selection. Fifteen iOS package-input validator cases passed; the actual archive resolver graph
  still needs positive proof. No archive, notarized artifact, upload, or installed-app proof.
- Sparkle update key was created in local Keychain account `beluga-mac-updates` using the
  byte-pinned official 2.10.0 tool. Only its public key is in Release.json. No private export.
- Existing notarization profile `opensteamer-production-v7` authenticated read-only; this is
  not submission/acceptance of the new Mac client. Separate Belugatime releases are unrelated.
- Cloudflare read-only authentication check reported an expired, unrefreshable login.
  Publishing browser sharing requires the user to renew it. No backend was deployed.

First-release limitations to state explicitly: the phone-microphone endpoint requires its
separate driver setup on a new Mac; this DMG never installs a privileged driver. In-app update
checks are currently admitted before Start Beluga, not while the host remains started (even
idle). The UI must not imply that a download or a negotiated peer proves actual audio playback.

## Remaining performance and updater proof boundaries

- WebRTC encoding and network sends use separate native queues, so a slow remote network
  receiver is not synchronously awaited by the source callback. The borrowed callback still
  visits native sinks serially; local CPU or native-lock contention can delay the next sink.
  Eight listeners at the configured 192 kbit/s each means 1.536 Mbit/s of payload before
  packet overhead/retransmissions, not a measured throughput or latency guarantee.
- The listener cap and absence of an application PCM FIFO do not prove hard bounds on every
  native WebRTC queue. Before claiming eight-listener performance, measure 1/4/8 native peers,
  callback percentiles against source frame intervals, CPU/RSS growth and sender/receiver stats
  with one impaired listener, separately verifying the phone stream's continuity.
- In-app update verification must include another process holding the shared host lock, not
  only the current menu process's state. Retaining that lock during the update cycle protects
  admission through installer stage 2; the interval after Sparkle terminates the menu process
  and before replacement/relaunch still needs an old-to-new process-ownership test. No safe
  complete self-update or production publication is claimed from the unit policy tests.

## Next checkpoint

- Keep the failed native/browser runs 1–6 and passing runs 7–8 as separate evidence; do not
  rewrite old results or substitute mock transport for the decoded-stereo criterion.
- Close the Sparkle installer lifetime gap using supported external-updater APIs before
  considering the client distribution-ready. The reviewed proposal is in
  `macOS/BelugaHost/UPDATE_BROKER_DESIGN.md`; no broker or
  installer has been launched and no source-bound release receipt has been produced.
- After source and packaging freeze, run the mandatory microphone-regression release
  gate against the exact committed candidate before a release build/sign/upload.
- Renew Cloudflare login, then validate sharing-specific TURN/abuse limits and deployed
  protocol behavior; do not reuse the phone's TURN authority or enable sharing prematurely.
