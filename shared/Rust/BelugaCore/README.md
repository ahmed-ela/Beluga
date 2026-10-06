# Beluga product core: incremental migration

This dependency-free Rust crate currently owns **media-handoff menu admission and
the worldwide host lifecycle state machine, and the handoff transaction ledger**. It is not the complete product-core
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
busy/exact identity/conflicting-reply guards, revocation, and unknown timeout outcomes. They use
temporary copies and never modify the production archive or source.
