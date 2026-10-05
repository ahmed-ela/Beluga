// Test-only loopback broker. This is NOT proof of the deployed Durable Object.
import { createServer } from "node:https";
import { readFile } from "node:fs/promises";
import { randomBytes, timingSafeEqual } from "node:crypto";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";
import { AUDIO_SHARE_PROTOCOL, parseAuthentication, parseClientMessage, validShareID } from "../../public/protocol.js";
import { validRelayEpochReport } from "./relay-contract.js";

const require = createRequire(new URL("../../../../services/RendezvousWorker/package.json", import.meta.url));
const { WebSocketServer } = require("ws");
const publicRoot = fileURLToPath(new URL("../../public/", import.meta.url));
const oracleRoot = fileURLToPath(new URL("./", import.meta.url));
const equal = (a, b) => typeof a === "string" && typeof b === "string" &&
  a.length === b.length && timingSafeEqual(Buffer.from(a), Buffer.from(b));
const id = () => randomBytes(16).toString("base64url");
const diagnosticStages = new Set(["start", "socket_open", "socket_error", "socket_close", "wire", "ready", "offer",
  "candidate", "cipher_open", "cipher_seal", "worklet", "csp"]);
const diagnosticCodes = new Set(["unknown", "invalid_key_material", "invalid_role", "invalid_proof", "invalid_link_origin",
  "invalid_signal_context", "invalid_signal", "signal_closed", "invalid_link", "invalid_message", "candidate_overflow",
  "unexpected_answer", "invalid_ready", "offer_overlap", "unexpected_media", "stale_candidate", "invalid_audio_description",
  "socket_error", "socket_closed", "connect_src", "OperationError", "NotSupportedError", "InvalidAccessError",
  "InvalidStateError", "SecurityError", "SyntaxError", "AbortError", "TypeError"]);

export async function createOracleServer({ key, cert, systemSource = null, relayIce = null }) {
  if (systemSource && relayIce) throw new Error("invalid_oracle_mode");
  const phases = systemSource ? ["revoke", "expiry", "owner_loss"] : ["revoke", "expiry"];
  let config = { revision: 0, action: "idle", phase: "none" };
  let report = { epochs: [], nativeSnapshots: [], failure: null, microphoneCalls: 0, complete: false,
    broker: { upgrades: 0, registrations: 0, authentications: 0, rejections: 0, signalsOwner: 0, signalsListener: 0,
      protocolSelections: 0, protocolAccepted: 0, upgradeProtocolMatches: 0 } };
  const shares = new Map();
  const sockets = new Set();
  const timers = new Set();
  const headers = { "Cache-Control": "no-store", "Referrer-Policy": "no-referrer",
    "Content-Security-Policy": "default-src 'self'; script-src 'self'; connect-src 'self'; worker-src 'self'; media-src 'self' blob:; object-src 'none'; base-uri 'none'" };
  const sendJSON = (response, value, status = 200) => {
    response.writeHead(status, { ...headers, "Content-Type": "application/json" });
    response.end(JSON.stringify(value));
  };
  const body = async (request) => {
    const chunks = []; let size = 0;
    for await (const chunk of request) {
      size += chunk.length; if (size > 32_768) throw new Error("body_limit"); chunks.push(chunk);
    }
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  };
  const server = createServer({ key, cert }, async (request, response) => {
    try {
      const path = new URL(request.url, "https://127.0.0.1").pathname;
      if (request.url.includes("?") || request.headers.host !== `127.0.0.1:${server.address().port}`) {
        sendJSON(response, { error: "invalid_request" }, 400); return;
      }
      if (request.method === "GET" && path === "/oracle/config") { sendJSON(response, config); return; }
      if (request.method === "GET" && path === "/oracle/state") { sendJSON(response, report); return; }
      if (request.method === "POST" && path === "/oracle/native") {
        const value = await body(request);
        if (!value || Object.keys(value).sort().join(",") !== "activeListeners,phase,sources,status" ||
            !["before_revoke", "after_revoke", "after_expiry", ...(systemSource ? ["after_owner_loss"] : []), "failure_before_cleanup", "success"].includes(value.phase) ||
            !["idle", "starting", "active", "ended", "failed"].includes(value.status) ||
            !Number.isSafeInteger(value.activeListeners) || value.activeListeners < 0 || value.activeListeners > 8 ||
            !Array.isArray(value.sources) || value.sources.length > (systemSource ? 3 : 2) || report.nativeSnapshots.length >= 8 ||
            !value.sources.every((source) => systemSource
              ? source && Object.keys(source).sort().join(",") === "attachedListeners,confirmedStarts,confirmedStops,starts,stops" &&
                Object.values(source).every((number) => Number.isSafeInteger(number) && number >= 0 && number <= 8)
              : source && Object.keys(source).sort().join(",") === "attachedListeners,deliveries,starts,stops" &&
              ["starts", "stops", "deliveries", "attachedListeners"].every((key) => Number.isSafeInteger(source[key]) && source[key] >= 0) &&
              source.starts < 100 && source.stops < 100 && source.deliveries <= 100_000 && source.attachedListeners <= 8)) {
          throw new Error("invalid_native_report");
        }
        report.nativeSnapshots.push(value); sendJSON(response, { accepted: true }); return;
      }
      if (request.method === "POST" && path === "/oracle/command") {
        const command = await body(request);
        if (!command || !["join", "rejoin", "complete", ...(systemSource ? ["start-emitter", "stop-emitter", "lose-owner"] : [])].includes(command.action)) throw new Error("invalid_command");
        if (systemSource && ["start-emitter", "stop-emitter", "lose-owner"].includes(command.action)) {
          if (Object.keys(command).join(",") !== "action") throw new Error("invalid_command");
          if (command.action === "lose-owner") {
            const active = [...shares.values()].filter((share) => !share.closed);
            if (active.length !== 1 || config.phase !== "owner_loss") throw new Error("invalid_command");
            active[0].owner.terminate();
          } else if (command.action === "start-emitter") await systemSource.startEmitter();
          else await systemSource.stopEmitter();
          sendJSON(response, { accepted: true }); return;
        }
        if (command.action === "join") {
          const url = new URL(command.url);
          if (url.origin !== `https://127.0.0.1:${server.address().port}` || url.pathname !== "/audio-share" ||
              url.search || url.hash.length > 160 || !phases.includes(command.phase)) throw new Error("invalid_command");
          config = { revision: config.revision + 1, action: "join", phase: command.phase, url: url.href };
          if (systemSource) config.challenge = systemSource.challenge;
          if (relayIce) config.relay = true;
        } else if (command.action === "rejoin") {
          if (!config.url || config.phase !== "revoke") throw new Error("invalid_command");
          config = { ...config, revision: config.revision + 1, action: "rejoin" };
        } else {
          config = { revision: config.revision + 1, action: "complete", phase: "none" };
          report.complete = true;
        }
        sendJSON(response, { accepted: true }); return;
      }
      if (request.method === "POST" && path === "/oracle/report") {
        const value = await body(request);
        // A report cannot become a channel for signaling/capability/PCM logging.
        if (!value || Object.keys(value).some((k) => !["epoch", "phase", "shareID", "decoded", "closed", "topology",
          "rmsLeft", "rmsRight", "leftRatio", "rightRatio", "sampleRate", "windows", "microphoneCalls", "failure",
          "stage", "errorStage", "errorCode", "socketCloseCode", "protocolMatches", "openReadyState", "elapsedMs",
          "stopReason", "stopStage", "stopClosed", "stopReady", "timerBindingRejected", "timerBindingCode", "peerState",
          "trackMuted", "trackReadyState", "inboundAudioReports", "packetsReceived", "bytesReceived", "totalSamplesReceived",
          "concealedSamples", "audioLevel", "totalAudioEnergy", ...(systemSource ? ["challengeNonce"] : []),
          ...(relayIce ? ["relay"] : [])].includes(k)) ||
          !Number.isSafeInteger(value.epoch) || value.epoch < 1 || value.epoch > 4 ||
          !phases.includes(value.phase) || !validShareID(value.shareID) ||
          (systemSource && value.challengeNonce !== systemSource.challenge.nonce) ||
          typeof value.decoded !== "boolean" || typeof value.closed !== "boolean" || typeof value.topology !== "boolean" ||
          !["rmsLeft", "rmsRight", "leftRatio", "rightRatio", "sampleRate", "windows", "microphoneCalls"].every((k) =>
            Number.isFinite(value[k]) && value[k] >= 0 && value[k] < 1_000_000) ||
          (value.failure !== null && !["decode", "topology", "browser", "deadline", ...(relayIce ? ["relay"] : [])].includes(value.failure)) ||
          (relayIce && !validRelayEpochReport(value)) ||
          !diagnosticStages.has(value.stage) || (value.errorStage !== null && !diagnosticStages.has(value.errorStage)) ||
          (value.errorCode !== null && !diagnosticCodes.has(value.errorCode)) ||
          !Number.isSafeInteger(value.socketCloseCode) || value.socketCloseCode < 0 || value.socketCloseCode > 4_999 ||
          (value.protocolMatches !== null && typeof value.protocolMatches !== "boolean") ||
          !Number.isSafeInteger(value.openReadyState) || value.openReadyState < 0 || value.openReadyState > 3 ||
          !Number.isSafeInteger(value.elapsedMs) || value.elapsedMs < 0 || value.elapsedMs > 90_000 ||
          (value.stopReason !== null && !["ended", "unavailable", "expired", "unknown"].includes(value.stopReason)) ||
          (value.stopStage !== null && !diagnosticStages.has(value.stopStage)) ||
          (value.stopClosed !== null && typeof value.stopClosed !== "boolean") ||
          (value.stopReady !== null && typeof value.stopReady !== "boolean") ||
          typeof value.timerBindingRejected !== "boolean" ||
          (value.timerBindingCode !== null && !["TypeError", "unknown"].includes(value.timerBindingCode)) ||
          !["new", "connecting", "connected", "disconnected", "failed", "closed"].includes(value.peerState) ||
          (value.trackMuted !== null && typeof value.trackMuted !== "boolean") || !["none", "live", "ended"].includes(value.trackReadyState) ||
          !Number.isSafeInteger(value.inboundAudioReports) || value.inboundAudioReports < 0 || value.inboundAudioReports > 8 ||
          !["packetsReceived", "bytesReceived", "totalSamplesReceived", "concealedSamples", "audioLevel", "totalAudioEnergy"].every((key) =>
            value[key] === null || (Number.isFinite(value[key]) && value[key] >= 0 && value[key] <= 9_007_199_254_740_991))) throw new Error("invalid_report");
        const index = report.epochs.findIndex((entry) => entry.epoch === value.epoch);
        if (index < 0) report.epochs.push(value); else report.epochs[index] = value;
        report.microphoneCalls = Math.max(report.microphoneCalls, value.microphoneCalls);
        if (value.failure) report.failure = value.failure;
        sendJSON(response, { accepted: true }); return;
      }
      const files = new Map([
        ["/oracle", [oracleRoot, "index.html", "text/html"]],
        ["/oracle/browser-oracle.js", [oracleRoot, "browser-oracle.js", "text/javascript"]],
        ["/oracle/waveform-worklet.js", [oracleRoot, "waveform-worklet.js", "text/javascript"]],
        ["/oracle/relay-contract.js", [oracleRoot, "relay-contract.js", "text/javascript"]],
        ...["core.js", "crypto.js", "protocol.js"].map((name) => [`/public/${name}`, [publicRoot, name, "text/javascript"]]),
      ]);
      if (request.method !== "GET" || !files.has(path)) { sendJSON(response, { error: "not_found" }, 404); return; }
      const [base, name, type] = files.get(path);
      response.writeHead(200, { ...headers, "Content-Type": type }); response.end(await readFile(resolve(base, name)));
    } catch {
      if (relayIce && request.url === "/oracle/report") report.failure = "relay";
      sendJSON(response, { error: "invalid_request" }, 400);
    }
  });
  server.requestTimeout = 5_000; server.headersTimeout = 5_000;
  const wss = new WebSocketServer({ noServer: true, maxPayload: 90_000,
    handleProtocols: (protocols) => {
      report.broker.protocolSelections++;
      const accepted = protocols.size === 1 && protocols.has(AUDIO_SHARE_PROTOCOL);
      if (accepted) report.broker.protocolAccepted++;
      return accepted ? AUDIO_SHARE_PROTOCOL : false;
    } });
  const send = (socket, message) => { if (socket.readyState === 1) socket.send(JSON.stringify(message)); };
  const end = (share, reason = "owner_lost") => {
    if (share.closed) return;
    share.closed = true; clearTimeout(share.timer); timers.delete(share.timer);
    for (const socket of [share.owner, ...share.listeners.values()]) {
      send(socket, { type: "ended", v: 1, reason }); socket.close(1000, "ended");
    }
    share.listeners.clear(); share.listenerProof = null;
  };
  server.on("upgrade", (request, socket, head) => {
    const match = /^\/v3\/audio-share\/([A-Za-z0-9_-]{22})$/.exec(request.url);
    if (!match || !validShareID(match[1]) || sockets.size >= 12 ||
        request.headers.host !== `127.0.0.1:${server.address().port}`) { socket.destroy(); return; }
    if (request.headers["sec-websocket-protocol"] === AUDIO_SHARE_PROTOCOL) report.broker.upgradeProtocolMatches++;
    wss.handleUpgrade(request, socket, head, (websocket) => {
      report.broker.upgrades++;
      sockets.add(websocket);
      let role = null, share = null, listenerID = null, nextSequence = 0;
      const timeout = setTimeout(() => websocket.close(1008, "authentication"), 5_000); timers.add(timeout);
      websocket.on("message", (bytes, binary) => {
        try {
          if (binary || bytes.length > 90_000) throw new Error();
          const wire = bytes.toString("utf8");
          if (!role) {
            const authentication = parseAuthentication(wire);
            if (!authentication) throw new Error();
            if (authentication.type === "register") {
              if (shares.has(match[1]) || authentication.maxListeners !== 8) throw new Error();
              const now = Date.now();
              share = { id: match[1], generation: id(), owner: websocket, listenerProof: authentication.listenerProof,
                expiresAt: now + authentication.ttlSeconds * 1_000, listeners: new Map(), closed: false };
              shares.set(share.id, share); role = "owner";
              report.broker.registrations++;
              share.timer = setTimeout(() => end(share, "expired"), share.expiresAt - now); timers.add(share.timer);
              send(websocket, { type: "registered", v: 1, shareID: share.id, generation: share.generation,
                expiresAt: share.expiresAt, serverTime: now, leaseExpiresAt: Math.min(now + 15_000, share.expiresAt), maxListeners: 8 });
            } else {
              share = shares.get(match[1]);
              if (!share || share.closed || Date.now() >= share.expiresAt || share.listeners.size >= 8 ||
                  !equal(authentication.proof, share.listenerProof)) throw new Error();
              role = "listener"; listenerID = id(); share.listeners.set(listenerID, websocket);
              report.broker.authentications++;
              if (relayIce && Date.now() + 15_000 >= relayIce.expiresAt) throw new Error();
              const ready = { type: "listener-ready", v: 1, shareID: share.id, generation: share.generation,
                listenerID, expiresAt: share.expiresAt, serverTime: Date.now(), iceServers: relayIce?.iceServers ?? [] };
              send(share.owner, { ...ready, role: "owner" }); send(websocket, { ...ready, role: "listener" });
            }
            clearTimeout(timeout); timers.delete(timeout); return;
          }
          if (!share || share.closed || Date.now() >= share.expiresAt) throw new Error();
          const message = parseClientMessage(wire); if (!message) throw new Error();
          if (message.type === "probe" && role === "owner") {
            const now = Date.now(); send(websocket, { type: "probe-ack", v: 1, nonce: message.nonce,
              serverTime: now, leaseExpiresAt: Math.min(now + 15_000, share.expiresAt) }); return;
          }
          if (message.type === "revoke" && role === "owner") { end(share, "revoked"); return; }
          if (message.type === "retire-listener" && role === "owner") {
            share.listeners.get(message.listenerID)?.close(1000, "retired"); return;
          }
          if (message.type !== "signal") throw new Error();
          if (role === "listener") {
            if (message.listenerID !== listenerID || message.seq !== nextSequence++) throw new Error();
            report.broker.signalsListener++;
            send(share.owner, { ...message, from: "listener" });
          } else {
            const target = share.listeners.get(message.listenerID); if (!target) return;
            report.broker.signalsOwner++;
            send(target, { ...message, from: "owner" });
          }
        } catch { report.broker.rejections++; websocket.close(1008, "invalid"); }
      });
      websocket.on("error", () => {});
      websocket.on("close", () => {
        clearTimeout(timeout); timers.delete(timeout); sockets.delete(websocket);
        if (role === "owner" && share) end(share);
        else if (share && listenerID && share.listeners.delete(listenerID) && !share.closed) {
          send(share.owner, { type: "listener-left", v: 1, listenerID });
        }
      });
    });
  });
  await new Promise((resolve, reject) => { server.once("error", reject); server.listen(0, "127.0.0.1", resolve); });
  return { origin: `https://127.0.0.1:${server.address().port}`, state: () => structuredClone(report),
    async close() {
      config = { revision: config.revision + 1, action: "complete", phase: "none" };
      for (const timer of timers) clearTimeout(timer);
      for (const share of shares.values()) end(share);
      for (const socket of sockets) socket.terminate();
      shares.clear();
      if (relayIce) {
        for (const server of relayIce.iceServers) { delete server.username; delete server.credential; }
        relayIce.iceServers.length = 0; relayIce = null;
      }
      const closed = new Promise((resolve) => server.close(resolve));
      server.closeAllConnections(); await closed; wss.close();
    } };
}
