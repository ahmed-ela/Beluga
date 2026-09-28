# Spatial-first startup: evidence and limits

Source base: `2cb336976d61ca4c149191a05489f22982014e86`.
Work branch: `perf/clear-first-screen`. Measurements below were made on 2026-09-19
with the pinned Xcode 26.6 / bundled LiveKit SDK, not the installed host or iPhone.

## Change

A new eligible Show starts with full source pixels at at most 5 fps. It retains the
existing video and peer-wide bitrate ceilings. This is not permission to use the
full-bandwidth tier. Qualified intermediate tiers preserve these startup pixels and
increase FPS within their ordinary approximate pixel-rate budget: with a 60-fps source,
balanced uses 13 fps and high uses 28 fps, instead of staying at 5 indefinitely.
This is an encode-work proxy, not measured codec demand or extra bandwidth permission.
Qualified full releases the startup limit. Confirmed congestion restores the
ordinary spatial/temporal policy without restarting capture. Explicitly low configured
ceilings do not opt in.

Ownership is exact peer + Show. Missing/stale reports cannot supply positive or
negative capacity evidence. Native apply failure retains only a terminal same-Show
disproof, not the unapplied quality proposal. See `TESTING_ORACLES.md` for boundaries.

Sender reports retain their exact native snapshot separately from diagnostic enrichment.
The cached delegate route may omit metadata (such as network type) present in native
statistics. When the selected pair is temporarily absent, substituting that cached
route used to look like a real route replacement and blur an otherwise healthy Show.
The service now feeds only the raw native snapshot into adaptation. Actual route events
and fresh native replacements retain their existing invalidation behavior.

A whole selected-pair telemetry gap may hold an already accepted discovery cap only
under its original deadline. Its marker belongs to the exact active Show and probe.
A genuinely advancing fast RTT after that gap may wait for the next ordinary report,
but cannot repair primary RTT permission, extend a lease, or grow the cap. Independent
sender queue pressure and fresh route/BWE negatives still terminate the wait. Malformed
or partial evidence cannot acquire it. Fresh sender counters survive the gap only as a
queue-delta baseline, never as bandwidth evidence.

## Native characterization

All profiles used 1080x1920 synthetic desktop detail and 5 input frames/sec. Each
case ran in a fresh test process using real H.264 encoding/decoding, no audio tracks,
no host service, no phone, and no user pixels. Contrast compares phase-known decoded
dark/light stripe pairs against source contrast; it is not a readability score.

| Dense profile | Initial total ceiling | First decoded frame | 2-pixel stripe contrast |
| --- | ---: | ---: | ---: |
| A: quarter dimensions | 905,041 bps | 348 ms, 270x480 | 0.000 |
| B: full dimensions | 905,041 bps | 316 ms, 1080x1920 | 0.977 |
| C: full dimensions | 1,693,440 bps | 237 ms, 1080x1920 | 1.004 |

Simple-pattern repeat timings varied: A 285-533 ms; B 239-247 ms. Do not extrapolate
these timings to a remote iPhone or claim that full-size frames always encode faster.

The native production-policy loopback presented full 1080x1920 detail at 261 ms and
kept that geometry/contrast through a 10-second observation. Its zero local ICE RTT
correctly did not authorize FPS upgrades. This proves startup survival, not recovery
to full frame rate. Synthetic policy tests separately exercise qualified promotion.

The delayed dynamic-FPS fixture uses two per-test loopback UDP sockets with 50 ms
delay in each direction. It rewrites all supported ICE candidates, filters alternatives,
pins exact local endpoints, bounds queued packets, and cleans up its sockets. Initial
blackout prevents connection; blackout after media starts stops decoded frames after
drain. No system network settings or running host are involved.

On the final candidate, this path measured 106 ms native RTT, presented its first
full-detail frame 296 ms after capture began, and finished at 54.5 decoded fps. All
decoded frames retained 1080x1920 geometry and >0.9 signed fine-stripe contrast during
the 12-second observation, including actual sparse selected-pair reports. This fixture
changes only a cursor over prebuilt dense content, not a moving-photo workload. The
timing excludes ICE setup and is not a promise about real-iPhone connection latency.

The pre-Show experiment observed sender-scoped BWE increase from 300,000 to 1,693,440
bps in about 1.56 s, with zero encoded video frames/media bytes and successful native
padding-probe feedback. This background-probing behavior was NOT added to production.
Process-global feedback is supplemental, not a peer-specific authorization.

## Reproduction and unproven boundaries

Use `scripts/validate-screen-startup.sh --scratch-path /absolute/dedicated/cache --native`
with an explicit reviewed `DEVELOPER_DIR`. See `SCREEN_STARTUP_REGRESSION_GUARDRAILS.md`
for the contributor gate and required invariant-to-test map. The gate builds/discovers
once and binds each fresh-process execution to that invocation's source identity;
do not reuse `--skip-build` across source edits. Default `swift test` skips native
diagnostics and does not establish that this gate passed.

Validation for the initial candidate: 239 focused adaptation/floor/capacity tests passed.
Three independent mutations (removing full-pixel shaping, accepting stale native
reports, and discarding failed-apply terminal disproof) each failed its behavioral
regression. The original policy file was restored byte-for-byte and all 239 tests
passed again.

The refined candidate passes 277 focused adaptation, input-wiring, and native-report
provenance tests. New regressions first reproduced the moderate-bandwidth 5-fps plateau,
sparse-report cap reset, and lost requalification handoff before the fixes. The opt-in
delayed fixture also asserts decoded detail and frame-rate improvement, not only requested
geometry. The native blackout test proves the fixture cannot use an unmediated ICE path.

The regression-hardening follow-up adds seeded transition sequences across source FPS,
configured caps, stale/missing/malformed reports, terminal pressure, expiry, failed native
apply, Hide and peer replacement. Four deliberate mutations were detected by actual
assertion failures: fixed-5-fps shaping (2 failures), bypassed timestamp admission
(31 failures, including 22 from the new sequences), removed gap/probe marker (3 failures),
and diagnostic-route contamination of native evidence (20 failures). Both production
files were restored to their exact pre-mutation hashes before final validation.
The final guarded invocation passed 324 deterministic methods and both fresh-process
native methods, with zero skips. The gate's own 48 fake-runner scenarios also passed.
The serial-XCTest log verifier was exercised against the actual reviewed Xcode output,
which did not emit the requested xUnit file; incomplete or empty results still fail closed.

The startup mode remains at 5 fps at lower qualified tiers; moderate qualified capacity
can now improve motion without requiring the full tier. These fixtures do not establish
moving-content load, Internet packet loss, simultaneous microphone/audio load, or iPhone presentation.
No deployment or physical-device result is implied by these source-level experiments.

## User-reported live quality/latency observation — 2026-09-28

The user reported that the image looked substantially better, but interaction/video
felt more delayed. Record this as an important qualitative observation: **better
perceived clarity together with greater perceived latency**, not yet a measured or
causally established tradeoff.

The proposed promotion-threshold experiment in commit
`6484f8698ae5e9e7829648282453779f211059bd` was **not installed** when this observation
was reported. A read-only check on 2026-09-28 found the same host process that had
started on 2026-09-27, with executable SHA-256
`f83ce7986aee069d3b7dac27ed6bdcdfa621695fc12d0fd9a240737fa57a3209`.
The observation therefore is not a before/after result for that experiment.

The prepared change lowers direct quality-promotion admission from 1.35 to 1.25 times
calibrated sustainable demand (about 7.4% lower; full-tier admission 16.2 to 15 Mbps).
Sender ceilings retain their independent 1.35 multiplier. It does not add buffering,
change tier geometry/FPS presets, or relax congestion/freshness safeguards. Source
validation passed; deployment and user-visible benefit remain separate, unproven stages.

A quality/latency tradeoff is plausible, not inevitable: more demanding frames may
increase encoding work or queueing on a constrained path; infrequent frame updates
can also feel like lag without a higher network RTT. These are hypotheses for this
observation, not diagnosed causes or an accepted latency regression.

To evaluate a later deployment, compare timestamped intervals with the exact host
artifact, client build, peer/Show identity, route, host/client load, and comparable content.
Record actual encoded/received dimensions and FPS, delivered video bitrate, bandwidth
estimate, RTT, loss/retransmission, and available encoder/sender/receiver timing.
Use counter deltas within one statistics-object lifetime: average sender buffering is
`delta(totalPacketSendDelay) / delta(packetsSent)`, and average receiver jitter-buffer
delay is `delta(jitterBufferDelay) / delta(jitterBufferEmittedCount)` when denominators
advance. These are component timings, **not end-to-end interaction latency**; do not
sum overlapping receiver metrics. See the [WebRTC statistics definitions](https://www.w3.org/TR/webrtc-stats/).
No synchronized before/after latency measurement was captured for the user's report,
and this documentation adds no telemetry collection or runtime change.
