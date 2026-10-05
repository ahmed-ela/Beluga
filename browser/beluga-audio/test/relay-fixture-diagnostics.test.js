import test from "node:test";
import assert from "node:assert/strict";
import { summarizeFixtureDiagnostics, validFixtureDiagnostics } from "./native-oracle/relay-fixture-diagnostics.mjs";
import { RELAY_FAILURE_CODES } from "./native-oracle/relay-contract.js";

const secret = "private-canary-https://example.invalid/credential";
const epoch = (number = 1) => ({ epoch: number, phase: number === 3 ? "expiry" : "revoke", failure: null,
  stage: "worklet", errorStage: null, errorCode: null, peerState: "connected", decoded: true, closed: true,
  topology: true, sampleRate: 48_000, rmsLeft: 0.1, rmsRight: 0.1, leftRatio: 20, rightRatio: 20,
  relay: { status: "verified", observations: 2 }, inboundAudioReports: 1, bytesReceived: 12_345, windows: 3,
  shareID: secret, url: secret, sdp: secret, username: secret, credential: secret });
const report = () => ({ failure: null, nativeExitCode: 0, rawError: secret,
  browser: { complete: true, failure: null, epochs: [epoch(1), epoch(2), epoch(3)],
    nativeSnapshots: [{ phase: "before_revoke", raw: secret }, { phase: "success", raw: secret }] } });
const summarize = (value = report(), boundary = "none") => summarizeFixtureDiagnostics(value, boundary);
test("fixed relay rejection survives later socket stage without widening the scalar schema", () => {
  for (const code of RELAY_FAILURE_CODES) {
    const value = report();
    value.browser.epochs = [{ ...epoch(), failure: "relay", decoded: false,
      relay: { status: "failed", observations: 0 }, stage: "socket_close", errorStage: "relay_proof", errorCode: code }];
    const projected = summarize(value, "native_exit");
    assert.equal(projected.errorCode, code);
    assert.equal(projected.errorStage, "relay_proof");
    assert.equal(projected.stage, "socket_close");
    assert.equal(Object.keys(projected).length, 22);
    safe(projected);
  }
});
function safe(value) {
  assert.equal(validFixtureDiagnostics(value), true);
  assert.equal(JSON.stringify(value).includes(secret), false);
  assert.equal(Object.values(value).every((item) => item === null || ["string", "boolean", "number"].includes(typeof item)), true);
}

test("projects one exact flat scalar schema, with no IDs or original objects", () => {
  const original = report(), value = summarize(original);
  assert.deepEqual(Object.keys(value).sort(), ["boundary", "runnerFailure", "nativeExitCode", "browserComplete",
    "browserFailure", "epochCount", "epoch", "phase", "stage", "errorStage", "errorCode", "peerState",
    "decoded", "closed", "topology", "waveformPass", "relayStatus", "relayObservations", "inboundAudioReports",
    "bytesReceived", "windows", "nativePhase"].sort());
  assert.equal(value.epoch, 3); assert.equal(value.epochCount, 3); assert.equal(value.phase, "expiry");
  assert.equal(value.waveformPass, true); assert.equal(value.nativePhase, "success"); safe(value);
  original.browser.epochs[2].bytesReceived = 0;
  assert.equal(value.bytesReceived, 12_345);
});

test("selects first explicit failure, then first incomplete, then last epoch", () => {
  const value = report(); value.browser.epochs[0].closed = false;
  value.browser.epochs[2].failure = "relay";
  assert.equal(summarize(value).epoch, 3);
  value.browser.epochs[1].relay.status = "failed";
  assert.equal(summarize(value).epoch, 2);
  value.browser.epochs[2].failure = null; value.browser.epochs[1].relay.status = "verified";
  assert.equal(summarize(value).epoch, 1);
  value.browser.epochs[0].closed = true;
  assert.equal(summarize(value).epoch, 3);
  for (const field of ["decoded", "closed", "topology"]) {
    const incomplete = report(); incomplete.browser.epochs[1][field] = false;
    assert.equal(summarize(incomplete).epoch, 2);
  }
});

test("missing and malformed structures stay bounded and cannot invent observations", () => {
  for (const value of [null, undefined, false, secret, [], {}, { browser: null }, { browser: [] }]) {
    const summary = summarizeFixtureDiagnostics(value, "none"); safe(summary);
    assert.equal(summary.epochCount, null); assert.equal(summary.epoch, null); assert.equal(summary.waveformPass, null);
  }
  const empty = report(); empty.browser.epochs = []; empty.browser.nativeSnapshots = [];
  assert.equal(summarize(empty).epochCount, 0); assert.equal(summarize(empty).epoch, null);
  assert.equal(summarize(empty).nativePhase, null);
  const maximum = report(); maximum.browser.epochs.push(epoch(4));
  maximum.browser.nativeSnapshots = Array.from({ length: 8 }, () => ({ phase: "success" }));
  safe(summarize(maximum)); assert.equal(summarize(maximum).epochCount, 4);
  const over = report(); over.browser.epochs = Array(5); over.browser.nativeSnapshots = Array(9);
  Object.defineProperty(over.browser.epochs, "0", { get() { throw new Error("must not traverse"); } });
  Object.defineProperty(over.browser.nativeSnapshots, "0", { get() { throw new Error("must not traverse"); } });
  const summary = summarize(over); safe(summary);
  assert.equal(summary.epochCount, null); assert.equal(summary.epoch, null); assert.equal(summary.nativePhase, null);
});

test("poisoned known fields become null or fixed unknown, never raw text", () => {
  const original = report(); original.failure = secret; original.nativeExitCode = secret;
  original.browser.complete = secret; original.browser.failure = secret;
  const current = epoch();
  for (const key of Object.keys(current)) current[key] = secret;
  current.relay = { status: secret, observations: secret };
  original.browser.epochs = [current]; original.browser.nativeSnapshots = [{ phase: secret }];
  const value = summarize(original, secret); safe(value);
  assert.equal(value.boundary, "report_invalid"); assert.equal(value.epochCount, 1);
  for (const key of ["runnerFailure", "browserFailure", "phase", "stage", "errorStage", "errorCode", "peerState", "relayStatus", "nativePhase"])
    assert.equal(value[key], "unknown", key);
  for (const key of ["nativeExitCode", "browserComplete", "epoch", "decoded", "closed", "topology", "waveformPass",
    "relayObservations", "inboundAudioReports", "bytesReceived", "windows"]) assert.equal(value[key], null, key);
  for (const key of Object.keys(value)) {
    assert.equal(validFixtureDiagnostics({ ...value, [key]: secret }), false, key);
    const missing = { ...value }; delete missing[key]; assert.equal(validFixtureDiagnostics(missing), false, key);
  }
  assert.equal(validFixtureDiagnostics({ ...value, raw: secret }), false);
});

test("numeric diagnostics reject nonfinite, fractional, negative and out-of-range values", () => {
  const fields = [
    ["nativeExitCode", 255, (r, value) => { r.nativeExitCode = value; }],
    ["epoch", 4, (r, value) => { r.browser.epochs[0].epoch = value; }],
    ["relayObservations", 64, (r, value) => { r.browser.epochs[0].relay.observations = value; }],
    ["inboundAudioReports", 8, (r, value) => { r.browser.epochs[0].inboundAudioReports = value; }],
    ["bytesReceived", Number.MAX_SAFE_INTEGER, (r, value) => { r.browser.epochs[0].bytesReceived = value; }],
    ["windows", 999_999, (r, value) => { r.browser.epochs[0].windows = value; }],
  ];
  for (const [field, maximum, assign] of fields) {
    for (const input of [NaN, Infinity, -Infinity, 0.5, -1, maximum + 1, true, "1", {}, []]) {
      const r = report(); r.browser.epochs = [epoch()]; assign(r, input);
      assert.equal(summarize(r)[field], null, field);
      assert.equal(validFixtureDiagnostics({ ...summarize(), [field]: input }), false, field);
    }
    const r = report(); r.browser.epochs = [epoch()]; assign(r, maximum);
    assert.equal(summarize(r)[field], maximum); safe(summarize(r));
  }
  assert.equal(validFixtureDiagnostics({ ...summarize(), epoch: 0 }), false);
  for (const input of [NaN, Infinity, -1, 0.5, 5, true, "1"])
    assert.equal(validFixtureDiagnostics({ ...summarize(), epochCount: input }), false);
});

test("waveform projection is diagnostic only, with exact sample rate and retained thresholds", () => {
  for (const [field, input, expected] of [["sampleRate", 44_100, false], ["rmsLeft", 0.01, false],
    ["rmsRight", 0, false], ["leftRatio", 8, false], ["rightRatio", 0, false],
    ["rmsLeft", NaN, null], ["rightRatio", Infinity, null], ["sampleRate", secret, null]]) {
    const r = report(); r.browser.epochs = [epoch()]; r.browser.epochs[0][field] = input;
    const value = summarize(r); assert.equal(value.waveformPass, expected); safe(value);
  }
});

test("fixed enum values round trip and every boundary remains a diagnostic label", () => {
  for (const boundary of ["report_invalid", "forced_termination", "cleanup", "runner", "native_exit",
    "browser_incomplete", "browser", "relay_proof", "stereo_or_lifecycle", "none"]) {
    const value = summarize(report(), boundary); assert.equal(value.boundary, boundary); safe(value);
  }
  for (const failure of ["interrupted", "relay_credentials_refused", "deadline", "runner_or_native_boundary", "cleanup"]) {
    const r = report(); r.failure = failure; assert.equal(summarize(r).runnerFailure, failure); safe(summarize(r));
  }
  const r = report(); r.browser.epochs = [epoch()];
  r.browser.failure = "relay"; r.browser.epochs[0].errorStage = "candidate";
  r.browser.epochs[0].errorCode = "OperationError"; r.browser.epochs[0].peerState = "failed";
  r.browser.nativeSnapshots = [{ phase: "failure_before_cleanup" }];
  const value = summarize(r); safe(value);
  assert.equal(value.browserFailure, "relay"); assert.equal(value.errorStage, "candidate");
  assert.equal(value.errorCode, "OperationError"); assert.equal(value.peerState, "failed");
  assert.equal(value.nativePhase, "failure_before_cleanup");
});
