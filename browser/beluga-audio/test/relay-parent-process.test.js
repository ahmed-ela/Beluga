import test from "node:test";
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { PassThrough, Writable } from "node:stream";
import { readSharingMasterInput, runOwnedRelayFixture, admitFixtureOutcome } from "./native-oracle/relay-parent-process.mjs";

const master = { apiToken: "public-test-only-master-token=", keyId: "a".repeat(32), name: "beluga-audio-share-v1" };
const envelope = () => ({ expiresAt: Date.now() + 180_000, iceServers: [{
  urls: ["turn:turn.cloudflare.com:3478?transport=udp"], username: "temporary-test-only", credential: "temporary-password" }] });
const report = () => ({ kind: "fixture-native-to-relay-headless-browser", passed: true, relayVerified: true,
  nativeExitCode: 0, ownedChildrenReaped: true, ownedProcessGroupsGone: true,
  systemAudioVerified: false, deployedWorkerVerified: false, unrelatedNetworksVerified: false, physicalDeviceVerified: false,
  browser: { complete: true, failure: null, microphoneCalls: 0, nativeSnapshots: [], broker: {},
    epochs: ["revoke", "revoke", "expiry"].map((phase, index) => ({ epoch: index + 1, phase,
      shareID: (index < 2 ? "A" : "B").repeat(21) + "A", decoded: true, closed: true, topology: true,
      failure: null, sampleRate: 48_000, microphoneCalls: 0, rmsLeft: 0.1, rmsRight: 0.1, leftRatio: 20, rightRatio: 20,
      relay: { status: "verified", observations: 2, elapsedMs: 1000, pairBytesReceivedDelta: 1000, audioBytesReceivedDelta: 800 } })) } });
function fakeChild(onInput) {
  const child = new EventEmitter(); child.pid = 100001; child.signals = [];
  child.stdout = new PassThrough(); child.stderr = new PassThrough();
  const input = [];
  child.stdin = new Writable({ write(chunk, encoding, callback) { input.push(Buffer.from(chunk)); callback(); },
    final(callback) { onInput?.(JSON.parse(Buffer.concat(input).toString("utf8")), child); callback(); } });
  child.kill = (signal) => { child.signals.push(signal); return true; };
  return child;
}
const options = (patch = {}) => ({ runMilliseconds: 60_000, testBundle: "/private/fixture.xctest",
  chrome: "/private/Chrome", ...patch });

test("sharing master is pipe-only, bounded, and detached on cancellation without logging payloads", async () => {
  const good = new PassThrough();
  const pending = readSharingMasterInput(good, { privatePipe: true });
  good.end(Buffer.from(JSON.stringify(master)));
  assert.deepEqual(await pending, master);
  for (const kind of ["abort", "oversize", "error", "timeout"]) {
    const stream = new PassThrough(), abort = new AbortController();
    const rejected = readSharingMasterInput(stream, { privatePipe: true, signal: abort.signal, timeoutMilliseconds: 5 });
    if (kind === "abort") { stream.write("partial"); abort.abort(); }
    if (kind === "oversize") stream.write(Buffer.alloc(16_385));
    if (kind === "error") stream.emit("error", new Error("must-not-escape"));
    await assert.rejects(rejected, { message: "sharing_input_refused" });
    for (const event of ["data", "end", "error", "close"]) assert.equal(stream.listenerCount(event), 0);
    assert.equal(stream.isPaused(), true);
  }
  await assert.rejects(readSharingMasterInput(new PassThrough(), { privatePipe: false }), /sharing_input_refused/);
});

test("parent admits only native relay stereo proof and exact source lifecycle with verified cleanup", () => {
  assert.deepEqual(admitFixtureOutcome(report(), 0), { passed: true, cleanupVerified: true });
  for (const change of [
    (v) => { v.nativeExitCode = 1; }, (v) => { v.relayVerified = false; }, (v) => { v.browser.complete = false; },
    (v) => { v.browser.failure = "relay"; }, (v) => { v.browser.microphoneCalls = 1; },
    (v) => { v.browser.epochs[0].rmsLeft = 0; }, (v) => { v.browser.epochs[1].rightRatio = Infinity; },
    (v) => { v.browser.epochs[1].shareID = v.browser.epochs[2].shareID; },
    (v) => { v.browser.epochs[2].shareID = v.browser.epochs[0].shareID; },
    (v) => { v.browser.epochs[0].relay.status = "failed"; },
    (v) => { v.systemAudioVerified = true; }, (v) => { v.physicalDeviceVerified = true; },
    (v) => { v.ownedProcessGroupsGone = false; },
  ]) { const value = report(); change(value); assert.equal(admitFixtureOutcome(value, 0).passed, false); }
  assert.equal(admitFixtureOutcome(report(), 1).passed, false);
  assert.deepEqual(admitFixtureOutcome(report(), 0, true), { passed: false, cleanupVerified: false });
  assert.deepEqual(admitFixtureOutcome({ kind: report().kind, ownedChildrenReaped: true,
    ownedProcessGroupsGone: true }, 0), { passed: false, cleanupVerified: false });
  for (const key of Object.keys(report())) {
    const partial = report(); delete partial[key];
    assert.deepEqual(admitFixtureOutcome(partial, 0), { passed: false, cleanupVerified: false });
  }
  const failed = { ...report(), passed: false, relayVerified: false, nativeExitCode: null,
    failure: "runner_or_native_boundary", browser: null };
  assert.deepEqual(admitFixtureOutcome(failed, 1), { passed: false, cleanupVerified: true });
});

test("fixture receives only ephemeral ICE on stdin with a sanitized environment and fixed executable path", async () => {
  const input = envelope(); let invocation;
  const child = fakeChild((received, process) => {
    assert.deepEqual(received, input);
    setImmediate(() => { process.stdout.write(JSON.stringify(report())); process.emit("close", 0); });
  });
  const outcome = await runOwnedRelayFixture(input, options({ executable: "/exact/node", environment: {
    PATH: "/usr/bin", HOME: "/private/test-home", NODE_PATH: "/private/ws", SECRET: master.apiToken,
    NODE_OPTIONS: "--require /unsafe.js" }, spawnImpl: (...args) => { invocation = args; return child; } }));
  assert.deepEqual(outcome, { passed: true, cleanupVerified: true });
  assert.equal(invocation[0], "/exact/node");
  assert.equal(invocation[1].at(-1), "true"); assert.equal(invocation[1].at(-2), "--relay-ice-stdin");
  assert.deepEqual(invocation[2].env, { PATH: "/usr/bin", HOME: "/private/test-home", NODE_PATH: "/private/ws" });
  assert.equal(JSON.stringify(invocation).includes(master.apiToken), false);
  assert.equal(JSON.stringify(invocation).includes(input.iceServers[0].credential), false);
  assert.deepEqual(child.signals, []);
});

test("cancellation waits for normal runner cleanup but can never retain a passing result", async () => {
  const abort = new AbortController(); let closed = false;
  const child = fakeChild(() => setImmediate(() => abort.abort()));
  child.kill = (signal) => {
    child.signals.push(signal);
    setImmediate(() => { closed = true; child.stdout.write(JSON.stringify(report())); child.emit("close", 1); });
    return true;
  };
  const outcome = await runOwnedRelayFixture(envelope(), options({ signal: abort.signal, spawnImpl: () => child }));
  assert.equal(closed, true); assert.deepEqual(child.signals, ["SIGTERM"]);
  assert.deepEqual(outcome, { passed: false, cleanupVerified: true });
});

test("forced runner termination remains cleanup-unverified even if a stale passing report arrives", async () => {
  const abort = new AbortController(); const child = fakeChild(() => setImmediate(() => abort.abort()));
  child.kill = (signal) => {
    child.signals.push(signal);
    if (signal === "SIGKILL") setImmediate(() => { child.stdout.write(JSON.stringify(report())); child.emit("close", null); });
    return true;
  };
  const outcome = await runOwnedRelayFixture(envelope(), options({ signal: abort.signal, spawnImpl: () => child,
    terminateGraceMilliseconds: 2, killGraceMilliseconds: 2 }));
  assert.deepEqual(child.signals, ["SIGTERM", "SIGKILL"]);
  assert.deepEqual(outcome, { passed: false, cleanupVerified: false });
});

test("malformed output, spawn failure and excessive output cannot escape into a passing or secret-bearing report", async () => {
  for (const mode of ["malformed", "oversize", "spawn"]) {
    const child = fakeChild((_, process) => setImmediate(() => {
      process.stdout.write(mode === "oversize" ? Buffer.alloc(65_537) : "private-error-must-not-escape");
      process.emit("close", 0);
    }));
    const outcome = await runOwnedRelayFixture(envelope(), options({ spawnImpl: () => {
      if (mode === "spawn") throw new Error("private-spawn-error"); return child;
    } }));
    assert.deepEqual(outcome, { passed: false, cleanupVerified: false });
    assert.equal(JSON.stringify(outcome).includes("private"), false);
  }
});
