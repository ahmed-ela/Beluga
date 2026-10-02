# External updater lifetime — partial implementation, not release-ready

The menu now launches an independently staged broker and no longer starts Sparkle
in-process. The replacement lifetime is connected in source, but not distribution-
ready: genuine signed old-to-new replacement and uncertain recovery still require
native proof. The historical checkpoints below explain the previous ownership gap
and its incremental implementation; they are not current release certification.

## Supported seam

The pinned Sparkle 2.10.0 public `SPUUpdater` initializer independently accepts
`hostBundle`, `applicationBundle`, `userDriver`, and `delegate`. A distinct signed
updater broker can target the main app for both bundles while remaining alive
itself. Public `SPUUserDriver.showUpdateInstalledAndRelaunched` reports installation
completion when the updater survives; the pinned `SPUInstallerDriver` delivers
that callback after `SPUInstallationFinishedStage3`. Do not replace it with
`sessionInProgress == false`, a UI dismissal, a delay, or process disappearance.

## Proposed ownership

1. Verify a canonical, writable installed main target and its expected signing
   identity. Refuse updates of mounted-DMG or translocated targets. Stage a distinct
   immutable signed broker outside the app being replaced, with its independently
   verified Sparkle dependency/helper closure.
2. Broker acquires the existing `WorldwideHostProcessLock` before starting any
   updater machinery, including resumed-installer probes. It owns that descriptor
   across target exit, replacement, and relaunch. No legacy lock ABI change or
   unsupported descriptor transfer is required.
3. Persist a separate exact-target operation fence before updater startup. Main
   menu and CLI runtime activation paths in the new target must honor it. Read-only
   diagnostics need not start streaming and may remain available.
4. Persist the sticky possibly-armed state before forwarding the **first** public
   user-driver `.install` reply. Download completion extracts automatically, so
   `showReady` is too late and the void `willExtractUpdate` hook cannot safely veto
   a persistence failure. Treat that later hook as an invariant check. A resumed
   `.installing` state may already have an installer; dismissal is not cancellation.
5. On the real public installed callback, retain ownership while verifying the
   exact candidate version, signature, dependency closure, and authenticated
   readiness from the new menu. Clear only that matching fence, then release
   ownership. Normal host startup competes for the unchanged shared lock.

## Fence and recovery requirements

The bounded strict record should bind schema, operation nonce, effective UID,
canonical target, bundle/team identity, predecessor build/executable identity,
candidate identity when known, and operation stage. Use canonical owner-only
storage, no symlink traversal, atomic persistence, and exact path/inode
revalidation. PID and timestamps may explain state but never authorize clearance.

An uncertain or malformed record denies target runtime activation. After broker
failure, reacquire the shared lock and use supported Sparkle resume behavior.
If no positive terminal completion/readback can be established, retain the
target fence and require recovery; do not infer safety from a missing installer.
An already-armed pre-marker updater requires explicit migration/recovery and is
not proved absent merely because the new marker does not exist.

## Bounded scope

This is app-only replacement, not privileged audio-driver recovery. Sparkle's
ordinary quit matching uses the target bundle identity plus resolved path, with
a translocation fallback; refusing translocated targets avoids relying on that
fallback. An unrelated frozen legacy CLI at another canonical path may safely
win the existing lock after broker failure: it is not this replacement target.
The new menu must wait for that ownership, not terminate that host or change
routes. Do not introduce an impossible global prohibition on all legacy binaries.

## Required implementation and proof

- Signed broker staging and recursive dependency/helper verification.
- Authenticated readiness channel bound to the exact candidate and operation.
- Every target entry path fenced before runtime effects.
- Genuine signed old-to-new replacement and quit/relaunch tests.
- Cancellation before/after extraction, broker crash/resume, and target-CLI race
  tests with continuous lock/fence evidence.
- Explicit recovery for missing/uncertain final callbacks and pre-marker state.

The broker executable is now built and help-smoked; no signed SDK operation,
installation, or native replacement has been accepted as a release gate.

## Fresh unarmed user decisions

The initial check's accepted one-shot Cancel action and the exact fresh offer's
Skip/dismiss action are distinct from interrupted-install recovery. Neither may
clear immediately at the UI callback. The live driver must first see the matching
native manual-cycle completion, an idle SDK and retained authority. An offer also
requires the exact admitted signed item and notDownloaded/user-initiated native
choice. Any installation attempt, downloaded/resumed offer, extraction, termination,
error or inconsistent callback invalidates this path.

The reason-specific completion is only valid synchronously inside that driver's
owner callback. Core independently matches the reason to the durable candidate,
requires the exact still-prepared snapshot, revalidates the admitted controlled
history and unchanged signed predecessor, then rechecks driver proof before
retiring the marker. This does not make a stored prepared record recoverable after
a crash. Initial network/feed failure and genuinely uncertain attempts still need
a separately reviewed recovery path before distribution is ready.

## Concrete remaining integration contracts

Keep the distribution as one draggable main app. Embed a distinct
`Contents/Helpers/BelugaUpdater.app` and copy its entire verified signed bundle to
a fresh private operation directory outside the replacement target before launch.
The broker needs its own complete pinned Sparkle framework/helper closure and
`@executable_path/../Frameworks` rpath; it must not load the target app's frameworks
or LiveKit. Extend the existing fixed code/alias/signature/dependency lists for the
nested and staged broker rather than allowing arbitrary extra executable files.
For this unsandboxed broker, the pinned SDK's existing in-process launcher does
not require extra top-level XPC copies or enabling additional services.

The producer now derives strict `beluga.update-candidate.v1` metadata from the
verified signed app, compares it with the final read-only mounted DMG, and adds
its four enclosure attributes before whole-feed signing. Version/build, executable
SHA-256 and the full signed app-tree SHA-256 are bound; the tree algorithm is
explicitly `beluga.bundle-tree-json-v1`, not an unspecified dependency subset.
The reader consumes the public `SUAppcastItem.propertiesDictionary` only with
positive `signingValidationStatus` success, rejecting deltas, packages, missing
fields and fallback version locations. This is expected release identity, not
installed-byte proof. No signed distribution has yet been produced with it.

Archived Sparkle items retain signing status without re-verifying a feed. The
session therefore requires this manual cycle's exact item from the fresh
`shouldProceedWithUpdate` callback before first installation; resumed/downloaded
and installing paths cannot borrow that authority. Ready/retry cannot skip the
first durable authorization. Rejection retains the fence and does not prove that
an older installer was cancelled. The public dictionary preserves literal custom
keys but not their namespace URI; the producer pins that XML namespace and the
whole-feed signature authenticates it. The reader does not claim URI attestation.

Neither this packaging inventory nor signed metadata alone proves broker caller
identity, new-menu readiness, pre-marker history, or genuine old-to-new replacement.

## Pure operation policy foundation

`BelugaUpdateOperation.swift` now implements a bounded canonical record and
monotonic sticky stages with exact target/candidate binding. Clearing its modeled
fence requires a fresh installed completion plus a one-use new-menu readiness
challenge. Restoring a terminal record does not restore that authority. Thirteen
focused tests passed in `mac-phone-catalog-update-policy-3.log` under
`<private-release-evidence>`.

This pure model performs no filesystem, signature, IPC, Sparkle, or process
operations, and is not wired into the updater. It intentionally does not authorize normal
unarmed "no update found" retirement: that needs its own exact positive cycle
completion policy before writing a fence for every check. Do not use cancellation
or a false session flag to retire a potentially armed operation.

## Durable storage and runtime admission evidence

`BelugaUpdateFenceStore` now provides bounded owner-only canonical records,
descriptor-relative no-follow access, exact byte/inode comparison, atomic
publication/replacement and durable synchronization. It never treats restored
terminal JSON as fresh clearance authority. Read is noncreating; create currently
requires an existing safe parent and provisions only the final private leaf.
The broker still must provision its bounded account-home parent namespace.

`BelugaUpdateRuntimeContext` derives target identity from the opened app directory
and its canonical vnode path, not the spelling of an alias. Account-home lookup
uses the effective user's passwd record rather than an overridable environment
variable. `CaptureServerMain` now acquires the existing shared lock, revalidates
that context and rejects an extant/unsafe operation record before runtime side
effects, retaining the same lease until teardown. This also covers a direct CLI
launch of the new app's executable. Read-only diagnostics and bare nonexclusive
development tools preserve their previous behavior.

The menu no longer starts Sparkle from initialization. Its first explicit check
reserves the existing shared lock before SDK startup; automatic checks/downloads
are disabled. This removes an eager startup-probe race, **not** the menu-exit gap:
that controller still lacks broker-owned durable publication and survival through
app replacement. It remains a release blocker.

`BelugaUpdateUserDriver` forwards the public user-driver API and records the real
installed/relaunched callback once, before standard UI can acknowledge it. That
observation is not itself signature, installed-byte or new-menu-readiness proof.

The shared operation/storage/runtime/lock implementation now resides in the
`BelugaUpdateCore` SwiftPM target. It has no CaptureServer, Sparkle, WebRTC or
capture dependency. Existing host callers import the same implementation; the
cross-version lock namespace and lock algorithm are unchanged. The descriptor-only
ACL helper is shared with diagnostics through its existing error-preserving
forwarder. This is source separation for the broker, not a broker executable.

The six focused storage/context/admission/user-driver/old-transaction suites passed
58/58 tests in
`<private-release-evidence>/mac-update-durable-fence-5.log`.
Only private temporary filesystem fixtures and fake UI were used. This is not a
signed old-to-new replacement, native installer, production path or live host test.

After the core extraction, the expanded run passed 115/115 tests in
`<private-release-evidence>/mac-update-core-adapter-1.log`, including
19 fake-driver tests. The adapter now requires an explicit synchronous install
authorization callback before forwarding `.install` or retrying target termination.
It consumes choice replies once, checks presentation identity again after possible
synchronous authorization reentry, and retires callback authority on cancellation,
error, dismissal and installed completion. Authorization denial forwards no install;
it does not assert that a previously armed installer is cancelled. The broker's
actual durable-write implementation is still required at this callback boundary.

## Unarmed completion boundary

Pinned Sparkle maps an unsuccessful or timed-out existing-installer probe to a
normal check path; a later no-update callback does not prove absence of an older
installer. A resumed installer can also bypass `willExtractUpdate`. Therefore a
restored or pre-marker/unknown operation cannot be cleared by `SUNoUpdateError`,
an idle session, UI dismissal or an elapsed timeout.

A future unarmed retirement path requires verified controlled history before SDK
startup, continuous ownership, no installer-arm/resume observation, an exact
positive no-update or pre-extraction-decline callback, and the matching actual
cycle completion. It must not synthesize installed/readiness proof. First-install
provenance and uncertain pre-marker migration remain explicit implementation and
verification work; they are not inferred from a missing marker.

## Broker-lifetime and SDK-composition checkpoint

`BelugaUpdateBrokerSession` now retains the actual shared lease, operation state
and exact durable snapshot through one cycle. Preparation verifies and provisions
under ownership before publishing; SDK startup is one-shot. Installation approval
persists the possibly-armed stage before returning true. Replacement verification
takes a fresh exact-target context, so it does not incorrectly require the old
app inode. New-menu challenge/readiness and final verification callbacks remain
mandatory external proof boundaries; these structs do not authenticate a process.
Only successful exact durable clearance releases the lease. Cancellation/failure
keeps the record and lease; deinitialization releases the lease but not the record.

`BelugaUpdateNamespace` creates only fixed account-derived parents under a borrowed
validated home descriptor. It rejects unsafe existing owner/mode/ACL/symlink state
without repairing it. Ordinary runtime admission still never creates directories.

The public user-driver wrapper and `BelugaUpdateSparkleSession` now live in the
separate `BelugaUpdateDriver` target. Native construction occurs only inside the
prepared authority callback, and SDK start is explicit, one-shot and manual-only.
The supported feed delegate binds the verified target feed without editing user
defaults. Install/retry and target termination require retained authority. The
void extraction callback checks invariants and stops on violation; it is not used
as a late throwing veto. All installed/no-update/abort/cycle results are observations,
not a license to clear a durable marker. The existing menu controller is not yet
replaced by this composition.

Read-only review found and the implementation fixed a cross-thread getter deadlock
and a post-clear state regression. Status uses a separate short-lived published
snapshot; irreversible successful clearance cannot be reclassified as a retained-
ownership failure by rejected reentry. Bounded private tests cover both.

Evidence under `<private-release-evidence>`:

- `mac-update-broker-core-build.log`: independent core build passed.
- `mac-update-broker-driver-3.log`: 148/148 focused tests passed.
- `mac-update-sparkle-session-2.log`: 18/18 actual registered session tests passed,
  including the real private lease/store plus fake engine composition and selector checks.

Compiler-error logs before those passes remain intact. No native updater, signed
old-to-new replacement, production filesystem namespace, phone or audio route was
used. Signed broker staging, installed-verifier wiring, authenticated readiness and
controlled unarmed retirement/recovery are still required before distribution.

## Signed-candidate metadata checkpoint

- `mac-update-candidate-integration-2.log`: 77/77 focused Swift tests passed
  (candidate parser 16, session 24, user driver 19, broker session 18).
- `mac-candidate-producer-1.log`: 24 Ruby cases, 467 assertions passed.
- The initial integration log remains preserved: its three assertions failed
  because `SUAppcastItem.empty()` is a singleton, not two different objects. The
  corrected regression decodes distinct memory-only fixtures with stored
  `.succeeded` status, proving that status alone does not pass the session gate.
- Independent source review checked the publisher/reader contract and pinned
  Sparkle callback ordering; this was not a native installer or signature test.

All logs are in `<private-release-evidence>`. No updater engine,
signing, notarization, deployment, host, phone or audio route was exercised.

## Installed-byte readback checkpoint

`BelugaUpdateBundleTree.inspect` now reads the actual executable and full app tree
using descriptor-relative no-follow traversal, exact UTF-8 byte order, bounded
streaming and final metadata/membership/root checks. Symlink targets are hashed
as raw bytes and never traversed. Its algorithm matches the Ruby producer,
including a shared literal golden vector with Unicode, quote, backslash and
newline filenames. It is a finite observation, not an atomic filesystem snapshot
or code-signing proof.

`BelugaUpdateInstalledArtifact.verify` adds native Security static validation:
Apple anchor, exact bundle/team, Developer ID Application leaf certificate,
strict nested/all-architecture checks, hardened runtime and no ad-hoc/linker-only
signatures. It uses the sealed Security plist, not convenience Bundle metadata.
Local validation explicitly disallows network access; online revocation,
Gatekeeper and notarization remain separate release checks. Equal before/after
tree observations and fresh context validation bind all four candidate fields.
The injected verifier seam is internal and accepts only exact owned private
test fixtures, not installed targets.

`mac-update-installed-readback-3.log` passes 105/105 focused Swift cases, including
15 tree and 13 installed-reader cases. `mac-candidate-producer-2.log` passes 25
Ruby cases/468 assertions. Earlier compiler logs retain the C-to-Swift imported-
flag spelling failures. Review found and corrected the initially broader leaf
certificate requirement; the fixed requirement also passes the native requirement
compiler. Actual native rejection of an unsigned private fixture is tested;
the positive artifact-policy cases use explicitly synthetic signature evidence.

These components are not yet connected to a broker executable. They do not prove
installer completion, authenticate a running menu, authorize first-install or
legacy migration, or replace dependency-layout and writable-install checks.
Genuine signed old-to-new replacement and authenticated readiness remain required.

## Broker packaging, staging and IPC checkpoint (before executable integration)

The dedicated distribution tools now describe `Contents/Helpers/BelugaUpdater.app`
(`com.elamin.beluga.Updater`), the third build product, its independent pinned
Sparkle closure and rpath, exact empty entitlement policy, matching sealed version/
build/feed/key settings, source receipts and inside-out signing. The host retains
its old Sparkle copy temporarily because the current menu controller still imports
it. The broker metadata is consistency evidence, never the SDK update target:
`hostBundle` and `applicationBundle` remain the verified main app. The executable
target/entrypoint is still missing; do not run a release build until it is integrated.

`BelugaUpdateBrokerArtifact` stages the complete verified broker into an exclusive
private operation directory outside the target. It copies regular bytes, exact
modes and raw links through bounded descriptor-relative no-follow operations,
rechecks source and copy signatures/tree/executable/native CDHash/configuration,
and pins the parent, operation and broker roots for fresh point-of-use readback.
Failure retains the partial private directory. It is not a launch helper or
authority to start Sparkle. ACLs/xattrs are not propagated; no Gatekeeper/notary
equivalence or atomic malicious-ABA protection is claimed. The tree API selects
only the fixed host or broker executable, not caller-selected arbitrary paths.

Installed readback now returns the same sealed configuration and exact native
20-byte CDHash along with the four-field artifact identity. These expectations
feed `BelugaUpdatePeerIdentity`, which uses public `LOCAL_PEERTOKEN`, public BSM
token decoders, `proc_pidpath_audittoken`, audit-token-selected dynamic `SecCode`
and kernel requirement matching. It rejects PID-only/static-code fallbacks and
binds exact UID, canonical executable, fixed Developer-ID role/team and native
CDHash. The channel checks the opposite native role as well as the wire role.

`BelugaUpdateIPCProtocol` is bounded canonical JSON with exact operation, target,
per-channel nonce and independent directional sequence counters. It rejects
duplicate/unknown/noncanonical fields, replay, wrong directions and changed
bindings. `BelugaUpdateIPCChannel` owns one local stream, authenticates before and
after complete length-bounded frames, suppresses SIGPIPE, fails fast on competing
calls, and poisons/retire-closes on uncertainty. Close requests cancellation; only
the current worker closes its descriptor, and composition must join that worker
before claiming teardown. Socket waits use a finite deadline and cancellation
slices, but synchronous offline Security validation has no hard cancellable bound.
Neither decoded `menuReady` nor `released` clears a fence or admits host runtime.

Required integration remains: a bounded private socket endpoint namespace within
Darwin's path limit, verified staging/launch, broker executable and SDK composition,
menu-instance-to-kernel-incarnation binding, real installed-callback/readiness
completion, controlled unarmed retirement and recovery. The main menu must stay
fenced and the broker retain the shared lease throughout. Do not infer this from
the communication primitives or ship the old in-process controller as if replaced.

Evidence under `<private-release-evidence>`:

- `mac-broker-staging-ipc-3.log`: 170/170 focused Swift cases passed, including
  14 staging, 18 tree, 14 installed readback, 16 peer identity, 9 wire and 22 real
  private local-socket cases, plus the prior broker/session/driver suites.
- `mac-broker-producer-1.log`: 30 Ruby cases/540 assertions passed.
- `mac-broker-staging-core-build.log`: independent core build passed.
- `product-identity-broker-ipc.log` and `testflight-package-broker-ipc.log`: product
  identity and 15 package-input behavior cases passed after the current manifest
  was repinned for public BSM linkage; no historical cache provenance changed.

Run 1 retains the compound C-macro import compiler failure. Run 2 retains the
channel fixture's incorrect Foundation canonical-path comparison: Foundation
rewrites `/private/tmp` as `/tmp`; actual descriptor `F_GETPATH` and vnode checks
now validate it. Review also caught and fixed native/wire role confusion and
unbounded lock admission; both have explicit regressions. Native kernel rejection
of the test runner's wrong executable and native requirement syntax are tested.
Positive signature/caller cases use explicit fixture evidence, not a signed
cross-process updater run. No release signing, broker launch, app replacement,
phone, host, route change or deployment occurred.

## Executable and menu composition checkpoint

`BelugaUpdater` now has an actual SwiftPM product and AppKit entrypoint. The main
menu no longer imports or constructs Sparkle. While idle it reserves the ordinary
shared lock, verifies the installed target, stages the broker outside that target,
creates a private control endpoint, releases its staging lease and launches the
exact verified broker. The broker must independently reacquire that same lock;
a competing host is never evicted. Both sides authenticate the exact native peer;
the menu additionally binds it to the process it spawned. No argument digest or
wire UUID is accepted as code identity or readiness.

The broker independently compares its retained signed bytes with the main app's
embedded broker, authenticates the old menu before preparing, persists that exact
broker identity/CDHash in the operation, and creates a distinct readiness endpoint
before starting the SDK. It remains alive across main-app replacement. Only the
real installed callback permits fresh candidate readback and a challenge to a new
authenticated main-process incarnation. The relaunched menu builds its UI while
runtime remains blocked, validates the retained predecessor broker and the current
candidate, and answers exactly one challenge. Durable clearance precedes ordinary
host-lock admission. A `.released` message by itself never enables runtime.

The short `/private/tmp/beluga-update-<uid>-<operation UUID>` namespace is owner-only
and descriptor/inode/mode/ACL checked, with exclusive control/readiness sockets
within Darwin's path limit. There is no blind unlink or reuse. A first canonical
frame may supply only a fresh connection nonce after native authentication; exact
operation and target remain the receiver's local authority. Terminal release uses
an authenticated receipt followed by bounded EOF: the broker must not exit while
the menu is still post-authenticating its receipt send. The receipt is cleanup,
not reversible clearance authority. Exit code1 after failed terminal acknowledgment
does not mean a previously cleared marker remains; inspect durable state.

The no-update path is deliberately distinct. A caller-supplied controlled-history
verifier is required at initial preparation and final retirement. The driver mints
one in-process completion only for its actual manual `noUpdate`/same-error cycle
completion, with no candidate, arm/resume, termination, startup failure or unknown
state. The core repeats that native proof, current prepared snapshot, unchanged
predecessor and retained-lease checks before a separate prepared-only retirement.
Restored records, missing markers, build numbers, cancellation and idle SDK flags
do not provide that authority. Other uncertain/cancelled attempts remain fenced;
their guided recovery is not implemented or certified.

Ownership-protocol1 is sealed by the broker-only distribution producer beginning
at build100. The source baseline `168036d74e08e7b49aad37907cf9b84b5dcc8456` has no
Sparkle; a fresh repository release query returned no releases. The producer checks
that ancestry and rejects in-process menu Sparkle construction/imports. This scopes
the first-shipped lineage; it does not auto-enroll unknown or unpublished uncontrolled
distributions. The signed old/new release test and publication audit must preserve
this contract. No first-distributed artifact has yet been signed or published.

Current evidence is `mac-broker-composition-4.log` (320 Swift tests),
`mac-broker-composition-producer-1.log` (31 Ruby cases/548 assertions),
`product-identity-broker-composition-2.log` and
`testflight-package-broker-composition.log` (15 cases), all under the existing
private scratch directory. The binary help-only smoke passed; its linked dependencies
include Sparkle but not LiveKit. The host temporarily retains its now-unused Sparkle
dependency/copy, matching the existing packaging inventory. Source, fixture and
compile evidence are not signed staging/IPC, Gatekeeper/notarization, real installer
completion, protected-runtime continuity or deployment proof.
