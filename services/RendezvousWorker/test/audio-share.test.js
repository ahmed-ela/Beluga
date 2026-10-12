import { env, evictDurableObject, runInDurableObject, SELF } from "cloudflare:test";
import { describe, expect, it, vi } from "vitest";
import Worker from "../src/index.js";
import { AUDIO_SHARE_PROTOCOL, encodeBase64URL, encodeShareLocator,
  shareLocatorRetirementMilliseconds } from "../../../browser/beluga-audio/public/protocol.js";
import { hashAdmission } from "../../../browser/beluga-audio/public/crypto.js";

// Locally generated fixtures only: production audio sharing remains explicitly disabled.
const fixtureID = () => encodeBase64URL(crypto.getRandomValues(new Uint8Array(16)));
const fixtureShareID = (now = Date.now()) => encodeShareLocator(crypto.getRandomValues(new Uint8Array(12)), now);
const proof = (fill) => encodeBase64URL(new Uint8Array(32).fill(fill));
const stubFor = (id) => env.AUDIO_SHARE.get(env.AUDIO_SHARE.idFromName(`audio-share:${id}`));
const headers = { Upgrade: "websocket", "Sec-WebSocket-Protocol": AUDIO_SHARE_PROTOCOL,
  Origin: "https://example.com" };
const open = async (id) => {
  const response = await SELF.fetch(`https://example.com/v3/audio-share/${id}`, { headers });
  expect(response.status).toBe(101);
  expect(response.headers.get("Sec-WebSocket-Protocol")).toBe(AUDIO_SHARE_PROTOCOL);
  const socket = response.webSocket;
  const queued = [];
  const waiters = [];
  socket.addEventListener("message", (event) => {
    const value = JSON.parse(event.data);
    const waiter = waiters.shift();
    if (waiter) waiter(value);
    else queued.push(value);
  });
  socket.accept();
  return { socket, send: (value) => socket.send(JSON.stringify(value)), next: () => {
    if (queued.length) return Promise.resolve(queued.shift());
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error("bounded message wait failed")), 1_000);
      waiters.push((value) => { clearTimeout(timeout); resolve(value); });
    });
  } };
};
const register = async (id, values = {}) => {
  const owner = await open(id);
  owner.send({ type: "register", v: 1, ownerProof: proof(1), listenerProof: proof(2),
    ttlSeconds: 600, maxListeners: 8, ...values });
  const registered = await owner.next();
  expect(registered.type).toBe("registered");
  return { owner, registered };
};
const admit = async (id, owner) => {
  const listener = await open(id);
  listener.send({ type: "authenticate", v: 1, proof: proof(2) });
  const [ownerReady, ready] = await Promise.all([owner.next(), listener.next()]);
  expect(ready.type).toBe("listener-ready");
  expect(ownerReady.listenerID).toBe(ready.listenerID);
  return { listener, ready };
};
const signal = (listenerID, seq = 0) => ({ type: "signal", v: 1, listenerID, seq,
  ciphertext: encodeBase64URL(new Uint8Array(32).fill(9)) });

describe("isolated audio-share registry", () => {
  it("stays dark when disabled; browser page is no-store/no-referrer, no permissions", async () => {
    const disabled = await Worker.fetch(new Request(`https://example.com/v3/audio-share/${fixtureID()}`, { headers }), {
      ...env, AUDIO_SHARE_ENABLED: "false",
    });
    expect(disabled.status).toBe(404);
    const page = await SELF.fetch("https://example.com/audio-share");
    expect(page.status).toBe(200);
    expect(page.headers.get("Cache-Control")).toBe("no-store");
    expect(page.headers.get("Referrer-Policy")).toBe("no-referrer");
    expect(page.headers.get("Permissions-Policy")).toContain("microphone=()");
    expect(page.headers.get("Content-Security-Policy")).toContain("frame-ancestors 'none'");
    expect(page.headers.get("X-Robots-Tag")).toContain("noindex");
    expect((await SELF.fetch("https://example.com/audio-share/core.js")).status).toBe(200);
    expect((await SELF.fetch("https://example.com/core.js")).status).toBe(404);
  });

  it("rejects query joins, wrong origins, unknown protocols, and noncanonical IDs", async () => {
    const id = fixtureShareID();
    for (const [url, requestHeaders] of [
      [`https://example.com/v3/audio-share/${id}?proof=forbidden`, headers],
      [`https://example.com/v3/audio-share/${id}`, { ...headers, Origin: "https://untrusted.example" }],
      [`https://example.com/v3/audio-share/${id}`, { ...headers, "Sec-WebSocket-Protocol": "secret-token" }],
      ["https://example.com/v3/audio-share/invalid", headers],
      [`https://example.com/v3/audio-share/${id}`, { ...headers, Authorization: "forbidden" }],
    ]) expect((await SELF.fetch(url, { headers: requestHeaders })).status).toBe(400);
  });

  it("requires first-frame authentication; wrong or owner-swapped proof never consumes a slot", async () => {
    const id = fixtureShareID();
    const { owner } = await register(id, { maxListeners: 1 });
    for (const value of [proof(1), proof(3)]) {
      const invalid = await open(id);
      invalid.send({ type: "authenticate", v: 1, proof: value });
      expect((await invalid.next()).type).toBe("error");
      invalid.socket.close(1000);
    }
    const { listener } = await admit(id, owner);
    listener.socket.close(1000);
    owner.socket.close(1000);
  });

  it("retains only verifier hashes and immutable deadline, not raw admission proofs", async () => {
    const id = fixtureShareID();
    const { owner, registered } = await register(id, { ttlSeconds: 86_400 });
    const stored = await runInDurableObject(stubFor(id), (_, state) => state.storage.get("audio-share-v1"));
    expect(stored.ownerHash).toBe(await hashAdmission(proof(1)));
    expect(stored.listenerHash).toBe(await hashAdmission(proof(2)));
    expect(JSON.stringify(stored)).not.toContain(proof(1));
    expect(JSON.stringify(stored)).not.toContain(proof(2));
    expect(stored.expiresAt - stored.createdAt).toBe(86_400_000);
    expect(registered.expiresAt - registered.serverTime).toBeGreaterThan(86_399_000);
    expect(registered.expiresAt - registered.serverTime).toBeLessThanOrEqual(86_400_000);
    owner.send({ type: "probe", v: 1, nonce: fixtureID() });
    const acknowledgment = await owner.next();
    expect(acknowledgment.type).toBe("probe-ack");
    expect(acknowledgment.leaseExpiresAt).toBeLessThanOrEqual(registered.expiresAt);
    expect((await runInDurableObject(stubFor(id), (_, state) => state.storage.get("audio-share-v1"))).expiresAt)
      .toBe(registered.expiresAt);
    owner.socket.close(1000);
  });

  it("bounds listener fan-out without eviction; targets opaque signals to only the selected listener", async () => {
    const id = fixtureShareID();
    const { owner } = await register(id, { maxListeners: 2 });
    const first = await admit(id, owner);
    const second = await admit(id, owner);
    const extra = await open(id);
    extra.send({ type: "authenticate", v: 1, proof: proof(2) });
    expect((await extra.next()).error).toBe("listener_limit");
    owner.send(signal(first.ready.listenerID));
    expect(await first.listener.next()).toEqual({ ...signal(first.ready.listenerID), from: "owner" });
    second.listener.send(signal(second.ready.listenerID));
    expect(await owner.next()).toEqual({ ...signal(second.ready.listenerID), from: "listener" });
    owner.socket.close(1000); first.listener.socket.close(1000); second.listener.socket.close(1000);
  });

  it("listener cannot revoke or target a sibling; its departure never ends owner or sibling", async () => {
    const id = fixtureShareID();
    const { owner } = await register(id);
    const first = await admit(id, owner);
    const second = await admit(id, owner);
    first.listener.send(signal(second.ready.listenerID));
    expect((await owner.next()).type).toBe("listener-left");
    const third = await admit(id, owner);
    third.listener.send({ type: "revoke", v: 1 });
    expect((await owner.next()).type).toBe("listener-left");
    owner.send(signal(second.ready.listenerID));
    expect((await second.listener.next()).from).toBe("owner");
    owner.socket.close(1000); first.listener.socket.close(1000); second.listener.socket.close(1000); third.listener.socket.close(1000);
  });

  it("late owner packets for a departed listener retire only that target, not its sibling", async () => {
    const id = fixtureShareID();
    const { owner } = await register(id);
    const first = await admit(id, owner);
    const second = await admit(id, owner);
    first.listener.socket.close(1000);
    expect((await owner.next()).listenerID).toBe(first.ready.listenerID);
    owner.send(signal(first.ready.listenerID));
    expect((await owner.next()).listenerID).toBe(first.ready.listenerID);
    owner.send(signal(second.ready.listenerID));
    expect((await second.listener.next()).from).toBe("owner");
    expect((await runInDurableObject(stubFor(id), (_, state) => state.storage.get("audio-share-v1"))).status).toBe("active");
    owner.socket.close(1000); second.listener.socket.close(1000);
  });

  it("server-authoritative revoke closes existing listeners and permanently rejects re-registration", async () => {
    const id = fixtureShareID();
    const { owner } = await register(id);
    const { listener } = await admit(id, owner);
    owner.send({ type: "revoke", v: 1 });
    expect((await owner.next()).reason).toBe("revoked");
    expect((await listener.next()).reason).toBe("revoked");
    expect((await SELF.fetch(`https://example.com/v3/audio-share/${id}`, { headers })).status).toBe(404);
    const stored = await runInDurableObject(stubFor(id), (_, state) => state.storage.get("audio-share-v1"));
    expect(stored.status).toBe("revoked");
    owner.socket.close(1000); listener.socket.close(1000);
  });

  it("expires admitted sockets exactly at deadline, including after hibernation", async () => {
    const id = fixtureShareID();
    const { owner, registered } = await register(id);
    const { listener } = await admit(id, owner);
    await evictDurableObject(stubFor(id));
    await runInDurableObject(stubFor(id), async (instance) => {
      const originalNow = Date.now;
      Date.now = () => registered.expiresAt;
      try { await instance.alarm(); } finally { Date.now = originalNow; }
    });
    expect((await owner.next()).reason).toBe("expired");
    expect((await listener.next()).reason).toBe("expired");
    expect((await runInDurableObject(stubFor(id), (_, state) => state.storage.get("audio-share-v1"))).status).toBe("expired");
    owner.socket.close(1000); listener.socket.close(1000);
  });

  it("owner application lease timeout closes listeners before nominal share expiry", async () => {
    const id = fixtureShareID();
    const { owner, registered } = await register(id);
    const { listener } = await admit(id, owner);
    await runInDurableObject(stubFor(id), async (instance) => {
      const originalNow = Date.now;
      Date.now = () => registered.leaseExpiresAt;
      try { await instance.alarm(); } finally { Date.now = originalNow; }
    });
    expect((await listener.next()).reason).toBe("owner_lost");
    expect((await owner.next()).reason).toBe("owner_lost");
    owner.socket.close(1000); listener.socket.close(1000);
  });

  it("drops binary, duplicate registration, and sequence replay without exposing signaling", async () => {
    const id = fixtureShareID();
    const { owner } = await register(id);
    const duplicate = await open(id);
    duplicate.send({ type: "register", v: 1, ownerProof: proof(1), listenerProof: proof(2), ttlSeconds: 600, maxListeners: 8 });
    expect((await duplicate.next()).error).toBe("unavailable");
    const binary = await open(id);
    binary.socket.send(new Uint8Array(64));
    expect((await binary.next()).error).toBe("invalid_authentication");
    const { listener, ready } = await admit(id, owner);
    listener.send(signal(ready.listenerID));
    await owner.next();
    listener.send(signal(ready.listenerID));
    expect((await owner.next()).type).toBe("listener-left");
    expect((await runInDurableObject(stubFor(id), (_, state) => state.storage.get("audio-share-v1"))).status).toBe("active");
    owner.socket.close(1000); listener.socket.close(1000); duplicate.socket.close(1000); binary.socket.close(1000);
  });

  it("bounds unauthenticated sockets and expires them without affecting the owner lease", async () => {
    const id = fixtureShareID();
    const { owner, registered } = await register(id);
    const pending = await Promise.all(Array.from({ length: 16 }, () => open(id)));
    expect((await SELF.fetch(`https://example.com/v3/audio-share/${id}`, { headers })).status).toBe(429);
    await runInDurableObject(stubFor(id), async (instance) => {
      const originalNow = Date.now;
      Date.now = () => registered.serverTime + 5_500;
      try { await instance.alarm(); } finally { Date.now = originalNow; }
    });
    for (const socket of pending) expect((await socket.next()).error).toBe("authentication_timeout");
    const { listener } = await admit(id, owner);
    owner.send({ type: "probe", v: 1, nonce: fixtureID() });
    expect((await owner.next()).type).toBe("probe-ack");
    owner.socket.close(1000); listener.socket.close(1000);
    for (const socket of pending) socket.socket.close(1000);
  });

  it("supports exactly eight authenticated listeners and never admits a ninth", async () => {
    const id = fixtureShareID();
    const { owner } = await register(id);
    const accepted = [];
    for (let index = 0; index < 8; index++) accepted.push(await admit(id, owner));
    const ninth = await open(id);
    ninth.send({ type: "authenticate", v: 1, proof: proof(2) });
    expect((await ninth.next()).error).toBe("listener_limit");
    expect(new Set(accepted.map(({ ready }) => ready.listenerID)).size).toBe(8);
    owner.socket.close(1000); ninth.socket.close(1000);
    for (const { listener } of accepted) listener.socket.close(1000);
  });

  it("owner disconnect closes admitted listeners; only a new ID can create a new share", async () => {
    const id = fixtureShareID();
    const { owner } = await register(id);
    const { listener } = await admit(id, owner);
    owner.socket.close(1000);
    expect((await listener.next()).reason).toBe("owner_lost");
    expect((await SELF.fetch(`https://example.com/v3/audio-share/${id}`, { headers })).status).toBe(404);
    const fresh = await register(fixtureShareID());
    fresh.owner.socket.close(1000); listener.socket.close(1000);
  });

  it("provisions no TURN before proof and occupancy; bounds credential TTL to the share", async () => {
    const id = fixtureShareID();
    const { owner } = await register(id, { ttlSeconds: 120, maxListeners: 1 });
    await runInDurableObject(stubFor(id), (instance) => {
      instance.env = { ...instance.env, AUDIO_SHARE_TURN_KEY_ID: "synthetic-test-key",
        AUDIO_SHARE_TURN_API_TOKEN: "synthetic-test-token" };
    });
    const calls = [];
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockImplementation(async (_url, request) => {
      calls.push(JSON.parse(request.body));
      return new Response(JSON.stringify({ iceServers: [{ urls: ["turn:turn.cloudflare.com:3478?transport=udp"],
        username: "synthetic-test-user", credential: "synthetic-test-password" }] }), {
        status: 201, headers: { "Content-Type": "application/json" },
      });
    });
    try {
      const wrong = await open(id);
      wrong.send({ type: "authenticate", v: 1, proof: proof(3) });
      expect((await wrong.next()).error).toBe("unavailable");
      expect(calls).toEqual([]);
      const { listener, ready } = await admit(id, owner);
      expect(calls).toHaveLength(1);
      expect(calls[0].ttl).toBeGreaterThanOrEqual(60);
      expect(calls[0].ttl).toBeLessThanOrEqual(120);
      expect(ready.iceServers.some((server) => server.urls[0].startsWith("turn:"))).toBe(true);
      const full = await open(id);
      full.send({ type: "authenticate", v: 1, proof: proof(2) });
      expect((await full.next()).error).toBe("listener_limit");
      expect(calls).toHaveLength(1);
      owner.socket.close(1000); listener.socket.close(1000); wrong.socket.close(1000); full.socket.close(1000);
    } finally { fetchSpy.mockRestore(); }
  });

  it("TURN failure keeps the owner active and releases the provisional listener", async () => {
    const id = fixtureShareID();
    const { owner } = await register(id, { maxListeners: 1 });
    await runInDurableObject(stubFor(id), (instance) => {
      instance.env = { ...instance.env, AUDIO_SHARE_TURN_KEY_ID: "synthetic-half-config" };
    });
    const unavailable = await open(id);
    unavailable.send({ type: "authenticate", v: 1, proof: proof(2) });
    expect((await unavailable.next()).error).toBe("turn_unavailable");
    await runInDurableObject(stubFor(id), (instance) => {
      instance.env = { ...instance.env, AUDIO_SHARE_TURN_KEY_ID: "" };
    });
    const { listener } = await admit(id, owner);
    owner.socket.close(1000); listener.socket.close(1000); unavailable.socket.close(1000);
  });

  it("never resurrects a listener when expiration wins a pending TURN request", async () => {
    const id = fixtureShareID();
    const { owner, registered } = await register(id, { ttlSeconds: 120 });
    await runInDurableObject(stubFor(id), (instance) => {
      instance.env = { ...instance.env, AUDIO_SHARE_TURN_KEY_ID: "synthetic-test-key",
        AUDIO_SHARE_TURN_API_TOKEN: "synthetic-test-token" };
    });
    const originalNow = Date.now;
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockImplementation(async () => {
      Date.now = () => registered.expiresAt;
      return new Response(JSON.stringify({ iceServers: [{ urls: ["turn:turn.cloudflare.com:3478?transport=udp"],
        username: "synthetic-test-user", credential: "synthetic-test-password" }] }), {
        status: 201, headers: { "Content-Type": "application/json" },
      });
    });
    try {
      const listener = await open(id);
      listener.send({ type: "authenticate", v: 1, proof: proof(2) });
      expect((await owner.next()).reason).toBe("expired");
      // Pending socket timeout may precede the final share-ended message; neither is a ready grant.
      const rejected = await listener.next();
      expect(["error", "ended"]).toContain(rejected.type);
      expect((await runInDurableObject(stubFor(id), (_, state) => state.storage.get("audio-share-v1"))).status).toBe("expired");
      owner.socket.close(1000); listener.socket.close(1000);
    } finally { Date.now = originalNow; fetchSpy.mockRestore(); }
  });
  it("refuses timeless/future locators and registration outside the birth window", async () => {
    const now = Date.now();
    for (const id of [encodeBase64URL(new Uint8Array(16)), fixtureShareID(now + 32_000)]) {
      expect((await SELF.fetch(`https://example.com/v3/audio-share/${id}`, { headers })).status).toBe(404);
    }
    const id = fixtureShareID(now - 181_000);
    const pending = await open(id);
    pending.send({ type: "register", v: 1, ownerProof: proof(1), listenerProof: proof(2),
      ttlSeconds: 600, maxListeners: 8 });
    expect((await pending.next()).error).toBe("invalid_creation_time");
    expect(await runInDurableObject(stubFor(id), (_, state) => state.storage.get("audio-share-v1"))).toBeUndefined();
    pending.socket.close(1000);
  });

  it("reservation deadline includes a held body, and oversized bodies fail before grant admission", async () => {
    await runInDurableObject(stubFor(fixtureShareID()), async (instance) => {
      const originalTimer = globalThis.setTimeout;
      const timer = vi.spyOn(globalThis, "setTimeout").mockImplementation((callback, delay, ...arguments_) =>
        originalTimer(callback, delay === 5_000 ? 10 : delay, ...arguments_));
      let cancelled = false;
      try {
        instance.env = { ...instance.env, AUDIO_SHARE_BUDGET: { idFromName: (value) => value,
          get: () => ({ fetch: async () => new Response(new ReadableStream({
            start(stream) { stream.enqueue(new TextEncoder().encode("{")); },
            cancel() { cancelled = true; },
          }), { headers: { "Content-Type": "application/json" }, status: 201 }) }) } };
        await expect(instance.reserveCreation(fixtureShareID(), 600)).rejects.toThrow("unavailable");
        expect(cancelled).toBe(true);
        instance.env = { ...instance.env, AUDIO_SHARE_BUDGET: { idFromName: (value) => value,
          get: () => ({ fetch: async () => new Response(" ".repeat(1_025), {
            headers: { "Content-Type": "application/json" }, status: 201,
          }) }) } };
        await expect(instance.reserveCreation(fixtureShareID(), 600)).rejects.toThrow("unavailable");
        expect(instance.state).toBeNull();
      } finally { timer.mockRestore(); }
    });
  });

  it.each([["count", 31], ["bytes", 5]])("bounds queued %s during held TURN and immediately fences owner admission", async (bound, queuedCount) => {
    const id = fixtureShareID();
    const { owner } = await register(id);
    const pending = await open(id);
    let release;
    let entered;
    const upstreamStarted = new Promise((resolve) => { entered = resolve; });
    const response = new Promise((resolve) => { release = resolve; });
    const spy = vi.spyOn(globalThis, "fetch").mockImplementation(() => { entered(); return response; });
    try {
      await runInDurableObject(stubFor(id), async (instance, state) => {
        instance.env = { ...instance.env, AUDIO_SHARE_TURN_KEY_ID: "synthetic-test-key",
          AUDIO_SHARE_TURN_API_TOKEN: "synthetic-test-token" };
        const sockets = instance.ctx.getWebSockets();
        const ownerSocket = sockets.find((socket) => instance.attachment(socket)?.phase === "owner");
        const pendingSocket = sockets.find((socket) => instance.attachment(socket)?.phase === "pending");
        const held = instance.webSocketMessage(pendingSocket, JSON.stringify({ type: "authenticate", v: 1, proof: proof(2) }));
        await upstreamStarted;
        const nextWire = () => bound === "bytes" ? " ".repeat(90_000) :
          JSON.stringify({ type: "probe", v: 1, nonce: fixtureID() });
        const queued = Array.from({ length: queuedCount }, () => instance.webSocketMessage(ownerSocket, nextWire()));
        expect(instance.pendingMessageCount).toBe(queuedCount + 1);
        expect(instance.pendingMessageBytes).toBeLessThanOrEqual(524_288);
        const shutdown = instance.webSocketMessage(ownerSocket, nextWire());
        expect(instance.ownerAdmissionRevoked).toBe(true);
        expect(instance.owner()).toBeNull();
        expect(instance.pendingMessageCount).toBe(queuedCount + 1);
        release(new Response(JSON.stringify({ iceServers: [{ urls: ["turn:turn.cloudflare.com:3478?transport=udp"],
          username: "synthetic-test-user", credential: "synthetic-test-password" }] }), {
          status: 201, headers: { "Content-Type": "application/json" },
        }));
        await Promise.all([held, ...queued, shutdown]);
        expect(instance.pendingMessageCount).toBe(0);
        expect(instance.pendingMessageBytes).toBe(0);
        expect(instance.currentSockets("listener")).toHaveLength(0);
        expect((await state.storage.get("audio-share-v1")).status).toBe("owner_lost");
      });
    } finally { spy.mockRestore(); owner.socket.close(1000); pending.socket.close(1000); }
  });

  it("rejects oversized UTF-8 before queueing and retires only the offending listener", async () => {
    const id = fixtureShareID();
    const { owner } = await register(id);
    const first = await admit(id, owner);
    const second = await admit(id, owner);
    await runInDurableObject(stubFor(id), async (instance) => {
      const target = instance.currentSockets("listener").find((socket) =>
        instance.attachment(socket).listenerID === first.ready.listenerID);
      await instance.webSocketMessage(target, "\u20ac".repeat(40_000));
      expect(instance.pendingMessageCount).toBe(0);
      expect(instance.pendingMessageBytes).toBe(0);
    });
    expect((await first.listener.next()).error).toBe("busy");
    expect((await owner.next()).listenerID).toBe(first.ready.listenerID);
    owner.send(signal(second.ready.listenerID));
    expect((await second.listener.next()).from).toBe("owner");
    owner.socket.close(1000); first.listener.socket.close(1000); second.listener.socket.close(1000);
  });

  it("collects a disabled-share tombstone only at its safe horizon and cannot resurrect its old link", async () => {
    const id = fixtureShareID();
    const { owner } = await register(id);
    owner.send({ type: "revoke", v: 1 });
    expect((await owner.next()).reason).toBe("revoked");
    const retirement = shareLocatorRetirementMilliseconds(id);
    await runInDurableObject(stubFor(id), async (instance, state) => {
      const originalNow = Date.now;
      instance.env = { ...instance.env, AUDIO_SHARE_ENABLED: "false" };
      try {
        Date.now = () => retirement - 1;
        await instance.alarm();
        expect((await state.storage.get("audio-share-v1")).status).toBe("revoked");
        Date.now = () => retirement;
        await instance.alarm();
        expect(await state.storage.get("audio-share-v1")).toBeUndefined();
        instance.env = { ...instance.env, AUDIO_SHARE_ENABLED: "true" };
        expect((await instance.fetch(new Request(`https://example.com/v3/audio-share/${id}`, { headers }))).status).toBe(404);
      } finally { Date.now = originalNow; }
    });
    owner.socket.close(1000);
  });

  it("spends failed TURN issuance durably and bounds cumulative churn independently of active slots", async () => {
    const id = fixtureShareID();
    const { owner } = await register(id, { maxListeners: 1 });
    await runInDurableObject(stubFor(id), (instance) => {
      instance.env = { ...instance.env, AUDIO_SHARE_TURN_KEY_ID: "synthetic-half-config" };
    });
    const failed = await open(id);
    failed.send({ type: "authenticate", v: 1, proof: proof(2) });
    expect((await failed.next()).error).toBe("turn_unavailable");
    expect((await runInDurableObject(stubFor(id), (_, state) => state.storage.get("audio-share-v1"))).listenerIssuances).toBe(1);
    await runInDurableObject(stubFor(id), (instance) => {
      instance.env = { ...instance.env, AUDIO_SHARE_TURN_KEY_ID: "" };
    });
    for (let index = 1; index < 64; index++) {
      const { listener, ready } = await admit(id, owner);
      listener.socket.close(1000);
      expect((await owner.next()).listenerID).toBe(ready.listenerID);
    }
    await evictDurableObject(stubFor(id));
    const denied = await open(id);
    denied.send({ type: "authenticate", v: 1, proof: proof(2) });
    expect((await denied.next()).error).toBe("issuance_limit");
    const stored = await runInDurableObject(stubFor(id), (_, state) => state.storage.get("audio-share-v1"));
    expect(stored.listenerIssuances).toBe(64);
    expect(stored.status).toBe("active");
    owner.socket.close(1000); denied.socket.close(1000); failed.socket.close(1000);
  });

  it("never uses phone TURN secrets when sharing TURN is not configured", async () => {
    const id = fixtureShareID();
    const { owner } = await register(id);
    await runInDurableObject(stubFor(id), (instance) => {
      instance.env = { ...instance.env, CLOUDFLARE_TURN_KEY_ID: "synthetic-phone-key",
        CLOUDFLARE_TURN_API_TOKEN: "synthetic-phone-token", TURN_FETCH_TIMEOUT_MS: "1",
        TURN_CREDENTIAL_TTL_SECONDS: "invalid" };
    });
    const spy = vi.spyOn(globalThis, "fetch").mockImplementation(async () => { throw new Error("phone TURN must not be used"); });
    try {
      const { listener, ready } = await admit(id, owner);
      expect(spy).not.toHaveBeenCalled();
      expect(ready.iceServers.every((server) => !server.urls.some((url) => url.startsWith("turn:")))).toBe(true);
      owner.socket.close(1000); listener.socket.close(1000);
    } finally { spy.mockRestore(); }
  });

  it("only the current owner retires one listener; stale IDs leave siblings and state intact", async () => {
    const id = fixtureShareID();
    const { owner } = await register(id);
    const first = await admit(id, owner);
    const second = await admit(id, owner);
    owner.send({ type: "retire-listener", v: 1, listenerID: first.ready.listenerID });
    expect((await first.listener.next()).reason).toBe("revoked");
    expect((await owner.next()).listenerID).toBe(first.ready.listenerID);
    for (const listenerID of [first.ready.listenerID, fixtureID()]) {
      owner.send({ type: "retire-listener", v: 1, listenerID });
      expect((await owner.next()).listenerID).toBe(listenerID);
    }
    const third = await admit(id, owner);
    third.listener.send({ type: "retire-listener", v: 1, listenerID: second.ready.listenerID });
    expect((await owner.next()).listenerID).toBe(third.ready.listenerID);
    owner.send(signal(second.ready.listenerID));
    expect((await second.listener.next()).from).toBe("owner");
    owner.send({ type: "probe", v: 1, nonce: fixtureID() });
    expect((await owner.next()).type).toBe("probe-ack");
    const stored = await runInDurableObject(stubFor(id), (_, state) => state.storage.get("audio-share-v1"));
    expect(stored.status).toBe("active");
    expect(stored.listenerIssuances).toBe(3);
    owner.socket.close(1000); first.listener.socket.close(1000); second.listener.socket.close(1000); third.listener.socket.close(1000);
  });
});
