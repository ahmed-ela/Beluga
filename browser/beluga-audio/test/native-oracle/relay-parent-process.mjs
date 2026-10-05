import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { admitSharingMaster } from "./relay-lifecycle.mjs";
import { relayEpochsPass } from "./relay-contract.js";
import { validShareID } from "../../public/protocol.js";
import { summarizeFixtureDiagnostics } from "./relay-fixture-diagnostics.mjs";

// Master bytes stay in the parent; the fixture receives only temporary ICE.
export function readSharingMasterInput(input, { privatePipe, signal, timeoutMilliseconds = 5_000 }) {
  if (!privatePipe || input.isTTY || signal?.aborted || !Number.isInteger(timeoutMilliseconds) ||
      timeoutMilliseconds < 1 || timeoutMilliseconds > 5_000) return Promise.reject(new Error("sharing_input_refused"));
  return new Promise((resolve, reject) => {
    const chunks = []; let size = 0, finished = false;
    const finish = (failed) => {
      if (finished) return;
      finished = true; clearTimeout(timer); input.pause();
      input.removeListener("data", data); input.removeListener("end", end);
      input.removeListener("error", failure); input.removeListener("close", failure);
      signal?.removeEventListener("abort", failure);
      let bytes;
      try {
        if (failed) throw new Error();
        bytes = Buffer.concat(chunks); resolve(admitSharingMaster(bytes));
      } catch { reject(new Error("sharing_input_refused")); }
      finally { bytes?.fill(0); for (const chunk of chunks) chunk.fill(0); chunks.length = 0; }
    };
    const data = (chunk) => {
      if (!(chunk instanceof Uint8Array) || (size += chunk.byteLength) > 16_384) { finish(true); return; }
      chunks.push(Buffer.from(chunk));
    };
    const end = () => finish(false), failure = () => finish(true);
    const timer = setTimeout(failure, timeoutMilliseconds);
    input.on("data", data); input.once("end", end); input.once("error", failure); input.once("close", failure);
    signal?.addEventListener("abort", failure, { once: true }); input.resume();
  });
}

export function admitFixtureOutcome(value, exitCode, forced = false) {
  const record = (item) => item !== null && typeof item === "object" && !Array.isArray(item);
  const scopeKeys = ["systemAudioVerified", "deployedWorkerVerified", "unrelatedNetworksVerified", "physicalDeviceVerified"];
  const completeReport = record(value) && value.kind === "fixture-native-to-relay-headless-browser" &&
    typeof value.passed === "boolean" && typeof value.relayVerified === "boolean" &&
    (value.nativeExitCode === null || Number.isInteger(value.nativeExitCode)) &&
    (!Object.hasOwn(value, "failure") || ["interrupted", "relay_credentials_refused", "deadline",
      "runner_or_native_boundary", "cleanup"].includes(value.failure)) && scopeKeys.every((key) => value[key] === false) &&
    (value.browser === null || (record(value.browser) && typeof value.browser.complete === "boolean" &&
      (value.browser.failure === null || typeof value.browser.failure === "string") &&
      Number.isSafeInteger(value.browser.microphoneCalls) && value.browser.microphoneCalls >= 0 &&
      Array.isArray(value.browser.epochs) && value.browser.epochs.every(record) &&
      Array.isArray(value.browser.nativeSnapshots) && record(value.browser.broker)));
  const cleanupVerified = !forced && Number.isInteger(exitCode) && completeReport &&
    value.ownedChildrenReaped === true && value.ownedProcessGroupsGone === true;
  const epochs = value?.browser?.epochs;
  const passed = cleanupVerified && exitCode === 0 && value.passed === true && value.relayVerified === true &&
    !value.failure && value.nativeExitCode === 0 && value.browser?.complete === true && value.browser.failure === null &&
    value.browser.microphoneCalls === 0 && relayEpochsPass(epochs) && epochs.every((epoch) =>
      validShareID(epoch.shareID) && ["rmsLeft", "rmsRight", "leftRatio", "rightRatio"].every((key) =>
        Number.isFinite(epoch[key])) && epoch.rmsLeft > 0.01 && epoch.rmsRight > 0.01 &&
      epoch.leftRatio > 8 && epoch.rightRatio > 8) && epochs[0].shareID === epochs[1].shareID &&
    epochs[2].shareID !== epochs[0].shareID &&
    scopeKeys.every((key) => value[key] === false);
  // Diagnostics describe the failed boundary; they never authorize a pass or
  // cleanup. Project only fixed enums/booleans/bounded counters, not child logs.
  const boundary = forced ? "forced_termination" : !completeReport ? "report_invalid" :
    !cleanupVerified ? "cleanup" : value.failure ? "runner" :
    value.nativeExitCode !== 0 ? "native_exit" : value.browser?.failure ? "browser" :
    value.browser?.complete !== true ? "browser_incomplete" :
    !relayEpochsPass(epochs) ? "relay_proof" : exitCode !== 0 ? "runner" :
    !passed ? "stereo_or_lifecycle" : "none";
  return { passed, cleanupVerified, diagnostics: summarizeFixtureDiagnostics(value, boundary) };
}

export function runOwnedRelayFixture(envelope, { signal, runMilliseconds, testBundle, chrome,
  spawnImpl = spawn, executable = process.execPath, environment = process.env,
  terminateGraceMilliseconds = 10_000, killGraceMilliseconds = 2_000 }) {
  if (signal?.aborted) return Promise.resolve({ passed: false, cleanupVerified: true });
  const runner = fileURLToPath(new URL("./run.mjs", import.meta.url));
  const env = Object.fromEntries(["PATH", "HOME", "TMPDIR", "DEVELOPER_DIR", "SDKROOT", "LANG", "NODE_PATH"]
    .filter((key) => environment[key] !== undefined).map((key) => [key, environment[key]]));
  return new Promise((resolve) => {
    let child, inputBytes, finished = false, stopping = false, forced = false, size = 0, timer, forceTimer, reapTimer;
    const chunks = [];
    const finish = (code) => {
      if (finished) return;
      finished = true; clearTimeout(timer); clearTimeout(forceTimer); clearTimeout(reapTimer);
      signal?.removeEventListener("abort", stop);
      let bytes, value;
      try { bytes = Buffer.concat(chunks); value = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)); }
      catch { value = null; }
      finally { bytes?.fill(0); inputBytes?.fill(0); for (const chunk of chunks) chunk.fill(0); chunks.length = 0; }
      const outcome = admitFixtureOutcome(value, code, forced);
      if (stopping || signal?.aborted) outcome.passed = false;
      resolve(outcome);
    };
    const stop = () => {
      if (finished || stopping) return;
      stopping = true;
      try { child?.kill("SIGTERM"); } catch { forced = true; }
      forceTimer = setTimeout(() => {
        if (finished) return;
        forced = true;
        try { child?.kill("SIGKILL"); } catch { /* Cleanup remains unverified. */ }
        reapTimer = setTimeout(() => finish(null), killGraceMilliseconds);
      }, terminateGraceMilliseconds);
    };
    try {
      child = spawnImpl(executable, [runner, "--test-bundle", testBundle, "--chrome", chrome,
        "--timeout-seconds", String(runMilliseconds / 1_000), "--relay-ice-stdin", "true"],
      { stdio: ["pipe", "pipe", "pipe"], env });
      child.once("error", () => { forced = true; if (child.pid) stop(); else finish(null); });
      child.once("close", (code) => finish(code));
      child.stdout.on("data", (chunk) => {
        if (finished) return;
        if (!(chunk instanceof Uint8Array) || (size += chunk.byteLength) > 65_536) { forced = true; stop(); return; }
        chunks.push(Buffer.from(chunk));
      });
      child.stderr.resume();
      child.stdin.on("error", stop);
      timer = setTimeout(stop, runMilliseconds + 25_000);
      signal?.addEventListener("abort", stop, { once: true });
      if (signal?.aborted) { stop(); return; }
      inputBytes = Buffer.from(JSON.stringify(envelope));
      child.stdin.end(inputBytes, () => inputBytes.fill(0));
    } catch { forced = true; if (child) stop(); else finish(null); }
  });
}
