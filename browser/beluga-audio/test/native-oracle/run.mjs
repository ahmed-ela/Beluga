// Explicit opt-in only. Owns one HTTPS fixture broker, private headless browser and XCTest.
// No CDP, signed-in browser, global trust, microphone, system tap or real audio output.
import { spawn } from "node:child_process";
import { mkdtemp, chmod, readFile, rm, writeFile, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { X509Certificate, createHash } from "node:crypto";
import { createOracleServer } from "./server.mjs";

const args = new Map();
for (let index = 2; index < process.argv.length; index += 2) {
  if (!["--test-bundle", "--chrome", "--timeout-seconds", "--result"].includes(process.argv[index]) || !process.argv[index + 1]) {
    throw new Error("Expected --test-bundle, optional --chrome/--timeout-seconds/--result");
  }
  if (args.has(process.argv[index])) throw new Error("Duplicate option");
  args.set(process.argv[index], process.argv[index + 1]);
}
const testBundle = resolve(args.get("--test-bundle") ?? "");
if (!args.has("--test-bundle") || !testBundle.endsWith(".xctest") || !(await stat(testBundle)).isDirectory()) throw new Error("Exact compiled XCTest bundle required");
const chrome = args.get("--chrome") ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
if (!(await stat(chrome)).isFile()) throw new Error("Chrome executable unavailable");
const seconds = Number(args.get("--timeout-seconds") ?? 60);
if (!Number.isSafeInteger(seconds) || seconds < 45 || seconds > 90) throw new Error("Bound must be 45...90 seconds");
const directory = await mkdtemp(join(tmpdir(), "beluga-native-browser-oracle."));
await chmod(directory, 0o700);
let broker, browser, native, deadline;
const children = new Set();
const ownedGroups = new Set();
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const childEnvironment = Object.fromEntries(["PATH", "HOME", "TMPDIR", "DEVELOPER_DIR", "SDKROOT", "LANG"]
  .filter((key) => process.env[key] !== undefined).map((key) => [key, process.env[key]]));
function child(command, argv, options = {}) {
  const process = spawn(command, argv, { stdio: ["ignore", "pipe", "pipe"], env: childEnvironment, detached: true, ...options });
  children.add(process); process.once("exit", () => children.delete(process));
  // A failed spawn has no live child; consume its EventEmitter error so finally
  // can always release the broker/profile. Native/certificate promises still reject.
  process.once("error", () => children.delete(process));
  return process;
}
function signalGroup(pid, signal) {
  try { process.kill(-pid, signal); return true; } catch (error) {
    // Unknown signal/permission failures count as still-live, never as clean teardown.
    return error.code !== "ESRCH";
  }
}
async function boundedCommand(command, argv, ms) {
  const process = child(command, argv); process.stdout.resume(); process.stderr.resume();
  const timer = setTimeout(() => process.kill("SIGKILL"), ms);
  try {
    const code = await new Promise((resolve, reject) => { process.once("error", reject); process.once("exit", resolve); });
    if (code !== 0) throw new Error("Certificate generation failed");
  } finally { clearTimeout(timer); }
}
let result = { passed: false, kind: "fixture-native-to-headless-browser", deployedWorkerVerified: false,
  systemAudioVerified: false, physicalDeviceVerified: false, nativeExitCode: null, browser: null };
try {
  const keyPath = join(directory, "key.pem"), certPath = join(directory, "cert.pem");
  await boundedCommand("/usr/bin/openssl", ["req", "-x509", "-newkey", "rsa:2048", "-nodes",
    "-keyout", keyPath, "-out", certPath, "-days", "1", "-config",
    fileURLToPath(new URL("./certificate.cnf", import.meta.url)), "-extensions", "san"], 10_000);
  await chmod(keyPath, 0o600); await chmod(certPath, 0o600);
  const key = await readFile(keyPath), cert = await readFile(certPath), certificate = new X509Certificate(cert);
  const pin = createHash("sha256").update(certificate.raw).digest("hex");
  const spki = createHash("sha256").update(certificate.publicKey.export({ type: "spki", format: "der" })).digest("base64");
  broker = await createOracleServer({ key, cert }); key.fill(0);
  browser = child(chrome, ["--headless=new", `--user-data-dir=${join(directory, "chrome-profile")}`,
    "--no-first-run", "--disable-default-apps", "--disable-extensions", "--disable-audio-input", "--disable-audio-output",
    "--autoplay-policy=no-user-gesture-required", "--disable-background-timer-throttling", "--disable-renderer-backgrounding",
    "--disable-backgrounding-occluded-windows", `--ignore-certificate-errors-spki-list=${spki}`, `${broker.origin}/oracle`]);
  if (browser.pid) ownedGroups.add(browser.pid);
  // Browser diagnostics can include private signaling. Never persist or print them.
  browser.stdout.resume(); browser.stderr.resume();
  native = child("/usr/bin/xcrun", ["xctest", "-XCTest",
    "CaptureServerTests.BelugaAudioShareBrowserIntegrationTests/testNativeStereoDecodeRejoinRevokeAndExpiry", testBundle],
    { env: { ...childEnvironment, BELUGA_AUDIO_SHARE_ORACLE_URL: broker.origin,
      BELUGA_AUDIO_SHARE_ORACLE_CERT_SHA256: pin } });
  if (native.pid) ownedGroups.add(native.pid);
  // XCTest asserts use fixed messages. Keep even their output out of the scalar proof.
  native.stdout.resume(); native.stderr.resume();
  const exit = new Promise((resolve, reject) => { native.once("error", reject); native.once("exit", (code) => resolve(code)); });
  const timeout = new Promise((_, reject) => { deadline = setTimeout(() => reject(new Error("Oracle deadline reached")), seconds * 1_000); });
  result.nativeExitCode = await Promise.race([exit, timeout]);
  result.browser = broker.state();
  const epochs = result.browser.epochs;
  result.passed = result.nativeExitCode === 0 && result.browser.complete && result.browser.failure === null &&
    result.browser.microphoneCalls === 0 && epochs.length === 3 && epochs.every((epoch) =>
      epoch.decoded && epoch.closed && epoch.topology && epoch.rmsLeft > 0.01 && epoch.rmsRight > 0.01 &&
      epoch.leftRatio > 8 && epoch.rightRatio > 8) && epochs[0].shareID === epochs[1].shareID &&
    epochs[2].shareID !== epochs[0].shareID;
} catch (error) {
  // Fixed failure names only; no URL/request/capability-bearing exception payloads.
  result.failure = error?.message === "Oracle deadline reached" ? "deadline" : "runner_or_native_boundary";
  if (broker) result.browser = broker.state();
} finally {
  clearTimeout(deadline);
  for (const pid of ownedGroups) signalGroup(pid, "SIGTERM");
  for (const child of children) child.kill("SIGTERM");
  await sleep(500);
  for (const pid of ownedGroups) signalGroup(pid, "SIGKILL");
  for (const child of children) child.kill("SIGKILL");
  const reapDeadline = Date.now() + 3_000;
  while ((children.size > 0 || [...ownedGroups].some((pid) => signalGroup(pid, 0))) && Date.now() < reapDeadline) await sleep(20);
  result.ownedChildrenReaped = children.size === 0;
  result.ownedProcessGroupsGone = [...ownedGroups].every((pid) => !signalGroup(pid, 0));
  if (!result.ownedChildrenReaped || !result.ownedProcessGroupsGone) result.passed = false;
  await broker?.close();
  await rm(directory, { recursive: true, force: true });
}
if (args.has("--result")) {
  const path = resolve(args.get("--result"));
  if (!(await stat(dirname(path))).isDirectory()) throw new Error("Result parent must already exist");
  await writeFile(path, `${JSON.stringify(result, null, 2)}\n`, { mode: 0o600, flag: "wx" });
}
console.log(JSON.stringify(result));
process.exitCode = result.passed ? 0 : 1;
