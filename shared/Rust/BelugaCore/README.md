# Beluga product core: incremental migration

This dependency-free Rust crate currently owns **media-handoff menu admission,
the worldwide host lifecycle state machine, the handoff transaction ledger, and
the one-use offer/timeline reducer, and the phone playback-operation reducer**. It is not the complete product-core
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
and six phone identity/clock ordering, proof-age, reservation and truthful-outcome defects. They use
temporary copies and never modify the production archive or source.
