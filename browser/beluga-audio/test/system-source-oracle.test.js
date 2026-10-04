import test from "node:test";
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { admitSystemSourceGate, parseRouteLine, systemSourceEvidencePasses } from "./native-oracle/system-source-contract.mjs";
import { createSystemSourceCancellation } from "./native-oracle/system-source-cancellation.mjs";

function gateFixture() {
  const item = (name) => ({ path: `/private/owned/${name}`, sha256: "a".repeat(64) });
  const gate = { schema: 1, checkedAt: 1_000, expiresAt: 91_000, oracleExecutionApproved: true,
    audioChallengeApproved: true, capture: { ...item("xctest"), designatedRequirement: "identifier test.capture",
      permission: "confirmed" }, emitter: item("emitter"), monitor: item("monitor"),
    routes: { input: "input", output: "output", system: "output" },
    phone: { state: "inactive", coexistenceChallengeApproved: false } };
  return { gate, artifacts: structuredClone({ capture: gate.capture, emitter: gate.emitter, monitor: gate.monitor }) };
}

test("real source opt-in requires fresh specific authority and executable identity before any native action", () => {
  const { gate, artifacts } = gateFixture();
  assert.equal(admitSystemSourceGate(gate, artifacts, 2_000), gate);
  const mutations = [
    (g) => { g.oracleExecutionApproved = false; }, (g) => { g.audioChallengeApproved = false; },
    (g) => { g.capture.permission = "unknown"; }, (g) => { g.capture.permission = true; },
    (g) => { g.capture.designatedRequirement = "different"; }, (g) => { g.capture.path = "/other/xctest"; },
    (g) => { g.emitter.sha256 = "b".repeat(64); }, (g) => { g.monitor.sha256 = "b".repeat(64); },
    (g) => { g.phone.state = "active"; }, (g) => { g.phone.state = "unknown"; },
    (g) => { g.phone.state = "unknown"; g.phone.coexistenceChallengeApproved = true; },
    (g) => { g.routes.input = "contains newline\n"; }, (g) => { g.extra = "not admitted"; },
    (g) => { g.checkedAt = 3_000; }, (g) => { g.expiresAt = 2_000; },
    (g) => { g.expiresAt = 200_000; },
  ];
  for (const mutate of mutations) {
    const value = structuredClone(gate); mutate(value);
    assert.throws(() => admitSystemSourceGate(value, artifacts, 2_000));
  }
  assert.throws(() => admitSystemSourceGate(gate, artifacts, 31_001), /stale_gate/);
  assert.doesNotThrow(() => admitSystemSourceGate(gate, artifacts, 40_000, { initial: false }));
  assert.throws(() => admitSystemSourceGate(gate, artifacts, 91_000, { initial: false }));
  gate.capture.permission = "one-request-approved";
  gate.phone = { state: "active", coexistenceChallengeApproved: true };
  assert.doesNotThrow(() => admitSystemSourceGate(gate, artifacts, 2_000));
});

function resultFixture() {
  const source = { starts: 1, confirmedStarts: 1, stops: 1, confirmedStops: 1, attachedListeners: 0 };
  const challenge = { nonce: "1".repeat(32), leftHz: 470, rightHz: 2310 };
  const snapshots = ["before_revoke", "after_revoke", "after_expiry", "after_owner_loss", "success"].map((phase, index) =>
    ({ phase, activeListeners: index === 0 ? 1 : 0, status: index === 0 ? "active" : index < 3 ? "ended" : "failed",
      sources: Array.from({ length: [1, 1, 2, 3, 3][index] }, () => index === 0
        ? { ...source, stops: 0, confirmedStops: 0, attachedListeners: 1 } : { ...source }) }));
  return { kind: "real-system-source-to-loopback-browser", failure: null, nativeExitCode: 0,
    nativeWasKilled: false, emitterWasKilled: false, monitorWasKilled: false, monitorExitCode: 0,
    emitterExitCode: 0, ownedChildrenReaped: true, ownedProcessGroupsGone: true, routeMonitorArmedBeforeAudio: true,
    routes: { input: "input", output: "output", system: "output" },
    routeReady: "READY input=input output=output system=output",
    routeResult: "RESULT notifications=0 teardown=clean input=input output=output system=output", challenge,
    emitter: { event: "complete", starts: 3, stops: 3, frames: 48_000, teardown: true },
    browser: { complete: true, failure: null, microphoneCalls: 0, nativeSnapshots: snapshots,
      epochs: ["revoke", "revoke", "expiry", "owner_loss"].map((phase, index) => ({ epoch: index + 1, phase,
        shareID: ["a", "a", "b", "c"][index].repeat(22), challengeNonce: challenge.nonce,
        decoded: true, closed: true, topology: true, failure: null, microphoneCalls: 0, sampleRate: 48_000,
        windows: 2, rmsLeft: 0.08, rmsRight: 0.08, leftRatio: 30, rightRatio: 30 })) } };
}

test("real source verdict refuses missing native teardown, owner loss, route history, waveform or challenge evidence", () => {
  assert.equal(systemSourceEvidencePasses(resultFixture()), true);
  const mutations = [
    (r) => { r.kind = "fixture-native-to-headless-browser"; }, (r) => { r.failure = "deadline"; },
    (r) => { r.nativeExitCode = null; }, (r) => { r.nativeWasKilled = true; },
    (r) => { r.emitterWasKilled = true; }, (r) => { r.monitorWasKilled = true; },
    (r) => { r.routeMonitorArmedBeforeAudio = false; }, (r) => { r.ownedProcessGroupsGone = false; },
    (r) => { r.routeResult = r.routeResult.replace("notifications=0", "notifications=1"); },
    (r) => { r.routeResult = r.routeResult.replace("teardown=clean", "teardown=failed"); },
    (r) => { r.routeResult = r.routeResult.replace("input=input", "input=changed"); },
    (r) => { r.emitter.teardown = false; }, (r) => { r.emitter.frames = 0; },
    (r) => { r.browser.epochs[3].phase = "expiry"; }, (r) => { r.browser.epochs.pop(); },
    (r) => { r.browser.epochs[0].challengeNonce = "2".repeat(32); },
    (r) => { r.browser.epochs[1].shareID = "replacement"; },
    (r) => { r.browser.epochs[0].rmsLeft = 0.01; }, (r) => { r.browser.epochs[0].rightRatio = 8; },
    (r) => { r.browser.epochs[0].closed = false; }, (r) => { r.browser.epochs[0].topology = false; },
    (r) => { r.browser.microphoneCalls = 1; }, (r) => { r.browser.nativeSnapshots.at(-1).sources[0].confirmedStops = 0; },
    (r) => { r.browser.nativeSnapshots.at(-1).sources[0].attachedListeners = 1; },
    (r) => { r.browser.nativeSnapshots = r.browser.nativeSnapshots.filter((s) => s.phase !== "after_owner_loss"); },
    (r) => { r.browser.nativeSnapshots[0].sources[0].confirmedStarts = 0; },
    (r) => { r.browser.nativeSnapshots[0].activeListeners = 0; },
    (r) => { r.browser.nativeSnapshots[1].sources[0].confirmedStops = 0; },
    (r) => { r.browser.nativeSnapshots[2].status = "active"; },
    (r) => { r.browser.nativeSnapshots[2].sources.pop(); },
    (r) => { r.browser.nativeSnapshots[2].sources[1].stops = 0; },
    (r) => { r.browser.nativeSnapshots[2].sources[1].confirmedStops = 0; },
    (r) => { r.browser.nativeSnapshots[2].sources[1].attachedListeners = 1; },
  ];
  for (const mutate of mutations) {
    const value = resultFixture(); mutate(value); assert.equal(systemSourceEvidencePasses(value), false);
  }
  assert.equal(parseRouteLine("READY input=input output=output system=output\nextra", resultFixture().routes), false);
});

const deferred = () => {
  let resolve;
  const promise = new Promise((done) => { resolve = done; });
  return { promise, resolve };
};

for (const signal of ["SIGINT", "SIGTERM"]) {
  test(`${signal} during setup cancels a pending phase and forbids any later resource start`, async () => {
    const signals = new EventEmitter(), cancellation = createSystemSourceCancellation(signals);
    const setup = deferred();
    let starts = 0, cleanups = 0;
    try {
      const pending = cancellation.run(setup.promise);
      const rejected = assert.rejects(pending, /interrupted/);
      signals.emit(signal);
      await rejected;
      assert.throws(() => { cancellation.throwIfCancelled(); starts++; }, /interrupted/);
      // A late setup result cannot reopen a cancelled scope.
      setup.resolve();
      await assert.rejects(cancellation.run(Promise.resolve()), /interrupted/);
      await cancellation.cleanup(async () => { cleanups++; });
      assert.equal(starts, 0); assert.equal(cleanups, 1);
      const result = cancellation.finalize({ failure: null }, true);
      assert.deepEqual(result, { failure: "interrupted", passed: false, systemAudioVerified: false });
    } finally { cancellation.dispose(); }
    assert.equal(signals.listenerCount("SIGINT"), 0); assert.equal(signals.listenerCount("SIGTERM"), 0);
  });
}

test("signals during teardown cannot interrupt or duplicate the bounded owned cleanup", async () => {
  const signals = new EventEmitter(), cancellation = createSystemSourceCancellation(signals), retirement = deferred();
  let cleanups = 0, retired = false;
  try {
    await cancellation.run(Promise.resolve());
    const cleaning = cancellation.cleanup(async () => { cleanups++; await retirement.promise; retired = true; });
    await Promise.resolve();
    signals.emit("SIGTERM"); signals.emit("SIGINT");
    const repeated = cancellation.cleanup(async () => { cleanups++; });
    assert.equal(repeated, cleaning); assert.equal(cleanups, 1); assert.equal(retired, false);
    retirement.resolve(); await cleaning;
    assert.equal(retired, true); assert.equal(cleanups, 1);
    assert.equal(cancellation.finalize({ failure: null }, true).passed, false);
  } finally { cancellation.dispose(); }
});

test("a late signal permanently replaces a provisional passing verdict before report publication", async () => {
  const signals = new EventEmitter(), cancellation = createSystemSourceCancellation(signals);
  try {
    await cancellation.run(Promise.resolve());
    await cancellation.cleanup(async () => {});
    const result = cancellation.finalize({ failure: null }, true);
    assert.equal(result.passed, true);
    signals.emit("SIGINT");
    assert.equal(cancellation.finalize(result, true).passed, false);
    signals.emit("SIGTERM");
    assert.deepEqual(cancellation.finalize(result, true),
      { failure: "interrupted", passed: false, systemAudioVerified: false });
  } finally { cancellation.dispose(); }
});
