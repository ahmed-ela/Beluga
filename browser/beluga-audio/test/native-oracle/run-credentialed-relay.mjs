// Explicit operator entry point. Does not read Keychain or enable production sharing.
import { fstatSync, writeFileSync } from "node:fs";
import { stat, lstat } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { runCredentialedRelay } from "./relay-lifecycle.mjs";
import { readSharingMasterInput, runOwnedRelayFixture } from "./relay-parent-process.mjs";

const controller = new AbortController();
const interrupt = () => controller.abort();
process.on("SIGINT", interrupt); process.on("SIGTERM", interrupt);
let master, resultPath, result = { passed: false, status: "PREFLIGHT_REFUSED", networkStarted: false };
try {
  const options = new Map();
  for (let index = 2; index < process.argv.length; index += 2) {
    const key = process.argv[index], value = process.argv[index + 1];
    if (!["--execute-authorized-relay", "--test-bundle", "--chrome", "--timeout-seconds", "--result"].includes(key) ||
        !value || options.has(key)) throw new Error();
    options.set(key, value);
  }
  if (options.get("--execute-authorized-relay") !== "true" || !options.has("--test-bundle")) throw new Error();
  const testBundle = resolve(options.get("--test-bundle"));
  const chrome = resolve(options.get("--chrome") ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome");
  const seconds = Number(options.get("--timeout-seconds") ?? 60);
  if (!testBundle.endsWith(".xctest") || !(await stat(testBundle)).isDirectory() || !(await stat(chrome)).isFile() ||
      !Number.isInteger(seconds) || seconds < 45 || seconds > 90) throw new Error();
  if (options.has("--result")) {
    const path = resolve(options.get("--result"));
    if (!(await stat(dirname(path))).isDirectory()) throw new Error();
    try { await lstat(path); throw new Error(); } catch (error) { if (error.code !== "ENOENT") throw error; }
    resultPath = path;
  }
  // Import the broker before reading credentials or issuing any request.
  await import("./server.mjs");
  const descriptor = fstatSync(0);
  master = await readSharingMasterInput(process.stdin, {
    privatePipe: descriptor.isFIFO() || descriptor.isSocket(), signal: controller.signal,
  });
  result = { passed: false, status: "LIFECYCLE_UNCERTAIN", networkMayHaveStarted: true, revocationComplete: false };
  result = await runCredentialedRelay({ master, runMilliseconds: seconds * 1_000, signal: controller.signal,
    runFixture: (envelope, options) => runOwnedRelayFixture(envelope, { ...options, testBundle, chrome }) });
} catch { result.passed = false; }
finally { master = null; }

// No await between the final interruption decision and report publication.
try {
  if (controller.signal.aborted) { result.passed = false; result.status = "INTERRUPTED"; }
  if (resultPath) writeFileSync(resultPath, `${JSON.stringify(result, null, 2)}\n`, { mode: 0o600, flag: "wx" });
  console.log(JSON.stringify(result)); process.exitCode = result.passed ? 0 : 1;
} finally { process.removeListener("SIGINT", interrupt); process.removeListener("SIGTERM", interrupt); }
