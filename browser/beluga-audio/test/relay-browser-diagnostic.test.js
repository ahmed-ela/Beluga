import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { runInNewContext } from "node:vm";
import { createRelayProof, failRelayEpoch, RELAY_FAILURE_CODES } from "./native-oracle/relay-contract.js";

// Execute the real browser diagnostic/stats functions with inert browser APIs.
// Only imports and the top-level live polling loop are replaced; this is not a
// substitute for real browser decoding, relay traversal or server validation.
async function harness(getStats) {
  const original = await readFile(new URL("./native-oracle/browser-oracle.js", import.meta.url), "utf8");
  const boundary = "const deadline = performance.now() + 55_000;";
  assert.equal(original.split(boundary).length, 2);
  const source = original.split(boundary)[0].replace(/^import .*;\n/gm, "");
  assert.equal(source.includes("import "), false);
  const reports = [];
  const functions = runInNewContext(`${source}\n({sampleStats, diagnostic,
    prepare(value) { record=value; starts.set(value,performance.now()); }, flush() { return reportQueue; }})`, {
    createRelayProof, failRelayEpoch, RELAY_FAILURE_CODES, AudioShareListener: class {},
    performance: { now: () => 1000, timeOrigin: 1_800_000_000_000 },
    navigator: { mediaDevices: {} }, addEventListener() {},
    fetch: async (_, request) => { reports.push(JSON.parse(request.body)); return { ok: true }; },
    setTimeout, clearTimeout,
  });
  const value = { stage: "worklet", errorStage: null, errorCode: null, closed: false, decoded: false,
    failure: null, relay: createRelayProof().snapshot() };
  functions.prepare(value);
  const client = { closed: false, peer: { getStats, connectionState: "connected" },
    oracleRelay: createRelayProof(), oracleWaveformGood: true,
    stop() { this.closed = true; value.closed = true;
      functions.diagnostic(value, "socket_close", { message: "socket_closed" }); },
  };
  return { value, client, reports, async run() {
    await functions.sampleStats(client, value); await functions.flush();
  } };
}

test("first proof rejection is recorded before intentional socket close", async () => {
  const h = await harness(async () => new Map());
  await h.run();
  assert.equal(h.value.failure, "relay");
  assert.equal(h.value.decoded, false);
  assert.equal(h.value.stage, "socket_close");
  assert.equal(h.value.errorStage, "relay_proof");
  assert.equal(h.value.errorCode, h.client.oracleRelay.failureReason());
  assert.equal(h.value.errorCode, "relay_audio_count");
  assert.equal(h.reports.some(r => r.errorCode === "socket_closed"), false);
  assert.equal(h.reports.every(r => r.errorCode === "relay_audio_count"), true);
});

test("getStats rejection records only a fixed code, never exception content", async () => {
  const h = await harness(async () => { throw new Error("private-credential-must-not-escape"); });
  await h.run();
  assert.equal(h.value.errorCode, "relay_stats_exception");
  assert.equal(h.value.errorStage, "relay_proof");
  assert.equal(h.value.decoded, false);
  assert.equal(h.value.relay.status, "failed");
  assert.equal(JSON.stringify(h.reports).includes("private-credential"), false);
});

test("a later getStats rejection clears verified proof before any error snapshot", async () => {
  const h = await harness(async () => { throw new Error("private-later-error"); });
  const stats = (time, bytes) => new Map([
    ["a", { id: "a", type: "inbound-rtp", kind: "audio", transportId: "t", timestamp: time, bytesReceived: bytes }],
    ["t", { id: "t", type: "transport", selectedCandidatePairId: "p", timestamp: time }],
    ["p", { id: "p", type: "candidate-pair", transportId: "t", localCandidateId: "l", state: "succeeded",
      timestamp: time, bytesReceived: bytes }],
    ["l", { id: "l", type: "local-candidate", transportId: "t", candidateType: "relay" }],
  ]);
  h.client.oracleRelay.observe(stats(1000, 1000), 1001, true);
  h.value.relay = h.client.oracleRelay.observe(stats(2000, 2000), 2001, true);
  assert.equal(h.value.relay.status, "verified");
  h.value.decoded = true;
  await h.run();
  assert.ok(h.reports.length > 0);
  for (const report of h.reports) {
    assert.equal(report.errorCode, "relay_stats_exception");
    assert.equal(report.decoded, false);
    assert.equal(report.failure, "relay");
    assert.equal(report.relay.status, "failed");
  }
  assert.equal(JSON.stringify(h.reports).includes("private-later-error"), false);
});
