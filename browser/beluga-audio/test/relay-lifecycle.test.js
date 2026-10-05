import test from "node:test";
import assert from "node:assert/strict";
import { admitSharingMaster, runCredentialedRelay } from "./native-oracle/relay-lifecycle.mjs";

const now = 1_800_000_000_000;
const master = () => ({ apiToken: "fixture-master-token", keyId: "fixture-key", name: "beluga-audio-share-v1" });
const server = (username = "fixture:temporary/user") => ({ urls: ["turn:turn.cloudflare.com:3478?transport=udp"],
  username, credential: "fixture-temporary-password" });
const json = (payload, status = 201, headers = {}) => new Response(JSON.stringify(payload),
  { status, headers: { "Content-Type": "application/json", ...headers } });
const good = () => json({ iceServers: [server(), server()] });
function harness({ issue = good, revoke = () => new Response(null, { status: 204 }),
  runFixture = async () => ({ passed: true, cleanupVerified: true }), signal, clock = () => now } = {}) {
  const calls = [], fixtureCalls = [];
  const run = () => runCredentialedRelay({ master: master(), runMilliseconds: 60_000, signal, now: clock,
    fetchImpl: async (url, options) => {
      calls.push({ url, options });
      return url.endsWith("generate-ice-servers") ? issue(options) : revoke(options);
    },
    runFixture: async (envelope, options) => {
      fixtureCalls.push({ envelope: structuredClone(envelope), options });
      return runFixture(envelope, options);
    } });
  return { run, calls, fixtureCalls };
}
const countIssue = (calls) => calls.filter(({ url }) => url.endsWith("generate-ice-servers")).length;
const countRevoke = (calls) => calls.filter(({ url }) => url.endsWith("/revoke")).length;

test("master is exact, bounded, parent-only canonical JSON with fixed refusal", () => {
  const encode = (value) => Buffer.from(JSON.stringify(value));
  assert.deepEqual(admitSharingMaster(encode(master())), master());
  assert.equal(admitSharingMaster(encode({ ...master(), apiToken: `${master().apiToken}=` })).apiToken, `${master().apiToken}=`);
  for (const value of [{ ...master(), name: "other" }, { ...master(), extra: "secret" },
    { ...master(), keyId: "../other" }, { ...master(), apiToken: "has whitespace" },
    { ...master(), apiToken: "short" }, { ...master(), apiToken: "a".repeat(4097) }, { ...master(), keyId: null }, null]) {
    assert.throws(() => admitSharingMaster(encode(value)), { message: "sharing_master_refused" });
  }
  for (const bytes of [Buffer.alloc(16_385), Buffer.from([0xff]),
    Buffer.from('{"name":"wrong","name":"beluga-audio-share-v1","apiToken":"a","keyId":"b"}')])
    assert.throws(() => admitSharingMaster(bytes), { message: "sharing_master_refused" });
});

test("issue once, pass only temporary envelope, await fixture, deduplicate and revoke once", async () => {
  const h = harness(); const result = await h.run();
  assert.equal(result.status, "passed"); assert.equal(result.passed, true);
  assert.equal(result.issuanceValidated, true); assert.equal(result.issuanceUncertain, false);
  assert.equal(result.knownUsernameCount, 1); assert.equal(result.revokedUsernameCount, 1);
  assert.equal(result.revokedAll, true); assert.equal(result.boundedTTLWarning, false);
  assert.equal(countIssue(h.calls), 1); assert.equal(countRevoke(h.calls), 1);
  assert.deepEqual(Object.keys(h.fixtureCalls[0].envelope).sort(), ["expiresAt", "iceServers"]);
  assert.equal(h.fixtureCalls[0].envelope.expiresAt, now + 180_000);
  assert.equal(h.fixtureCalls[0].envelope.iceServers[0].credentialType, "password");
  assert.deepEqual(h.fixtureCalls[0].options, { signal: undefined, runMilliseconds: 60_000 });
  assert.equal(h.calls[0].url, "https://rtc.live.cloudflare.com/v1/turn/keys/fixture-key/credentials/generate-ice-servers");
  assert.equal(h.calls[0].options.body, '{"ttl":180}');
  assert.equal(h.calls[1].url, "https://rtc.live.cloudflare.com/v1/turn/keys/fixture-key/credentials/fixture%3Atemporary%2Fuser/revoke");
  for (const { options } of h.calls) {
    assert.equal(options.method, "POST"); assert.equal(options.redirect, "error"); assert.equal(options.cache, "no-store");
    assert.equal(options.headers.Authorization, "Bearer fixture-master-token");
  }
});

test("refused, malformed, oversized and incomplete issuance never launches or claims complete revocation", async () => {
  for (const issue of [() => json({ error: "raw-sensitive-error" }, 403),
    () => new Response("not-json", { status: 201 }),
    () => new Response("x".repeat(65_537), { status: 201 }),
    () => json({ iceServers: [server()] }, 201, { "Content-Length": "65537" }),
    () => json({ iceServers: [{ ...server(), username: null }] }),
    () => { throw new Error("raw-fetch-secret"); }]) {
    const h = harness({ issue }); const result = await h.run();
    assert.equal(result.passed, false); assert.equal(result.issuanceUncertain, true);
    assert.equal(result.boundedTTLWarning, true); assert.equal(result.revokedAll, false);
    assert.equal(h.fixtureCalls.length, 0); assert.equal(countIssue(h.calls), 1);
    assert.equal(JSON.stringify(result).includes("secret"), false);
  }
});

test("known IDs from malformed response revoke even when validation cannot complete", async () => {
  for (const payload of [{ iceServers: [server(), { ...server("second"), urls: "turn:other.example" }] },
    { iceServers: [server(), { username: "second" }], unknown: true },
    { iceServers: [server(), { ...server(), username: "\ud800" }] }]) {
    const h = harness({ issue: () => json(payload) }); const result = await h.run();
    assert.equal(result.passed, false); assert.equal(result.issuanceUncertain, true);
    assert.equal(result.revokedAll, false); assert.equal(result.boundedTTLWarning, true);
    assert.equal(result.revokedUsernameCount, result.knownUsernameCount);
    assert.ok(result.knownUsernameCount >= 1); assert.equal(h.fixtureCalls.length, 0);
  }
  const h = harness({ issue: () => json({ iceServers: [server()] }, 201, { "Content-Type": "text/plain" }) });
  const result = await h.run(); assert.equal(result.revokedUsernameCount, 1); assert.equal(result.issuanceValidated, false);
  const excess = harness({ issue: () => json({ iceServers: Array.from({ length: 17 }, (_, index) => server(`user-${index}`)) }) });
  const limited = await excess.run();
  assert.equal(limited.knownUsernameCount, 16); assert.equal(limited.revokedUsernameCount, 16);
  assert.equal(limited.revokedAll, false); assert.equal(limited.boundedTTLWarning, true);
});

test("issue timeout is five seconds, aborts transport and never retries", { timeout: 8_000 }, async () => {
  let requestSignal;
  const h = harness({ issue: (options) => { requestSignal = options.signal; return new Promise(() => {}); } });
  const result = await h.run();
  assert.equal(requestSignal.aborted, true); assert.equal(result.issuanceUncertain, true);
  assert.equal(result.boundedTTLWarning, true); assert.equal(countIssue(h.calls), 1); assert.equal(h.fixtureCalls.length, 0);
});

test("launch throw, media refusal, invalid fixture result and cleanup uncertainty still revoke", async () => {
  for (const runFixture of [async () => { throw new Error("fixture-secret"); },
    async () => ({ passed: false, cleanupVerified: true }),
    async () => ({ passed: true, cleanupVerified: false }),
    async () => ({ passed: true, cleanupVerified: true, extra: "secret" })]) {
    const h = harness({ runFixture }); const result = await h.run();
    assert.equal(result.passed, false); assert.equal(result.revokedAll, true);
    assert.equal(countRevoke(h.calls), 1); assert.equal(countIssue(h.calls), 1);
  }
});

test("abort before issuance has no request; abort during issuance remains uncertain", async () => {
  const before = new AbortController(); before.abort();
  const h = harness({ signal: before.signal }); const a = await h.run();
  assert.equal(a.status, "interrupted"); assert.equal(a.issuanceAttempted, false); assert.equal(h.calls.length, 0);
  const during = new AbortController();
  const k = harness({ signal: during.signal, issue: () => { during.abort(); return good(); } });
  const b = await k.run(); assert.equal(b.interrupted, true); assert.equal(b.issuanceUncertain, true);
  assert.equal(b.boundedTTLWarning, true); assert.equal(k.fixtureCalls.length, 0);
});

test("abort after validated issuance but before launch still revokes known username", async () => {
  const abort = new AbortController(); let ticks = 0;
  const h = harness({ signal: abort.signal, clock: () => { if (++ticks === 2) abort.abort(); return now; } });
  const result = await h.run();
  assert.equal(result.issuanceValidated, true); assert.equal(result.revokedAll, true);
  assert.equal(result.interrupted, true); assert.equal(result.passed, false);
  assert.equal(h.fixtureCalls.length, 0); assert.equal(countRevoke(h.calls), 1);
});

test("response arriving after abort still cancels its body without awaiting cancellation", { timeout: 1_000 }, async () => {
  const abort = new AbortController(); let resolveFetch, bodyCancelled;
  const cancelled = new Promise((resolve) => { bodyCancelled = resolve; });
  const h = harness({ signal: abort.signal, issue: () => new Promise((resolve) => { resolveFetch = resolve; }) });
  const pending = h.run(); abort.abort();
  const result = await pending;
  assert.equal(result.interrupted, true); assert.equal(result.issuanceUncertain, true);
  resolveFetch({ status: 201, body: { cancel() { bodyCancelled(); return new Promise(() => {}); } } });
  await cancelled;
  assert.equal(h.fixtureCalls.length, 0); assert.equal(countIssue(h.calls), 1);
  assert.equal(result.passed, false); assert.equal(result.boundedTTLWarning, true);
});

test("chunk arriving after abort is scrubbed and cannot restart issuance processing", { timeout: 1_000 }, async () => {
  const abort = new AbortController(); let resolveRead, reading; let cancels = 0;
  const entered = new Promise((resolve) => { reading = resolve; });
  const reader = { read() { reading(); return new Promise((resolve) => { resolveRead = resolve; }); },
    cancel() { cancels++; return Promise.resolve(); } };
  const h = harness({ signal: abort.signal, issue: () => ({ status: 201,
    headers: new Headers({ "Content-Type": "application/json" }), body: { getReader: () => reader } }) });
  const pending = h.run(); await entered; abort.abort();
  const result = await pending; assert.equal(cancels, 1);
  const late = Buffer.from(JSON.stringify({ iceServers: [server()] }));
  resolveRead({ done: false, value: late });
  await new Promise((resolve) => setImmediate(resolve));
  assert.ok(late.every((byte) => byte === 0));
  assert.equal(result.knownUsernameCount, 0); assert.equal(result.issuanceUncertain, true);
  assert.equal(result.boundedTTLWarning, true); assert.equal(h.fixtureCalls.length, 0);
});

test("abort during media never races away from the child's cleanup receipt", async () => {
  const abort = new AbortController(); let finish, started;
  const entered = new Promise((resolve) => { started = resolve; });
  const h = harness({ signal: abort.signal, runFixture: () => {
    started(); return new Promise((resolve) => { finish = resolve; });
  } });
  const pending = h.run(); await entered; abort.abort();
  await Promise.resolve(); assert.equal(countRevoke(h.calls), 0);
  finish({ passed: true, cleanupVerified: true });
  const result = await pending; assert.equal(result.interrupted, true); assert.equal(result.fixtureCleanupVerified, true);
  assert.equal(result.revokedAll, true); assert.equal(result.passed, false); assert.equal(countRevoke(h.calls), 1);
});

test("parent abort during revocation cannot abort the fresh cleanup request", async () => {
  const abort = new AbortController();
  const h = harness({ signal: abort.signal, revoke: (options) => {
    abort.abort(); assert.equal(options.signal.aborted, false); return new Response(null, { status: 204 });
  } });
  const result = await h.run(); assert.equal(result.interrupted, true); assert.equal(result.revokedAll, true);
  assert.equal(result.fixturePassed, true); assert.equal(result.passed, false);
});

test("failed revocation retains media result but refuses terminal pass and warns about bounded TTL", async () => {
  for (const revoke of [() => new Response(null, { status: 500 }), () => { throw new Error("revoke-secret"); }]) {
    const h = harness({ revoke }); const result = await h.run();
    assert.equal(result.status, "revoke_failed"); assert.equal(result.fixturePassed, true);
    assert.equal(result.revokeFailedCount, 1); assert.equal(result.revokedAll, false);
    assert.equal(result.passed, false); assert.equal(result.boundedTTLWarning, true); assert.equal(countRevoke(h.calls), 1);
  }
});

test("all lifecycle report fields are whitelisted scalars with no broader proof claims", async () => {
  const result = await harness().run();
  assert.deepEqual(Object.keys(result).sort(), ["status", "passed", "issuanceAttempted", "issuanceValidated", "issuanceUncertain",
    "fixtureStarted", "fixturePassed", "fixtureCleanupVerified", "knownUsernameCount", "revokedUsernameCount", "revokeFailedCount",
    "revokedAll", "interrupted", "boundedTTLWarning", "ttlSeconds", "systemAudioVerified", "deployedWorkerVerified", "physicalDeviceVerified",
    "unrelatedNetworksVerified"].sort());
  assert.ok(Object.values(result).every((value) => ["boolean", "number"].includes(typeof value) || value === "passed"));
  const serialized = JSON.stringify(result);
  for (const secret of [master().apiToken, master().keyId, server().username, server().credential, "https:"])
    assert.equal(serialized.includes(secret), false);
  for (const key of ["systemAudioVerified", "deployedWorkerVerified", "physicalDeviceVerified", "unrelatedNetworksVerified"])
    assert.equal(result[key], false);
});
