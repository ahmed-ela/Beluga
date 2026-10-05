import test from "node:test";
import assert from "node:assert/strict";
import { PassThrough } from "node:stream";
import { EventEmitter } from "node:events";
import { admitRelayIce, readRelayIce, RELAY_INPUT_MAX_BYTES } from "./native-oracle/relay-contract-input.mjs";
import { createRelayProof, validRelayReport, validRelayEpochReport, failRelayEpoch,
  relayEpochsPass, finishRelayResult, RELAY_FAILURE_CODES } from "./native-oracle/relay-contract.js";
import { createSystemSourceCancellation } from "./native-oracle/system-source-cancellation.mjs";

const now = 1_800_000_000_000;
const envelope = () => ({ iceServers: [{ urls: ["turn:turn.cloudflare.com:3478?transport=udp"],
  username: "temporary-fixture", credential: "public-test-only", credentialType: "password" }], expiresAt: now + 120_000 });
const encode = (value) => Buffer.from(JSON.stringify(value));
const refused = (operation) => assert.throws(operation, { message: "relay_credentials_refused" });
function stats(time = now, pairBytes = 1000, audioBytes = 800) {
  return new Map([
    ["a", { id: "a", type: "inbound-rtp", kind: "audio", transportId: "t", timestamp: time, bytesReceived: audioBytes }],
    ["t", { id: "t", type: "transport", selectedCandidatePairId: "p", timestamp: time }],
    ["p", { id: "p", type: "candidate-pair", transportId: "t", localCandidateId: "l", state: "succeeded",
      timestamp: time, bytesReceived: pairBytes }],
    ["l", { id: "l", type: "local-candidate", transportId: "t", candidateType: "relay" }],
  ]);
}
function verified() {
  const proof = createRelayProof();
  proof.observe(stats(), now + 1, true);
  return { proof, report: proof.observe(stats(now + 1000, 2000, 1600), now + 1001, true) };
}
function epochs() {
  return ["revoke", "revoke", "expiry"].map((phase, index) => ({ epoch: index + 1, phase,
    decoded: true, closed: true, topology: true, failure: null, sampleRate: 48_000,
    microphoneCalls: 0, relay: verified().report }));
}
function result() {
  return { passed: true, ownedChildrenReaped: true, ownedProcessGroupsGone: true,
    browser: { failure: null, epochs: epochs() } };
}

test("temporary ICE uses the production Cloudflare normalizer and exact expiry envelope", () => {
  assert.deepEqual(admitRelayIce(encode(envelope()), now, 60_000), envelope());
  for (const mutate of [
    (v) => { v.apiToken = "not-allowed"; }, (v) => { v.keyId = "not-allowed"; },
    (v) => { v.expiresAt = now + 89_999; }, (v) => { v.expiresAt = now + 300_001; },
    (v) => { v.expiresAt = String(v.expiresAt); }, (v) => { v.expiresAt = now - 1; },
    (v) => { v.iceServers[0].urls = "turn:other.example:3478"; },
    (v) => { v.iceServers[0].apiToken = "not-allowed"; },
    (v) => { v.iceServers[0].credential = "has whitespace"; },
    (v) => { v.iceServers = [{ urls: "stun:stun.cloudflare.com:3478" }]; },
  ]) { const value = envelope(); mutate(value); refused(() => admitRelayIce(encode(value), now, 60_000)); }
  refused(() => admitRelayIce(Buffer.alloc(RELAY_INPUT_MAX_BYTES + 1), now, 60_000));
  refused(() => admitRelayIce(Buffer.from([0xff]), now, 60_000));
  refused(() => admitRelayIce(Buffer.from('{"iceServers":[],"expiresAt":0,"expiresAt":1}'), now, 60_000));
  refused(() => admitRelayIce(encode(envelope()), now, 44_999));
});

test("stdin is bounded, pipe-only, scrubbed and detached on abort", async () => {
  const input = new PassThrough(), abort = new AbortController();
  const pending = readRelayIce(input, { privatePipe: true, runMilliseconds: 60_000, now: () => now, signal: abort.signal });
  input.write(Buffer.from('{"partial":"never-reported"'));
  abort.abort();
  await assert.rejects(pending, { message: "relay_credentials_refused" });
  assert.equal(input.listenerCount("data"), 0); assert.equal(input.listenerCount("end"), 0);
  assert.equal(input.listenerCount("error"), 0); assert.equal(input.listenerCount("close"), 0);
  assert.equal(input.isPaused(), true);
  const good = new PassThrough();
  const complete = readRelayIce(good, { privatePipe: true, runMilliseconds: 60_000, now: () => now });
  good.end(encode(envelope())); assert.deepEqual(await complete, envelope());
  await assert.rejects(readRelayIce(new PassThrough(), { privatePipe: false, runMilliseconds: 60_000 }),
    { message: "relay_credentials_refused" });
  const tty = new PassThrough(); tty.isTTY = true;
  await assert.rejects(readRelayIce(tty, { privatePipe: true, runMilliseconds: 60_000 }),
    { message: "relay_credentials_refused" });
});

test("stdin timeout, oversize and stream errors emit only a fixed refusal", async () => {
  for (const action of ["timeout", "oversize", "error"]) {
    const input = new PassThrough();
    const pending = readRelayIce(input, { privatePipe: true, runMilliseconds: 60_000,
      now: () => now, timeoutMilliseconds: 5 });
    if (action === "oversize") input.write(Buffer.alloc(RELAY_INPUT_MAX_BYTES + 1));
    if (action === "error") input.emit("error", new Error("secret-value"));
    await assert.rejects(pending, { message: "relay_credentials_refused" });
    assert.equal(input.listenerCount("data"), 0);
  }
});

test("same selected relay path and inbound audio must both progress across decoded windows", () => {
  const proof = createRelayProof();
  assert.equal(proof.observe(null, now, false).status, "pending");
  assert.equal(proof.observe(stats(), now + 0.5, true).status, "pending");
  const report = proof.observe(stats(now + 1000, 2000, 1600), now + 1000.5, true);
  assert.equal(validRelayReport(report, true), true);
  assert.deepEqual(report, { status: "verified", observations: 2, elapsedMs: 1000,
    pairBytesReceivedDelta: 1000, audioBytesReceivedDelta: 800 });
  assert.deepEqual(proof.snapshot(), report); // No closed-peer stats needed to retain evidence.
  assert.equal(createRelayProof().snapshot().status, "pending");
});

test("direct, unselected, foreign, missing and ambiguous relay observations fail closed", () => {
  for (const mutate of [
    (s) => { s.get("l").candidateType = "host"; }, (s) => { s.get("l").candidateType = "srflx"; },
    (s) => { s.get("l").transportId = "other"; }, (s) => { s.get("a").transportId = "other"; },
    (s) => { s.get("p").transportId = "other"; }, (s) => { s.get("t").selectedCandidatePairId = "missing"; },
    (s) => { s.get("p").state = "in-progress"; }, (s) => { s.delete("l"); },
    (s) => { s.set("a2", { ...s.get("a"), id: "a2" }); },
    (s) => { s.set("t2", { ...s.get("t"), id: "t2" }); },
    (s) => { s.set("duplicate", { ...s.get("a") }); },
    (s) => { s.get("l").candidateType = "host"; s.set("unused", { id: "unused", type: "local-candidate", candidateType: "relay" }); },
    (s) => { s.get("a").timestamp = now - 1500; },
    (s) => { s.get("p").timestamp = now + 2; },
  ]) {
    const value = stats(); mutate(value); const proof = createRelayProof();
    assert.equal(proof.observe(value, now + 1, true).status, "failed");
    assert.equal(proof.observe(stats(now + 1000, 2000, 1600), now + 1001, true).status, "failed");
  }
});

test("frozen, regressed, changed, cached and unrelated counters cannot complete proof", () => {
  for (const mutate of [
    (s) => { s.get("p").bytesReceived = 1000; }, (s) => { s.get("a").bytesReceived = 800; },
    (s) => { s.get("p").bytesReceived = 999; }, (s) => { s.get("a").bytesReceived = 799; },
    (s) => { s.get("p").timestamp = now; }, (s) => { s.get("a").timestamp = now; },
    (s) => { s.get("t").timestamp = now; },
    (s) => { s.get("p").id = "new"; s.get("t").selectedCandidatePairId = "new"; },
    (s) => { s.get("a").id = "new"; },
    (s) => { s.get("l").id = "new"; s.get("p").localCandidateId = "new"; },
    (s) => { s.get("p").bytesReceived = 1000; s.set("other", { ...s.get("p"), id: "other", bytesReceived: 9999 }); },
  ]) {
    const proof = createRelayProof(); proof.observe(stats(), now + 1, true);
    const next = stats(now + 1000, 2000, 1600); mutate(next);
    assert.equal(proof.observe(next, now + 1001, true).status, "failed");
  }
  const proof = createRelayProof(); proof.observe(stats(), now + 1, true);
  assert.equal(proof.observe(stats(now + 50, 2000, 1600), now + 51, true).status, "failed");
});

test("every relay rejection branch exposes a fixed sticky reason without changing the five-field proof", () => {
  const covered = new Set();
  const check = (proof, expected) => {
    covered.add(expected);
    assert.equal(proof.snapshot().status, "failed");
    assert.equal(proof.failureReason(), expected);
    assert.deepEqual(Object.keys(proof.snapshot()).sort(), ["status", "observations", "elapsedMs",
      "pairBytesReceivedDelta", "audioBytesReceivedDelta"].sort());
    assert.equal(validRelayReport(proof.snapshot()), true);
    proof.fail("secret-must-not-become-a-reason");
    proof.observe(stats(now + 10_000, 5000, 4000), now + 10_001, true);
    const epoch = { decoded: true, failure: null };
    failRelayEpoch(epoch, proof);
    assert.equal(proof.failureReason(), expected);
    assert.equal(epoch.decoded, false); assert.equal(epoch.failure, "relay");
    assert.equal(JSON.stringify({ reason: proof.failureReason(), report: proof.snapshot(), epoch }).includes("secret"), false);
  };
  const initial = (reason, mutate = () => {}, receivedAt = now + 1) => {
    const value = stats(); mutate(value);
    const proof = createRelayProof();
    assert.equal(proof.failureReason(), null);
    proof.observe(value, receivedAt, true); check(proof, reason);
  };
  initial("relay_received_at", () => {}, NaN);
  const unavailable = createRelayProof(); unavailable.observe(null, now, true); check(unavailable, "relay_stats_unavailable");
  initial("relay_entry_count", (s) => { for (let i = 0; i < 125; i++) s.set(`extra${i}`, { id: `extra${i}` }); });
  initial("relay_entry_id", (s) => s.set("invalid", null));
  initial("relay_duplicate_id", (s) => s.set("duplicate", { ...s.get("a") }));
  for (const key of ["a", "t"]) {
    const reason = key === "a" ? "relay_audio_count" : "relay_transport_count";
    initial(reason, (s) => s.delete(key));
    initial(reason, (s) => s.set("extra", { ...s.get(key), id: "extra" }));
  }
  for (const [reason, mutate] of [
    ["relay_audio_binding", (s) => { s.get("a").transportId = "foreign"; }],
    ["relay_pair_missing", (s) => s.delete("p")],
    ["relay_pair_state", (s) => { s.get("p").state = "in-progress"; }],
    ["relay_pair_binding", (s) => { s.get("p").transportId = "foreign"; }],
    ["relay_local_missing", (s) => s.delete("l")],
    ["relay_local_not_relay", (s) => { s.get("l").candidateType = "host"; }],
    ["relay_local_binding", (s) => { s.get("l").transportId = "foreign"; }],
    ["relay_pair_counter", (s) => { s.get("p").bytesReceived = Infinity; }],
    ["relay_audio_counter", (s) => { s.get("a").bytesReceived = 0.5; }],
    ["relay_pair_zero", (s) => { s.get("p").bytesReceived = 0; }],
    ["relay_audio_zero", (s) => { s.get("a").bytesReceived = 0; }],
  ]) initial(reason, mutate);
  for (const key of ["a", "t", "p"]) {
    initial("relay_timestamp_missing", (s) => { delete s.get(key).timestamp; });
    initial("relay_timestamp_future", (s) => { s.get(key).timestamp = now + 2; });
    initial("relay_timestamp_stale", (s) => { s.get(key).timestamp = now - 1500; });
  }
  const later = (reason, mutate = () => {}, elapsed = 1000) => {
    const proof = createRelayProof(); proof.observe(stats(), now + 1, true);
    assert.equal(proof.failureReason(), null);
    const next = stats(now + elapsed, 2000, 1600); mutate(next);
    proof.observe(next, now + elapsed + 1, true); check(proof, reason);
  };
  for (const key of ["a", "t", "p", "l"]) {
    later("relay_identity_changed", (s) => {
      s.get(key).id = "new";
      if (key === "t") for (const linked of ["a", "p", "l"]) s.get(linked).transportId = "new";
      if (key === "p") s.get("t").selectedCandidatePairId = "new";
      if (key === "l") s.get("p").localCandidateId = "new";
    });
  }
  later("relay_interval", () => {}, 50);
  later("relay_deadline", () => {}, 90_001);
  for (const [key, field, previous] of [["p", "timestamp", now], ["a", "timestamp", now],
    ["t", "timestamp", now], ["p", "bytesReceived", 1000], ["a", "bytesReceived", 800]]) {
    later("relay_nonprogress", (s) => { s.get(key)[field] = previous; });
  }
  const capped = createRelayProof();
  for (let i = 0; i < 64; i++) capped.observe(stats(now + i * 100, 1000 + i, 800 + i), now + i * 100 + 1, true);
  assert.equal(capped.snapshot().observations, 64); assert.equal(capped.failureReason(), null);
  capped.observe(stats(now + 6400, 1064, 864), now + 6401, true); check(capped, "relay_observation_limit");
  const waveform = createRelayProof(); waveform.observe(null, now, false);
  assert.equal(waveform.failureReason(), null); assert.equal(waveform.snapshot().status, "pending");
  waveform.observe(stats(), now + 1, true); waveform.observe(stats(), now + 1001, false); check(waveform, "relay_waveform");
  const exception = createRelayProof();
  exception.observe({ values() { throw new Error("secret-credential-or-address-must-not-escape"); } }, now, true);
  check(exception, "relay_exception");
  const forced = createRelayProof(); forced.fail("secret-external-argument"); check(forced, "relay_forced");
  assert.equal(Object.isFrozen(RELAY_FAILURE_CODES), true);
  assert.equal(new Set(RELAY_FAILURE_CODES).size, RELAY_FAILURE_CODES.length);
  // getStats() rejects outside observe(); the browser uses this one fixed code.
  assert.ok(RELAY_FAILURE_CODES.includes("relay_stats_exception"));
  assert.deepEqual([...covered].sort(), RELAY_FAILURE_CODES.filter((code) => code !== "relay_stats_exception").sort());
});

test("later relay failure clears decoded before the server-admitted terminal report", () => {
  for (const broken of ["nonrelay", "frozen", "waveform"]) {
    const { proof, report } = verified(); const epoch = { decoded: true, failure: null, relay: report };
    const next = stats(now + 2000, 3000, 2400);
    if (broken === "nonrelay") next.get("l").candidateType = "host";
    if (broken === "frozen") next.get("p").bytesReceived = 2000;
    assert.equal(proof.observe(next, now + 2001, broken !== "waveform").status, "failed");
    failRelayEpoch(epoch, proof);
    assert.equal(epoch.decoded, false); assert.equal(epoch.failure, "relay");
    assert.equal(validRelayEpochReport(epoch), true);
    assert.equal(validRelayEpochReport({ ...epoch, decoded: true }), false);
    assert.equal(validRelayEpochReport({ ...epoch, failure: "browser" }), false);
  }
});

test("relay scalar reports reject secret fields, nonfinite and unbounded proof", () => {
  const report = verified().report;
  for (const key of ["credential", "username", "url", "address", "candidate", "pairID"])
    assert.equal(validRelayReport({ ...report, [key]: "not-allowed" }), false);
  for (const patch of [{ observations: 65 }, { observations: 1 }, { elapsedMs: 90_001 },
    { elapsedMs: 99 }, { pairBytesReceivedDelta: Infinity }, { audioBytesReceivedDelta: 0 }])
    assert.equal(validRelayReport({ ...report, ...patch }), false);
});

test("exact three independent epochs and clean termination are required; no expanded claims", () => {
  assert.equal(relayEpochsPass(epochs()), true);
  for (const mutate of [(v) => v.pop(), (v) => v.push(v[0]), (v) => { v[1].relay = createRelayProof().snapshot(); },
    (v) => { v[1].phase = "expiry"; }, (v) => { v[2].decoded = false; }, (v) => { v[0].sampleRate = 44_100; }]) {
    const value = epochs(); mutate(value); assert.equal(relayEpochsPass(value), false);
  }
  const good = finishRelayResult(result(), false);
  assert.equal(good.passed, true); assert.equal(good.relayVerified, true);
  for (const key of ["systemAudioVerified", "deployedWorkerVerified", "unrelatedNetworksVerified", "physicalDeviceVerified"])
    assert.equal(good[key], false);
  for (const key of ["ownedChildrenReaped", "ownedProcessGroupsGone"]) {
    const value = result(); value[key] = false; assert.equal(finishRelayResult(value, false).passed, false);
  }
});

test("signals during input or cleanup permanently fail relay and clean up once", async () => {
  for (const signal of ["SIGINT", "SIGTERM"]) {
    const signals = new EventEmitter(), scope = createSystemSourceCancellation(signals);
    const abort = new AbortController(), input = new PassThrough(); let interrupted = false, cleanups = 0;
    signals.on(signal, () => { interrupted = true; abort.abort(); });
    const pending = scope.run(readRelayIce(input, { privatePipe: true, runMilliseconds: 60_000, signal: abort.signal }));
    signals.emit(signal); await assert.rejects(pending);
    await scope.cleanup(async () => { cleanups++; signals.emit(signal); });
    await scope.cleanup(async () => { cleanups++; });
    const final = finishRelayResult(result(), interrupted);
    assert.equal(final.passed, false); assert.equal(final.relayVerified, false); assert.equal(final.failure, "interrupted");
    assert.equal(cleanups, 1); assert.equal(input.listenerCount("data"), 0); scope.dispose();
  }
});
