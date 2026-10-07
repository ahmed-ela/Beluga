# Beluga product core: incremental migration

This dependency-free Rust crate currently owns **media-handoff menu admission,
the worldwide host lifecycle state machine, the handoff transaction ledger, and
the one-use offer/timeline reducer, the phone playback-operation reducer, and
the invitation acceptance policy, the bounded signaling replay window, and
catalog-checkpoint attempt admission/revocation, durable reconnect counter
proposals, pairing-commit phase/recovery plans, supported-player arbitration,
availability retry proposals, safe-output retry/cooldown, system-audio start
selection, and hosted-call scalar admission/projection**.
It is not the complete product-core
rewrite. Swift/native code still owns observation, target identity fences, transfer authorization,
platform media effects, pairing, audio capture, and real-time callback lifetimes.

ABI 1 accepts seven flags (bits 0–6): started, finished, changing phone,
request in flight, session ready, target present, command installed. The action
remains visible after startup independently of transient peer/session readiness.
Every original enabled guard is required. Unknown versions or flags disable
admission. Native exact-target dispatch checks must remain in place.

The lifecycle has idle/inviting/paired/stopped states, independent availability
and media ownership, terminal stop, and fail-closed malformed-state handling.
Native Swift preserves canonical Unicode String equality, embedded NUL values,
original spelling, and the original 1–64 UTF-8-byte availability admission bound;
a bounded map bridges those primitives to opaque nonzero scalar tokens. Rust
owns the transition policy, not the native String primitive or media effects.

The handoff ledger retains one host receipt/reply and one viewer commit. Native
Swift supplies nonzero identity tokens using exact UUID and envelope equality,
including canonical String equality and nonreflexive NaN comparisons. Rust owns
busy admission, exact completion matching, cached reply idempotence, revocation,
and timeout/clear unknown outcomes. Effects never authorize native media pause.

The offers reducer retains independent sent/received owners, their observation
times, sequence counters, and the complete timeline numeric admission rules.
Its copied ABI carries IEEE-754 Double bits so native floating semantics are
preserved: exclusive two-second freshness/deadlines, inclusive phone sample age,
exact numeric identities, monotonic observations, and original uncertainty math.
A new authorized receive burns its sequence and retires the old receipt before
late validation; matching consumption retires its owner before late validation.
Declined operations may therefore change state. Clear removes transient owners
and observations without resetting counters; reset explicitly calls initial().

Native projection retains only the bounded original payloads and exact
String/UUID/receipt primitives. Commit-header identity and current-primary
identity are separate typed facts. A supplied receipt maps to its token only
after full native equality, and prepareCommit uses that supplied envelope's
actual text validation. Native update validity and context/video text rules,
wire codecs, peer authorization/continuity, actual phone playback confirmation,
exact-source Mac Pause and protected microphone/audio leases remain native.
Offer acceptance and scalar effects are never proof of playback or Pause.

The phone operation uses copied raw Double bits, distinct typed message/proof/
completion identity domains, an optional nonzero proof token and bounded state.
It preserves arbitrary initial clocks, foreign-before-time and stale-after-time
ordering, unrenewed original proof age, reservation-before-send, reply expiry and
known Mac outcomes even if continuing phone playback fails. Native Swift still
constructs requests, decodes provider messages, retains the whole private-UUID
proof, localizes status, and performs WKWebView/audio/peer effects. Copied results
must pass native custody checks before a UUID, callback or pause admission exists.
Independent reference traces, native equality/value copies, malformed projections,
candidate exhaustion, actual C/Swift linkage and signed Simulator composition are
required. Raw policy tests do not prove physical playback or acoustic output.

Invitation acceptance uses copy-only scalar state and exhaustive typed operations.
Rust preserves foreign-owner and consumed-before-phase guards, optional admission
consumption, active completion without prior admission, and exact cancellation.
Swift keeps the whole generation UUID, a fresh per-arm native custody marker,
closures, authenticated records, cryptography and persistence. A prepared callback
leaves its before-state unchanged and supplies a success candidate which the native
boundary validates before invoking the exact synchronous closure. Actual success
commits that candidate; the original thrown error leaves state and custody retryable.
There is no post-effect FFI or implied rollback of a callback's partial effects.
Value copies remain independent gates. Malformed copied results cannot grant
callbacks, consume admission early, fabricate completion or prevent local cleanup.
Independent original-reference traces and copied-output corruption tests complement
the Rust tests; none substitutes for real network pairing or physical-device proof.

The signaling replay policy uses a pointer-free, copied state with an explicit
empty/populated distinction and a 64-packet bitmap. Sequence zero and UInt64.max
remain valid; age and advance boundaries preserve the original limited-reordering
rules. Duplicate, outside-window, malformed-state and unknown-ABI refusals leave
the supplied state unchanged. Native code retains AEAD and JSON decoding before
admission, semantic validation after admission, and ownership of approved reset
sites. This reducer neither authenticates a peer nor authorizes a reset. The
adapter must validate every copied result and fail closed on a broken bridge;
there is no successful native fallback. Migration verification must include actual
C/Swift links, independent original-reference traces, authentication ordering and
durable-client reset/retirement tests, not only raw reducer tests.

The catalog-checkpoint policy preserves one Add, exact bound Update, synchronous
terminal revocation, and full-snapshot Readback even after revocation/owner loss.
Rust returns only a copied candidate; a native lock retains UUIDs, storage calls,
snapshot and binding. The adapter validates the candidate before the store effect,
then commits it only after a successful return. Native storage errors propagate
unchanged and leave the cursor's last known successful checkpoint retryable.
A backend write-then-throw is not rollback proof; fresh Readback rejects durable
divergence. Revoked writes skip the owner callback, whereas a second Add calls it
before refusal, preserving original ordering. Invalid copied outputs cause a
sticky bridge fault without discarding known storage/bindings or granting writes.
These policies do not replace catalog capacity, cryptographic validation, process
ownership, cross-process synchronization or asynchronous native generation fences.

Reconnect counters use a stateless copied snapshot, not a second durable ledger.
Distinct Rust domains keep outbound, accepted-peer and incoming-request counters
separate. Outbound zero remains a numeric proposal so the original native
constructor rejects sequence zero without committing; MAX exhausts unchanged.
Inbound admission is strictly newer and includes MAX. Unknown domains leave the
exact raw snapshot unchanged. There is no initial/reset function or fallback.
Native active/identity guards and inbound signature authentication precede policy;
exact copied-output validation precedes the original signing/key-agreement
constructor. Only constructor success commits the relevant counter. Native callers
still persist before sending; a proposal is not authentication, storage or network
proof. Independent numerical/reference traces, genuine native cryptographic tests,
compiled guard controls and cross-language layout/link proof are required.

Pairing commit is a stateless copied snapshot with exhaustive role, phase,
cache, operation, decision and authentication domains. Rust preserves the
original error and authentication ordering, cached-message custody and stored
shape rules. It does not carry keys, signatures, UUIDs or serialized records.
The native adapter rejects malformed plans before effects and has no successful
Swift fallback. Native identity and proof verification, unchanged message
construction, successful storage and current-session transmission fences remain
mandatory. Sending completion does not activate a host; an authenticated
activation acknowledgement does. Active-host completion is ephemeral rather
than becoming a new recovery cache. Verification requires failed storage at each
durable cut, including actual write-then-throw behavior; a model trace is not durable,
cryptographic or physical-device evidence.

Supported-player arbitration is a stateless copied contract over exactly two
native observations (browser and Music) and an optional retained selection.
Any indeterminate child read returns retry while retaining the selection hold;
otherwise the selected playing source wins, then the first playing source,
then the selected available paused source, then the first available source.
No available source publishes none. Rust uses exhaustive source/observation/
decision domains, while native code retains the original `playbackRate > 0`
comparison, full snapshots, capabilities, opaque tokens, fetch epochs and all
queued command/handoff effects. A stale fetch is rejected before any core call.
Starting a pending fetch alone does not revoke existing publication authority.
Malformed copied results revoke current publications, preserve the hold, and
return a bounded distinct retry diagnostic, never a successful Swift fallback.
Verification includes independent literal 48-case traces, closed-field and
copied-output refusal cases, native stale/recovery histories and retained command
admission, with actual C/Swift layout and link checks. An ordinal or policy pass
does not prove live discovery, phone continuation, native pause or acoustic output.

Availability retry has exactly seven admitted copied states: delays 1/2/4/8/16/30
before validation, and delay1 after validation. Only successfully handled parsed
waiting/ready events reset backoff; a WebSocket upgrade alone cannot do so. Failure
returns the prior delay and then doubles the successor up to30. The by-value ABI
uses State16/Event8/Result32, alignment4, preserving exact raw state on malformed
inputs. Native rejection-only correlation checks every result before commitment;
a bridge fault retains the prior scalars, becomes sticky and terminates only
after the exact socket's original cleanup and current-generation guards.
Sockets, crypto/authentication, native event handling, timers, cancellation and
supervisor task ownership are not transferred to Rust. Tests use frozen original
arithmetic/literal histories, actual-C-first copied corruption and the real inert
supervisor; its empty-default immutable exit observer conveys no authorization.
Source integration alone is not an archive/link, network or installed-host pass.

The reviewed artifact profile has **macos-arm64, ios-arm64, and
ios-arm64_x86_64-simulator slices**, using only already-installed pinned targets.
Each slice is a **static `BelugaCore.framework`**, with its module map under
`Modules/` and public header under `Headers/`. The framework namespace prevents
SwiftPM/Xcode from flattening its module map into the same global include output
as the independent audio-authority static library. The main framework binary is
the unchanged Rust static archive, not a dynamically loaded library.
Intel Macs and Android do not use this core yet. A candidate does not become the
checked production artifact until the native adapter integration is ready.
Supporting another target requires a reviewed, already-installed pinned target
and additional actual cross-language link tests; the builder never installs tools.

Run from this directory, with the existing toolchain homes:

```sh
RUSTUP_HOME=/Volumes/t7/opensteamer-rustup-1.97.1 CARGO_HOME=/Volumes/t7/opensteamer-cargo-1.97.1 /Volumes/t7/opensteamer-cargo-1.97.1/bin/cargo test --offline --locked -- --test-threads=1
ruby scripts/build-xcframework.rb --refresh-source-manifest
ruby scripts/build-xcframework.rb
ruby scripts/verify-xcframework.rb
ruby scripts/mutation-tests.rb
```

Builds refuse to overwrite any existing artifact. To reproduce without replacing
the checked artifact, pass an absent output path to the builder, then verify it.
Source and artifact manifests enforce exact file membership and bytes. The
verifier compiles, links, and executes inert Mac C and Swift smoke programs against
the actual archive, and cross-links both languages for iOS device and each Simulator
architecture without launching them. Cross-link success is not physical-phone proof.
These programs never open apps, access phones, or change routes.

Source-only mutation tests must fail on behavioral assertions for the original
visibility defect, ignored unknown bits, missing command admission, availability
departure erasing an independent media owner, stale media-end ownership, transaction
busy/exact identity/conflicting-reply guards, revocation, unknown timeout outcomes,
sixteen offer identity, retirement, replay, boundary, counter, and unknown-operation defects,
six phone identity/clock ordering, proof-age, reservation and truthful-outcome defects,
and nine invitation owner/order, optional-callback, pre-effect state, thrown-effect,
completion, rearm and cancellation defects, plus eleven signaling-replay sequence,
boundary, duplicate, history and malformed-state preservation defects, plus twelve
catalog admission, revocation, exact native fact and malformed-domain defects, plus
twelve reconnect exhaustion, monotonicity, independent-counter and malformed-domain
defects. They use
temporary copies and never modify the production archive or source.
