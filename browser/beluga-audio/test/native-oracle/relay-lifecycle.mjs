// Parent-only lifecycle. This module never logs, persists, or passes the master to a child.
import { normalizeCloudflareIceServers } from "../../../../services/RendezvousWorker/src/ice.js";

const endpoint = "https://rtc.live.cloudflare.com/v1/turn/keys";
const ttlSeconds = 180, requestMilliseconds = 5_000, maxBody = 65_536, maxUsernames = 16;
const exact = (value, keys) => value !== null && typeof value === "object" && !Array.isArray(value) &&
  Object.keys(value).sort().join(",") === keys;
const safeUsername = (value) => typeof value === "string" && value.length > 0 &&
  Buffer.byteLength(value) <= 1_024 && !/[\s\u0000-\u001f\u007f]/u.test(value) &&
  !/[\ud800-\udfff]/u.test(value);
function masterRecord(value) {
  if (!exact(value, "apiToken,keyId,name") || value.name !== "beluga-audio-share-v1" ||
      typeof value.apiToken !== "string" || !/^[A-Za-z0-9_.=~-]{20,4096}$/.test(value.apiToken) ||
      typeof value.keyId !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(value.keyId)) throw new Error("sharing_master_refused");
  return Object.freeze({ apiToken: value.apiToken, keyId: value.keyId, name: value.name });
}
export function admitSharingMaster(bytes) {
  try {
    if (!(bytes instanceof Uint8Array) || bytes.byteLength === 0 || bytes.byteLength > 16_384) throw new Error();
    const text = new TextDecoder("utf-8", { fatal: true }).decode(bytes).trim();
    const value = JSON.parse(text);
    // The private parent supplies JSON.stringify output; duplicate keys are refused.
    if (JSON.stringify(value) !== text) throw new Error();
    return masterRecord(value);
  } catch { throw new Error("sharing_master_refused"); }
}

async function request(fetchImpl, url, apiToken, { body, signal, json = false }) {
  const controller = new AbortController();
  let rejectStop, reader, response, bytes;
  const chunks = [];
  const stopped = new Promise((_, reject) => { rejectStop = reject; });
  const stop = () => { controller.abort(); rejectStop(new Error("request_unproven")); };
  const timer = setTimeout(stop, requestMilliseconds);
  signal?.addEventListener("abort", stop, { once: true });
  if (signal?.aborted) stop();
  try {
    return await Promise.race([stopped, (async () => {
      if (controller.signal.aborted) throw new Error();
      response = await fetchImpl(url, { method: "POST", redirect: "error", cache: "no-store",
        headers: { Authorization: `Bearer ${apiToken}`, ...(json ? { "Content-Type": "application/json" } : {}) },
        ...(body === undefined ? {} : { body }), signal: controller.signal });
      if (controller.signal.aborted) {
        // The outer deadline may have cleaned up before this response existed.
        try { Promise.resolve(response?.body?.cancel()).catch(() => {}); } catch {}
        throw new Error();
      }
      if (!json) return { status: response.status };
      const length = response.headers.get("content-length");
      if (length !== null && (!/^\d+$/.test(length) || Number(length) > maxBody)) throw new Error();
      reader = response.body?.getReader();
      if (!reader) throw new Error();
      let size = 0;
      while (true) {
        const next = await reader.read();
        if (controller.signal.aborted) {
          if (next.value instanceof Uint8Array) next.value.fill(0);
          throw new Error();
        }
        if (next.done) break;
        if (!(next.value instanceof Uint8Array) || (size += next.value.byteLength) > maxBody) throw new Error();
        chunks.push(Buffer.from(next.value));
      }
      bytes = Buffer.concat(chunks);
      const payload = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
      return { status: response.status, payload,
        contentTypeValid: /^application\/json(?:\s*;|$)/i.test(response.headers.get("content-type") ?? "") };
    })()]);
  } finally {
    clearTimeout(timer); signal?.removeEventListener("abort", stop);
    // Cancellation is best-effort for an uncooperative injected transport, never a retry.
    try { Promise.resolve(reader ? reader.cancel() : response?.body?.cancel()).catch(() => {}); } catch {}
    bytes?.fill(0); for (const chunk of chunks) chunk.fill(0); chunks.length = 0;
  }
}

export async function runCredentialedRelay({ master, runMilliseconds, signal, fetchImpl = globalThis.fetch,
  runFixture, now = Date.now }) {
  const report = { status: "input_refused", passed: false, issuanceAttempted: false, issuanceValidated: false,
    issuanceUncertain: false, fixtureStarted: false, fixturePassed: false, fixtureCleanupVerified: false,
    knownUsernameCount: 0, revokedUsernameCount: 0, revokeFailedCount: 0, revokedAll: false,
    interrupted: signal?.aborted === true, boundedTTLWarning: false, ttlSeconds,
    systemAudioVerified: false, deployedWorkerVerified: false, physicalDeviceVerified: false, unrelatedNetworksVerified: false };
  const usernames = new Set();
  let admitted, envelope;
  const interrupt = () => { report.interrupted = true; };
  signal?.addEventListener("abort", interrupt, { once: true });
  try {
    admitted = masterRecord(master);
    if (!Number.isInteger(runMilliseconds) || runMilliseconds < 45_000 || runMilliseconds > 90_000 ||
        typeof fetchImpl !== "function" || typeof runFixture !== "function" || typeof now !== "function") throw new Error();
    if (report.interrupted) return report;
    const issuedAt = now();
    if (!Number.isSafeInteger(issuedAt) || issuedAt < 0 || !Number.isSafeInteger(issuedAt + ttlSeconds * 1_000)) throw new Error();
    report.status = "issuance_unproven"; report.issuanceAttempted = true; report.issuanceUncertain = true;
    const response = await request(fetchImpl, `${endpoint}/${admitted.keyId}/credentials/generate-ice-servers`, admitted.apiToken,
      { body: JSON.stringify({ ttl: ttlSeconds }), signal, json: true });
    // Collect bounded safe IDs before schema/URL normalization, including malformed
    // successful responses. Incomplete inventory remains uncertain even if these revoke.
    if (Array.isArray(response.payload?.iceServers)) {
      for (const server of response.payload.iceServers) {
        if (safeUsername(server?.username) && usernames.size < maxUsernames) usernames.add(server.username);
      }
    }
    if (response.status !== 201) { report.status = "issue_refused"; throw new Error(); }
    if (!response.contentTypeValid) throw new Error();
    const iceServers = normalizeCloudflareIceServers(response.payload);
    const expiresAt = issuedAt + ttlSeconds * 1_000, observedAt = now();
    if (usernames.size === 0 || !iceServers.every((server) => !Object.hasOwn(server, "username") ||
        (safeUsername(server.username) && usernames.has(server.username))) ||
        !Number.isSafeInteger(observedAt) || observedAt < issuedAt ||
        expiresAt - observedAt < runMilliseconds + 30_000) throw new Error();
    report.issuanceValidated = true; report.issuanceUncertain = false;
    envelope = { iceServers, expiresAt };
    if (report.interrupted || signal?.aborted) return report;
    report.status = "fixture_failed"; report.fixtureStarted = true;
    // Do not race this promise against cancellation: its adapter owns bounded child cleanup.
    const fixture = await runFixture(envelope, { signal, runMilliseconds });
    if (!exact(fixture, "cleanupVerified,passed") || typeof fixture.passed !== "boolean" ||
        typeof fixture.cleanupVerified !== "boolean") throw new Error();
    report.fixturePassed = fixture.passed; report.fixtureCleanupVerified = fixture.cleanupVerified;
    if (!fixture.cleanupVerified) report.status = "fixture_cleanup_unproven";
  } catch {
    // Intentionally no exception names, messages, URLs, usernames or credentials.
  } finally {
    report.knownUsernameCount = usernames.size;
    // At most 16 requests in one five-second cleanup window, never a retry.
    const revocations = await Promise.allSettled([...usernames].map(async (username) => {
        // Fresh non-parent-cancelled deadline: a signal cannot skip revocation.
        const response = await request(fetchImpl,
          `${endpoint}/${admitted.keyId}/credentials/${encodeURIComponent(username)}/revoke`, admitted.apiToken, {});
        if (response.status !== 204) throw new Error();
    }));
    report.revokedUsernameCount = revocations.filter((result) => result.status === "fulfilled").length;
    report.revokeFailedCount = revocations.length - report.revokedUsernameCount;
    report.revokedAll = report.issuanceValidated && usernames.size > 0 && report.revokeFailedCount === 0 &&
      report.revokedUsernameCount === usernames.size;
    report.boundedTTLWarning = report.issuanceAttempted && (!report.revokedAll || report.issuanceUncertain);
    report.interrupted ||= signal?.aborted === true;
    report.passed = report.issuanceValidated && report.fixturePassed && report.fixtureCleanupVerified &&
      report.revokedAll && !report.interrupted;
    if (report.interrupted) report.status = "interrupted";
    else if (report.revokeFailedCount > 0) report.status = "revoke_failed";
    else if (report.passed) report.status = "passed";
    if (envelope) {
      for (const server of envelope.iceServers) { delete server.username; delete server.credential; }
      envelope.iceServers.length = 0;
    }
    usernames.clear(); admitted = null; envelope = null;
    signal?.removeEventListener("abort", interrupt);
  }
  return report;
}
