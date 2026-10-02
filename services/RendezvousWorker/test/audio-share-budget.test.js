import { env, evictDurableObject, runInDurableObject } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { encodeBase64URL, encodeShareLocator } from "../../../browser/beluga-audio/public/protocol.js";

const KEY = "audio-share-budget-v1";
const DAY = 86_400_000;
const locator = (now = Date.now()) => encodeShareLocator(crypto.getRandomValues(new Uint8Array(12)), now);
const freshStub = () => env.AUDIO_SHARE_BUDGET.get(env.AUDIO_SHARE_BUDGET.idFromName(
  `isolated-budget:${encodeBase64URL(crypto.getRandomValues(new Uint8Array(16)))}`));
const request = (shareID, ttlSeconds = 600, extra = {}) => new Request("https://audio-share-budget.internal/reserve", {
  method: "POST", headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ v: 1, shareID, ttlSeconds, ...extra }),
});

describe("isolated durable anonymous-sharing creation budget", () => {
  it("bounds the internal authority queue before appending more durable work", async () => {
    await runInDurableObject(freshStub(), async (instance, state) => {
      let release;
      instance.queue = new Promise((resolve) => { release = resolve; });
      const held = Array.from({ length: 32 }, () => instance.fetch(request(locator())));
      expect(instance.pendingReservations).toBe(32);
      expect((await instance.fetch(request(locator()))).status).toBe(429);
      expect(instance.pendingReservations).toBe(32);
      release();
      const responses = await Promise.all(held);
      expect(responses.every((response) => response.status === 201)).toBe(true);
      expect(instance.pendingReservations).toBe(0);
      expect((await state.storage.get(KEY)).entries).toHaveLength(32);
    });
  });

  it("serializes concurrent reservations at the exact active ceiling and retains no bearer proofs", async () => {
    const stub = freshStub();
    await runInDurableObject(stub, (instance) => {
      instance.env = { ...instance.env, AUDIO_SHARE_ACTIVE_GRANT_LIMIT: "2", AUDIO_SHARE_DAILY_CREATION_LIMIT: "4" };
    });
    const responses = await Promise.all(Array.from({ length: 8 }, () => stub.fetch(request(locator()))));
    expect(responses.filter((response) => response.status === 201)).toHaveLength(2);
    expect(responses.filter((response) => response.status === 429)).toHaveLength(6);
    const state = await runInDurableObject(stub, (_, state) => state.storage.get(KEY));
    expect(state.entries).toHaveLength(2);
    expect(Object.keys(state).sort()).toEqual(["entries", "lastObservedAt", "v"]);
    for (const entry of state.entries) {
      expect(Object.keys(entry).sort()).toEqual(["createdAt", "expiresAt", "shareID"]);
      expect(entry.expiresAt - entry.createdAt).toBe(600_000);
    }
  });

  it("refills active capacity only at immutable server expiry; daily capacity refills only after a full day", async () => {
    const stub = freshStub();
    await runInDurableObject(stub, async (instance, state) => {
      instance.env = { ...instance.env, AUDIO_SHARE_ACTIVE_GRANT_LIMIT: "1", AUDIO_SHARE_DAILY_CREATION_LIMIT: "2" };
      const originalNow = Date.now;
      const began = Date.now();
      try {
        Date.now = () => began;
        const firstID = locator(began);
        expect((await instance.fetch(request(firstID, 1))).status).toBe(201);
        expect((await instance.fetch(request(locator(began), 1))).status).toBe(429);
        Date.now = () => began + 1_000;
        expect((await instance.fetch(request(locator(began + 1_000), 1))).status).toBe(201);
        Date.now = () => began + 2_000;
        expect((await instance.fetch(request(locator(began + 2_000), 1))).status).toBe(429);
        expect((await state.storage.get(KEY)).entries).toHaveLength(2);
        Date.now = () => began + DAY;
        await instance.alarm();
        expect((await state.storage.get(KEY)).entries).toHaveLength(1);
        expect((await instance.fetch(request(firstID, 1))).status).toBe(400);
        expect((await instance.fetch(request(locator(began + DAY), 1))).status).toBe(201);
        Date.now = () => began + DAY + 2_000;
        await instance.alarm();
        expect((await state.storage.get(KEY)).entries).toHaveLength(1);
      } finally { Date.now = originalNow; }
    });
  });

  it("duplicate reservations, actor/ID rotation and hibernation cannot bypass the retained daily bound", async () => {
    const stub = freshStub();
    await runInDurableObject(stub, (instance) => {
      instance.env = { ...instance.env, AUDIO_SHARE_DAILY_CREATION_LIMIT: "2" };
    });
    const first = locator();
    const drainedStatus = async (input) => {
      const response = await stub.fetch(input);
      // Eviction waits for in-flight HTTP requests, including their response bodies.
      // A status-only assertion leaves that request alive in the Workers test pool.
      await response.text();
      return response.status;
    };
    expect(await drainedStatus(request(first))).toBe(201);
    expect(await drainedStatus(request(first))).toBe(429);
    expect(await drainedStatus(request(locator()))).toBe(201);
    await evictDurableObject(stub);
    await runInDurableObject(stub, (instance) => {
      instance.env = { ...instance.env, AUDIO_SHARE_DAILY_CREATION_LIMIT: "2" };
    });
    expect(await drainedStatus(request(locator()))).toBe(429);
    expect((await runInDurableObject(stub, (_, state) => state.storage.get(KEY))).entries).toHaveLength(2);
  });

  it("rejects malformed, timeless, stale and future registrations before durable reservation", async () => {
    const stub = freshStub();
    const now = Date.now();
    for (const malformed of [request(locator(), 0), request(locator(), 86_401), request(locator(), 1, { extra: true }),
      request(encodeBase64URL(new Uint8Array(16))), request(locator(now - 181_000)), request(locator(now + 32_000)),
      new Request("https://audio-share-budget.internal/reserve?extra=1", {
        method: "POST", headers: { "Content-Type": "application/json" }, body: "{}",
      }), new Request("https://example.com/reserve", {
        method: "POST", headers: { "Content-Type": "application/json" }, body: "{}",
      })]) expect((await stub.fetch(malformed)).status).toBe(400);
    expect(await runInDurableObject(stub, (_, state) => state.storage.get(KEY))).toBeUndefined();
  });

  it("fails closed for invalid bounded configuration, disabled sharing and regressing server time", async () => {
    for (const [name, value] of [["AUDIO_SHARE_DAILY_CREATION_LIMIT", "0"],
      ["AUDIO_SHARE_DAILY_CREATION_LIMIT", "1001"], ["AUDIO_SHARE_DAILY_CREATION_LIMIT", "01"],
      ["AUDIO_SHARE_ACTIVE_GRANT_LIMIT", "129"]]) {
      const stub = freshStub();
      await runInDurableObject(stub, (instance) => { instance.env = { ...instance.env, [name]: value }; });
      expect((await stub.fetch(request(locator()))).status).toBe(503);
      expect(await runInDurableObject(stub, (_, state) => state.storage.get(KEY))).toBeUndefined();
    }
    const disabled = freshStub();
    await runInDurableObject(disabled, (instance) => { instance.env = { ...instance.env, AUDIO_SHARE_ENABLED: "false" }; });
    expect((await disabled.fetch(request(locator()))).status).toBe(400);
    const stub = freshStub();
    expect((await stub.fetch(request(locator()))).status).toBe(201);
    await runInDurableObject(stub, async (instance, state) => {
      const saved = await state.storage.get(KEY);
      const originalNow = Date.now;
      try {
        Date.now = () => saved.lastObservedAt - 1;
        expect((await instance.fetch(request(locator(Date.now())))).status).toBe(503);
        await instance.alarm();
        expect(await state.storage.get(KEY)).toEqual(saved);
      } finally { Date.now = originalNow; }
    });
  });

  it("corrupt durable budget state cannot be reset to mint fresh grants", async () => {
    const stub = freshStub();
    await runInDurableObject(stub, (_, state) => state.storage.put(KEY, {
      v: 1, lastObservedAt: Date.now(), entries: [{ shareID: locator(), createdAt: -1, expiresAt: 1 }],
    }));
    await evictDurableObject(stub);
    expect((await stub.fetch(request(locator()))).status).toBe(503);
  });
});
