import { DurableObject } from "cloudflare:workers";
import { iceServersForJoin } from "./ice.js";
import {
  AUDIO_SHARE_LIMITS as LIMITS, AUDIO_SHARE_PROTOCOL, encodeBase64URL, exactKeys,
  freshShareLocator, joinableShareLocator, parseAuthentication, parseClientMessage,
  shareLocatorRetirementMilliseconds, validProof, validShareID,
  utf8Length,
} from "../../../browser/beluga-audio/public/protocol.js";
import { constantTimeProofsEqual, hashAdmission } from "../../../browser/beluga-audio/public/crypto.js";

const STORAGE_KEY = "audio-share-v1";
const PHASES = new Set(["pending", "owner", "listener", "closed"]);
const STATUSES = new Set(["active", "expired", "revoked", "owner_lost"]);
const json = (error, status) => new Response(JSON.stringify({ error }), {
  status, headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
});
const randomID = () => encodeBase64URL(crypto.getRandomValues(new Uint8Array(16)));
const send = (socket, value) => {
  try { if (socket.readyState === 1) { socket.send(JSON.stringify(value)); return true; } } catch { /* fail closed below */ }
  return false;
};
const close = (socket, code = 4404, reason = "audio share unavailable") => {
  try { socket.close(code, reason); } catch { /* an already-closed socket is sufficient */ }
};
const validState = (value) => exactKeys(value, ["v", "shareID", "generation", "ownerHash", "listenerHash",
  "createdAt", "expiresAt", "maxListeners", "listenerIssuances", "status"]) && value.v === 1 && validShareID(value.shareID) &&
  validShareID(value.generation) && validProof(value.ownerHash) && validProof(value.listenerHash) &&
  value.ownerHash !== value.listenerHash && Number.isSafeInteger(value.createdAt) && value.createdAt > 0 &&
  Number.isSafeInteger(value.expiresAt) && value.expiresAt > value.createdAt &&
  value.expiresAt - value.createdAt <= LIMITS.maxTTLSeconds * 1_000 &&
  freshShareLocator(value.shareID, value.createdAt) &&
  Number.isSafeInteger(value.maxListeners) && value.maxListeners >= 1 && value.maxListeners <= LIMITS.maxListeners &&
  Number.isSafeInteger(value.listenerIssuances) && value.listenerIssuances >= 0 &&
  value.listenerIssuances <= LIMITS.maxLifetimeIssuances &&
  STATUSES.has(value.status);
const validAttachment = (value) => exactKeys(value, ["v", "phase", "shareID", "generation", "listenerID",
  "authDeadline", "leaseDeadline", "ownerSequence", "listenerSequence", "rateStart", "rateCount"]) &&
  value.v === 1 && PHASES.has(value.phase) && validShareID(value.shareID) &&
  (value.generation === null || validShareID(value.generation)) &&
  (value.listenerID === null || validShareID(value.listenerID)) &&
  [value.authDeadline, value.leaseDeadline, value.ownerSequence, value.listenerSequence,
    value.rateStart, value.rateCount].every((number) => Number.isSafeInteger(number) && number >= 0) &&
  value.rateCount <= LIMITS.messagesPerMinute && value.ownerSequence <= LIMITS.maxSequence + 1 &&
  value.listenerSequence <= LIMITS.maxSequence + 1 &&
  (value.phase !== "listener" || (value.generation !== null && value.listenerID !== null)) &&
  (value.phase !== "owner" || (value.generation !== null && value.listenerID === null));

export class AudioShareSession extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.ctx = ctx;
    this.env = env;
    this.state = null;
    this.corrupt = false;
    this.queue = Promise.resolve();
    this.pendingMessageCount = 0;
    this.pendingMessageBytes = 0;
    this.ownerAdmissionRevoked = false;
    this.initialized = ctx.blockConcurrencyWhile(async () => {
      const stored = await ctx.storage.get(STORAGE_KEY);
      if (stored !== undefined && !validState(stored)) this.corrupt = true;
      else this.state = stored ?? null;
      for (const socket of ctx.getWebSockets()) {
        if (!this.attachment(socket)) { this.corrupt = true; close(socket); }
      }
      if (this.corrupt) for (const socket of ctx.getWebSockets()) close(socket);
    });
  }

  serialize(operation) {
    const result = this.queue.then(async () => { await this.initialized; return operation(); });
    this.queue = result.catch(() => {});
    return result;
  }

  attachment(socket) {
    try { const value = socket.deserializeAttachment(); return validAttachment(value) ? value : null; }
    catch { return null; }
  }

  currentSockets(phase) {
    return this.ctx.getWebSockets().filter((socket) => {
      const attachment = this.attachment(socket);
      return socket.readyState === 1 && attachment?.phase === phase &&
        (phase === "pending" || (this.state && attachment.shareID === this.state.shareID &&
          attachment.generation === this.state.generation));
    });
  }

  owner() {
    if (this.ownerAdmissionRevoked) return null;
    const owners = this.currentSockets("owner");
    return owners.length === 1 ? owners[0] : null;
  }

  async scheduleAlarm() {
    const deadlines = [];
    if (this.state?.status === "active") deadlines.push(this.state.expiresAt);
    else if (this.state) deadlines.push(shareLocatorRetirementMilliseconds(this.state.shareID));
    for (const socket of this.ctx.getWebSockets()) {
      const attachment = this.attachment(socket);
      if (socket.readyState !== 1 || !attachment) continue;
      if (attachment.phase === "pending") deadlines.push(attachment.authDeadline);
      if (attachment.phase === "owner") deadlines.push(attachment.leaseDeadline);
    }
    if (deadlines.length) await this.ctx.storage.setAlarm(Math.max(Date.now(), Math.min(...deadlines)));
    else await this.ctx.storage.deleteAlarm();
  }

  async end(status) {
    if (!this.state || this.state.status !== "active") return;
    // Retain the tombstone through every possible original lifetime. Its birth-fenced ID
    // remains permanently ineligible for registration even after the tombstone is collected.
    this.state = { ...this.state, status };
    try { await this.ctx.storage.put(STORAGE_KEY, this.state); }
    catch { this.corrupt = true; }
    for (const socket of this.ctx.getWebSockets()) {
      const attachment = this.attachment(socket);
      if (attachment) socket.serializeAttachment({ ...attachment, phase: "closed" });
      send(socket, { type: "ended", v: 1, reason: status });
      close(socket, status === "expired" ? 4408 : 4404);
    }
    try { await this.scheduleAlarm(); } catch { this.corrupt = true; }
  }

  async enforceDeadlines() {
    if (this.corrupt) { for (const socket of this.ctx.getWebSockets()) close(socket); return; }
    const now = Date.now();
    if (this.env.AUDIO_SHARE_ENABLED !== "true") {
      await this.end("revoked");
      for (const socket of this.currentSockets("pending")) this.reject(socket, "unavailable");
    }
    for (const socket of this.currentSockets("pending")) {
      if (this.attachment(socket).authDeadline <= now) this.reject(socket, "authentication_timeout");
    }
    if (this.state?.status !== "active") {
      if (this.state && now >= shareLocatorRetirementMilliseconds(this.state.shareID)) {
        await this.ctx.storage.delete(STORAGE_KEY);
        this.state = null;
      }
      return;
    }
    if (this.state.expiresAt <= now) { await this.end("expired"); return; }
    const owner = this.owner();
    if (!owner || this.attachment(owner).leaseDeadline <= now) await this.end("owner_lost");
  }

  reject(socket, error) {
    const attachment = this.attachment(socket);
    if (attachment) socket.serializeAttachment({ ...attachment, phase: "closed" });
    send(socket, { type: "error", v: 1, error });
    close(socket);
  }

  fetch(request) {
    return this.serialize(async () => {
      const url = new URL(request.url);
      const match = /^\/v3\/audio-share\/([A-Za-z0-9_-]+)$/.exec(url.pathname);
      if (this.env.AUDIO_SHARE_ENABLED !== "true" || !match || !validShareID(match[1]) ||
          request.method !== "GET" || url.protocol !== "https:" || url.search ||
          request.headers.get("Upgrade")?.toLowerCase() !== "websocket" ||
          request.headers.get("Sec-WebSocket-Protocol") !== AUDIO_SHARE_PROTOCOL) return json("invalid_join", 400);
      if (!joinableShareLocator(match[1])) return json("unavailable", 404);
      if (this.corrupt) return json("unavailable", 503);
      await this.enforceDeadlines();
      if (this.state && (this.state.shareID !== match[1] || this.state.status !== "active")) return json("unavailable", 404);
      if (this.currentSockets("pending").length >= LIMITS.maxPendingSockets) return json("busy", 429);
      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);
      const now = Date.now();
      server.serializeAttachment({ v: 1, phase: "pending", shareID: match[1], generation: null,
        listenerID: null, authDeadline: now + LIMITS.authenticationMs, leaseDeadline: 0,
        ownerSequence: 0, listenerSequence: 0, rateStart: now, rateCount: 0 });
      this.ctx.acceptWebSocket(server);
      await this.scheduleAlarm();
      return new Response(null, { status: 101, webSocket: client,
        headers: { "Sec-WebSocket-Protocol": AUDIO_SHARE_PROTOCOL } });
    });
  }

  rejectBeforeQueue(socket) {
    const attachment = this.attachment(socket);
    if (attachment?.phase === "owner" && socket === this.owner()) {
      // Revoke the shared admission gate before appending a terminal mutation. A held
      // upstream completion cannot install a listener while serialized shutdown waits.
      this.ownerAdmissionRevoked = true;
      for (const current of this.ctx.getWebSockets()) close(current, 4429);
      return this.serialize(async () => { await this.end("owner_lost"); await this.scheduleAlarm(); });
    }
    this.reject(socket, attachment?.phase === "pending" ? "invalid_authentication" : "busy");
    if (attachment?.phase === "listener" && this.state?.status === "active" &&
        attachment.generation === this.state.generation) {
      const owner = this.owner();
      if (!owner || !send(owner, { type: "listener-left", v: 1, listenerID: attachment.listenerID })) {
        this.ownerAdmissionRevoked = true;
        for (const current of this.ctx.getWebSockets()) close(current, 4429);
        return this.serialize(async () => { await this.end("owner_lost"); await this.scheduleAlarm(); });
      }
    }
    return Promise.resolve();
  }

  webSocketMessage(socket, wire) {
    // Check UTF-16 length before allocating UTF-8. Only a bounded wire can enter the
    // Promise chain; reserve before append, including while a TURN request is held.
    if (typeof wire !== "string" || wire.length > LIMITS.maxWireBytes) return this.rejectBeforeQueue(socket);
    const size = utf8Length(wire);
    if (size > LIMITS.maxWireBytes || this.pendingMessageCount >= LIMITS.maxPendingMessages ||
        this.pendingMessageBytes + size > LIMITS.maxPendingMessageBytes) return this.rejectBeforeQueue(socket);
    this.pendingMessageCount += 1;
    this.pendingMessageBytes += size;
    return this.serialize(async () => {
      try {
        await this.enforceDeadlines();
        const attachment = this.attachment(socket);
        if (this.corrupt || !attachment || attachment.phase === "closed" || socket.readyState !== 1) {
          close(socket); return;
        }
        if (attachment.phase === "pending") {
          const authentication = parseAuthentication(wire);
          if (!authentication) { this.reject(socket, "invalid_authentication"); return; }
          if (authentication.type === "register") await this.register(socket, attachment, authentication);
          else await this.authenticate(socket, attachment, authentication);
          await this.scheduleAlarm();
          return;
        }
        if (this.state?.status !== "active" || attachment.generation !== this.state.generation) {
          this.reject(socket, "unavailable"); return;
        }
        const now = Date.now();
        const rateCount = now - attachment.rateStart >= 60_000 ? 1 : attachment.rateCount + 1;
        const rateStart = now - attachment.rateStart >= 60_000 ? now : attachment.rateStart;
        if (rateCount > LIMITS.messagesPerMinute) { await this.depart(socket, attachment); close(socket, 4429); return; }
        socket.serializeAttachment({ ...attachment, rateCount, rateStart });
        const message = parseClientMessage(wire);
        if (!message) { await this.depart(socket, attachment); close(socket, 4400); return; }
        if (message.type === "revoke") {
          if (attachment.phase !== "owner") { await this.depart(socket, attachment); close(socket, 4400); return; }
          await this.end("revoked");
        } else if (message.type === "retire-listener") {
          if (attachment.phase !== "owner" || socket !== this.owner()) {
            await this.depart(socket, attachment); close(socket, 4400); return;
          }
          const matches = this.currentSockets("listener").filter((candidate) =>
            this.attachment(candidate).listenerID === message.listenerID);
          if (matches.length > 1) { await this.end("owner_lost"); return; }
          const listener = matches[0];
          if (listener) {
            send(listener, { type: "ended", v: 1, reason: "revoked" });
            await this.depart(listener, this.attachment(listener));
            close(listener);
          } else if (!send(socket, { type: "listener-left", v: 1, listenerID: message.listenerID })) {
            await this.end("owner_lost");
          }
        } else if (message.type === "probe") {
          if (attachment.phase !== "owner" || socket !== this.owner()) {
            await this.depart(socket, attachment); close(socket, 4400); return;
          }
          const leaseDeadline = Math.min(this.state.expiresAt, now + LIMITS.ownerLeaseMs);
          socket.serializeAttachment({ ...this.attachment(socket), leaseDeadline });
          if (!send(socket, { type: "probe-ack", v: 1, nonce: message.nonce, serverTime: now,
            leaseExpiresAt: leaseDeadline })) await this.end("owner_lost");
        } else await this.forward(socket, attachment, message);
        await this.scheduleAlarm();
      } catch {
        // Collapse upstream/storage failures; never expose credential-bearing exception strings.
        const attachment = this.attachment(socket);
        if (attachment?.phase === "owner") await this.end("owner_lost");
        else if (attachment?.phase === "listener") await this.depart(socket, attachment);
        this.reject(socket, "unavailable");
      }
    }).finally(() => {
      this.pendingMessageCount -= 1;
      this.pendingMessageBytes -= size;
    });
  }

  async register(socket, attachment, message) {
    if (this.state) { this.reject(socket, "unavailable"); return; }
    if (!freshShareLocator(attachment.shareID)) { this.reject(socket, "invalid_creation_time"); return; }
    const [ownerHash, listenerHash] = await Promise.all([
      hashAdmission(message.ownerProof), hashAdmission(message.listenerProof),
    ]);
    if (Date.now() >= attachment.authDeadline || socket.readyState !== 1) {
      this.reject(socket, "authentication_timeout"); return;
    }
    // The separate fixed global authority serializes reservation and expiry; socket departure
    // never releases it. A failed/uncertain reservation cannot create this durable share.
    const grant = await this.reserveCreation(attachment.shareID, message.ttlSeconds);
    if (!grant) { this.reject(socket, "creation_limit"); return; }
    if (Date.now() >= attachment.authDeadline || socket.readyState !== 1 ||
        !freshShareLocator(attachment.shareID)) {
      this.reject(socket, "authentication_timeout"); return;
    }
    this.state = { v: 1, shareID: attachment.shareID, generation: randomID(), ownerHash, listenerHash,
      createdAt: grant.createdAt, expiresAt: grant.expiresAt,
      maxListeners: message.maxListeners, listenerIssuances: 0, status: "active" };
    await this.ctx.storage.put(STORAGE_KEY, this.state);
    const now = Date.now();
    const leaseDeadline = Math.min(this.state.expiresAt, now + LIMITS.ownerLeaseMs);
    socket.serializeAttachment({ ...attachment, phase: "owner", generation: this.state.generation, leaseDeadline });
    if (!send(socket, { type: "registered", v: 1, shareID: this.state.shareID,
      generation: this.state.generation, expiresAt: this.state.expiresAt, serverTime: now,
      leaseExpiresAt: leaseDeadline, maxListeners: this.state.maxListeners })) await this.end("owner_lost");
  }

  async reserveCreation(shareID, ttlSeconds) {
    if (!this.env.AUDIO_SHARE_BUDGET) throw new Error("unavailable");
    const stub = this.env.AUDIO_SHARE_BUDGET.get(this.env.AUDIO_SHARE_BUDGET.idFromName("global-v1"));
    const started = Date.now();
    const controller = new AbortController();
    let timer;
    let reader;
    try {
      // The same finite deadline covers headers AND a bounded fully drained body.
      // Do not end the race at headers and leave response.text() able to hang.
      const operation = (async () => {
        const response = await stub.fetch(new Request("https://audio-share-budget.internal/reserve", { method: "POST",
          headers: { "Content-Type": "application/json" }, signal: controller.signal,
          body: JSON.stringify({ v: 1, shareID, ttlSeconds }) }));
        if (controller.signal.aborted) {
          if (response.body) void response.body.cancel().catch(() => {});
          throw new Error("unavailable");
        }
        if (!/^application\/json(?:\s*;|$)/i.test(response.headers.get("Content-Type") ?? "") ||
            !response.body) throw new Error("unavailable");
        reader = response.body.getReader();
        const bytes = new Uint8Array(1_024);
        let size = 0;
        while (true) {
          const { done, value } = await reader.read();
          if (controller.signal.aborted) throw new Error("unavailable");
          if (done) break;
          if (value.byteLength > bytes.byteLength - size) throw new Error("unavailable");
          bytes.set(value, size);
          size += value.byteLength;
        }
        reader.releaseLock();
        reader = undefined;
        if (response.status === 429) return null;
        if (response.status !== 201) throw new Error("unavailable");
        const grant = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes.subarray(0, size)));
        if (!exactKeys(grant, ["v", "shareID", "createdAt", "expiresAt"]) || grant.v !== 1 ||
            grant.shareID !== shareID || !Number.isSafeInteger(grant.createdAt) ||
            grant.createdAt < started - LIMITS.creationFutureMs ||
            grant.createdAt > Date.now() + LIMITS.creationFutureMs ||
            !Number.isSafeInteger(grant.expiresAt) ||
            grant.expiresAt - grant.createdAt !== ttlSeconds * 1_000 ||
            grant.expiresAt <= Date.now() ||
            !freshShareLocator(shareID, grant.createdAt)) throw new Error("unavailable");
        return grant;
      })();
      return await Promise.race([
        operation,
        new Promise((_, reject) => { timer = setTimeout(() => {
          controller.abort(); reject(new Error("unavailable"));
        }, LIMITS.authenticationMs); }),
      ]);
    } finally {
      clearTimeout(timer);
      controller.abort();
      // Cancellation is best-effort and must not become another unbounded await.
      if (reader) void reader.cancel().catch(() => {});
    }
  }

  async authenticate(socket, attachment, message) {
    // Admission precedes occupancy, listener allocation, or any TURN request.
    if (this.state?.status !== "active" || attachment.shareID !== this.state.shareID ||
        !constantTimeProofsEqual(await hashAdmission(message.proof), this.state.listenerHash)) {
      this.reject(socket, "unavailable"); return;
    }
    await this.enforceDeadlines();
    if (this.state.status !== "active" || socket.readyState !== 1 || Date.now() >= attachment.authDeadline) {
      this.reject(socket, "unavailable"); return;
    }
    if (this.currentSockets("listener").length >= this.state.maxListeners) { this.reject(socket, "listener_limit"); return; }
    if (this.state.listenerIssuances >= LIMITS.maxLifetimeIssuances) { this.reject(socket, "issuance_limit"); return; }
    // Spend before any upstream request, including a failed TURN request. This is cumulative,
    // independent of the simultaneous listener bound, and survives hibernation/churn.
    this.state = { ...this.state, listenerIssuances: this.state.listenerIssuances + 1 };
    await this.ctx.storage.put(STORAGE_KEY, this.state);
    let iceServers;
    try {
      const remainingSeconds = Math.floor((this.state.expiresAt - Date.now()) / 1_000);
      const configuredTTL = Number(this.env.AUDIO_SHARE_TURN_CREDENTIAL_TTL_SECONDS ?? "600");
      if (!Number.isSafeInteger(configuredTTL) || configuredTTL < 60) throw new Error();
      const hasManagedTurn = Boolean(this.env.AUDIO_SHARE_TURN_KEY_ID || this.env.AUDIO_SHARE_TURN_API_TOKEN);
      if (hasManagedTurn && remainingSeconds < 60) throw new Error();
      // No fallback to phone TURN secrets or phone credential/budget configuration.
      iceServers = await iceServersForJoin({ STUN_URLS: this.env.STUN_URLS,
        CLOUDFLARE_TURN_KEY_ID: this.env.AUDIO_SHARE_TURN_KEY_ID,
        CLOUDFLARE_TURN_API_TOKEN: this.env.AUDIO_SHARE_TURN_API_TOKEN,
        TURN_FETCH_TIMEOUT_MS: this.env.AUDIO_SHARE_TURN_FETCH_TIMEOUT_MS ?? "5000",
        TURN_CREDENTIAL_TTL_SECONDS: String(Math.min(configuredTTL, remainingSeconds)) });
    } catch { this.reject(socket, "turn_unavailable"); return; }
    await this.enforceDeadlines();
    const owner = this.owner();
    if (this.state.status !== "active" || !owner || socket.readyState !== 1 || Date.now() >= attachment.authDeadline) {
      this.reject(socket, "unavailable"); return;
    }
    const listenerID = randomID();
    socket.serializeAttachment({ ...attachment, phase: "listener", generation: this.state.generation, listenerID });
    const ready = { type: "listener-ready", v: 1, shareID: this.state.shareID, generation: this.state.generation,
      listenerID, expiresAt: this.state.expiresAt, serverTime: Date.now(), iceServers };
    if (!send(owner, { ...ready, role: "owner" })) { await this.end("owner_lost"); return; }
    if (!send(socket, { ...ready, role: "listener" })) await this.depart(socket, this.attachment(socket));
  }

  async forward(socket, attachment, message) {
    const listeners = this.currentSockets("listener").filter((candidate) =>
      this.attachment(candidate).listenerID === message.listenerID);
    const listener = listeners.length === 1 ? listeners[0] : null;
    const owner = this.owner();
    if (!listener && owner === socket && attachment.phase === "owner") {
      // Listener departure can race an already queued offer/candidate; retire only that target.
      if (!send(owner, { type: "listener-left", v: 1, listenerID: message.listenerID })) await this.end("owner_lost");
      return;
    }
    if (!listener || !owner || (attachment.phase === "listener" && socket !== listener) ||
        (attachment.phase === "owner" && socket !== owner)) {
      await this.depart(socket, attachment); close(socket, 4400); return;
    }
    const target = attachment.phase === "owner" ? listener : owner;
    const listenerAttachment = this.attachment(listener);
    const key = attachment.phase === "owner" ? "ownerSequence" : "listenerSequence";
    if (message.seq !== listenerAttachment[key]) {
      await this.depart(socket, attachment); close(socket, 4400); return;
    }
    listener.serializeAttachment({ ...listenerAttachment, [key]: listenerAttachment[key] + 1 });
    if (!send(target, { ...message, from: attachment.phase })) {
      if (target === owner) await this.end("owner_lost");
      else { await this.depart(listener, listenerAttachment); close(listener); }
    }
  }

  async depart(socket, attachment) {
    socket.serializeAttachment({ ...attachment, phase: "closed" });
    if (!this.state || attachment.generation !== this.state.generation) return;
    if (attachment.phase === "owner") await this.end("owner_lost");
    if (attachment.phase === "listener" && this.state.status === "active") {
      const owner = this.owner();
      if (!owner || !send(owner, { type: "listener-left", v: 1, listenerID: attachment.listenerID })) {
        await this.end("owner_lost");
      }
    }
  }

  webSocketClose(socket) {
    return this.serialize(async () => {
      const attachment = this.attachment(socket);
      if (attachment && attachment.phase !== "closed") await this.depart(socket, attachment);
      close(socket, 1000, "closed");
      await this.scheduleAlarm();
    });
  }

  webSocketError(socket) { return this.webSocketClose(socket); }
  alarm() { return this.serialize(async () => { await this.enforceDeadlines(); await this.scheduleAlarm(); }); }
}

const assets = new Map([
  ["/audio-share", "/index.html"], ["/audio-share/", "/index.html"],
  ["/audio-share/listener.js", "/listener.js"], ["/audio-share/protocol.js", "/protocol.js"],
  ["/audio-share/core.js", "/core.js"],
  ["/audio-share/crypto.js", "/crypto.js"], ["/audio-share/style.css", "/style.css"],
]);

export async function routeAudioShare(request, env) {
  const url = new URL(request.url);
  if (!url.pathname.startsWith("/v3/audio-share") && !url.pathname.startsWith("/audio-share")) return null;
  if (env.AUDIO_SHARE_ENABLED !== "true") return json("not_found", 404);
  const asset = assets.get(url.pathname);
  if (asset) {
    if (request.method !== "GET" || url.search || url.protocol !== "https:" || !env.AUDIO_SHARE_ASSETS) {
      return json("not_found", 404);
    }
    const assetURL = new URL(request.url);
    assetURL.pathname = asset;
    const response = await env.AUDIO_SHARE_ASSETS.fetch(new Request(assetURL, { method: "GET" }));
    const headers = new Headers(response.headers);
    headers.set("Cache-Control", "no-store");
    headers.set("Referrer-Policy", "no-referrer");
    headers.set("X-Content-Type-Options", "nosniff");
    headers.set("X-Robots-Tag", "noindex, nofollow, noarchive");
    headers.set("Permissions-Policy", "microphone=(), camera=(), display-capture=()");
    headers.set("Content-Security-Policy", `default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self' wss://${url.host}; media-src blob:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`);
    return new Response(response.body, { status: response.status, headers });
  }
  const match = /^\/v3\/audio-share\/([A-Za-z0-9_-]+)$/.exec(url.pathname);
  if (!match || !validShareID(match[1]) || request.method !== "GET" || url.search || url.protocol !== "https:" ||
      request.headers.get("Upgrade")?.toLowerCase() !== "websocket" ||
      request.headers.get("Sec-WebSocket-Protocol") !== AUDIO_SHARE_PROTOCOL || request.headers.has("Authorization")) {
    return json("invalid_join", 400);
  }
  const expectedOrigin = env.AUDIO_SHARE_BROWSER_ORIGIN ?? url.origin;
  const origin = request.headers.get("Origin");
  if ((origin !== null && origin !== expectedOrigin) || !env.AUDIO_SHARE) return json("invalid_join", 400);
  if (!joinableShareLocator(match[1])) return json("unavailable", 404);
  const actor = request.headers.get("CF-Connecting-IP") ?? "unknown";
  const limits = await Promise.all([
    env.JOIN_RATE_LIMITER.limit({ key: `actor:audio-share:${actor}` }),
    env.JOIN_RATE_LIMITER.limit({ key: `channel:audio-share:${match[1]}` }),
  ]);
  if (limits.some((limit) => !limit.success)) return json("rate_limited", 429);
  const stub = env.AUDIO_SHARE.get(env.AUDIO_SHARE.idFromName(`audio-share:${match[1]}`));
  return stub.fetch(new Request(`https://audio-share.internal${url.pathname}`, { headers: {
    Upgrade: "websocket", "Sec-WebSocket-Protocol": AUDIO_SHARE_PROTOCOL,
  } }));
}
