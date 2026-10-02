# Paired-phone catalog integration audit

Status: **not integrated into production callers**. This is a read-only source
audit and integration contract, not live pairing, release, or device evidence.
The existing host continues to own one selected phone and one media session.
The separate catalog store must not silently change that behavior.

## Existing call sites

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
