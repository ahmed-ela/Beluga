// Separately opt-in. No build, signing, TCC changes, host launch, phone access or route writes.
import { spawn } from "node:child_process";
import { constants, writeFileSync } from "node:fs";
import { open, readFile, realpath, stat, lstat, mkdtemp, chmod, rm, writeFile } from "node:fs/promises";
import { basename, dirname, join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { createHash, randomBytes, X509Certificate } from "node:crypto";
import { createOracleServer } from "./server.mjs";
import { admitSystemSourceGate, captureDesignatedRequirement, parseRouteLine, systemSourceEvidencePasses } from "./system-source-contract.mjs";
import { createSystemSourceCancellation } from "./system-source-cancellation.mjs";

const hash = (bytes) => createHash("sha256").update(bytes).digest("hex");
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const args = new Map();
const children = new Set(), groups = new Set();
const cancellation = createSystemSourceCancellation();
const environment = Object.fromEntries(["PATH", "HOME", "TMPDIR", "DEVELOPER_DIR", "SDKROOT", "LANG"]
  .filter((key) => process.env[key] !== undefined).map((key) => [key, process.env[key]]));
let directory, broker, brokerClose, native, emitter, monitor, deadline, resultPath, cancelled = false;
const result = { kind: "real-system-source-to-loopback-browser", passed: false, systemAudioVerified: false,
  deployedWorkerVerified: false, phoneCoexistenceVerified: false, internetTURNVerified: false,
  authorizationEvidence: "operator-provided-not-an-OS-permission-preflight", failure: null,
  nativeExitCode: null, emitterExitCode: null, monitorExitCode: null,
  nativeWasKilled: false, emitterWasKilled: false, monitorWasKilled: false,
  routeMonitorArmedBeforeAudio: false, ownedChildrenReaped: false, ownedProcessGroupsGone: false };

function bounded(promise, milliseconds, code = "phase_deadline", interruptible = true) {
  let timer;
  const operation = Promise.race([promise, new Promise((_, reject) => { timer = setTimeout(() => reject(new Error(code)), milliseconds); })]);
  return (interruptible ? cancellation.run(operation) : operation).finally(() => clearTimeout(timer));
}
function child(command, argv, extra = {}, captureOutput = true) {
  cancellation.throwIfCancelled();
  if (cancelled) throw new Error("runner_cancelled");
  const process = spawn(command, argv, { stdio: ["pipe", "pipe", "pipe"], detached: true, env: environment, ...extra });
  const owned = { process, queue: [], waiters: [], code: undefined, text: "", outputInvalid: false };
  children.add(owned); if (process.pid) groups.add(process.pid);
  owned.exit = new Promise((resolve) => {
    const finish = (code) => {
      if (owned.code !== undefined) return;
      owned.code = code; children.delete(owned);
      for (const waiter of owned.waiters.splice(0)) waiter.reject(new Error("child_closed"));
      resolve(code);
    };
    process.once("error", () => finish(-1)); process.once("exit", (code) => finish(code ?? -1));
  });
  process.stdin.on("error", () => {});
  process.stdout.on("data", (bytes) => {
    if (!captureOutput) return;
    owned.text += bytes.toString("utf8");
    if (owned.text.length > 8192) { owned.outputInvalid = true; owned.text = ""; return; }
    let at;
    while ((at = owned.text.indexOf("\n")) >= 0) {
      const line = owned.text.slice(0, at); owned.text = owned.text.slice(at + 1);
      const waiter = owned.waiters.shift();
      if (waiter) waiter.resolve(line);
      else if (owned.queue.length < 32) owned.queue.push(line);
      else owned.outputInvalid = true;
    }
  });
  // Native/browser diagnostics can contain capability-bearing exceptions; never retain them.
  process.stderr.resume();
  owned.line = () => bounded(new Promise((resolve, reject) => {
    if (owned.outputInvalid) { reject(new Error("invalid_child_output")); return; }
    if (owned.queue.length) resolve(owned.queue.shift());
    else if (owned.code !== undefined) reject(new Error("child_closed"));
    else owned.waiters.push({ resolve, reject });
  }), 12_000);
  return owned;
}
function groupAlive(pid, signal = 0) {
  try { process.kill(-pid, signal); return true; } catch (error) { return error.code !== "ESRCH"; }
}
async function commandOutput(command, argv) {
  // Only certificate generation and read-only signature checks use this bounded helper.
  const owned = child(command, argv, {}, false), process = owned.process;
  let output = "";
  for (const stream of [process.stdout, process.stderr]) stream.on("data", (bytes) => {
    if (output.length <= 16_384) output += bytes.toString("utf8");
  });
  try {
    const code = await bounded(owned.exit, 10_000);
    if (code !== 0 || output.length > 16_384) throw new Error("identity_or_certificate_failed");
    return output;
  } finally {
    if (owned.code === undefined) {
      process.kill("SIGKILL");
      await bounded(owned.exit, 3_000, "helper_teardown_deadline", false).catch(() => {});
    }
  }
}
async function artifact(value) {
  if (!value || typeof value.path !== "string" || await realpath(value.path) !== value.path ||
      !(await stat(value.path)).isFile()) throw new Error("invalid_artifact");
  return { path: value.path, sha256: hash(await readFile(value.path)) };
}
function closeBroker() {
  if (!broker) return Promise.resolve();
  return brokerClose ??= bounded(broker.close(), 3_000, "broker_teardown_deadline", false);
}

try {
  for (let index = 2; index < process.argv.length; index += 2) {
    const key = process.argv[index], value = process.argv[index + 1];
    if (!["--gate", "--test-bundle", "--chrome", "--timeout-seconds", "--result"].includes(key) || !value || args.has(key))
      throw new Error("usage");
    args.set(key, value);
  }
  for (const key of ["--gate", "--test-bundle", "--result"]) if (!args.has(key)) throw new Error("usage");
  const seconds = Number(args.get("--timeout-seconds") ?? 75);
  if (!Number.isInteger(seconds) || seconds < 60 || seconds > 90) throw new Error("usage");
  resultPath = resolve(args.get("--result"));
  if (!(await stat(dirname(resultPath))).isDirectory()) throw new Error("invalid_result");
  try { await lstat(resultPath); resultPath = undefined; throw new Error("result_exists"); }
  catch (error) { if (error.code !== "ENOENT") throw error; }
  const gateFile = await open(resolve(args.get("--gate")), constants.O_RDONLY | constants.O_NOFOLLOW);
  let gateBytes;
  try {
    const info = await gateFile.stat();
    if (!info.isFile() || info.uid !== process.getuid() || (info.mode & 0o077) !== 0 || info.size > 16_384)
      throw new Error("invalid_gate_file");
    gateBytes = await gateFile.readFile();
  } finally { await gateFile.close(); }
  cancellation.throwIfCancelled();
  const gate = JSON.parse(gateBytes.toString("utf8"));
  const artifacts = { capture: await artifact(gate.capture), emitter: await artifact(gate.emitter), monitor: await artifact(gate.monitor) };
  // This slice admits only the existing signed XCTest executable. A new app host needs separate review.
  if (basename(artifacts.capture.path) !== "xctest") throw new Error("capture_host_not_supported");
  await commandOutput("/usr/bin/codesign", ["--verify", "--strict", artifacts.capture.path]);
  const signature = await commandOutput("/usr/bin/codesign", ["--display", "--requirements", "-", artifacts.capture.path]);
  artifacts.capture.designatedRequirement = captureDesignatedRequirement(signature);
  admitSystemSourceGate(gate, artifacts, Date.now());
  const recheck = () => {
    cancellation.throwIfCancelled();
    if (cancelled) throw new Error("runner_cancelled");
    return admitSystemSourceGate(gate, artifacts, Date.now(), { initial: false });
  };
  const bundle = resolve(args.get("--test-bundle"));
  if (!bundle.endsWith(".xctest") || !(await stat(bundle)).isDirectory()) throw new Error("invalid_test_bundle");
  const chrome = args.get("--chrome") ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
  if (!(await stat(chrome)).isFile()) throw new Error("invalid_browser");
  result.gateSHA256 = hash(gateBytes); result.capturePermissionMode = gate.capture.permission;
  result.routes = gate.routes;
  const randomness = randomBytes(16);
  result.challenge = { nonce: randomness.toString("hex"), leftHz: 400 + (randomness[0] % 100) * 10,
    rightHz: 2300 + (randomness[1] % 100) * 10 };
  directory = await mkdtemp(join(tmpdir(), "beluga-system-source-oracle.")); await chmod(directory, 0o700);
  const keyPath = join(directory, "key.pem"), certPath = join(directory, "cert.pem"), events = join(directory, "route-events");
  await commandOutput("/usr/bin/openssl", ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", keyPath,
    "-out", certPath, "-days", "1", "-config", fileURLToPath(new URL("./certificate.cnf", import.meta.url)), "-extensions", "san"]);
  await chmod(keyPath, 0o600); await writeFile(events, "", { mode: 0o600, flag: "wx" });
  const key = await readFile(keyPath), cert = await readFile(certPath), certificate = new X509Certificate(cert);
  const pin = hash(certificate.raw);
  const spki = createHash("sha256").update(certificate.publicKey.export({ type: "spki", format: "der" })).digest("base64");
  const work = (async () => {
    recheck();
    monitor = child(gate.monitor.path, [events, gate.routes.input, gate.routes.output, gate.routes.system]);
    result.routeReady = await monitor.line();
    if (!parseRouteLine(result.routeReady, gate.routes)) throw new Error("route_monitor_not_armed");
    result.routeMonitorArmedBeforeAudio = true;
    emitter = child(gate.emitter.path, [String(seconds), String(result.challenge.leftHz), String(result.challenge.rightHz), gate.routes.output]);
    if (await emitter.line() !== '{"event":"ready"}') throw new Error("emitter_not_ready");
    let starts = 0, stops = 0;
    broker = await createOracleServer({ key, cert, systemSource: { challenge: result.challenge,
      async startEmitter() {
        recheck();
        if (starts !== stops || starts >= 3 || monitor.code !== undefined) throw new Error("emitter_order");
        emitter.process.stdin.write("START\n");
        const ack = JSON.parse(await emitter.line());
        if (Object.keys(ack).sort().join(",") !== "event,starts" || ack.event !== "started" || ack.starts !== starts + 1)
          throw new Error("emitter_start_unconfirmed");
        starts++;
      },
      async stopEmitter() {
        if (starts !== stops + 1) throw new Error("emitter_order");
        emitter.process.stdin.write("STOP\n");
        const ack = JSON.parse(await emitter.line());
        if (Object.keys(ack).sort().join(",") !== "event,stops" || ack.event !== "stopped" || ack.stops !== stops + 1)
          throw new Error("emitter_stop_unconfirmed");
        stops++;
      } } });
    key.fill(0);
    if (cancelled || cancellation.cancelled) { await closeBroker(); throw new Error("runner_cancelled"); }
    child(chrome, ["--headless=new", `--user-data-dir=${join(directory, "chrome-profile")}`, "--no-first-run",
      "--disable-default-apps", "--disable-extensions", "--disable-audio-input", "--disable-audio-output",
      "--autoplay-policy=no-user-gesture-required", "--disable-background-timer-throttling", "--disable-renderer-backgrounding",
      "--disable-backgrounding-occluded-windows", `--ignore-certificate-errors-spki-list=${spki}`, `${broker.origin}/oracle`], {}, false);
    recheck();
    native = child(gate.capture.path, ["-XCTest", "CaptureServerTests.BelugaAudioShareBrowserIntegrationTests/testRealSystemSourceStereoRejoinRevokeExpiryAndOwnerLoss", bundle],
      { env: { ...environment, BELUGA_AUDIO_SHARE_ORACLE_URL: broker.origin, BELUGA_AUDIO_SHARE_ORACLE_CERT_SHA256: pin,
        BELUGA_AUDIO_SHARE_SYSTEM_SOURCE_PERMISSION: gate.capture.permission,
        BELUGA_AUDIO_SHARE_SYSTEM_SOURCE_GATE_SHA256: result.gateSHA256,
        BELUGA_AUDIO_SHARE_SYSTEM_SOURCE_NONCE: result.challenge.nonce } }, false);
    result.nativeExitCode = await native.exit;
    result.browser = broker.state();
    emitter.process.stdin.write("QUIT\n"); result.emitter = JSON.parse(await emitter.line());
    result.emitterExitCode = await bounded(emitter.exit, 3_000);
    monitor.process.stdin.write("STOP\n"); result.routeResult = await monitor.line();
    result.monitorExitCode = await bounded(monitor.exit, 3_000);
  })();
  await cancellation.run(Promise.race([work,
    new Promise((_, reject) => { deadline = setTimeout(() => reject(new Error("deadline")), seconds * 1_000); })]));
} catch (error) {
  const names = new Set(["usage", "invalid_result", "result_exists", "invalid_gate_file", "capture_host_not_supported",
    "capture_identity_mismatch", "invalid_gate", "execution_not_authorized", "stale_gate", "phone_not_admitted",
    "capture_authorization_unknown", "invalid_artifact", "artifact_mismatch", "invalid_routes", "deadline", "interrupted"]);
  result.failure = names.has(error?.message) ? error.message : "runner_or_native_boundary";
} finally {
  try {
    await cancellation.cleanup(async () => {
      cancelled = true;
      clearTimeout(deadline);
      if (broker) result.browser = broker.state();
      for (const [name, owned] of [["native", native], ["emitter", emitter], ["monitor", monitor]]) {
        if (owned && owned.code === undefined) result[`${name}WasKilled`] = true;
      }
      for (const pid of groups) groupAlive(pid, "SIGTERM");
      await sleep(300);
      for (const pid of groups) if (groupAlive(pid)) groupAlive(pid, "SIGKILL");
      const until = Date.now() + 3_000;
      while ((children.size || [...groups].some((pid) => groupAlive(pid))) && Date.now() < until) await sleep(25);
      result.ownedChildrenReaped = children.size === 0;
      result.ownedProcessGroupsGone = [...groups].every((pid) => !groupAlive(pid));
      await closeBroker();
      if (directory) await bounded(rm(directory, { recursive: true, force: true }), 3_000, "scratch_teardown_deadline", false);
    });
  } catch { result.failure ??= "cleanup_failed"; }
}
// Keep handlers through setup, teardown and the last verdict. Publishing the small report
// is synchronous: there is no awaited write between this final interruption check and exit status.
try {
  cancellation.finalize(result, systemSourceEvidencePasses(result));
  if (resultPath) writeFileSync(resultPath, `${JSON.stringify(result, null, 2)}\n`, { mode: 0o600, flag: "wx" });
  console.log(JSON.stringify(result));
  process.exitCode = result.passed ? 0 : 1;
} finally { cancellation.dispose(); }
