// Pure admission/evidence checks. This module cannot launch a process or access audio.
import { isAbsolute } from "node:path";

const exact = (value, keys) => value && typeof value === "object" && !Array.isArray(value) &&
  Object.keys(value).sort().join(",") === [...keys].sort().join(",");
const sha = (value) => typeof value === "string" && /^[a-f0-9]{64}$/.test(value);
const safeText = (value, bound = 256) => typeof value === "string" && value.length > 0 &&
  value.length <= bound && !/[\x00-\x1f\x7f]/.test(value);
const require = (condition, code) => { if (!condition) throw new Error(code); };
const artifactKeys = ["path", "sha256"];

export function admitSystemSourceGate(gate, artifacts, now, { initial = true } = {}) {
  require(exact(gate, ["schema", "checkedAt", "expiresAt", "oracleExecutionApproved", "audioChallengeApproved",
    "capture", "emitter", "monitor", "routes", "phone"]), "invalid_gate");
  require(gate.schema === 1 && gate.oracleExecutionApproved === true && gate.audioChallengeApproved === true,
    "execution_not_authorized");
  require(Number.isSafeInteger(now) && Number.isSafeInteger(gate.checkedAt) && Number.isSafeInteger(gate.expiresAt) &&
    gate.checkedAt <= now && now < gate.expiresAt && gate.expiresAt - gate.checkedAt <= 120_000 &&
    gate.expiresAt > gate.checkedAt && (!initial || now - gate.checkedAt <= 30_000), "stale_gate");
  require(exact(gate.phone, ["state", "coexistenceChallengeApproved"]) &&
    typeof gate.phone.coexistenceChallengeApproved === "boolean" &&
    (["absent", "inactive"].includes(gate.phone.state) ||
      (gate.phone.state === "active" && gate.phone.coexistenceChallengeApproved === true)), "phone_not_admitted");
  require(exact(gate.capture, [...artifactKeys, "designatedRequirement", "permission"]) &&
    ["confirmed", "one-request-approved"].includes(gate.capture.permission) &&
    safeText(gate.capture.designatedRequirement, 4096), "capture_authorization_unknown");
  require(exact(gate.emitter, artifactKeys) && exact(gate.monitor, artifactKeys), "invalid_artifact");
  for (const name of ["capture", "emitter", "monitor"]) {
    const expected = gate[name], actual = artifacts?.[name];
    require(safeText(expected.path, 4096) && isAbsolute(expected.path) && sha(expected.sha256) &&
      actual?.path === expected.path && actual?.sha256 === expected.sha256, "artifact_mismatch");
  }
  require(artifacts.capture.designatedRequirement === gate.capture.designatedRequirement, "capture_identity_mismatch");
  require(exact(gate.routes, ["input", "output", "system"]) &&
    Object.values(gate.routes).every((value) => safeText(value) && !/\s/.test(value)), "invalid_routes");
  return gate;
}

export function parseRouteLine(line, expected, terminal = false) {
  if (!exact(expected, ["input", "output", "system"])) return false;
  const pattern = terminal
    ? /^RESULT notifications=0 teardown=clean input=(\S+) output=(\S+) system=(\S+)$/
    : /^READY input=(\S+) output=(\S+) system=(\S+)$/;
  const match = typeof line === "string" && pattern.exec(line);
  return !!match && match[1] === expected.input && match[2] === expected.output && match[3] === expected.system;
}

export function systemSourceEvidencePasses(result) {
  if (!result || result.kind !== "real-system-source-to-loopback-browser" || result.failure !== null ||
      result.nativeExitCode !== 0 || result.nativeWasKilled !== false || result.emitterWasKilled !== false ||
      result.monitorWasKilled !== false || result.monitorExitCode !== 0 || result.emitterExitCode !== 0 ||
      result.ownedChildrenReaped !== true || result.ownedProcessGroupsGone !== true ||
      result.routeMonitorArmedBeforeAudio !== true || !parseRouteLine(result.routeReady, result.routes) ||
      !parseRouteLine(result.routeResult, result.routes, true)) return false;
  const challenge = result.challenge;
  if (!exact(challenge, ["nonce", "leftHz", "rightHz"]) || !/^[a-f0-9]{32}$/.test(challenge.nonce) ||
      ![challenge.leftHz, challenge.rightHz].every((n) => Number.isInteger(n) && n >= 200 && n <= 4000) ||
      challenge.leftHz === challenge.rightHz) return false;
  const emitter = result.emitter;
  if (!exact(emitter, ["event", "starts", "stops", "frames", "teardown"]) || emitter.event !== "complete" ||
      emitter.starts !== 3 || emitter.stops !== 3 || !Number.isSafeInteger(emitter.frames) ||
      emitter.frames <= 0 || emitter.teardown !== true) return false;
  const browser = result.browser;
  if (!browser || browser.complete !== true || browser.failure !== null || browser.microphoneCalls !== 0 ||
      !Array.isArray(browser.epochs) || browser.epochs.length !== 4) return false;
  const phases = ["revoke", "revoke", "expiry", "owner_loss"];
  if (!browser.epochs.every((epoch, index) => epoch.epoch === index + 1 && epoch.phase === phases[index] &&
      typeof epoch.shareID === "string" && /^[A-Za-z0-9_-]{22}$/.test(epoch.shareID) &&
      epoch.challengeNonce === challenge.nonce && epoch.decoded === true && epoch.closed === true &&
      epoch.topology === true && epoch.failure === null && epoch.microphoneCalls === 0 && epoch.sampleRate === 48_000 &&
      Number.isSafeInteger(epoch.windows) && epoch.windows > 0 &&
      [epoch.rmsLeft, epoch.rmsRight, epoch.leftRatio, epoch.rightRatio].every(Number.isFinite) &&
      epoch.rmsLeft > 0.01 && epoch.rmsRight > 0.01 && epoch.leftRatio > 8 && epoch.rightRatio > 8)) return false;
  if (browser.epochs[0].shareID !== browser.epochs[1].shareID ||
      new Set([browser.epochs[0].shareID, browser.epochs[2].shareID, browser.epochs[3].shareID]).size !== 3) return false;
  const snapshots = browser.nativeSnapshots;
  const snapshotPhases = ["before_revoke", "after_revoke", "after_expiry", "after_owner_loss", "success"];
  if (!Array.isArray(snapshots) || snapshots.length !== snapshotPhases.length) return false;
  return snapshots.every((snapshot, index) => {
    const live = index === 0;
    return exact(snapshot, ["phase", "activeListeners", "status", "sources"]) && snapshot.phase === snapshotPhases[index] &&
      snapshot.activeListeners === (live ? 1 : 0) &&
      (live ? snapshot.status === "active" : index >= 3 ? snapshot.status === "failed" : ["ended", "failed"].includes(snapshot.status)) &&
      Array.isArray(snapshot.sources) && snapshot.sources.length === [1, 1, 2, 3, 3][index] && snapshot.sources.every((source) =>
        exact(source, ["attachedListeners", "confirmedStarts", "confirmedStops", "starts", "stops"]) &&
        source.starts === 1 && source.confirmedStarts === 1 && source.stops === (live ? 0 : 1) &&
        source.confirmedStops === (live ? 0 : 1) && source.attachedListeners === (live ? 1 : 0));
  });
}
