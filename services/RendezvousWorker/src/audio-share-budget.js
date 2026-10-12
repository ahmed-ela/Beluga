import { DurableObject } from "cloudflare:workers";
import { AUDIO_SHARE_LIMITS as LIMITS, exactKeys, freshShareLocator,
  validShareID } from "../../../browser/beluga-audio/public/protocol.js";

const KEY = "audio-share-budget-v1";
const DAY_MS = 86_400_000;
const MAX_RETAINED = 1_000;
const reply = (value, status) => new Response(JSON.stringify(value), { status, headers: {
  "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store",
} });
const integer = (value, fallback, maximum) => {
  const text = value ?? String(fallback);
  if (typeof text !== "string" || !/^[1-9][0-9]*$/.test(text)) return null;
  const number = Number(text);
  return Number.isSafeInteger(number) && number <= maximum ? number : null;
};
const validEntry = (entry) => exactKeys(entry, ["shareID", "createdAt", "expiresAt"]) &&
  validShareID(entry.shareID) && Number.isSafeInteger(entry.createdAt) && entry.createdAt > 0 &&
  Number.isSafeInteger(entry.expiresAt) && entry.expiresAt > entry.createdAt &&
  entry.expiresAt - entry.createdAt <= LIMITS.maxTTLSeconds * 1_000 &&
  freshShareLocator(entry.shareID, entry.createdAt);
const validState = (state) => exactKeys(state, ["v", "lastObservedAt", "entries"]) && state.v === 1 &&
  Number.isSafeInteger(state.lastObservedAt) && state.lastObservedAt >= 0 &&
  Array.isArray(state.entries) && state.entries.length <= MAX_RETAINED &&
  state.entries.every(validEntry) && new Set(state.entries.map((entry) => entry.shareID)).size === state.entries.length &&
  state.entries.every((entry) => entry.createdAt <= state.lastObservedAt);

/** One fixed global-v1 object owns atomic rolling-day/active creation admission. It has no
 * public route and stores no bearer proofs. Reservations are never released by socket events:
 * immutable server expiry avoids delayed-close/release races and bounds retained entries. */
export class AudioShareBudget extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.ctx = ctx;
    this.env = env;
    this.queue = Promise.resolve();
    this.pendingReservations = 0;
    this.state = { v: 1, lastObservedAt: 0, entries: [] };
    this.corrupt = false;
    this.initialized = ctx.blockConcurrencyWhile(async () => {
      const saved = await ctx.storage.get(KEY);
      if (saved !== undefined && !validState(saved)) this.corrupt = true;
      else if (saved !== undefined) this.state = saved;
    });
  }

  serialize(operation) {
    const result = this.queue.then(async () => { await this.initialized; return operation(); });
    this.queue = result.catch(() => {});
    return result;
  }

  async persist(now, entries) {
    const next = { v: 1, lastObservedAt: now, entries };
    await this.ctx.storage.put(KEY, next);
    this.state = next;
    const deadlines = entries.flatMap((entry) => [entry.createdAt + DAY_MS, entry.expiresAt])
      .filter((deadline) => deadline > now);
    if (deadlines.length) await this.ctx.storage.setAlarm(Math.min(...deadlines));
    else await this.ctx.storage.deleteAlarm();
  }

  fetch(request) {
    if (this.pendingReservations >= LIMITS.maxPendingMessages) return Promise.resolve(reply({ error: "creation_limit" }, 429));
    this.pendingReservations += 1;
    return this.serialize(async () => {
      try {
        const url = new URL(request.url);
        if (this.env.AUDIO_SHARE_ENABLED !== "true" || request.method !== "POST" ||
            url.origin !== "https://audio-share-budget.internal" || url.pathname !== "/reserve" ||
            url.search || request.headers.get("Content-Type") !== "application/json") {
          return reply({ error: "invalid_reservation" }, 400);
        }
        const wire = await request.text();
        if (wire.length > 1_024) return reply({ error: "invalid_reservation" }, 400);
        let message;
        try { message = JSON.parse(wire); } catch { return reply({ error: "invalid_reservation" }, 400); }
        const now = Date.now();
        if (!exactKeys(message, ["v", "shareID", "ttlSeconds"]) || message.v !== 1 ||
            !freshShareLocator(message.shareID, now) || !Number.isSafeInteger(message.ttlSeconds) ||
            message.ttlSeconds < 1 || message.ttlSeconds > LIMITS.maxTTLSeconds) {
          return reply({ error: "invalid_reservation" }, 400);
        }
        const daily = integer(this.env.AUDIO_SHARE_DAILY_CREATION_LIMIT, 100, MAX_RETAINED);
        const active = integer(this.env.AUDIO_SHARE_ACTIVE_GRANT_LIMIT, 32, 128);
        if (this.corrupt || daily === null || active === null ||
            !Number.isSafeInteger(now) || now < this.state.lastObservedAt) {
          return reply({ error: "unavailable" }, 503);
        }
        const entries = this.state.entries.filter((entry) => now < entry.createdAt + DAY_MS);
        if (entries.some((entry) => entry.shareID === message.shareID) || entries.length >= daily ||
            entries.filter((entry) => now < entry.expiresAt).length >= active) {
          // Prune expired rolling-day entries even when admission is denied.
          await this.persist(now, entries);
          return reply({ error: "creation_limit" }, 429);
        }
        const grant = { shareID: message.shareID, createdAt: now,
          expiresAt: now + message.ttlSeconds * 1_000 };
        await this.persist(now, [...entries, grant]);
        return reply({ v: 1, ...grant }, 201);
      } catch {
        this.corrupt = true;
        return reply({ error: "unavailable" }, 503);
      }
    }).finally(() => { this.pendingReservations -= 1; });
  }

  alarm() {
    return this.serialize(async () => {
      const now = Date.now();
      if (this.corrupt || !Number.isSafeInteger(now) || now < this.state.lastObservedAt) return;
      try { await this.persist(now, this.state.entries.filter((entry) => now < entry.createdAt + DAY_MS)); }
      catch { this.corrupt = true; }
    });
  }
}
