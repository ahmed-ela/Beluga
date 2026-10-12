# Beluga Mac client — release and migration ledger

Current baseline: Mac 0.3.1/build102 is released; the user reports that it works.
The Rust migration below is new source work, not a deployed replacement. Earlier
dated checkpoints retain their original proof limits and are not current release status.

## Mac release candidate 0.3.2/build103 — 2026-10-12

The user authorized checkpointing, PR squash merge after validation, and Mac
distribution. This candidate is not yet built, notarized or published. Apple Silicon
Macs on macOS 14 or newer are the current supported installer target; Intel support
is not claimed. Browser-sharing and Android delivery remain paused.

The existing signed stable Sparkle feed and separate authenticated updater broker
provide in-app **Check for Updates**; users do not need to reinstall from GitHub.
Checks and installation remain user-initiated and require idle admission; automatic
checks/downloads and silent replacement during streaming are not enabled. The real
old-to-new installed update rehearsal remains explicitly user-deferred, not passed.

The migration checkpoint includes the reviewed Rust/native adapters and immutable
component test evidence. The two production adaptation-owner gates remain false;
the full rewrite and installed/physical qualification are not declared complete.
Current gate source seals were reviewed against their exact predecessors and
updated for only three additive dormant/helper changes. Historical maps, mandatory
case/control inventories, signed Simulator requirements and receipt checks remain
unchanged. The final combined source-bound release gate is still required.

## Rust migration goal — 2026-10-06

The authorized goal is a behavior-preserving Rust rewrite of product core logic,
not a claim that rewriting syntax fixes lifecycle bugs. Native SwiftUI/AppKit,
AVFoundation, ScreenCaptureKit, Keychain and existing WebRTC bindings remain thin
platform adapters while their policy and transaction ownership move into Rust.
The live host, pairing records, phones and audio routes are not development targets.
Browser-sharing and Android delivery remain paused; preserve their protocol compatibility.

2026-10-11 latest offline checkpoint: ordered manual SDK-check admission in the
actual updater session now uses the two-phase Rust ABI. Native authority can
synchronously reenter; the pending request is read afterwards and denial/refusal
cannot erase a nested admitted cycle. Full Rust865, offline packaging134/30,946
assertions, and genuine-SDK actual-source XCTest59 pass. All17 compiled Rust
controls and two compiled Swift controls fail their mapped ordinary assertions,
then exact restored methods/full59 pass. The official four-target artifact is
enrolled recoverably (source `dd60f870...`, artifact `090ee0fc...`). Evidence:
`/Volumes/t7/beluga-updater-sdk-admission.20261010.sAzLJU`.
This is offline/fake-effect policy proof, not native SDK installation, a whole
current Package pass or deployed upgrade. The combined gate's stale source/case/
mutation/marker inventories are being enrolled before final validation. Remaining
adaptation/audio/handoff policies, native/installed proof and final release remain
open; all seven top-level workstreams stay active. No commit/push/deployment or
live host, phone, pairing, credential or route changes follow from these tests.

2026-10-09 source checkpoint: the real Swift full179 owner capture and closed
zero-clock Rust proposal boundary are now enrolled. Original native clock/route
sidecars and dependency producers are retained; malformed, refused, or re-entrant
results cannot escape as accepted replacements. Eleven new regression methods,
including an independent complete capture golden and 54 malformed-result cases,
compile against the actual CaptureServer module. They have not been executed.
The checked-in Rust framework is aligned to the already verified current source
artifact (manifest `cd930fa1d34c385d13cd0df03ee0d42f7235164a6d24500ca1aeee81be37e133`);
the predecessor is preserved outside the checkout. This is an unwired foundation,
not a second live owner or completed migration. Remaining work includes the full
clocked/lifecycle ABI closure, one authoritative service storage/publication path,
native regression execution, and release validation. No installed app changed.
Compile-only evidence: `/Volumes/t7/beluga-owner-codec-compile.20261009-20261009-64846-sasyba/COMPILE_ONLY_RECEIPT.md`.

2026-10-09 next source checkpoint: the public clocked Owner boundary now covers
exactly 202 and 212–218 using the retained typed implementation, not a new reducer.
All 745 ordinary Rust source tests pass, including 18 newly discovered complete-
Owner clocked methods, with zero ignored or filtered cases and a natural exit 0.
The constrained test environment now explicitly binds the pinned rustdoc; the
preceding harness failure remains retained. This changes the source epoch, so the
prior zero-clock artifact receipt above is not evidence for the added ABI. Fresh
packaging/C/Swift smoke qualification, native clocked import and sole live state
publication remain pending. Review also identified the post-ACK108 stale-owner
and refusal-cleanup seams as prerequisites to live wiring; neither is solved by
these source tests. Installed apps, phones and routes remain unchanged.
Evidence: `/Volumes/t7/beluga-owner-clocked-source-tests.20261009-20261009-70113-i31233/SOURCE_TEST_RECEIPT.md`.

2026-10-09 clocked source/library checkpoint: exact source manifest
`ccda3d13235ad536d78e5696e935b1ddfbee07d58c7c104f2aa47e68003e6e74` passes
745 ordinary Rust tests (18 clocked methods; no ignored/filtered cases),125 offline
packaging tests/8955 assertions, and six ordinary assertion-failing clocked mutation
controls with six exact restored passes. Valid-input201 denial closes the prior
null-pointer test blind spot; non-1 provider returns0/2/MAX are covered without
conflating valid reply correlation with callback success. The failed initial
packaging sandbox envelope is retained; only the fixture's prescribed internal
scratch prefix and `/dev/null` were admitted on the passing retry.

The existing offline producer built all four Rust release targets. Staged and final
artifacts passed exact native-member/inventory/source/header/metadata verification,
both official Owner symbols and all six private-symbol refusals per architecture,
standalone Mac C/Swift executions and iOS-device/Simulator cross-links. The current
source framework is now aligned to artifact manifest
`ac946ce2c4f6063199d33bddb75ea31ce207c3e90076b7c050c133b1ad546c96`;
the prior `cd930fa1...` framework is byte/mode-exactly preserved outside the checkout.
This is NOT an installed update or a completed Rust migration. No native actor test,
physical/Simulator app, host, pairing, credential or audio route was changed.

The clocked Swift adapter and all live publication cuts remain unwired. Source
review confirms108 must gate the original native attempt/sink/latch ownership
AFTER irreversible ACK and BEFORE fresh current Owner capture/adoption. Full179
equality across the ACK await is not an ownership proof: a legitimate same-attempt
routeChanged event can advance revision/route evidence. Successful ACK also revokes
the original probe, so post-ACK admission cannot require its pre-ACK validity.
Fresh same-frame tuple checks, producer-origin/callback custody and mandatory
refusal cleanup remain separate implementation/verification gates.
The frozen source-only108 prerequisite is
`/Volumes/t7/beluga-native-owner-prepare-raw-author.PwHK6W/next-owner-fallible/product-owner-clocked-lifecycle-proposal/POST_ACK_OWNER_ADOPTION_PLAN.md`,
SHA-256 `23efb95ba8a3a3573591e341e07a73b40bc73316313ce4d05071e08d4269e8c9`.
It is design evidence, not an applied live fix or an executed actor test.

Evidence: `/Volumes/t7/beluga-owner-clocked-source-tests.20261009-20261009-74217-1co2d52/SOURCE_TEST_RECEIPT.md`,
`/Volumes/t7/beluga-owner-clocked-artifact.20261009-20261009-78434-16li0zc/ARTIFACT_BUILD_RECEIPT.md`,
and `/Volumes/t7/beluga-owner-clocked-vendor-promotion.20261009-20261009-79984-1m4n5h1/VENDOR_PROMOTION_RECEIPT.md`.

2026-10-09 native clocked source checkpoint: the SAME copied-value boundary now
imports202/212–218 with lazy original-cut reads, shared cross-family reentry
poison, actual Instant receipts and complete179/13-time/whole-route recapture.
Its native RTT factory seals default versus injected producer origin; queue/RTT
imports retain immutable profiles and sticky faults. Independent review exposed
an invalid-healthy-RTT import hole, now rejected through the existing pure RTT
opcode3 validity contract without querying a retained producer, sampling a clock,
or adopting that predicate's transformed state. A named regression covers ten
forged healthy fields and retained malformed faulted words.

The actual79-source CaptureServer module emits, and24 ordinary XCTest methods
(11 zero-clock,13 clocked) TYPECHECK against that fresh module. NO tests were
executed or discovered. The compiler's C-thunk conversion issue and the first
retry's stale-module search precedence were corrected; both failures are retained.
Rust source/library manifests remain `ccda3d13...`/`ac946ce2...`, so unchanged Rust
jobs were not rerun. This is still an UNWIRED source foundation: same-frame actual
publication, native execution, failure-prefix/mandatory cleanup and all remaining
writer/await families are separate gates. The host, apps, pairings and routes are
unchanged. Compile-only receipt:
`/Volumes/t7/beluga-owner-clocked-codec-compile.20261009-20261009-88285-1jqtp1t/COMPILE_ONLY_RECEIPT.md`.

2026-10-09 public501 source/library checkpoint: genuine full-Owner preparation is
now one official ABI over the retained implementation. All seven caller outputs
remain unchanged on denial; completed-None preserves correlated outcome and actual
read transcript while leaving state, edits and origin journal empty. Fresh source
manifest `56dbafd86f9ab333f0ab3352aef467c744e76fd36cd7c1f0e995207c8e9b8224`
passes757 ordinary Rust cases (198 library, including12 new preparation and18
clocked methods; no ignored/filtered cases) and125 offline packaging tests/10314
assertions. Four preparation and six clocked deliberately broken implementations
each fail an ordinary assertion after compiling; all ten exact restored singletons
pass. Existing test discovery is exactly retained plus the twelve new methods.

All four Rust release targets built. Staged/final artifact verification checks
three official/seven forbidden private symbols per architecture, native archive
members, exact inventory/source/header/metadata, actual standalone Mac C/Swift
executions and iOS-device/Simulator cross-links. Source Vendor now contains
artifact manifest `f9b56f5f00cafc9957781bffd04eaee51def546420562f2ad97279086a0d1309`;
the predecessor `ac946ce2...` is byte/mode-exactly retained outside the checkout.
This is NOT installed deployment or full migration. Native Report/Instant/route
custody, complete regular diagnostic/Set-origin goldens, Prepared sealing,
authoritative single-tuple publication and remaining writer/await families are
still pending. The preceding native24-method typecheck receipt belongs to its
older Rust library epoch and is not execution evidence for501. No host, installed
app, phone, pairing, credential or audio route changed; no commit/push occurred.

Evidence: `/Volumes/t7/beluga-owner-prepare-source-tests.20261009-20261009-94458-1ghapgy/SOURCE_TEST_RECEIPT.md`,
`/Volumes/t7/beluga-owner-prepare-packaging-tests.20261009-20261009-95499-1h9y71d/PACKAGING_TEST_RECEIPT.md`,
`/Volumes/t7/beluga-owner-prepare-mutations.20261009-20261009-96757-1dtl4w5/MUTATION_RECEIPT.md`,
`/Volumes/t7/beluga-owner-prepare-clocked-mutations.20261009-20261009-97172-4v9b4k/MUTATION_RECEIPT.md`,
`/Volumes/t7/beluga-owner-prepare-artifact.20261009-20261009-97745-r0tw1j/ARTIFACT_BUILD_RECEIPT.md`,
and `/Volumes/t7/beluga-owner-prepare-vendor-promotion.20261009-20261009-98947-1p73b81/VENDOR_PROMOTION_RECEIPT.md`.

2026-10-09 native501 telemetry-copy checkpoint: the actual sender-report's
nativeSnapshot now copies into the public192-byte report POD without clock,
producer or resource authority. Whole Optional routes, absence versus present
zero, IEEE/u64 payloads, native UTF8 packing and original UTC identity are
retained. Six new ordinary XCTest methods cover a full31-field handwritten
golden and the route/optional/UTF8/timestamp boundaries. All79 actual CaptureServer
sources emit; all30 codec methods (11 zero-clock,13 clocked,6 report) TYPECHECK
against that fresh module and the qualified501 header. They were NOT executed
or discovered. Rust source/Vendor manifests remain `56dbafd8...`/`f9b56f5f...`;
unchanged Rust jobs were not rerun. Actual native entry factory, read permission,
Prepared custody, whole-owner publication and native/release execution remain
pending. No installed app, host, phone, pairing, credential or route changed.
Evidence: `/Volumes/t7/beluga-owner-prepare-report-compile.20261009-20261009-1728-izqbgi/COMPILE_ONLY_RECEIPT.md`.

2026-10-09 public601 source/library and common-guard checkpoint: genuine inactive
Owner adoption now uses the retained typed implementation through the fourth
official ABI. Expected revision, Prepared-origin distinctions, suspension counters,
and refusal publication are covered. One additional full222 regular terminal-fault
golden preserves its complete output/read/time transcript; its synthetic minimum
was corrected from999 to80 without changing expected outputs. Smoke assertions
explicitly retain demand fault140: their zero-read/nonzero-counter result is not
credited to queue fault41 alone. Original private proposal evidence is retained.

Current source manifest `c7d03fb3731fd5b6c6784494d967533374928e2cd50f8c1e90b72c6088c9ce2a`
passes770 ordinary Rust tests (211 library;13 preparation,12 inactive adoption,
18 clocked;31 cohorts; zero ignored/filtered). Discovery is exactly the retained757
plus13 new methods.125 offline packaging tests pass11717 assertions, with no skips,
failures or errors. Four inactive, four preparation and six clocked deliberately
broken implementations compile and fail ordinary assertions; all14 exact restored
singletons pass. Their210 filtered library cases are singleton mutation selection,
not filtering in the770-test full suite.

All four Rust release targets built, with exact staged/final archive-member,
inventory/source/header/metadata checks, four official and eight forbidden private
symbols per architecture, four actual standalone Mac C/Swift smoke executions,
and12 iOS-device/Simulator cross-links. These links are NOT device execution.
Candidate/source Vendor artifact manifest is now
`02b4d0bb4a15b257aa8757dfbbf157f2893cfaee57c1acc2c482ca012b4ccf57`.
The predecessor `f9b56f5f...` was independently rehashed and retained byte/mode-exact
outside the checkout. This is a SOURCE library promotion, not installed deployment.

The native Owner codec now has one closed private common guard for busy/poison,
invocation and defer ownership; existing held worker bodies and callback retirement
order remain unchanged except the scoped invocation. Current codec digest is
`d9e52748fb56ed786bdf205dcd6692db9d3ba7897eb211c0f0eb8fa68288c3a3`.
All79 actual CaptureServer sources emit and all30 ordinary codec XCTest methods
TYPECHECK against the new library and fresh module. NO XCTest discovery, loading,
execution, actor effect or live Owner adoption occurred. Caller value arguments
remain pre-evaluated: this guard is not the actual native entry capture/publication
factory. That factory, full222 importer/Prepared sealing, native producer/read
custody, sole immutable service Owner storage/publication, every writer/await and
post-ACK cleanup seam, native regression execution and release validation remain.
No installed app, host, phone, pairing, credential or audio route changed; no commit,
push or deployment occurred. Current source menu audit found visibility depends
only on successful startup; missing readiness/target disables instead of hiding.
The user's installed menu behavior has not been independently reproduced/read back.

Evidence:
`/Volumes/t7/beluga-owner-inactive-source-tests.20261009-20261009-52580-1j4jjj1/SOURCE_TEST_RECEIPT.md`,
`/Volumes/t7/beluga-owner-inactive-packaging-tests.20261009-20261009-55009-um6h2j/PACKAGING_TEST_RECEIPT.md`,
`/Volumes/t7/beluga-owner-inactive-new-mutations.20261009-20261009-56433-n5t51h/MUTATION_RECEIPT.md`,
`/Volumes/t7/beluga-owner-inactive-mutations.20261009-20261009-57337-pq7gz/MUTATION_RECEIPT.md`,
`/Volumes/t7/beluga-owner-inactive-clocked-mutations.20261009-20261009-58648-sphuat/MUTATION_RECEIPT.md`,
`/Volumes/t7/beluga-owner-inactive-artifact.20261009-20261009-60261-1uof8ta/ARTIFACT_BUILD_RECEIPT.md`,
`/Volumes/t7/beluga-owner-inactive-vendor-promotion.20261009-20261009-64809-skwic1/VENDOR_PROMOTION_RECEIPT.md`,
and `/Volumes/t7/beluga-owner-inactive-guard-compile.20261009-20261009-65699-3qthy5/COMPILE_ONLY_RECEIPT.md`.

Post-checkpoint resource admission: fresh `/Volumes/t7` readback has1,509,244 KiB
available, below the unchanged next compiler planning reserve of1,667,172 KiB
(512 MiB safety floor plus1,142,884 KiB measured compile allowance). No further
compiler job or unqualified native storage patch was started at that capacity.
Retained evidence and shared dependency caches were not deleted. The goal remains
active/incomplete; this environmental gate does not establish a product failure or
authorize cleanup, installed changes, or weaker validation.

2026-10-09 native single-Owner storage checkpoint: the actual service now stores
one immutable native OwnerValue for policy/revision/fast flag/lane/evidence Instant/
freshness minimum/applied recommendation. The seven prior names are get-only views,
not setters or stored mirrors. All83 original individual writer statements remain
83 separate full-tuple assignments at their original cuts; unchanged members come
from the then-current tuple, not a whole Owner saved across an await. The two
constructor defaults, min-only freshness semantics, every original await, negative
failure prefix, native output/applied ordering, irreversible ACK and mandatory
cleanup order are retained. Main and two independent source reviews matched the
38-hunk projection; a peer also inverted/replayed the enrolled bytes exactly.

Service source `00ba8150...` is now
`dc263f94ab0ae7a896f1236906d90d7b96b44f57ddc900185051b7b8ead6c18f`.
Codec `8df3a5e36816413874c92a8ff6eb8b464686d86b376e9dd56f6b05b301898dae`
changes only its first-line comment from `d9e52748...`; proposal code remains
unwired. All79 actual CaptureServer sources emit and all30 existing codec methods
TYPECHECK against the fresh module and unchanged qualified Rust library. No XCTest
discovery/loading/execution, native actor effect or Rust Owner adoption occurred.
Source/library manifests stay `c7d03fb3...`/`02b4d0bb...`; unchanged Rust jobs were
not rerun. This is actual authoritative native storage preparation, not a completed
Rust rewrite. The known original post-ACK success mutation preceding its fresh
ownership gate remains uncorrected and is a separate required integration repair.

The compiler scratch parent moved to the internal workspace volume, whose fresh
capacity exceeds the SAME1,667,172 KiB planning reserve; the SAME512 MiB runtime
floor and deny-all-writes-except-work/network-denying sandbox remained. All source,
artifact and dependency reads on `/Volumes/t7` stayed read-only to that job. No
retained evidence/cache was deleted, no new runner/controller or cold SwiftPM build
was introduced, and the old `/Volumes/t7` capacity observation above remains
historical rather than a current all-volume blocker. Fresh input pins all match;
both compiler phases ended naturally with empty logs, no signal/guard and exit0.
Receipt: `/Users/ahmed/Documents/Codex/2026-08-24/do-x20/beluga-native-owner-storage-compile.20261009-20261009-73114-144adal/COMPILE_ONLY_RECEIPT.md`.
Actual native entry capture/read permission, full222 import/sealed Prepared custody,
public501/601 publication, all Rust writer/await families, native execution and release
validation remain. The full goal stays active; no host, app, phone, pairing,
credential, audio route, commit, push or deployment changed.

2026-10-09 native Owner regression compile successor:24 DEBUG-only observation
lines add checked-Sendable, actor-local readback through the actual Owner getter.
The existing inert/resource-nil guard remains; no setter, stored mirror, clock,
producer, native effect or original writer was changed. Current service is
`38004bae4dcdff8b718ba70152200b07ab16f85fd85026bf9d54b5b22207b196`;
codec stays `8df3a5e3...`. Two ordinary source regressions use the unchanged,
explicitly injected BatchAActualServiceFixture for both constructor profiles,
real stop and repeated stop, with closed gates, local input unchanged, no listeners
or retained cleanup jobs. Their assertion bodies have not executed, and initially
empty fields do not discriminate every reset or populated native sidecar.

Session57206 compiled all79 actual service sources with natural exit0, then FAILED
the32-method test typecheck: the new test omitted its explicit CaptureCore testable
import. Original103-pin input map and failure diagnostics remain. Root repaired
only that import, retaining every assertion. Session8376 consumed natural exit0
after reusing the same freshly emitted module under exact unchanged source/fixture/
artifact/dependency pins; only the pinned test import changed. The new107-pin
map additionally binds that module and the retained old map/emission/failure logs.
Those107 explicit pins are not an exhaustive compiler dependency trace; retained
dependency modules were reused rather than freshly rebuilt. No full dependency
rebuild or release-gate credit is claimed.
All32 methods TYPECHECK, zero discovery/load/execution. This is not a native test
PASS, assertion-failing mutant, source algorithm change or deployed repair.

Receipt: `/Users/ahmed/Documents/Codex/2026-08-24/do-x20/beluga-native-owner-inert-compile.20261009-20261009-85112-kzgasl/COMPILE_ONLY_RECEIPT.md`.
Reused module `55f30e6d...`; input map `27b2bccd...`; ordered digest `b3f30cd1...`.
The same serial lock, planning/runtime reserves, phase deadline and compiler
sandbox remained. No cleanup, new runner, cold SwiftPM build or unchanged Rust
test rerun occurred. Existing native runtime/load-set admission, full222/import/
Prepared/publication, all owner writer families and post-ACK/release/physical
proof remain required. The full goal is ACTIVE; no installed host, app, phone,
pairing, credential, route, commit, push or deployment changed.

2026-10-09 native terminal501 source integration successor: main and two independent
reviews rejected the original08ff source packet before enrollment because invented
startup166/slot5 mutations could pass a full222 recapture. Frozen v2 f3ec9185 fixes
that gap by correlating the original cached native startup predicate to exact166
and Retain/Clear slot5. Eleven additive ordinary regression methods include both
forgeries, demand-only terminal success, queue-only zero-additional-clock/raw
refusal, full54 diagnostic/IEEE fidelity and common-guard poisoning. The invalid
demand projection is actual failure evidence, not a fabricated valid result or an
actor-state seed. No new arbitrary policy seed or runtime permission was added.

All six source postimages exactly match frozen PINS15ed09c6; independent inverse
and callsite audits pass. The existing common guard body is byte-unchanged. The
actual actor-file entry captures original peer/capture/source/sink/tokens/visibility
and Owner/report/native timers inside that synchronous guard, before the explicit
policy clock. It validates full222 and constructs a sealed one-use UNPUBLISHED
receipt. The closed terminal-fault/no-origin Regular501 seam has declarations only:
no event callsite,601/active continuation, native effect or live Owner publication.

Root session47348 naturally compiled all79 actual service sources and TYPECHECKED
43 ordinary methods, with empty logs/no signal/guard. All103 explicit input pins
were independently rehashed; they are not an exhaustive compiler dependency trace,
and retained dependency modules were reused rather than rebuilt. No discovery,
XCTest loading/assertion execution or native test PASS is claimed. Rust c7d03fb3
and artifact/Vendor02b4d0bb remain unchanged; their prior qualified cohorts were
not rerun for this Swift-only source epoch. Same serial lock, planning/runtime
reserves,600-second phase deadlines and compiler sandbox; no cleanup/cold build.

Receipt: `/Users/ahmed/Documents/Codex/2026-08-24/do-x20/beluga-native-terminal-prepare-compile.20261009-20261009-94358-vb688c/COMPILE_ONLY_RECEIPT.md`.
Module `c644f76e...`; input map `684b52af...`; ordered digest `65b91a50...`.
Service `a682b763...`; codec `ad0a15c4...`; Owner codec tests `75905855...`.
Actual factory/receipt currentness/one-use behavior, reachable active-startup and
nine-timer histories, status3–5 native refusals, runtime/load-set admission,
publication/all writer/await families/post-ACK cleanup and full release/physical
gates remain. The existing nil-peer inert fixture cannot supply genuine bound
terminal/native peer authority. The full goal stays ACTIVE; no installed host,
app, phone, pairing, credential, route, security, commit, push or deployment changed.

### Common publication and source-oracle successor — 2026-10-09

SOURCE / COMPILE-ONLY checkpoint; full Rust rewrite remains ACTIVE and undeployed.
The common guarded zero/clocked publication transaction is now in the codec, with
one existing held scope spanning admission, capture, genuine Rust production/import,
full currentness recapture and a sole callback-free store. Its release slot remains
uninhabited: this does not convert any of the actual actor's 83 stored-tuple cuts.
Prepared receipts now strongly retain the exact originating Boundary and reject
wrong-owner use by identity, still consuming the use before rejection. This closes
a future address-reuse custody gap; it was not an observed live-app failure.

Nine additive Owner-codec XCTest methods cover transaction deltas, lazy clock cuts,
complete payload/guard/generation admission, stale and bit-identical ABA, swallowed
cross-family reentry, malformed/public refusal, producer retention and guard lifetime.
The fixture's stored tuple/witness is simulated, not actual native resource authority.
Separately repaired seven existing source-string methods in four test files to require
complete seven-field Owner stores while preserving their original order/forbidden-action
assertions. All 101 methods remain, plus two inert String discriminator methods.
Independent review rejected the first patch's incomplete initializer anchors before
enrollment; the corrected v2 had 17 full-line matches and byte-exact inverse projections.
Both frozen packets remain separate evidence; no assertion execution or mutant credit.

Root serial session 29910 ended naturally at exit 0: all 79 actual CaptureServer
sources emitted fresh DEBUG and no-DDEBUG modules; all 155 selected test methods
typechecked against the fresh DEBUG module. Zero methods executed, zero discovery,
zero native effects. No-DDEBUG is the same -Onone conditional compile recipe, not an
optimized/signed packaged Release build. Its one 918-byte unreachable warning is
expected because release cannot construct the publication slot. Retained dependency
modules were reused; this is not a fresh full SwiftPM build or complete dependency trace.

Receipt: `/Users/ahmed/Documents/Codex/2026-08-24/do-x20/beluga-owner-publication-compile.20261009-20261009-10163-1jp6u76/COMPILE_ONLY_RECEIPT.md`
(SHA `0cf035395eae2c1746233a274df35bfd4dcbea8f30c6f3ceb586c51d902c24e1`).
DEBUG module `099176854c32ba02698385a21d2932fb1d8354ee53d4013dad0e35ec9dff92f5`;
no-DDEBUG module `038a504cc9fad5298a1b554aae533b3c765ce28f8e49ee3ba125d89e47171f4b`.
Input map `95b2a8b423684c16e628072634f13c8d5c7824bf1eb7a93a05437faa22c35dbd`;
ordered digest `7d97c68dcac95fa5e0c985c34f7f9583b26b53a0c67422fdd682af1329ce6050`.
All 107 explicit pins were freshly rehashed after terminal. Codec `9f70cae51d58b7ee531c10ec5675472395eac2ad657598de7ba39051ed0053ab`;
Owner tests `48b81ab70589dc1a3de5e5610823900ecf9615c2d95d52c565fed7133db25883`.
Service `a682b763...`, Rust source `c7d03fb3...` and artifact/Vendor `02b4d0bb...`
are unchanged; earlier qualified Rust/packaging/mutation cohorts were not rerun.

The exact existing serial lock was naturally released and rechecked available;
no owned job remains active. Existing planning/runtime reserves, phase deadlines
and network/write-denying compiler sandbox were retained, with no cleanup or cold build.
Behavior execution still needs a current source-bound linked test artifact and separately
qualified loader/discovery. The existing incremental full-build recipe is available,
but its staging/cache custody and complete reserve calculation differ from this compile-only
admission; monitoring routes alone cannot establish loader inertness. Actual cut-specific
witnesses, all writer/native/await families, fresh post-ACK admission, mandatory cleanup
independent of Rust refusal, sidecar-specific negative coverage and full release/physical
gates remain. No installed host/app/phone/pairing/credential/routes/security, commit,
push or deployment changed. Do not claim migration completion from this checkpoint.

Migration stages (do not mark the whole goal complete after the first stage):

- [x] Handoff menu admission (source/core/adapter checkpoint only): one Rust policy shared by actual menu enablement and
      tests; retain the button when session authority disappears, with a disabled
      explanation. Preserve exact-target dispatch and phone-confirmed Mac Pause.
- [ ] Handoff transaction reducer: exact owner/operation, fixed deadline, one-use
      consumption, confirmation and cancellation. Differential event traces against
      the current implementation must cover replacement and late-result races.
- [ ] Pairing/catalog/session core: durable replay counters, independent availability
      versus media ownership, bounded admission and exact-generation retirement.
      No Keychain migration or wire-format change as a rewrite side effect.
- [ ] Media selection/commands and network adaptation: preserve sticky source selection,
      native readback, acknowledged Show ownership and the visible video floor.
- [ ] Audio lifecycle/control core: preserve immediate microphone privacy-stop,
      exact native activation ownership, conditional input restoration and unchanged
      outputs. Keep real-time callbacks allocation-free and bounded.
- [ ] Updater transaction core: signed artifact/source binding, quiescent admission,
      exclusive replacement, exact rollback and irreversible-commit semantics.
- [ ] Remove superseded Swift business logic only after each production Rust call path
      passes its parity gate. Native wrappers and third-party runtime behavior remain
      separately audited; the Rust compiler cannot prove those foreign contracts.

Each stage requires discovered non-skipping Rust tests, exhaustive small-state or
property/event-sequence tests, assertion-failing negative mutants, and tests through
the actual compiled C ABI and production Swift adapter. Unknown ABI/input values fail
closed. Source and checked-in libraries are manifest-bound; release validation must
reject stale or unbound artifacts. Keep the existing independent native, Simulator,
physical and release gates, and add race/sanitizer/fuzz coverage where the migrated
boundary introduces memory or concurrent ownership. No deployment claim from a
successful reducer test or archive.

Released-menu diagnosis: the released menu conditionally removes the entire handoff control
when `connectedMediaTarget` is nil. The coordinator ties that target to its generic
`sessionPrepared` presentation phase, so an availability retry can hide it while the
separate media lifetime survives. This is source-confirmed; the user's external Mac
has not been observed at that exact transition. Stable presentation is separate from
authorization: unavailable or replaced sessions must still refuse dispatch.

Current source repair (not released): menu readiness now follows the retained,
prepared concrete media owner rather than the availability presentation phase.
The target is issued only after startup and authenticated response-send return;
each concrete service receives a fresh owner nonce, including same-exchange
replacement. It is retired before stop/query suspension, while uncertain native
teardown still retains the service. Exact paired-record, catalog, service and
generation guards remain mandatory. The control stays visible with a disabled
explanation when there is no current target. This does not grant transport health
or bypass source readback, phone confirmation, or native microphone policy.

Current Rust build profile is Mac arm64, iOS device arm64 and iOS Simulator
arm64/x86_64. Native Intel Mac support is not advertised. Cross-linking the phone
archive is distinct from signed Simulator execution and physical-phone behavior.

### First Rust checkpoint — 2026-10-06

The production Mac package now links the new `BelugaCore.xcframework`. Rust owns
handoff menu admission and the worldwide host lifecycle reducer; the former Swift
lifecycle transition implementation has been removed. Availability and media owners
remain independent. Swift is a copied-scalar/String bridge, preserving its existing
canonical Unicode equality and each owner's original identifier spelling.

Verification: 15 Rust tests pass together; all 126 focused Mac integration tests and
all 470 discovered mandatory Mac regression tests pass with zero failures/skips.
Actual archive C and Swift link/execution oracles pass, and five independently broken
source variants fail their intended behavioral assertions. Release-gate self-tests
pass 72 cases/1,388 assertions; they now require the core's exact source/artifact
manifests, pinned link tools, test discovery and negative mutations. An independent
read-only review found no concrete must-fix for this slice.

Evidence is retained in `/Volumes/t7/beluga-rust-integration.S3img9` and the new
crate's ignored `target/review-evidence.VV4nIc` directory. This is not a full release
receipt, deployed menu/pixel proof, physical handoff proof, or completion of the whole
Rust rewrite. Mac 0.3.1/build102 and the running host remain unchanged. Next: migrate
transaction ownership without weakening phone-confirmed exact-source Mac Pause.

### Shared Rust handoff ledger — 2026-10-06

The production `WebRTCTransport` host/viewer transaction slots now use the same
`BelugaCore` archive on Mac and iOS. The old Swift transaction reducer is removed.
Rust owns bounded admission, exact opaque-token matching, cached reply conflicts,
receipt retirement and unknown cancellation/expiry outcomes. Swift retains at most
the two original native values, preserving UUID/String equality, Unicode spelling,
NaN behavior and exact native execution revocation. It validates copied-output
custody before consuming effects; malformed results cannot manufacture a successful
Pause or silently discard an owned receipt. No native Pause executes in Rust.

Each of the three slices packages the static archive inside a namespaced
`BelugaCore.framework`; its module map is under `Modules/`, not a shared global
include output. This corrects the actual Simulator build collision with the existing
audio-authority library without repackaging that independent library. The artifact
is bound to the exact crate inventory, manifests and pinned tools. C and Swift
execute the Mac archive's transaction ABI; both languages also
cross-link against the actual device and two Simulator architectures. Ten new Rust
ledger tests include 85 reachable scalar states with 2,890 transitions and 20,000
churn events. Six additional compiled behavioral mutants must fail their intended
assertions. The release gate now also requires the discovered shared handoff tests,
production bridge differential/Unicode/value-copy/custody tests, real ordered-channel
peer cases and signed Simulator operation/WK/audio-lease tests without new skips.

This checkpoint migrates the bounded ledger, not the full handoff stage: offer
authority and deadline policy are the next slice below; phone player operations
and provider readback still need separate migration and native proof. The existing immediate microphone-stop,
privacy, exact-source Pause and release gates remain mandatory. This source change
does not install a new Mac or TestFlight build or prove physical transfer.

The ledger's fresh canonical offline gate passed all 32 phases, with 470 Mac,
54 shared handoff, 27 shared signaling, 25 product-core Rust and 35 existing audio
Rust tests. The signed development Simulator passed 487 tests with the same 22
physical-only exclusions. Native driver, sanitizer, signing and artifact checks
also passed; the independently verified receipt and local checkpoint `f302411`
are retained in `/Volumes/t7/beluga-rust-handoff.9PynxC/RESULTS.md`. This is source
evidence, not deployed or physical handoff evidence.

### Shared Rust one-use offers and timelines — predecessor checkpoint

The old production Swift offers/timeline reducer is removed. The additive copied
ABI now puts sequence floors, original deadlines, freshness, position/rate drift,
independent sent/received slots and pre-validation retirement in Rust. The native
adapter retains only the two original payloads and exact UUID/String primitives;
actual supplied receipt validation, original spelling and native value copies
remain intact. Clear does not reset replay counters, tokens never recycle, and
malformed copied effects close authority without manufacturing playback or Pause.

The local `c81566c` checkpoint passed the complete 32-phase canonical offline gate:
44 product-core Rust tests, 27 compiled behavioral mutants, 470 Mac tests,
84 shared handoff tests, 27 shared signaling tests and 35 legacy audio Rust tests.
The signed Simulator passed 487 tests with the unchanged 22 physical exclusions;
native, sanitizer, signing and artifact checks passed. Thirty new Swift methods compare the
original reducer over 14,425 bounded traces and 8,192 seeded events, cover numeric,
Unicode, receipt-copy and exhaustion boundaries, and test legitimate and malformed
copied-result patterns. Two compiled native bridge mutants failed their intended
assertions and exact source restoration passed. The independently audited receipt
is retained in `/Volumes/t7/beluga-rust-offers-integration.8O1zib/RESULTS.md`.
This predecessor evidence does not cover the subsequent phone-operation source;
the complete gate remains mandatory on its final source and promoted artifact.

### Rust phone playback operation — source implementation, not released

The original phone-operation Swift reducer is replaced by the bounded Rust policy;
request validation, strict provider codec, exact native UUID/proof equality and
WKWebView/audio/session ownership remain native. A copied ABI preserves original
Double bits, observed-clock ordering, irrevocable proof invalidation, one pending
pause reservation, reply expiry and truthful known/unknown Mac outcomes. Native
copied-result validation closes authority on malformed data without inventing Pause.

Private preparation passed 32 Rust tests (19,200 independent-reference steps) and
an actual linked C ABI probe. The unchanged nine Coordinator tests passed a fresh
signed Simulator baseline before migration. Twenty new native tests retain a
frozen original Swift reference, 1,944 bounded traces and 8,192 seeded events;
the original 17 operation tests, four WK boundary tests and all nine Coordinator
tests remain mandatory. The produced Mac/device/two-architecture Simulator core
passed actual C/Swift link checks and independent artifact review. Its production
adapter passed all 50 focused signed Simulator tests with zero skips/failures.
Two compiled native identity/custody mutants failed their intended assertions;
the restored controls passed and every source byte was restored. Evidence lives
in `/Volumes/t7/beluga-rust-phone-operation.D09uv7/RESULTS.md`.

The final-source 32-phase canonical gate is required before this checkpoint can
be committed or released; the focused proof does not substitute it. This is not
real YouTube, actual Mac Pause, physical-phone or deployment proof. The broader
Rust rewrite remains incomplete; pairing/catalog/session policy is the next seam.

### Latest local policy checkpoint and menu regression coverage — 2026-10-07

Local invitation-acceptance checkpoint `38948b256aa352236877560b3d741de023c5afac`
is predecessor evidence. The subsequent prepared-media menu repair is preserved in
local checkpoint `40a4c8bfb62d4d78ca28af8e18d38b8b2c54e1a4`. Its own complete
38-phase canonical offline gate passed on source
`27fc9e0d663440dc8e1caf138352f829644cc9f52d44c3abd94e650031801c63`;
the receipt was independently verified and audited. Retained receipt:
`/Volumes/t7/beluga-mac-client-microphone-gate.kKuACR/validation-runs/microphone-20261007-49631-1vzwmqd/receipt.json`,
SHA-256 `257d06dd677f6b89775965d01747618704e6667fa286095799fda5e36933f275`.
This records a local source checkpoint, not a new release or deployed behavior.
Subsequent replay source cannot borrow this menu receipt.

Prepared-media repair adds 17 tests through the actual coordinator and menu with
genuine cryptographic pairing/reconnect records. Together with the existing menu
and coordinator suites, 62 focused tests pass. They cover availability-only churn,
startup/send suspension, same-exchange replacement, stale requests/results, late
completion, replay/forged requests, uncertain native stop, shutdown and exact
microphone snapshot forwarding. Both stop and completion-query barriers are held
to observe revocation before either cleanup path returns. Compiled negative
controls restore the old phase rule, reuse a service nonce, and delay both cleanup
revocations; each failed ordinary assertions for its intended defect. The new
class and all 17 methods are mandatory release-gate pins, not optional fixtures.

This is offline source/adapter evidence, not a live reproduction on the user's
Mac, a physical phone handoff or deployment. Selective bounded reducer slices
are implemented, but the broad handoff and pairing/catalog/session stages above
remain incomplete. Native provider readback, playback confirmation, persistence,
cryptography, microphone/audio ownership and release effects retain their
independent gates; the full Rust rewrite remains active.

### Signaling replay policy — local source checkpoint verified

The production replay window now uses the bounded Rust policy through a copied
24-byte state/32-byte result ABI. Rust owns the optional highest sequence, the
64-packet reordering bitmap and accepted/duplicate/outside-window decisions.
Zero is a valid first sequence; the direct reducer's UInt64 maximum and ages
63/64 are boundary cases, not a change to existing outbound or wire limits.
Native Swift validates exact input/output correlation, stores only a valid
copied successor, and preserves value-independent copies. A malformed initial
value is retained verbatim with sticky closure; malformed steps retain the exact
previous state. Neither silently retries from or resets to an empty window.

Authentication, key/credential ownership and decoding remain native. The actual
receiver opens/authenticates and decodes before replay admission: AEAD failure
or undecodable plaintext does not burn a sequence. The pairing/availability
clients still commit replay admission before their later native payload semantic
validation; a decoded but semantically rejected payload can therefore burn its
sequence, preserving the original ordering. Observer fixtures read the actual
stored state after commit or refusal; they do not grant reset authority or prove
signed reconnect acceptance.

Reset ownership is unchanged and native: pairing resets after a validated
opposite-role departure; availability resets for a valid local-role Ready
(including repeated same-exchange Ready), and for an opposite-role departure
bound to the current exchange. Wrong-role inputs and departures for a foreign
exchange must not reset the stored window. Other receivers gain no new reset
path. There is no Rust
credential, Keychain, wire-format, persistence or native runtime-effect migration.

The focused native inventory preserves 56 cases: the unchanged Crypto9 and
Rendezvous19 suites plus 28 new Swift Testing methods (native bridge19, genuine
AEAD/decode3, durable parser/reset/order6). The updated full gate separately
enrolls those three new suites with exact source/discovery/result identities.
It also requires all 119 product-core Rust cases, 53 compiled Rust behavioral
mutants (the prior42 plus new11), exact source/artifact manifests, and the seventh
actual C/Swift replay link contract. These are required inventories, not a claim
that the current 119/53 or full 41-phase gate has passed.

The candidate's build/link and retained artifact audit passed separately. A
fresh focused native invocation passed all 56 named cases before and after
restoration; eleven compiled controls failed their intended ordinary assertions
for copied-output custody, sticky closure, actual stored commit/observation order
and exact native reset scopes. All three restored body objects match the baseline
byte-for-byte. Retained native receipt:
`/Volumes/t7/beluga-replay-integration-draft.bI4qL7/native-controls/native-replay-controls-20261007-85316-y09pw9/receipt.json`,
SHA-256 `b497bd7c921aedd0f2338eb6de73074bd4a1a7d0820319f64bf6af80d93f2ab8`.
The reviewed helper enforces original object timestamps; copied-file timestamps
are not independent original-stat evidence. The final replay source subsequently
passed all 41 offline phases, 119 Rust cases and 53 compiled intended mutations.
Receipt `microphone-20261007-92351-12cvl2j/receipt.json` under the dedicated cache's
validation-runs has SHA-256
`796b2bbfc1a381a5a061d7b475e2d36fed1e6cee20d21e72e74e3bdf23b99989`.
Mandatory verification and two independent retained audits passed before the
local checkpoint `7ff3c776e4b49c992f75dd0ef5f5a19a3466e420`.
This is not hidden-unobserved-initializer, physical phone, live connection,
media transfer or deployment proof. Changed catalog source cannot borrow that receipt.

### Catalog checkpoint admission — preceding validated source checkpoint

The eighth Rust policy now proposes one-Add/exact-Update admission and terminal
revocation through an 8-byte state, 16-byte event and 12-byte result. Native code
retains the actual reference class, NSLock, three complete UUIDs, owner callback,
full snapshot and concrete catalog store. Revoked writes do not call the owner;
bound Add still does before refusal. Readback loads fresh storage first and may
recover the exact pair after revocation or owner loss.

Copied candidates are validated before effects and installed only after a store
call successfully returns. A thrown storage error is propagated unchanged and
does not precommit binding/state; write-then-throw divergence is not rollback.
A malformed bridge leaves a sticky write denial without erasing known bindings.

Actual Rust execution passed 127 nonignored tests, including all eight new
independent-reference cases. The four-target static artifact passed actual Mac
C/Swift probes and device/Simulator cross-links, independent retained audit, and
source-only promotion. Focused native execution passed 113 concrete in-memory
catalog/host cases, including all 18 new checkpoint tests. A test-only typed
catalog fixture preserves exact canonical storage encoding; production validation
is unchanged. These focused receipts do not replace fresh compiled native
assertion controls, signed Simulator coverage or the final full regression gate.
The final unchanged catalog source subsequently passed nine compiled native
assertion controls and all 41 offline phases. Receipt
`microphone-20261007-29130-1u93t2y/receipt.json` under the dedicated cache has SHA-256
`08622fcd1de4fbd11e5886b40098b8fd9d189c98efba6622c0ff5efef657ee66`;
mandatory verification and independent retained audits passed before local
checkpoint `ee12ba8ff9462d95b2a33615376d9fc4b93daab8`.
Deployment remains pending. Pairing
catalog persistence, asynchronous generation ownership and the full product-core
migration remain incomplete; no installed host or phone is changed here.

### Durable reconnect counters — source integration and focused validation

The ninth typed Rust policy proposes outbound increment/exhaustion and inbound
strictly-newer high-water admission through copied 24/16/32-byte values. It has no
stored ledger or initializer. Native record schema, activation/identity guards,
request authentication, original constructors and durable-before-send ordering
remain unchanged. Copied candidates are validated before construction and only
the relevant counter commits after success; sequence-zero constructor failure
still leaves the record unchanged. Twelve Rust tests include independent numeric
expectations and 37,050 modeled success/failure traces; 27 new native tests use
actual C exports and genuine synthetic signatures/key agreement. All 139 current
product-core Rust cases passed. The official four-target XCFramework candidate
passed C/Swift interface smokes and was promoted into source only, with its prior
dependency preserved. Device/Simulator crosslinks are not physical execution.

The native 27 cases plus all 9 original pairing cases pass. Eight deliberately
compiled native counter/authentication-order breakages fail their intended ordinary
assertions; both original production objects restore byte-identically and all 36
cases pass again. Retained receipt `native-reconnect-counter-controls-20261007-68729-1wq29dp/receipt.json`
has SHA-256 `66bb60892fec027fa338b5f494f30581d234bac921b4e9ae774c60295ea2d953`.
The initial failed fixture run remains preserved: explicit UInt64 bounds and
separate validation of randomized CryptoKit signatures correct the test assumptions,
without changing product code or accepting mismatched signed transcripts.

Four new genuine coordinator/storage fixtures cover no-write failure versus actual
write-then-throw durable burn and cold retry. They are enrolled in the whole Mac 508
and separate signed inert-root pairing 106 inventories. The 115 parser self-tests
pass, including rejection of multiline declarations. Fresh complete 42-phase
validation is still required for this changed source; the prior 41-phase receipt
cannot be borrowed. Pairing commit/recovery, media arbitration and other product
lifecycle policies remain to migrate. No host/phone installation, push or deployment
is performed here.

### Pairing commit and recovery — tenth source integration, not released

The ninth checkpoint subsequently passed all 42 source-bound offline phases and
was committed locally as `2e3b5871049ca66e08969831b3c6bace23ca3bac`. Its receipt
SHA-256 is `321597bb1e097833f8ce34c938da20009dd85f5bfcee97647e5f4448f10cb3be`.
That receipt does not authorize or validate the tenth changed source.

The tenth bounded Rust policy owns pairing-commit admission/recovery decisions
through copied 24/16/40-byte values and one stateless C export. Native identity,
authentication, opaque signed/MACed commits, Codable schema, counters and storage
effects remain platform adapters. Cached acknowledgements still authenticate the
new proposal first; completion-send does not activate; activation retires recovery.
Malformed copied output fails distinctly rather than taking a successful Swift
fallback. The original two durable host ACK cuts and post-send owner fence remain.

Focused execution passed 159 ordinary Rust cases and built the official four-target
dependency with C/Swift runtime smokes on Mac and iOS crosslinks. Only the source
dependency was promoted; the prior dependency remains retained. Native tests then
passed 29 genuine-crypto/actual-C cases, five real coordinator ACK persistence
cases and two concrete Mac decoder cases. Isolated byte backends distinguish
no-write failure, write-then-throw and actual cold readback, not power-loss proof.
A per-call throwing preconstructor probe is a boundary/error-order fixture, not an
actual CryptoKit constructor failure. Denial-only immutable decoder selection
cannot return a candidate, survive in decoded records or modify stored bytes.

The final test fixture follows Foundation's Sendable userInfo contract without
removing malformed-type controls. Candidate-roundtrip and Viewer store/bootstrap
composition are additionally enrolled. The tenth checkpoint subsequently passed
the complete 43-phase gate and independent audits and was committed locally as
`1f66f784533f67053800077e5eea1ae10bea37a3`; receipt SHA-256 is
`8948a80d52b9a924a73ee1a66311db1e52bd438807d318d0acb5a57e4e0d556d`.
It is not proof for the changed eleventh source. Browser sharing/Android delivery
remain paused. Neither checkpoint represents an installed-host/phone update or
full migration completion.

### Supported-player arbitration — eleventh local checkpoint, not released

The two-provider browser/Music selection policy now uses a stateless Rust reducer
through copied 20-byte input and 16-byte output values. It preserves the original
first-playing-provider hold, browser-before-Music fallback, selected paused source
and retry behavior. Native discovery, media snapshots, opaque handoff descriptors,
publication identity, queued commands, authentication and platform effects remain
native. The original fetch-epoch guard runs before projection and the C call.
Invalid current copied output retires publication authority, retains the selection
hold and returns one distinct throttled diagnostic; no successful Swift fallback.

Actual focused execution passed 17 Rust cases (48 literal choices, 720 single-field
and 4,320 two-field invalid trials) and 34 Mac cases through the real C boundary:
20 new arbitration/lifecycle/corruption tests plus 14 unchanged selector regressions.
The official four-target source dependency was built and promoted locally; Mac
C/Swift smokes executed and three iOS target links passed, not physical execution.
The first native build exposed a test-local generic-inference error; evidence was
preserved and explicit Bool specialization passed the fresh attempt. No product
assertion was removed. Gate parser self-tests passed 133 cases/15,179 assertions.

The fresh canonical gate passed all 43 phases: 176 core tests, 35 microphone Rust
tests, 111 compiled intended Rust assertion controls, 550 Mac cases/139 critical,
516 signed Simulator passes plus unchanged 22 physical-only exclusions, and 108
inert pairing cases. Independent terminal audits and current-source receipt
verification passed. Three native compiled controls failed only at their intended
ordinary assertions, followed by exact source restoration and 34 passing tests;
the other nine planned native controls are not claimed as executed.
Local commit is `11b68c2608bfc6b6cbb613365c7ff8fbee5da442`; full-gate receipt SHA
is `2baeb14171e64c59c812eb466ff990470cf3432190f33dce04beccf416677bb7`.
That receipt binds the predecessor's exact source, not this changed documentation
or subsequent batch. Crosslinks/isolated driver loading are not physical or
installed HAL proof; only six pairing phases retain equivalent process sidecars.
Detailed progress and terminal evidence are retained outside source in
`/Volumes/t7/beluga-supported-player-validation.TLmvsI/RESULTS.md`. The installed
Mac menu transition, physical phone behavior and deployment remain unverified.

### Connection/recovery batch — source integration in progress

Four small policies are being migrated together: availability retry, safe-output
attempt budget/cooldown, system-audio start/resume, and hosted-call scalar
observation/evidence/peer-generation admission. Availability source integration
is present, with actual-C-first fault tests and real supervisor exit observation.
All four copied Rust policies/exports and real native actor callers are now
source-integrated. Forty actual-crate focused tests passed (15 availability,
11 safe-output,4 system-audio,10 hosted-call), including independent malformed
constructor/peer fields. A fresh four-target library was built, its Mac C/Swift
smokes executed, and its three iOS crosslinks passed. It replaced only the source
dependency; no installed app was changed.

Actual native compilation and 47 focused tests passed, including the inert real
actor, callback joins and supervisor lifecycle. The first attempt exposed a
test-only duplicate-ready setup error; the corrected valid transition and a new
duplicate-ready regression passed without changing product code. Six compiled
native singleton controls failed exclusively at their intended ordinary
assertions. Two other controls produced mixed assertion/timeout or unexpected
error results and are explicitly not credited as clean kills. Exact full source
restoration was checked; a fresh restored-baseline run and full gate remain.

The expanded gate requires all 44 new native methods, 186 total critical Mac
methods, exact reviewed native bodies, and unchanged historical phases and
physical exclusions. Independent static review passed; fresh gate execution and
a new local checkpoint remain pending. Detailed receipts and preserved failures
are in `/Volumes/t7/beluga-batch-a-validation.5JlLEU/RESULTS.md`. Earlier focused
receipts do not bind subsequent gate/documentation edits or prove live effects.
No full-gate pass, new checkpoint, installed runtime or deployment is claimed.
Native sockets, timers, route transactions, authorization identity, callback
ownership, and observation high-water assignment before evidence-state rejection
remain native. A malformed bridge must never mint authorization or reset retry
state. Full product-core migration remains active and incomplete.

The first retained fresh full-gate attempt stopped at the identity mutation
phase's 1,800-second deadline; it did not produce a full-gate receipt or establish
a product assertion failure. A measured validator took 4.324 seconds, repeated
410 times by the unchanged mutation suite before fixture copying and behavior
checks. Invocation-local literal batching reduced the measured validator to
2.029 seconds. Every assertion still independently reads its file, retains its
diagnostic position, and fails closed on worker/protocol/read failure. Single-line
byte counting and the actual binary grep fallback remain separate from multiline
UTF-8 counting. No source-content or verdict cache, skipped mutation, enlarged
deadline, or live runtime change is introduced. The expanded focused suite also
found and reproduced a consecutive-newline binary-filename parity error; its
empty-field splitting is corrected. Fresh focused verification, independent
review and the entire unchanged full gate are still required. Evidence is in
`/Volumes/t7/beluga-identity-cost.FeTdwU` and the external batch ledger above.

### Calibrated tier demand — verified source checkpoint, 2026-10-08

Production adaptation now consumes the Rust-owned eight-tier demand profiles,
configured video/RTP ceilings, sustainable tier, initial tier and direct-upgrade
admission through the actual C exports and recomputing verifier. All eight cached
profiles publish atomically only after verification. Dynamic rejection is sticky
on the real owner and retires speculative permission without fabricating congestion.
Peer/Show identity, clocks, native encoding effects and microphone priority remain
native. Calibrated arithmetic, quality thresholds and latency tuning are unchanged.

Actual scoped execution passed 28 Rust tests, 12 compiled behavioral mutations
with each exact restored control, and a restored production Swift singleton after
an owned mutation produced 27 ordinary assertion failures. Fresh final startup
validation passed 377 deterministic methods and two independently fresh native
processes, with no failures/skips. The fake startup runner passed all 49 scenarios;
the final gate-verifier suite passed 196 tests / 47,923 assertions with no failures,
errors or skips. These are distinct proof layers, not a full release receipt.

The official four-target framework build passed the strict actual C23/Swift23
marker order and all three iOS crosslinks in both staged/final cohorts. Source
manifest SHA is `fb9145287d2e3c78fd51519d7b6edf9a0a5f5516babed5b29d48c1125d38a05e`;
artifact manifest SHA is `863df0b19d4f9d1ad1fa50ad6642a7fd72fa38b1579a542a4fc04021154dbd7d`.
Independent read-only audits verified manifests, actual copied native artifact,
anchored test inventories and unchanged predecessor checks. Earlier failed
attempts are preserved: a denied owner still aging RTT history, buffered test-log
interleaving, and misplaced C-smoke marker order. Their fixes did not weaken the
oracles or alter the calibrated policy.

The additive gate now enrolls 433 Rust tests, 411 mutation controls, 60 source
files, 46 runtime markers and 359 native IDs; all 43 historical product phases
remain. Only the scoped cohorts above are credited as executed in this checkpoint,
not the entire enrolled catalog. Evidence and retained failures are in
`/Volumes/t7/beluga-tier-demand-migration.IOsQ4v/RESULTS.md`.

At this dated checkpoint the queued-media command gate was still private design.
Its subsequent adoption and actual validation are recorded below.
The full rewrite and installed Move-media transition verification remain unfinished.
No new commit, push, app installation, runtime operation or deployment is claimed;
the installed Mac/phones and default audio routes remain untouched.

### Queued media-command admission — verified source checkpoint, 2026-10-08

The production native command owner now consumes Rust-owned lifecycle/command-epoch
wrapping and the complete six-operation gate through the actual C export and
recomputing verifier. The original native gate was independently frozen before
Rust authoring. Native NSLock ownership, Swift String/Set equality, original context
spelling, concrete provider, one-use claim, queue/deadline/readback and phone-confirmed
Mac Pause remain unchanged. A rejected copied result preserves the last verified
scalars and latches denial; it never resets or grants a replacement owner. First
denial retains native contexts; an already-faulted later close clears only that set.

Actual current-source verification passed all 454 Rust tests (24 suites), 136 focused
XCTest methods, and final startup's 392 deterministic methods plus two independently
fresh one-test native processes. All had zero failures/skips. The focused cohort
contains the 15 new actual-ABI/native-reference tests and retains all 71 Chrome,
30 system-controller and 20 prepared-menu integration tests. All 28 compiled Rust
behavioral mutants failed the mapped ordinary assertion and passed each identical
restored singleton. One compiled production Swift verifier mutant caused seven
ordinary assertion failures; the exact restored adapter passed that same singleton.
Compiler errors, deadlines, fake runs and Swift Testing's empty cohort are not proof.

The official four-target framework build passed both exact C24/Swift24 runtime-marker
cohorts and all three iOS crosslinks. Source manifest SHA:
`6fee0e9a5b9eafd774533db36876e3b9c1510e9e2eea4b864825cc897e262b31`;
artifact manifest SHA:
`429ea8e02c204e8ffb75b12e4eca69522e3b876e1a299b16091f60bcbb5cba6b`.
Current artifact readback and source/gate binding passed. The fake startup runner
passed 49 scenarios; the full gate-verifier fixture suite passed 202 tests / 50,304
assertions with zero failures/errors/skips. These are separate evidence layers.

Mandatory enrollment is additive: 454 Rust methods, 439 controls, 62 source files,
48 runtime markers, 51 native classes and 374 pinned native IDs; all 43 historical
product phases remain. The whole 439-control catalog and full product release gate
are not credited as executed here. Evidence, retained prior framework and exact
logs are in `/Volumes/t7/beluga-media-command-gate-validation.3o6xtL/RESULTS.md`.

The full rewrite remains active. Remaining Swift policy includes catalog mutations
and selection-generation admission, adaptation hysteresis/probes/recovery, screen
suspension transcripts, audio lifecycle/admission, native handoff timeline admission
and updater check/broker/Sparkle-cycle lifecycle. Existing Rust subreducers do not
make these owners thin adapters. The next whole-owner design freezes the complete
screen suspension/resume transcript and native protocol behavior. Suspension entry
is currently dormant: no service caller or enablement is part of that migration.

This checkpoint does not verify installed menu transitions or physical handoff and
does not deploy, install, commit or push anything. The live host, physical phones,
pairings, credentials and audio routes remain untouched.

### Whole screen-suspension transcript — verified source checkpoint, 2026-10-08

The complete nine-phase, 18-operation copied-scalar owner is now in Rust. The original
native owner was independently frozen before authoring. Rust owns phase, binding,
notice/generation admission, projections and custody actions through the actual C
producer and recomputing verifier. Native wrappers retain full immutable UUID/String/
protocol proofs, original validity/equality, and atomic successor-plus-custody publication.
Mutating copied-result denial preserves the verified snapshot and latches local refusal;
the original nonmutating queries deliberately refuse without poisoning the owner.
No reset, lossy identity, fallback grant or optimistic native effect was introduced.

Current-source verification passed all 486 Rust tests across 25 suites, the 32 new
actual-ABI/native-reference tests, and all original coordinator 9, commit-latch 3 and
shared protocol 10 tests: 54 focused XCTest passes, zero failures/skips. All 14 compiled
Rust behavioral mutants failed the mapped ordinary singleton assertion and passed each
exact restored control. One compiled production Swift query-verifier mutant produced
two ordinary assertion failures; the exact restored adapter passed the same singleton.
The first native compilation failed solely on two test-fixture qualification errors;
those errors and the failed log remain retained, uncredited and distinct from the
subsequent fresh passing cohort. No assertion or independent expectation was weakened.

Final startup validation passed 424 deterministic methods plus two independently fresh
one-test native processes with zero skips/failures. The 49 fake-runner scenarios passed.
The full gate-verifier suite passed 208 tests / 52,400 assertions with no failures,
errors or skips. The official four-target framework build passed exact C25/Swift25
runtime-marker order and all three iOS cross-links in both staged/final cohorts.
Source manifest SHA `d2476a34bd2d5a31baf954ffaad526752126e5ad4bcc5b483f432643a5e7cd5b`;
artifact manifest SHA `1398e08f02ae0485e46d205df453ca2a2c3ce6bd259aab3202f35e33a0698a2a`.
Final source/artifact readback and all 482 current startup source hashes passed.
These are distinct proof layers; cross-links and fake tests are not phone execution.

Mandatory enrollment is additive: 486 Rust methods, 453 mutation controls, 64 source
files, 50 runtime markers, 52 Mac classes and 406 pinned native IDs. Every previous
ordered prefix and all 43 historical product phases remain. Only the 14 scoped mutants
above—not the whole 453-control catalog or full product-release gate—were executed in
this checkpoint. Original coordinator/latch/protocol suites are source companions but
not new members of the 406-ID list; their separate 54-test execution is recorded above.
Evidence, exact logs and the recoverably retained old framework are in
`/Volumes/t7/beluga-suspension-transcript-validation.vm9MBK/RESULTS.md`.

Suspension entry remains dormant; this migration adds no service caller, activation or
live-runtime behavior. Installed Move-media transitions and physical handoff are still
unverified. The full Rust rewrite remains active. Next coherent owner: complete durable
catalog add/update/select/forget policy, preserving all eight slots, exact no-op/error
ordering, revisions, native storage/crypto and write failures. Private original preimages
and a proposed contract are retained at `/Volumes/t7/beluga-phone-catalog-mutation-design.3fDhoY`;
no concrete catalog ABI, new Rust implementation or reference derivative has been adopted.
Runtime selection-generation admission remains a separate next owner. Full adaptation,
audio lifecycle, native handoff timeline and updater check/broker/Sparkle-cycle ownership
also remain; their existing Rust subreducers do not finish those owners.

Nothing was deployed, installed, committed or pushed in this checkpoint. The installed
app/host, phones, pairing data, credentials and audio routes remain untouched.

### Durable phone catalog — scoped source checkpoint, 2026-10-08

The complete durable add/update/select/forget policy now uses the production Rust
owner through a 104-byte copied input, 72-byte copied result and exact recomputing
C verifier. The original source and unchanged 21-test catalog suite were frozen
before authoring. Rust owns ordered header/uniqueness/trailer/token admission,
duplicate-before-capacity and binding-before-counter decisions, monotonic pairing/
recovery/counters, all eight-slot custody plans, explicit selection, forget/reindex,
exact no-op admission and full-width revision exhaustion.

Native code retains the shared in-process NSLock, full UUID/Data/String and complete
record/catalog equality, signing keys and deployed crypto decoding, canonical JSON/
size/schema checks, migration receipt custody and actual storage writes. Invalid
copied results refuse effects without clearing retained custody or poisoning a future
valid operation. No keys, pairing schema, legacy bytes or wire format change; this is
not cross-process compare-and-swap or new live-connection authorization.

Actual scoped evidence: 27 new Rust integration tests passed; the complete 513-case
core cohort passed at historical manifest `79fc8948…` across 26 nonempty suites with
zero failures/ignored cases. Focused native execution passed 74 XCTest methods:
13 new tests independently derived from the frozen original native reference, plus
the unchanged catalog 21, checkpoint 18, menu 21 and bootstrap one. Genuine decoded
crypto records, complete snapshots/errors and exact persisted bytes are compared,
including error order, failed writes/write-then-throw, old-token retry/cold read and
two-instance serialization. All 72 result bytes are corrupted after the actual C
producer at every used stage; zero writes and original native custody are required.
In-memory backend coverage is not live Keychain or physical-phone proof.

All 21 compiled Rust behavioral mutants failed their intended ordinary singleton
equality assertion (natural exit 101) and each identical restored control passed
(natural exit 0), bound to historical manifest `0b701715…`. They were not rerun after
the subsequent Cargo-duration-parser-only change. A production Swift verifier mutant
(`== 1` to `<= 1`) compiled and produced 21 intended ordinary throws-assertion failures,
natural exit 1. The exact adapter was restored and its singleton passed one XCTest.
Empty Swift Testing cohorts are never credited.

The official four-target XCFramework passed staged and final C26/Swift26 marker
cohorts, native linking and three iOS cross-links, and was adopted recoverably.
Source manifest `bee25e51b2bf888c3ff5bd4611dd079d882a44515100134fc3d743ec87dbc3b8`
matches the framework; artifact manifest is
`de7a378ff43e9d25e6e753caeea1850481550645b4f3f43f8bc401b27a505aa0`.
Final source/artifact/native/link readback passed. Startup checks passed 498 deterministic
methods and two separate fresh-process native singletons; fake-runner checks passed
49 scenarios. All original eight gate prefixes and 43 phases/22 Simulator exclusions
remain; enrollment does not mean the whole product release gate ran.

The initial 215-test verifier run had four fixture-integration failures. Four
fixture-only corrections preserved generic discovery/refusal checks and exact actual
native inventories; focused 11 tests/4,202 assertions passed. A fresh full rerun then
had zero failures but one owned-process cleanup error. One diagnostic captured actual
post-KILL group EPERM followed by child/group ESRCH about 3.2 ms later, preserving the
original refusal/nil proof. The narrow reviewed repair allows indeterminate polling
only within the existing post-successful-KILL deadline for the exact captured group;
EPERM never proves absence. All initial, TERM, signal and final proof checks remain
fail-closed. Five new pinned controls plus the original four pass: nine tests/129
assertions, zero failures/errors/skips. The expanded full verifier rerun passed:
220 tests, 56,283 assertions, zero failures/errors/skips, natural exit 0; seed 55032,
629.492468 seconds. Both earlier full failures remain retained. Exact logs are
retained at `/Volumes/t7/beluga-phone-catalog-validation.cp3A2U/RESULTS.md`.

The earlier Move-media fix keeps the item visible while the host runs, disabled with
a reason when no exact prepared media target exists. Generic availability transitions
do not retire an independently valid prepared media owner; commands still recheck the
exact phone, selection epoch, exchange and service before and after suspension.
Installed menu transitions, actual same-position continuation and phone-confirmed
Mac Pause remain unverified. Source-level tests are not installed handoff proof.

The broader Rust rewrite remains active. Runtime catalog-action/selection-generation
admission, exact task retirement, one-use first-pair intent and post-await activation
are the next coherent owner; its private source preimages/independent expectations
are preparation only, with no ABI or implementation adopted. Full adaptation,
audio lifecycle/admission, native handoff timeline and updater check/broker/Sparkle
cycle ownership also remain. Suspension entry remains dormant. Nothing was deployed,
installed, committed or pushed; live apps, phones, pairing data, credentials and
default audio routes remain untouched by this checkpoint.

### Runtime catalog and selection admission — scoped source checkpoint, 2026-10-08

The next coherent owner is now adopted: runtime catalog-action admission, selection
retirement, one-use first-pair grants/intents, post-await activation and prepared-media
admission use Rust through an exact 24/16/40-byte copied ABI and 58 ordered stages.
Native retains full identities/records, crypto, persistence and platform effects. A
hardwired C verifier recomputes the complete result before adoption; malformed output
refuses new authority without dropping native cleanup custody. Exact old-client close
still precedes joining its retained task, and final action-cleanup faults cannot be
reported as ordinary success. This supersedes only the preceding private-owner status.

Actual scoped results: original-native baseline 14 XCTest; new Rust integration 32;
official staged/final four-target framework 116 ABI/import/link checks; native companion
cohort 108 XCTest, all with zero failures/skips. A subsequent deterministic fixture-arm
change separately passed all seven fault-actor cases. The earlier 108 uses its historical
fixture, not the successor. Five real compiled Rust mutants failed their intended
singletons and each restored control passed. Two native compiled mutants also failed:
verifier bypass caused six ordinary assertions; omitted task join caused 82. Their
exact restored singletons passed, and no temporary fault remains in canonical source.

Current source manifest is
`163402df16dad1361b4ccf8a61dd7044bde221e4b7b072b8ad57b2713b40ea9c`;
artifact manifest is
`515d90eb5edcda9cb09462f6af3359e8349129a92dd5480dee5ed425ec747d7f`.
Metadata-only final readback passed with a complete current native-source manifest.
Detailed logs, restored preimages, exact pins and historical binding qualifications
are retained at `/Volumes/t7/beluga-runtime-catalog-owner.JWuMpb/RESULTS.md`.

Mandatory release-gate enrollment for this owner is still private preparation, not
adopted or executed; its strict old source inventory currently refuses the candidate.
The plan preserves all existing prefixes, 474 official mutation controls, 43 phases
and 22 explicit Simulator exclusions. A planned 545-case inventory is not a fresh
545-case execution. Full adaptation, audio lifecycle/admission, native handoff timeline
and updater broker/Sparkle ownership remain. Installed Move-media transitions,
same-position continuation and phone-confirmed Mac Pause remain unverified. Nothing
was deployed, installed, committed or pushed; live apps, phones, pairing data,
credentials and default audio routes were untouched. The broader goal remains active.

### Runtime catalog release-gate enrollment — scoped source checkpoint, 2026-10-09

Mandatory test/source/discovery enrollment is now adopted and checked. All eight
predecessor inventory vectors remain exact prefixes; current totals are
545 Rust tests, 474 existing official mutation controls, 68 core source paths,
54 C/Swift link markers, 56 Mac classes, 448 critical Mac cases, 43 phases and
22 explicit Simulator exclusions. The runtime owner adds exact 32 Rust and
8/14/7 native cases, and 15 reviewed source bodies including the checkpoint helper.
Both producer discovery and receipt verification reject missing, duplicate,
malformed or extra runtime cases. Existing mutation recipes, phase order, exclusions,
release-hook fixtures and ABI/product bodies were not changed by this enrollment.

Fresh executed evidence: startup deterministic 527 XCTest plus both separate native
singleton invocations, all with zero failures/skips; fake startup runner 49 rejection
scenarios; focused validator 16 cases/5,835 assertions; full validator 229 cases/
58,808 assertions; actual Cargo discovery and execution of all 545 reviewed tests,
with no failures/ignored coverage. Every earlier 220 validator declaration survives;
nine strict fixtures were appended. Validator fixture results are not new execution
of every compiled mutation control or the complete 43-phase release workflow.

The first startup attempt failed on the private runner's ASCII locale and was
uncredited; the fresh UTF-8 run passed. The first new inventory check exposed a
multiline Swift enum tokenizer false-refusal, fixed only in the validator; all exact
58-stage/15-offset constraints remain. The private test controller also received
bounded exact-child/group cleanup coverage. Failed attempts and historical source
bindings remain retained, never relabeled as passing current evidence.

Rust source/artifact manifests remain respectively 163402df16dad1361b4ccf8a61dd7044bde221e4b7b072b8ad57b2713b40ea9c
and 515d90eb5edcda9cb09462f6af3359e8349129a92dd5480dee5ed425ec747d7f.
Detailed root-owned logs and source manifests are retained at
`/Volumes/t7/beluga-runtime-catalog-gate-validation.cHQaOP/RESULTS.md`.
This supersedes only the previous private-enrollment status, not broader completion.

Next coherent owner: complete network-adaptation policy, cadence/evidence freshness
and staged native apply/commit-or-retain semantics. Preparation identified a missing
actual-service held-await/rollback oracle; existing value-copy and source-slice tests
are not that proof. Freeze the complete current independent native semantics before
design/adoption, preserving visible pixels, one-use Show attempts and the fallback
versus dedicated native-timestamp asymmetry. Full audio lifecycle/admission, native
handoff timeline and updater broker/Sparkle ownership also remain. Suspension entry
is dormant; browser/Android delivery remains paused. Installed menu transitions,
same-position continuation and phone-confirmed Mac Pause remain unverified. Nothing
was installed, deployed, committed or pushed; live apps, phones, pairing data,
credentials and audio routes were untouched. The full Rust goal remains active.

### Network adaptation — frozen native oracle and private Rust checkpoint, 2026-10-09

The complete adaptation owner is **not adopted** yet. The current native outer
policy/cadence oracle, linked to the unchanged already-adopted queue/RTT/tier
subowners, passed 268 discovered non-skipping XCTest cases: the prior 242 plus
21 frozen policy traces and five service-evidence reference cases. The five
copied-evidence cases are not actual active-capture/held-await service proof.
Four compiled native adverse controls failed their intended assertions and each
exact restored singleton passed. An earlier interrupted C2 invocation has no
terminal credit; only its fresh continuation counts. Failed discovery syntax
attempts and all historical preimages remain retained.

The entire private safe typed Rust candidate now compiles. Exact discovery and
execution passed **570 tests**: all 545 predecessor tests, 14 original-native-
derived bookkeeping cases and 11 separate policy traces, zero failures/ignored
coverage. The first compile attempt's 35 Option-pattern diagnostics is retained
and uncredited; its exact 18 `Some` pattern repair changed no branch bodies or
expectations. Review strengthened two fixture blind spots: per-event adjacent
full-width UInt64 admission, and genuinely newer-versus-older attempt fences.
Four compiled bookkeeping controls and two compiled policy controls each failed
their intended ordinary assertion and passed after exact restoration. These ten
selected native/Rust controls are not execution of all 474 official controls.

Test receipts bind source identity
`97c84ea6337ee2440a59941f5b04577c4600aa68eba0d364c85a482e8f320e10`,
before this documentation checkpoint. Canonical product/ABI/framework and
release-hook bodies were unchanged during these private validations; Rust and
artifact manifest pins remain 163402df16dad1361b4ccf8a61dd7044bde221e4b7b072b8ad57b2713b40ea9c
and 515d90eb5edcda9cb09462f6af3359e8349129a92dd5480dee5ed425ec747d7f.
Detailed scope, exact source bindings, logs and custody receipts are retained in:

- `/Volumes/t7/beluga-network-adaptation-owner-baseline.geO8lP/RESULTS.md`
- `/Volumes/t7/beluga-network-adaptation-owner-controls-resume.zn05z5/RESULTS.md`
- `/Volumes/t7/beluga-network-adaptation-rust-option-validation.GnPzaK/RESULTS.md`
- `/Volumes/t7/beluga-network-adaptation-rust-bookkeeping-controls.Ahujv8/RESULTS.md`
- `/Volumes/t7/beluga-network-adaptation-strengthened-validation.tGU9GO/RESULTS.md`
- `/Volumes/t7/beluga-network-adaptation-branch-controls.MxD7W3/RESULTS.md`

Remaining before adoption: complete independent all-state parity, native exact
clock/Duration and assignment-provenance mapping, proposal-local full route
sidecars, lazy conditional read bounds, raw ABI/result correlation, restrictive
malformed-output handling, and a legitimate actual-service capture/held-await
rollback oracle. The representation proposal at
`/Volumes/t7/beluga-network-adaptation-native-boundary-plan.Bi5sLt/PLAN.md`
is design only. Copied state and private traces grant no native authority.
Then production-adapter, native startup and full release gates are still required.
Installed Move-media transitions and phone-confirmed same-position playback/Mac
Pause remain separate proof. No deployment, installation, commit or push occurred;
live apps, host, phones, pairing records, credentials and routes were untouched.
The full behavior-preserving Rust migration goal remains ACTIVE.

### Native adaptation representation — laboratory follow-up

A separate root-owned standalone assay passed 24 signed Duration normalization
vectors, five required policy deltas, 22 actual-native-origin round trips and
25 ordered coordinate-pair checks. All 16 bounded arbitrary Instant probes were
exact on this macOS26.5.1/Swift6.3.3 runtime, including ±one attosecond. Eight
Duration-only extremes were never advanced against an Instant. This is not an
all-platform precision promise or a product minimum-OS change. Its receipt binds
the documentation successor `bc294a60f4b44d17e34d3e86f69a9e195f1530a4688fe1ccd6faf6e8ed0b4389`.

Two independent static call-tree reviews derived a tight maximum of 15 lazy
clock reads per public policy step and a safe single-Owner-stage bound15, with
explicit/default native times outside that budget. E/A reads must remain separate,
faulted facades still evaluate their original native arguments, and a collector's
lifetime is unbounded. This is static evidence, not an executed callback ABI.
Complete logs and exact limits: `/Volumes/t7/beluga-native-duration-validation.GF1SPY/RESULTS.md`.
Assignment journals, route sidecars, adapter/ABI, malformed-output handling and
actual-service capture/await proof still remain; the private owner is unadopted.
No installed/live state changed. The full migration goal remains ACTIVE.

### Native adaptation assignment-provenance — executed private checkpoint

The complete private Rust owner now records all13 native timestamp slots at
their executed assignment sites, distinguishing Retain/Clear/Set even when
coordinates are equal. Symbolic sources preserve current versus corresponding
prepared sidecars, actual conditional read ordinals and checked exact deltas.
Working-origin copies flatten newly written sources rather than referencing
mutated output slots. Invocation metadata does not change native numeric/NaN
policy equality, revision decisions or semantic Debug snapshots.

Exact discovery/execution passed **582 tests**: all570 predecessor methods and
test bodies unchanged, plus12 independent provenance regressions. Review found
and closed two private validation gaps before this passing run: dropped clock
reads and invalid provenance erased by subsequent assignment. Sticky per-frame
fault and tracked-clock validity are now required before whole-output resolution.
New cases include equal-coordinate queue/RTT/evidence stamps, already-absent
clears, sparse copies, prepared equal/distinct/absent imports, restrictive fast
failure write sets, cadence equality/early-return/finish ordering and invalid
source/delta/transcript rejection. Native Swift max tie behavior was verified
directly from the pinned SDK's public interface: equality selects supplied now.

Four fresh compiled adverse variants—wrong cadence equality winner, wrong
prepared/current alias, erased sticky fault and omitted clock-validity check—
failed their intended ordinary assertions; every exact restored singleton passed.
An earlier harness-footer classification failure is preserved and uncredited.
These raise cumulative selected control coverage to14; they are NOT execution
of all474 official controls. The unchanged canonical source during these runs
was `33a37ecc6da237e4714747a5154a2f7ada14ba4b0ddf08ab4da204c60edd6e76`
(1183 files), before this documentation-only successor.

Immutable private source/receipt paths:

- `/Volumes/t7/beluga-network-adaptation-assignment-journal.ZfkfOw/RESULTS.md`
- `/Volumes/t7/beluga-network-adaptation-assignment-controls-resume.99nNwF/RESULTS.md`

Still **not adopted**. Frame entry, the same tracked-clock instance and immutable
corresponding sidecar binding remain caller obligations. Coordinate agreement
is not an event-origin allowlist or native capability. Complete independent
all-state parity, supported-OS native reconstruction, full route sidecars,
lazy native callback/raw ABI correlation, restrictive native failure handling
and legitimate actual-service capture/held-await rollback proof remain. Then
native startup/release and installed phone-confirmed handoff gates are required.
No deployment, installation, commit/push or live runtime/phone/route change.
The full behavior-preserving Rust migration goal remains ACTIVE.

### Supported-OS native timestamp boundary — private executed checkpoint

A private native-value boundary now encodes exact signed Duration values with
portable checked UInt64/Int64 limbs, preserving macOS14/iOS17 minimums rather than
adopting the earlier laboratory's newer Swift Int128 requirement. Actual native
current/prepared/explicit/read Instant sidecars remain immutable per invocation.
Typed Policy9/Owner10/Cadence3 scopes, per-slot action/source/delta rules,
one-shot result identity, sticky read/provenance denial and whole-output staging
are implemented in the prototype. Scoped merge preserves fresh unowned values.
Review closed optional Clear bypass and unowned whole-snapshot overwrite risks.

Serial root-owned compilation passed macOS14, iOS17 device and iOS17 Simulator
targets with empty diagnostics. On current macOS26.5.1, all24 named boundary
scenarios,25 Duration vectors and961 add/subtract rows passed. The latter cover
729 distinct operand pairs. Required native reconstruction now includes200ms.
Independent complete positive receipt/source/custody audit: PASS.

Five compiled adverse variants (lost carry, wrong prepared alias, foreign frame,
unauthorized Clear, partial invalid output) failed their intended ordinary
assertions; each exact restoration passed the complete24/25/961 laboratory
ledger. Cumulative selected controls are19, NOT all474 official controls. One
earlier control preflight failure is preserved and uncredited. Logs:

- /Volumes/t7/beluga-native-time-boundary.EOMDGb/RESULTS.md
- /Volumes/t7/beluga-native-time-boundary-controls-resume.8QDOmf/RESULTS.md

Receipts bind pre-documentation source
cd438cbee5e4e6dff1f3078c3be1c739af08fe6246ca809337e7397666dc5993.
Still not product-linked/adopted. Native minimum-OS/phone runtime is untested;
iOS artifacts are compatibility objects only. Supplied event-shaped descriptors
and harness envelope identity do not prove originating Rust evaluation or native
permissions. Typed product event/action/transcript factories, actual callback/raw
ABI/layout/result custody, all-state/full-route parity and legitimate actual
service capture/held-await rollback remain before canonical adoption/release.
No live host/phone/audio/credential change, deployment or commit/push occurred.
The complete behavior-preserving Rust migration goal remains ACTIVE.

### Actual Rust/native clock callback bridge — restricted private checkpoint

The complete582-test private Rust candidate is now connected to the native
timestamp frame through an actual C ABI and synchronous lazy Swift callback,
not a detached result projector. Selected real Policy/Owner bind, queue reset,
RTT implicit/copy/lease and Cadence methods execute through that bridge.
TryClockFacts propagates callback denial immediately; original infallible APIs
share those implementations and forward provenance. Failed drafts are discarded,
without fake time, panic escape, callback replay or partially published results.

Root-serial validation3 passed588 ordinary Rust tests (all582 frozen plus six),
21 named cross-language scenarios,45 callback faults, six output corruptions
and20 raw denials. Exact metadata, native read transcript, branch-specific
journals, native component range and all owned coordinates are checked before
one-shot reconstruction. Five C POD records have literal Rust/C layout checks.
C/header and Swift module compilation passed macOS14/iOS17/device/Simulator17;
only the current Mac linked and executed the actual release Rust archive.
This is not minimum-OS runtime, iOS Rust linkage, device or artifact proof.
Independent full positive body/receipt/ledger audit: PASS.

Three compiled controls coalescing event/apply reads, removing exact coordinate
echo correlation and omitting native output range validation failed their
intended ordinary assertions. Every restored copy passed all21 scenarios.
Independent complete control/body/receipt audit: PASS. Cumulative selected
controls are22, not the complete474 official controls. Ten positive and18
control children have natural statuses and exact direct PGID absence receipts;
no blanket detached-descendant cleanup claim is made. Preserved earlier compiler
and ledger failures remain separate and uncredited, never relabeled as passes.

Evidence:

- /Volumes/t7/beluga-native-rust-clock-bridge.20261009-69194-qvqcjq/RESULTS.md
- /Volumes/t7/beluga-native-rust-clock-controls.20261009-79746-1vvt7j5/RESULTS.md

Receipts bind pre-documentation source
65262faff869d0088f2904fb52cacd035e8da77facfb97c2b18d104edfc07bcd,
1183 files. This assay accepts only its explicit constructor/seed fields;
it does not transfer arbitrary existing owner state or serialize its complete
successor. try_* methods themselves are not rollback-atomic; callers must discard
the entire failed draft. Standalone reset_path has direct Rust, not C-bridge,
coverage. Actual-read setters, real Policy3.5/2second setters, evidence/prepared
adoption, complete state/event/full-route codecs, restrictive native failure
handling and real service capture/held-await rollback remain before canonical
adoption, release and installed/phone proof. Header include-guard hygiene remains
a minor private follow-up. No installed app/host/phone/route/credential action,
deployment or commit/push occurred. The full migration goal remains ACTIVE.

### Complete stored-owner codec and selected bind ABI — private checkpoint

The private Rust candidate now transfers all stored Policy, Owner and Cadence
fields through a checked C representation, without reconstructing defaults,
normalizing telemetry, discarding dormant profiles, or rerunning RTT policy
validation. The complete Owner is179 atoms; Policy is168 and Cadence is5.
All45 typed options,25 IEEE bit locations,13 native-domain timestamps, eight
demand profiles and opaque raw RTT words have independent literal golden coverage.
Snapshot export requires a pristine invocation journal; result phases cannot be
replayed as fresh snapshots. Phase tags are not authentication or native authority.

The actual selected fallible Policy/Owner bind methods now consume the entire
decoded owner through the real synchronous native-clock callback and produce the
whole179-atom successor plus exact scoped journals/coordinates. Failed private
drafts are discarded and all six output buffers remain unchanged on denial.
This is sequential publication, not concurrent multi-buffer atomicity; buffer,
callback and context lifetimes remain the trusted caller's responsibility.

Root-serial validation3 passed612 distinct ordinary Rust tests: all588 predecessor
tests unchanged plus18 independent golden and six raw ABI tests. Native-linked
execution passed32 named scenarios (all21 prior clock-bridge plus11 codec cases).
Full-state unchanged, faulted-reset and operational healthy-reset results are
compared to independent expected fixtures; every header/metadata field and all57
imported POD field offsets are asserted. C/header and Swift minimum-target
compilation passed arm64 macOS14/iOS17/device/Simulator17; only the current Mac
linked and executed the Rust release archive. No iOS Rust linkage, minimum-OS
runtime, device, installed-app or release proof is implied.
Independent complete positive source/body/receipt/ledger audits: PASS.

Five compiled adverse controls omitted a field, swapped startup fields in both
encoder/decoder, normalized negative zero, collapsed a present-empty sample and
substituted dormant profile7. Each failed its intended ordinary assertion with
natural exit101; all five byte-identical restored copies passed all18 golden
tests with natural exit0. Cumulative selected controls are27, not the complete474
official controls. Ten positive and ten control children had natural statuses and
matching direct-PGID absence; no cleanup exit or blanket detached-descendant
absence was credited. Earlier31-case receipts remain distinct earlier inputs.

Evidence:

- /Volumes/t7/beluga-native-owner-codec.20261009-85726-1j4i8l/RESULTS.md
- /Volumes/t7/beluga-native-owner-codec-controls.rp0e7E/RESULTS.md

The executed positive/control input is pre-documentation source
e357219749c162022f940fee2e6f0c41c08455f761ad20a363f132e693c73c7d,
1183 files; the later roadmap-only successor is not relabelled execution input.
Full-state structural codec validation is not returned-output computation
correlation, native realizability, resource admission or hard-real-time proof.
Actual native route bodies/time sidecars, incoming/current/prepared custody,
complete raw event factories and fallible operations, restrictive failure
handling, Swift product owner publication, service held-await fences and
returned exact rollback remain before canonical adoption. Remaining audio,
admission and updater owners, full release/installed/physical proof remain in
the full migration. Header include-guard hygiene from the prior private stage
is fixed. No product source adoption, installed app/host/phone/route/credential
action, deployment or commit/push occurred. The complete behavior-preserving
Rust migration goal remains ACTIVE.


### Nine zero-clock owner events — private Rust/native checkpoint

The private candidate now exposes nine existing Policy/Owner operations through
the actual `beluga_private_owner_event` C ABI, consuming and returning the complete
179-atom owner rather than a reduced constructor. Both current and observed
snapshots are structurally decoded before semantic early returns. The closed
40-byte request carries only the operation's permitted payload; these operations
have no Rust clock/callback input, no native clock reads and no invented time.
Local native event factories authorize only Retain/Clear for the minimal owned
slots. Clear(None) remains a distinct journal action from Retain; all15 native
read replies stay zero. Explicit/prepared timestamp ingress, Set, forbidden
slots, extra reads and replay are rejected before one-shot reconstruction.

Independent literal fixtures cover all179 successor atoms, every output metadata
field, selective journals, guards, absent/zero/MAX identities, wrapping revisions
and separate current/observed ownership. A private arithmetic parity correction
uses Swift's selected-operand `observed >= current ? observed : current` rule
instead of Rust `f64::max`, preserving NaN payloads and signed-zero operand bits.
31 literal IEEE rows also compare against actual native Swift.max. This is a
structural migration mismatch, not the Move media disappearance diagnosis or a
proven reachable live-product regression; current producers use finite times.

Root-serial validation1 passed630 distinct ordinary Rust tests, including all612
unchanged predecessor cases plus18 event cases, with all32 result footers closed.
Actual current-Mac Rust-linked execution passed46 named native scenarios: all32
predecessor cases plus14 event cases. C/header and Swift minimum-target compilation
passed arm64 macOS14/iOS17/device/Simulator17; only the current Mac linked and ran
the release Rust archive. Independent complete positive body/receipt/ledger audit:
PASS. This is not iOS Rust linkage, minimum-OS runtime, installed/device or release
proof.

Four compiled adverse controls changed timestamp tie selection, aliased observed
from current, saturated a wrapping revision and skipped Clear for absent
promotion. Each failed its intended ordinary assertion with natural exit101;
every byte-identical restored97-body copy passed all18 event tests with natural
exit0. Ten positive and eight control children have exact natural status and
matching direct-PGID absence receipts; no cleanup exit or detached-descendant
claim is credited. Cumulative selected controls are31, not all474 official
controls. These four Rust assertions are not native-frame mutation coverage.
Independent complete controls/body/receipt/ledger audit: PASS.

Evidence:

- /Volumes/t7/beluga-native-owner-events.20261009-7992-33gy7r/RESULTS.md
- /Volumes/t7/beluga-native-owner-events-controls.cISsWg/RESULTS.md

Execution input remains source
656f5f2a6a20fc38dda77183f816c10f581439cd6ec490036053863f7f5c583a,
1183 files; this later roadmap-only successor is not relabelled execution input.
On denial all six output buffers remain unchanged, but successful publication is
sequential, not concurrent multi-buffer atomicity. Raw pointer lifetimes, buffer
provenance and concurrent access remain the trusted caller's responsibility.
Structural validation does not prove native authority, complete output
computation correlation, resource admission or hard-real-time behavior.
Remaining event factories/fallible operations, actual-read setters, route and
timestamp custody, restrictive failure handling, Swift product-owner publication,
service held-await fences and exact rollback, audio/admission/updater owners,
full release and physical proof remain before full canonical adoption. No product
source adoption, live host/phone/audio/credential action, deployment or commit/push
occurred. The full behavior-preserving Rust migration goal remains ACTIVE.

### Eighteen actual-clock lifecycle events — private Rust/native checkpoint

The private candidate exposes18 existing Policy/Owner lifecycle operations through
`beluga_private_owner_clock_event`, using the complete179-atom stored owner and,
where required, a separate complete168-atom observed Policy. The closed48-byte
request decodes every input before semantic guards. Shared generic fallible methods
preserve lazy native clock-read sites, exact read order, and original local
partial-mutation/revision ordering. Native time failure stops immediately; the raw
boundary discards its unpublished draft and leaves all six outputs unchanged.

The native frame derives a closed local operation/read plan before any sampling.
Wrong/excess cuts are rejected before the provider; only minimal Retain/Clear time
edits are admitted, including Clear(None). This batch does not copy or Set native
Instants. Independent full-state fixtures cover every successor atom, selective
journal/metadata/transcript, healthy/faulted queue and RTT paths, bind-before-show
and zero-cut guards, observed CopyFence, all reachable failure ordinals, wrapping
identities, malformed inputs/outputs, and sticky one-shot rejection.

Root-serial validation1 passed650 distinct ordinary Rust tests (630 unchanged
predecessors plus20 new cases) and65 exact native BEGIN/PASS scenarios (46 plus19).
No skipped/filtered cases. Three-target arm64 macOS14/iOS17/device/Simulator C and
Swift compilation passed with empty diagnostics; only the current Mac linked and
executed the Rust release archive. This is not iOS Rust linkage, signed Simulator,
minimum-OS runtime, installed behavior or release proof. Independent positive audit
passed all101 frozen bodies, receipt/cohorts and ten natural child/group triples.

Four compiled controls swallowed a reset failure, moved a Show guard before bind,
moved route revision after a failing stage, and removed the native pre-provider
clock-site guard. Each failed its intended ordinary assertion. Exact restored
copies passed20 Rust cases each or the complete65 native cases. Ten natural child
triples retain actual spawned PID/log custody; distinct native mutant/restored
executables retain identity/SHA. All101 bodies in each copy, all13 positive custody
pins and the successful Rust archive remained exact. Independent full controls audit
passed. Cumulative selected controls are35, not the full474 official controls.

Evidence: /Volumes/t7/beluga-native-owner-clock-events.20261009-9592-19pbl2t/RESULTS.md
and /Volumes/t7/beluga-native-owner-clock-events.20261009-9592-19pbl2t/CHECKPOINT.md.
Execution input is6756b6de28d5560037e0e0c040687f27aa0a562742c283d4e9fca5c0558a1e91,
1183 files; a later roadmap-only successor must not relabel those runs.

This is private candidate work, not canonical product-code adoption. Successful
six-buffer publication is sequential, not concurrent atomicity; caller pointer
provenance/lifetimes/context/exclusive access remain trusted obligations. Remaining
actual-read/report setters and deadline arithmetic, native factories/time/route
custody, selective product-owner publication, held-await fences/rollback,
audio/admission/updater owners, and full release/physical proof remain. No live
host/phone/audio/credential, installation, deployment, commit or push action occurred.
The full behavior-preserving migration goal remains ACTIVE, and the menu repair
remains source-confirmed, not deployed.

### Generic fallible report policy — private Rust checkpoint, 2026-10-09

Four existing report-policy operations now have shared fallible Rust methods:
regular update, capacity update, expiry and suspension. The old infallible APIs
forward to the same implementations. Lazy clock sites, branch/partial-mutation
order, explicit observedAt deadlines, diagnostics and deferred baseline order
remain unchanged. Clock errors stop immediately; any future raw caller must
discard the whole unpublished draft rather than promise rollback.

The private validation2 passed667 ordinary Rust tests (650 unchanged plus17 new)
and65 freshly relinked/executed native compatibility scenarios, with no
skipped/filtered cases. Validation1's single fixture-setup failure is retained
separately and receives no passing credit. Independent positive audit verified
all104 packet bodies, predecessor lineage, exact cohorts and four natural
child/status/group triples. Existing three-target C/Swift compilation evidence
is predecessor-only; this batch freshly linked/executed only the Mac archive.

Four separately compiled controls swallowed a report error, changed deadline
origin, moved capacity admission before expiry, and eagerly sampled suspension
health. Each failed its intended ordinary assertion; all four exact-restored
copies passed the complete667 Rust tests. Eight natural child triples, positive
receipt/log/archive custody and all104 restored bodies were independently
verified. Cumulative selected controls are39, not the full474 official controls.

Evidence: /Volumes/t7/beluga-native-owner-report-events.20261009-52378-wgnt7k/RESULTS.md
and /Volumes/t7/beluga-native-owner-report-events.20261009-52378-wgnt7k/CHECKPOINT.md.
Execution input is416e927fe80b3148991c86df1b199f2b6b64cdb7c1ca0cf2fac829d86f7157ea,
1183 files; later documentation must not relabel that input.

This remains private preparation, not canonical product-code adoption or a full
stored-owner native report ABI. The next native slice is exact full-owner
expiry/suspension with independently input-derived lazy-read plans. Regular and
capacity reports additionally need genuine native deadline Set authority and
complete result/diagnostic correlation. Product publication, held-await fences,
audio/admission/updater ownership and release/physical proof remain. No live
host, phone, audio-route, credential, installation, deployment, commit or push
action occurred. The full Rust goal remains ACTIVE; the menu repair is unreleased.

### Full-owner expiry/suspension ABI — private Rust/native checkpoint, 2026-10-09

The private stored-owner boundary now invokes actual shared `try_expire` and
`try_suspension_decision` methods through operations301/302. Full179 state,
strict32-byte request, explicit-time shape and11 disjoint aligned ranges are
validated before semantic guards. Complete draft/result/metadata/journal/read
validation precedes all seven output writes; failure discards the unpublished
draft and leaves every output untouched. Success is sequential publication,
not concurrent atomicity; pointer/context lifetimes and exclusivity remain
trusted native caller obligations.

The independently input-derived native frame permits expiry[]/Q and
suspension[]/L/LQ, exact read budgets, explicit observedAt only for expiry, and
mask0xef Retain/Clear only. No prepared time, Set, arbitrary provider or
output-derived authority is admitted. Suspension retains copied stored lease
age rather than substituting fresh L time. Unowned sidecars and Owner revision,
evidence and applied fields are unchanged.

A private arithmetic correction preserves Swift's negative smart-shift result
for opaque signed backoff counters. MAX increment is denied only when expiry
actually consumes the failing branch; skipped MAX fields remain accepted and
unchanged. This is native-boundary safety/parity work, not a new live-product
diagnosis or proof that Rust eliminates runtime policy errors.

Root consumed validation1/session27195 with natural exit0:692 ordinary Rust
tests (667 unchanged plus25 independent literal cases),87 exact native cases
(65 unchanged plus22 new), and three arm64 macOS14/iOS17 device/Simulator C and
Swift minimum-target compilations. No skipped/filtered tests. The current Mac
freshly linked and executed the release Rust archive; this is not iOS Rust
linkage, signed Simulator, minimum-OS runtime or physical/deployment proof.

Root consumed controls/session85193 with natural exit0. Four compiled mutations
made MAX rejection overbroad, changed negative backoff, excluded exact expiry
equality, and bypassed the native pre-provider terminal clock-site guard. Each
failed its intended ordinary assertion, not compilation, abort or timeout.
The three exact-restored Rust copies passed all692 tests; the native copy
passed all87 cases. Ten natural child/status/group-absence triples are retained.
Post-run source/receipt/executable readback is not a stronger in-run executable
or child-log identity fence; this private control driver has that custody limit.
Cumulative selected controls are43, not all474 official controls.

Evidence: /Volumes/t7/beluga-native-owner-terminal-events.20261009-20261009-83350-18swaz2/RESULTS.md
and /Volumes/t7/beluga-native-owner-terminal-events.20261009-20261009-83350-18swaz2/CHECKPOINT.md.
Execution input remains e8d4470797fc6f568564a0c032520b137236b1912080b26d8e1974fe2af2ba1b,
1183 files. A later documentation-only successor must not relabel those runs.

Regular/capacity report inputs/results/diagnostics and genuine native deadline
Set authority remain. Selective product publication, route/time custody,
held-await fences/rollback, audio/admission/updater owners, canonical integration,
full release gates and installed/physical proof still belong to the active full
Rust goal. This is private preparation, not canonical product-code adoption.
No host/phone/audio/credential, installation, deployment, commit or push action
occurred; the Move media menu repair remains unreleased.


### Full-owner regular/capacity reports — private Rust/native checkpoint, 2026-10-09

Private operations401/402 now decode the complete179-atom stored owner and exact
report, call the existing shared fallible report methods once, and validate all
eight outputs before publication. Failure leaves every output untouched; success
is sequential, not concurrent atomicity. Stored owner fields168–178 remain intact.
Actual native Instants resolve through a one-use input-derived frame with exact
lazy sites, closed budgets and singleton Set origins, including explicit+3.5/+2
and current-probe sparse Copy. Native route/resources and actor adoption remain.

Root consumed validation4/session57390 with natural exit0:722 ordinary Rust tests
(692 unchanged plus30 literal cases),114 exact native cases (87 plus27), three
arm64 macOS14/iOS17 device/Simulator C and Swift minimum-target compilations, and
actual current-Mac fresh release archive linkage/execution. Ten natural children,
zero ignored/filtered tests. Independent positive readback PASS. This is not
iOS Rust linkage, signed Simulator, minimum-OS runtime, or physical/release proof.

Root consumed controls2/session5365 with natural exit0. Five separately compiled
ordinary assertion failures removed the deferred baseline, changed explicit
deadline origin, changed sparse Copy origin, moved expiry after admission, and
removed the native pre-provider closed-site fence. Four exact-restored Rust
clones passed all722 tests each; the restored native clone passed all114 cases.
All five118-file maps restored.144 natural children (139 exit0, four exit101,
one exit1), exact compiled executable/log/directory pins, unchanged positive
archive, and zero cleanup credit. Independent control readback PASS. Selected
private controls are48 cumulatively, not all474 official controls.

Failed validation1–3 and controls1 remain failures with originals/logs preserved.
Repairs corrected Swift initialization legality, two inaccurate literal native
fixtures, and Ruby2.6 parser compatibility; no reducer weakening or abort/compile
failure pass credit. Validation4 alone is positive; controls2 alone is negative
control evidence. Execution input remains e312cef16ffc5a8d85749d203220258b809398aeaa56f7dd12bd51c698f4d552,
1183 files; a later documentation successor cannot relabel those runs.

Evidence: /Volumes/t7/beluga-native-owner-full-report.20261009-20261009-23534-87rxg7/RESULTS.md
and /Volumes/t7/beluga-native-owner-full-report.20261009-20261009-23534-87rxg7/CHECKPOINT.md.
Positive terminal SHA9d3882b0b4782ed0970a9f91ee2203334fd0d1691e1222ea1c08f5472d191d1c;
control terminal SHA4809ca3a36ec1762ada7065258557f88557a3d8c8c1528847075456998b7a09c.

The full Rust goal remains ACTIVE. Next private owner preparation is underway
in /Volumes/t7/beluga-native-owner-preparation.oKEytA: generic fallible proposal
preparation and separately versioned prepared scalar continuation codec. This
new work is not yet tested/adopted evidence. Raw prepared ABI, correlated native
route/Instant sidecars, exact sender-await/currentness/rollback/effect harness,
canonical integration, other owners and full release/installed proof remain.
No live host/phone/audio/credential, install/deploy, commit or push action occurred;
the Move media source repair remains unreleased. Rust does not compile-prove
policy correctness or native foreign-resource contracts.

### Fallible owner preparation and prepared scalar codec — private checkpoint, 2026-10-09

This result supersedes the older preparation-not-yet-tested note above. The
shared `try_prepare_proposal` preserves the original entry guards, report
overrides, nil-expiry no-op, lazy default cuts and complete proposal fields.
It propagates clock/arithmetic failure before returning a proposal, without
mutating the stored owner. The old API forwards the same method; no second
policy algorithm or fake-clock preview was introduced.

A separate domain4/phase3 prepared222 codec preserves every proposed policy,
generation/revision, lane, recommendation, route-action and diagnostic scalar.
It does not replace stored179, carry native resources, or serialize invocation
journals as permission. Journals must be separately validated and the actual
native route/Instants correlated and resolved before any later publication.

Root consumed validation1/session23085 with natural exit0:764 ordinary Rust
tests (722 unchanged plus28 preparation and14 independent literal codec cases),
the unchanged114 native cases, three arm64 macOS14/iOS17 device/Simulator C and
Swift minimum-target compilations, and fresh current-Mac release archive
linkage/execution. Ten natural children, zero ignored/filtered tests. Independent
positive readback PASS. No new prepared raw ABI or native actor cohort is claimed.

Root consumed controls1/session22178 with natural exit0. Three separately
compiled ordinary exit101 assertions caught a missing expected-revision guard,
missing strict-report override, and swapped expected/applying serialized
revisions. Each exact-restored122-body clone rebuilt and passed all764 Rust
tests. Each reran the unchanged pinned positive native114 executable; this is
not a new native relink.111 natural children (108 exit0/three exit101),102
retained compiled executable pins, closed ordered log ledger and zero cleanup
credit. Independent control readback PASS. These selected private controls are
51 cumulatively, not a run of all474 official controls. No preparation-stage
validation/control failure was credited or hidden.

Evidence: /Volumes/t7/beluga-native-owner-preparation.oKEytA/RESULTS.md
and /Volumes/t7/beluga-native-owner-preparation.oKEytA/CHECKPOINT.md.
Positive terminal SHAa690c2df6bfcf3f7f78d579a1016f8d9c2ad61bc1b1a2f73897dec0f7ef960b2;
control terminal SHA81a7983a804c6003dcc9fe9431a5b8239cb03dfbb6364b3d078b18f59a0f2c1a.
Execution input remains ab5da2cbec761cda7e975d07b4ff16e686d7cba8b95eb5028f4c768ee3bff7e1,
1183 files; a later documentation-only successor cannot relabel these runs.

The full Rust goal remains ACTIVE. Next: prepared raw boundary and independent
native preparation reference, correlated actual route/Instant sidecars, fallible
remaining owner events, exact sender-await/currentness/rollback/effect harness,
canonical integration, other owners and full release/installed proof. Native
entry guards must precede acquiring the original default observed time; do not
add an eager clock read on rejected entries. No live host/phone/audio/credential,
install/deploy, commit or push action occurred. The Move media repair remains
unreleased; Rust does not compile-prove policy correctness or foreign-resource
authority.

## Earlier implementation ledger

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
embedding/autoplay, source re-anchoring while loading, live completion wiring
and audio coexistence remain integration work. This is not a transfer
or deployment claim. See the handoff component section in `TESTING_ORACLES.md`.

Native source checkpoint (2026-10-03): the host now creates opaque, one-use
descriptors from exact native Chrome observations, not artwork metadata. A
specialized Pause path revalidates original source/timeline/phone position at
the final renderer operation and requires paused-position readback. Stop,
timeout, controller invalidation and revoked caller authority cancel queued work.
Separate playback-continuity identifiers retire pause/resume, seek, buffering and
rate-change ABA without changing normal source-selection or command identity.
The actual controller/composite/backend and extracted script tests use explicit
boundary doubles. The product capability stays disabled. This is not a completed
transfer, live-runtime verification or deployment.

Transaction checkpoint (2026-10-03): optional ordered-channel commit,
cancellation and completion messages now bind to the exact offer and current
connection. The host service retains its native source before sending an offer,
cross-checks native source scalars against the publication, preserves the native
deadline, and passes transport revocation into final native execution. A generic
Pause ACK cannot complete this transaction. Missing replies, expiry, invalid
control messages or uncertain native readback resolve as outcome unknown, with
no automatic Pause replay or Mac resume. The menu does not call this entry point
yet, the iOS receiver still deliberately ignores the feature, and owner-scoped
audio coexistence remains unwired. Headless real-peer tests prove transport
behavior with supplied playback/outcome boundaries, not actual phone playback or
the complete service-to-native transfer. Current iOS compile proof is separate
from a fresh Simulator runtime run and physical device proof.

Player completion checkpoint (2026-10-03): the local player now reserves one
Mac-pause request only from current exact playback evidence, waits for the same
operation's correlated result, and distinguishes a confirmed Mac pause from an
unknown or rejected outcome. Missing replies and pending playback interruptions
stop local playback without claiming the Mac stayed untouched or automatically
retrying/resuming it. After confirmed completion, ordinary local pause, seek,
rate changes and buffering no longer re-enter handoff verification; the old
evidence cannot authorize another request. The SwiftUI sheet uses these explicit
states. The completion is still supplied by a boundary double in local tests;
the product receiver/menu and scoped audio owner remain unwired, and the feature
remains disabled. No complete transfer or deployment is claimed.

## Current handoff integration checkpoint — 2026-10-03

This supersedes the earlier handoff component snapshots above, not their proof limits.
The menu/service, current-peer iOS receiver, SwiftUI presentation, ordered commit/reply,
and exact audio-owner cleanup are now wired in source. Negotiation remains **off by
default**; no completed native Mac/physical-phone transfer or release is claimed.

Two composed Simulator tests now use actual local WebRTC peers, the production VM
event consumer, the real coordinator/WK bridge, and the actual audio lifecycle owner.
Provider HTML, native audio endpoints, and native Mac completion are explicit doubles.
The successful path sends one exact-source commit; transport retirement sends none,
does not fall back to generic Pause, and cannot unmute an uncertain session. Both
test factories must release their inert audio devices after exact WebKit cleanup.

A separate opt-in real-YouTube Simulator probe found a startup defect: `onReady`
arrives before `getVideoUrl()` contains a video ID. Readiness now names the requested
player, while playback samples still require the actual exact provider identity.
The unmodified production player confirms fresh advancing playback of the public
YouTube API demo in a foreground scene. This proves provider playback in Simulator,
not audible physical-phone output or a native Mac pause. Keep external network
probes separate from deterministic CI, and never substitute a ready callback or
an off-scene black snapshot for visible advancing-playback evidence.

Latest selected Simulator run: 474 passes, zero failures, 22 exact hardware-only
skips. Provider identity, visibility, cleanup and readiness script mutations fail
their unchanged assertions. Full service/menu-to-provider-to-native transfer,
physical audio coexistence and guarded release verification remain outstanding.

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
