# Paired-phone catalog integration audit

Status: **integrated into production callers in source**. The original inventory
below records the pre-integration boundaries; it is not live pairing, release,
or device evidence. The first-pair onboarding correction below remains subject
to the release operator's focused tests and gate.
The existing host continues to own one selected phone and one media session.
The separate catalog store must not silently change that behavior.

## Original call-site inventory

| Boundary | Current responsibility |
| --- | --- |
| `WorldwidePairingStore.swift` | Host identity, one viewer record, reset, and the isolated Keychain data boundary. |
| `WorldwidePairingBootstrap.swift` | Six checkpoint writes: pending record, proposal, accepted acknowledgement, completion, completion-sent, activation acknowledgement. |
| `WorldwideHostCoordinator.swift` | Startup reset/load; bootstrap-failure recovery load; eight recovery/reconnect writes; selected record in actor memory. |
| `CaptureServerMain.swift` | Sole production composition with `WorldwideKeychainDataStore()` and the `resetWorldwidePairing` startup option. |
| `CaptureServerOptions.swift` | Explicit `--reset-worldwide-pairing`, permitted only with worldwide mode. |
| `BelugaHostPresentation.swift`, `BelugaMenuBarApplication.swift` | Display the selected phone name. Presentation is explicitly not media-health evidence. |
| `WorldwidePairingStoreTests.swift`, `WorldwideHostCoordinatorTests.swift` | Existing persistence, reset, recovery, supervision, and test-only data-store composition. |
| `scripts/check-product-identity.sh`, `scripts/test-product-identity.sh`, `scripts/test-audit-public-release.sh` | Fixed isolated service, protected-service absence, no arbitrary service initializer, and explicit production composition. |
| `scripts/check-product-branding.sh` | File-specific compatibility-token allowance for the existing store/tests; new files need a narrow allowance only if necessary. |
| Historical paired-host/diagnostic update controllers and their contract tests | Attribute-only proof of the original identity and single-viewer accounts. They are not catalog-aware. |

No direct pairing-store calls were found in current bundle/signature validators,
public-release audit, or host-deployment verifier. Their artifact/source checks
do not establish catalog selection or counter continuity. Historical controllers
must not be loosened or repinned in place.

## Persistence contract

- Use only a new account in the existing isolated opensteamer service; preserve
  the host identity and protected legacy namespace boundaries.
- Import the original single-viewer record once, retaining its exact bytes and
  import receipt. A committed catalog, including an empty one, is authoritative.
  Never consult the original viewer account again as a fallback.
- Add/update must not select implicitly. Updates replace only an existing exact
  pair/key/transcript/root binding and reject counter/state/recovery regression.
  An update must never recreate a forgotten device.
- Require the exact catalog revision token for every mutation. The proposed
  process-wide lock is not cross-process compare-and-swap; retain the existing
  single-host process ownership boundary.
- Finish migration before starting any legacy/bootstrap runtime writer. The new
  store lock does not cover `WorldwidePairingStore.savePairedViewer`; a legacy
  writer could advance a replay counter between import read and catalog commit.
  After migration, route every checkpoint/reset through the catalog. Never run
  old and new persistence paths concurrently or infer safety from the new lock.
- Reset/forget writes an authoritative empty or reduced catalog, never deletes
  the catalog item. `start(resetPairing:)` currently resets before loading host
  identity; adapt that ordering explicitly rather than reviving original bytes.
- Preserve persistence-before-outbound-message ordering at every existing
  recovery/reconnect checkpoint. Do not mirror newer counters into the retained
  original record merely to make an old binary appear compatible.

## Runtime and menu contract

Expose sanitized phone labels/IDs and action availability, not pairing records,
roots, signing material, or derived admission proofs, to the menu. A displayed
snapshot is not authority. Revalidate its expected revision at action admission.
`sessionPrepared` means signaling was negotiated, not that a phone is connected
or that the host is quiet.

Before select, forget, or pair-another-phone can replace runtime ownership,
require a fresh exact-generation quiet boundary: no current availability
exchange, media exchange, retained media service, unfinished native stop,
bootstrap, or pending replacement; valid host owner; matching selection epoch
and catalog token. A waiting title, cached peer flag, or cancelled task alone is
insufficient. Do not disconnect an active viewer to manufacture this boundary.
If fresh quiet evidence cannot be obtained, keep the action unavailable.

Set an action latch and retire the old callback generation synchronously before
the first await. Close/join only the captured predecessor transport/tasks, then
recheck owner, quiet boundary, selection epoch, and persistence token before
committing selection. A failed close or ambiguous native stop must not allow a
replacement. Start availability only for the explicitly selected record; never
choose the first, newest, or last-used remaining phone as an automatic fallback.

Required asynchronous fences:

- Bootstrap callbacks and persistence must retain exact bootstrap attempt and
  pair identity. Bootstrap-failure recovery must not load an unrelated currently
  selected record. `stop()` currently marks finished after awaiting socket close;
  terminalize the attempt before that await and reject delayed writes.
- Recovery completion-sent writes currently occur after `await client.send`.
  Recheck exact selection epoch, pair, current client, and owner before saving or
  assigning `pairedRecord`; do not overwrite a successor with the local copy.
- Availability retry cleanup must use its captured client and loop generation,
  never clear/close the successor stored in global `availabilityClient`. Fence
  status publication after close/retry awaits too.
- Reconnect start/stop/send and media-completion callbacks must retain selection,
  exchange, and exact service identity after every await. In particular, fence
  publication after reconnect-response send, not only after service startup.

The wire ABI stays unchanged: one selected record supplies one authenticated
availability locator, and one active WebRTC phone session remains the limit.
Browser audio-share capabilities must not acquire phone-selection authority.
"Move media to phone" is a separate unresolved requirement, not part of this
catalog integration.

## Explicit first-pair onboarding

The real menu's user-started `pairAnotherPhone` flow may select its exact newly
authenticated ACTIVE phone only when the coordinator admitted that attempt from
a pristine catalog: no records, no selection, revision 1, and no legacy import
receipt. This is runtime-scoped intent bound to the bootstrap attempt, selection
epoch, and exact admission snapshot, not a catalog-store default. Generic
`addPairedPhone` and `updatePairedPhone` still never select.

Consume the opportunity on the first admitted pairing attempt, including a
failure before its first durable checkpoint. An explicit select/deselect, forget,
or reset denies it. Startup never chooses an existing record; interrupted
bootstrap recovery and a later retry cannot inherit the first attempt's intent.
A prior catalog with records or an empty forget tombstone never qualifies.

Even after the authenticated ACTIVE checkpoint, leave selection nil until the
exact bootstrap has stopped and its transport/task teardown has returned. Then
recheck current owner and mutation admission, exact attempt/epoch/admission
snapshot, and the checkpoint's fresh whole-catalog readback. Its only record
must equal the authenticated completion and its selection must still be nil.
Select that exact ID through the normal revision-checked store API, then start
availability. A foreign revision (including select/deselect back to nil), catalog
generation, owner loss, cancellation, or stale completion must never write a
selection. Existing/second-phone pairing resumes its predecessor unchanged.

Focused behavior and mutation coverage lives in `WorldwideHostCoordinatorTests`:

| Boundary / unsafe mutation | Regression |
| --- | --- |
| Select before ACTIVE/close, or open availability for the wrong record | `testExplicitFirstPairSelectsExactActivePhoneOnlyAfterBootstrapTeardown` |
| Infer first-pair permission from nil selection or an empty tombstone | `testPriorCatalogExplicitDeselectAndResetNeverAcquireFirstPairIntent` |
| Carry intent into startup, recovery, or later pairing | `testInterruptedFirstPairRemainsUnselectedAcrossRestartAndAnotherPairing` |
| Restore consumed intent after a pre-checkpoint failure | `testFailedFirstPairBeforeCheckpointDoesNotTransferIntentToRetry` |
| Admit a cancelled start or pass its intent to a retry | `testCancelledFirstPairStartCannotActivateOrTransferIntentToRetry` |
| Strand a selected predecessor after caller cancellation, resume before drain, or recover a foreign catalog/owner | `testCancelledPairAnotherResumesOnlyUnchangedPredecessorAfterConfirmedDrain` |
| Remove the post-teardown owner or mutation-admission check | `testFirstPairRechecksOwnerAndMutationAdmissionAfterHeldTeardown` |
| Ignore foreign revision, selected successor, or catalog generation | `testFirstPairRejectsForeignRevisionSelectionAndCatalogGenerationDuringTeardown` |
| Let a stopped bootstrap activate its durable record later | `testStoppedFirstPairCannotSelectAfterLateTeardownOrOnRestart` |
| Replace the existing selected phone while adding another | `testPairAnotherDoesNotOverwriteOrSelectAndFailedAttemptDoesNotRecoverOldPair` |

These use real coordinator/checkpoint/catalog paths and a real cryptographic
pairing transcript over an in-memory transport, with a held retirement close.
They do not claim physical QR pairing, public-service reachability, or first
installation proof. No tests were run while authoring this correction.

Cancellation after predecessor retirement is handled separately from first-pair
activation: after positively confirmed transport drain and successful current
owner/catalog revalidation, use the existing safe-recovery helper to resume only
the unchanged selected phone. A foreign revision or owner failure throws before
that cancellation-recovery branch and never restores availability.

The stopped-bootstrap regression bounds shutdown before releasing the late
coordinator close. Current shutdown cancels but does not join `pairingTask`;
it separately calls `bootstrap.stop()`, closes that transport, and joins the
already-finished signaling consumer. Thus the held completion callback cannot
block revocation, and its eventual return still has no selection authority.
After releasing the held close, the regression waits for the fixed non-sensitive
`Worldwide pairing completion task finished` lifecycle marker emitted by the
captured pairing task's final `defer`. Only the original coordinator's logger
records this single attempt. Durable-state assertions follow that exact task-end
receipt, not a transport-close counter or an assumed scheduler delay.

## Release and downgrade boundary

Original account attributes no longer prove current selection once the catalog
exists. A fresh catalog-aware release profile needs explicit catalog metadata and
runtime readiness evidence, while preserving original-account bytes. Leave
consumed historical controller namespaces and evidence untouched.

A catalog-unaware old host would reread the retained original phone and frozen
counters. It can therefore revive a forgotten/unselected phone or lose replay
high-water marks. After catalog commitment, permit only catalog-aware rollback,
or explicitly prohibit that downgrade. Old wire compatibility is not old-binary
storage compatibility; an old original-record mirror is not a safe substitute.

## Focused regression requirements

- Original identity/record import preserves selection and counters exactly;
  corrupt catalog and stale token fail closed without original fallback.
- Reset/forget survives recreation with original bytes retained and no revival;
  stale update cannot insert, select, or regress a record.
- Held bootstrap/recovery/reconnect send resumes after selection/forget and
  cannot save or publish into its successor.
- Old availability close/retry and media-completion callbacks cannot close the
  new client, clear its service, or change its presentation.
- Active exchange without media, retained failed stop, stale menu revision,
  owner loss, and concurrent selection attempts all deny replacement.
- All original durable checkpoint-before-send guarantees and v1/v2 protocol
  compatibility remain covered. No live Keychain, phone, host, or route action
  was performed for this audit.
