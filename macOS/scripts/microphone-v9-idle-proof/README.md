# Passive microphone driver proof

Build with the unchanged product diagnostic decoder from committed, clean
`168036d74e08e7b49aad37907cf9b84b5dcc8456`:

```sh
ruby macOS/scripts/microphone-v9-idle-proof/test-beluga-microphone-idle-proof.rb
```

The runner builds the actual native production CLI and a separate offline test
executable. It writes its build proof under a new private temporary directory,
not either source checkout. Neither fixtures nor a skip/test input mode are
linked into the production CLI. No live CoreAudio call is needed for the tests.

## Native interface

All commands require real/effective UID 501. The binary makes only passive
property reads; it does not register listeners, start a consumer, change routes,
stop a host, install a driver, or restart CoreAudio.

```text
--verify-idle --phase before-publish --schema 1 --nonce <64-lowercase-hex> --expected-instance <actual-instance>
--bootstrap-instance --phase after-reload --schema 2 --nonce <64-lowercase-hex>
--observe-initial-idle --phase after-reload --schema 2 --nonce <64-lowercase-hex> --expected-instance <bootstrapped-instance>
--verify-idle --phase after-probe --schema 2 --nonce <64-lowercase-hex> --expected-instance <same-instance>
--bootstrap-prior-instance --phase after-rollback --schema 1 --nonce <64-lowercase-hex>
--verify-idle --phase after-rollback --schema 1 --nonce <64-lowercase-hex> --expected-instance <fresh-prior-instance>
```

`--bootstrap-instance` may run only after the transaction worker independently
proves the fresh CoreAudio generation and exact candidate installation/load
boundary. It obtains the new driver instance from **one actual complete fresh
v2 property observation**. There is no pre-pinned, fixture-derived, or guessed
instance. Its JSON is not provenance, idle acceptance, or PCM proof.

The distinct `--bootstrap-prior-instance` command is recovery-only. Its caller
must first independently prove the exact restored predecessor bytes/protected
code and a fresh CoreAudio reload generation. It uses the unchanged normal
reader: one actual absent-v2 `UnknownProperty` may lead to one complete fresh v1
observation. No other error permits fallback, and a v2 result is refused. It
returns non-green exit 75, then requires four fresh mirrored v1 observations
pinned to that newly observed instance. It does not reuse the pre-restart
instance, require invented positive history after initialization, or claim v2
PCM/candidate acceptance.

The normal commands require four fresh advancing visible/writer/visible/writer
observations from unchanged instance, lifecycle, schema and complete inventories.
Every endpoint revalidation checks exact UID, model, alive/hidden flags,
input/output channels and stream roles, exact virtual and physical packed
interleaved Float32 mono 48 kHz ASBDs, and clock domain `0x6f73564d`.
Device **and stream** identities remain pinned throughout. The unchanged
production decoder permits v1 fallback only on actual `UnknownProperty`; a
schema-2 phase then rejects any v1 result.

The caller **must** impose a monotonic child deadline of at most 20 seconds,
own the dropped-UID child PID/group, close its input, bound stdout/stderr, and
reap it after TERM/KILL on timeout. CoreAudio's synchronous calls have no
in-process timeout guarantee. A timeout, signal exit, partial output, failed
teardown, or conflicting process generation cannot produce acceptance. The
privileged worker must capture output in a root-held relative result channel;
ordinary user-writable result files do not establish trusted transaction proof.

## Result contract

Contract: `beluga.microphone.passive-idle.v1`.

| Command | Kind | Exit | Observations | Idle acceptance |
|---|---|---:|---:|---|
| Bootstrap | `BOOTSTRAP_INSTANCE_REQUIRES_FRESH_IDLE_AND_PUBLIC_PROBE` | 75 | 1 | false |
| Prior recovery bootstrap | `PRIOR_INSTANCE_REQUIRES_FRESH_MIRRORED_IDLE` | 75 | 1 | false |
| Initial idle | `INITIAL_COMPLETE_IDLE_REQUIRES_PUBLIC_PROBE` | 75 | 4 | false |
| Before-publish/after-probe idle | `NORMAL_IDLE` | 0 | 4 | true for this passive phase only |
| Failure | `REFUSED` | 64/65 | absent | false |

Successful observations include nonce, UID, phase/schema, actual instance,
device/stream IDs, endpoint-contract marker, per-read selectors, fresh clock
windows, complete-payload SHA-256, registration count/revision, and epoch fields.
Initial genuine idle registrations are allowed; optional `initialPristine`
classifies the stricter empty initialized state without making it green.
Bootstrap sets `requiresFreshMirroredIdle=true`; every initial result sets
`requiresPublicProbe=true`. Consumers must bind all these fields and exact
array counts to their owned invocation, not merely check the exit code.

After-probe idle requires positive issued seed/session and successful balanced
start/stop and seed-create/clear history. History alone is **not** evidence that
the owned public probe ran: independently parse the exact nonce-bound PCM
result before accepting this phase. Retained registrations, retired-core
history and truthful failure evidence are not erased or forced to a synthetic
two-slot shape.

## Separate public oracle boundary

The frozen product CLI is:

```text
mirror-loopback --nonce <fresh-token> --required-headroom-seconds <60...86400> --result <relative-json-path>
```

It tests both restart-clock orders, then one visible-first PCM challenge. It has
no order selector. Invoking it twice does not prove hidden-first exact PCM.
Any new both-order PCM extension must exercise the actual queue-start order and
verify each owned nonce/result, without modifying the frozen product artifact.
This helper does not supply that extension and makes no FaceTime, voice-dictation,
route-continuity, loaded-byte provenance or physical-phone claim.

## Native root-held receipt consumption

The worker can include `../opensteamer-microphone-v9-proof.rs` as a Rust module.
It has no I/O, interpreter dependency, process launcher, or live-query entry point.

```text
verify_public(bytes, owned_nonce, actual_instance, pinned_route_fingerprint)
verify_idle(bytes, IdleExpected { phase, schema, nonce, instance, exit_code })
bind_after_probe(&idle_receipt, &public_receipt)
bind_after_rollback(&prior_bootstrap_receipt, &fresh_idle_receipt)
```

`instance=None` is allowed only for one-read after-reload or after-rollback
bootstrap. Both bootstraps and four-read initial v2 idle yield non-green typed
progression. The prior bootstrap additionally has `requiresPublicProbe=false`;
only fresh mirrored-v1 recovery idle may follow it. After-probe binding
requires schema 2, exact instance/device IDs/final issued seed/session, and all
four sequence/capture ticks newer than the owned public result. Recovery binding
requires schema 1, exact freshly bootstrapped instance/device/stream IDs, all
four reads newer than the bootstrap, and nonregressing history. Zero prior-v1
issued history remains valid; it is not candidate PCM proof. The caller must
independently prove the exact restored protected prior bytes and new CoreAudio
generation. Positive history alone is not substituted for public PCM.

The caller must independently require exit 0 for the public child, own the
root-held output descriptor, seal/pin all child bytes and exact arguments, bound
and reap the UID 501 child, and prove the loaded-driver generation. Receipt JSON
can never establish those external facts by itself. The native parser rejects
duplicate/unknown/missing fields, malformed JSON, wrong numeric types, stale
samples, role-count mismatch, seed/session/lifecycle regression, route changes,
incomplete teardown and wrong independently regenerated nonce PCM hashes.

Run its actual offline native tests, with no audio calls:

```sh
rustc --edition=2021 -D warnings --test macOS/scripts/opensteamer-microphone-v9-proof.rs -o /private/tmp/owned-native-proof-tests
/private/tmp/owned-native-proof-tests --test-threads=1
```

`offline-public-fixture.json` is test-only parser input, derived from explicitly
synthetic offline waveform output; it is not live evidence. It is referenced only
under Rust `cfg(test)` and is not linked into the production validator.
