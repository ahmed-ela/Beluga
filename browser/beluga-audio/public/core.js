import {
  AUDIO_SHARE_LIMITS as LIMITS, AUDIO_SHARE_PROTOCOL, candidateMatchesDescription, exactKeys,
  inspectAudioOnlySDP, parseLinkFragment, preferStereoReception, validShareID, utf8Length,
} from "./protocol.js";
import { createSignalCipher, deriveAdmission } from "./crypto.js";

// Bound pending work before it enters an asynchronous crypto/native-operation chain.
// Signaling is metadata only; a stalled peer must not retain an unbounded message queue.
const MAX_PENDING_MESSAGES = 64;
const MAX_PENDING_BYTES = 524_288;

export function readAndClearLink(location, history) {
  const link = parseLinkFragment(location.hash);
  const allowedLocation = location.protocol === "https:" && !location.search;
  // The capability is never put in a request URL, referrer, analytics, or local storage.
  history.replaceState(null, "", location.pathname);
  if (!allowedLocation || !link) {
    link?.secret.fill(0);
    return null;
  }
  return link;
}

const validIceServers = (servers) => Array.isArray(servers) && servers.length <= 16 && servers.every((server) => {
  if (server === null || typeof server !== "object" || Array.isArray(server)) return false;
  const keys = Object.keys(server);
  if (!keys.every((key) => ["urls", "username", "credential", "credentialType"].includes(key))) return false;
  const urls = typeof server.urls === "string" ? [server.urls] : server.urls;
  return Array.isArray(urls) && urls.length >= 1 && urls.length <= 8 && urls.every((url) =>
    typeof url === "string" && url.length <= 2_048 && /^(stun|stuns|turn|turns):[^\s@]+$/.test(url)) &&
    (server.username === undefined || (typeof server.username === "string" && server.username.length <= 1_024)) &&
    (server.credential === undefined || (typeof server.credential === "string" && server.credential.length <= 1_024)) &&
    (server.credentialType === undefined || server.credentialType === "password");
});

export class AudioShareListener {
  constructor(link, origin, callbacks, dependencies = {}) {
    const url = new URL(origin);
    if (url.protocol !== "https:" || url.username || url.password || url.search || url.hash ||
        !validShareID(link?.shareID) || !(link.secret instanceof Uint8Array) || link.secret.length !== 32) {
      throw new Error("invalid_link");
    }
    this.link = link;
    this.origin = url.origin;
    this.callbacks = callbacks;
    this.dependencies = {
      WebSocket: globalThis.WebSocket, RTCPeerConnection: globalThis.RTCPeerConnection,
      now: () => performance.now(),
      // Window timers reject a plain dependency-object receiver in real browsers.
      // Keep the platform receiver explicit; injected test clocks still override these.
      setTimeout: (callback, milliseconds) => globalThis.setTimeout(callback, milliseconds),
      clearTimeout: (handle) => globalThis.clearTimeout(handle), ...dependencies,
    };
    this.socket = null;
    this.peer = null;
    this.cipher = null;
    this.ready = false;
    this.closed = false;
    this.started = false;
    this.playbackActive = false;
    this.localDescription = null;
    this.remoteDescription = null;
    this.candidates = [];
    this.inbound = Promise.resolve();
    this.outbound = Promise.resolve();
    this.pendingInbound = 0;
    this.pendingInboundBytes = 0;
    this.pendingOutbound = 0;
    this.pendingOutboundBytes = 0;
    this.deadline = 0;
    this.deadlineTimer = null;
    this.authTimer = null;
  }

  async start() {
    if (this.started || this.closed) return;
    this.started = true;
    this.callbacks.status("connecting");
    try {
      let proof = await deriveAdmission(this.link.secret, "listener", this.link.shareID);
      if (this.closed) return;
      const url = new URL(`/v3/audio-share/${this.link.shareID}`, this.origin);
      url.protocol = "wss:";
      const socket = new this.dependencies.WebSocket(url.href, AUDIO_SHARE_PROTOCOL);
      this.socket = socket;
      this.authTimer = this.dependencies.setTimeout(() => this.stop("unavailable"), LIMITS.authenticationMs);
      socket.addEventListener("open", () => {
        if (this.closed || socket.protocol !== AUDIO_SHARE_PROTOCOL) { this.stop("unavailable"); return; }
        socket.send(JSON.stringify({ type: "authenticate", v: 1, proof }));
        proof = null;
      });
      socket.addEventListener("message", (event) => {
        this.queueWire(event.data);
      });
      socket.addEventListener("close", () => this.stop("ended"));
      socket.addEventListener("error", () => this.stop("unavailable"));
    } catch { this.stop("unavailable"); }
  }

  queueWire(wire) {
    if (this.closed) return;
    if (typeof wire !== "string" || wire.length > LIMITS.maxWireBytes) { this.stop("unavailable"); return; }
    const size = utf8Length(wire);
    if (size > LIMITS.maxWireBytes || this.pendingInbound >= MAX_PENDING_MESSAGES ||
        this.pendingInboundBytes + size > MAX_PENDING_BYTES) { this.stop("unavailable"); return; }
    this.pendingInbound++;
    this.pendingInboundBytes += size;
    this.inbound = this.inbound.then(() => this.handleWire(wire))
      .catch(() => this.stop("unavailable"))
      .finally(() => { this.pendingInbound--; this.pendingInboundBytes -= size; });
  }

  async handleWire(wire) {
    if (this.closed) return;
    if (typeof wire !== "string" || utf8Length(wire) > LIMITS.maxWireBytes) throw new Error("invalid_message");
    const message = JSON.parse(wire);
    if (message?.v !== 1) throw new Error("invalid_message");
    if (message.type === "ended" || message.type === "error") { this.stop("ended"); return; }
    if (!this.ready) { await this.acceptReady(message); return; }
    if (this.dependencies.now() >= this.deadline) { this.stop("expired"); return; }
    const payload = await this.cipher.open(message);
    if (this.closed) return;
    if (payload.kind === "offer") await this.acceptOffer(payload.sdp);
    else if (payload.kind === "ice") {
      if (!this.remoteDescription) {
        if (this.candidates.length >= LIMITS.maxBufferedCandidates) throw new Error("candidate_overflow");
        this.candidates.push(payload.candidate);
      } else await this.acceptCandidate(payload.candidate);
    } else throw new Error("unexpected_answer");
  }

  async acceptReady(message) {
    if (!exactKeys(message, ["type", "v", "role", "shareID", "generation", "listenerID", "expiresAt",
      "serverTime", "iceServers"]) || message.type !== "listener-ready" || message.role !== "listener" ||
      message.shareID !== this.link.shareID || !validShareID(message.generation) || !validShareID(message.listenerID) ||
      !Number.isSafeInteger(message.expiresAt) || !Number.isSafeInteger(message.serverTime) ||
      message.serverTime <= 0 || message.expiresAt <= message.serverTime ||
      message.expiresAt - message.serverTime > LIMITS.maxTTLSeconds * 1_000 || !validIceServers(message.iceServers)) {
      throw new Error("invalid_ready");
    }
    this.dependencies.clearTimeout(this.authTimer);
    this.deadline = this.dependencies.now() + message.expiresAt - message.serverTime;
    this.deadlineTimer = this.dependencies.setTimeout(() => this.stop("expired"), message.expiresAt - message.serverTime);
    this.cipher = await createSignalCipher(this.link.secret, {
      shareID: message.shareID, generation: message.generation,
      listenerID: message.listenerID, expiresAt: message.expiresAt,
    }, "listener");
    this.link.secret.fill(0);
    if (this.closed) { this.cipher.close(); return; }
    const peer = new this.dependencies.RTCPeerConnection({ iceServers: message.iceServers,
      bundlePolicy: "max-bundle", rtcpMuxPolicy: "require" });
    this.peer = peer;
    peer.addEventListener("datachannel", () => this.stop("unavailable"));
    peer.addEventListener("track", (event) => {
      if (this.closed || event.track.kind !== "audio") { event.track.stop(); this.stop("unavailable"); return; }
      this.callbacks.track(event.track);
    });
    peer.addEventListener("connectionstatechange", () => {
      if (["failed", "closed", "disconnected"].includes(peer.connectionState)) this.stop("ended");
      else if (peer.connectionState === "connected") {
        this.callbacks.status(this.playbackActive ? "listening" : "waiting");
      }
    });
    peer.addEventListener("icecandidate", (event) => {
      if (this.closed || !event.candidate) return;
      const candidate = event.candidate.toJSON();
      const bounded = { candidate: candidate.candidate, sdpMid: candidate.sdpMid,
        sdpMLineIndex: candidate.sdpMLineIndex, usernameFragment: candidate.usernameFragment };
      if (!this.localDescription || !candidateMatchesDescription(bounded, this.localDescription)) {
        this.stop("unavailable"); return;
      }
      this.sendPayload({ kind: "ice", candidate: bounded });
    });
    this.ready = true;
    this.callbacks.status("waiting");
  }

  async acceptOffer(sdp) {
    if (this.remoteDescription) throw new Error("offer_overlap");
    this.remoteDescription = inspectAudioOnlySDP(sdp, "sendonly");
    await this.peer.setRemoteDescription({ type: "offer", sdp });
    if (this.closed) return;
    const transceivers = this.peer.getTransceivers();
    if (transceivers.length !== 1 || transceivers[0].receiver.track.kind !== "audio" ||
        transceivers[0].sender.track !== null) throw new Error("unexpected_media");
    transceivers[0].direction = "recvonly";
    const createdAnswer = await this.peer.createAnswer();
    const answer = { type: "answer", sdp: preferStereoReception(createdAnswer.sdp) };
    this.localDescription = inspectAudioOnlySDP(answer.sdp, "recvonly");
    // Queue the answer before setLocalDescription can dispatch the first trickled candidate.
    this.sendPayload({ kind: "answer", sdp: answer.sdp });
    await this.peer.setLocalDescription(answer);
    for (const candidate of this.candidates.splice(0)) await this.acceptCandidate(candidate);
  }

  async acceptCandidate(candidate) {
    if (!candidateMatchesDescription(candidate, this.remoteDescription)) throw new Error("stale_candidate");
    await this.peer.addIceCandidate(candidate);
  }

  sendPayload(payload) {
    if (this.closed) return;
    let size;
    try { size = utf8Length(JSON.stringify(payload)); } catch { this.stop("unavailable"); return; }
    if (size > LIMITS.maxPlaintextBytes || this.pendingOutbound >= MAX_PENDING_MESSAGES ||
        this.pendingOutboundBytes + size > MAX_PENDING_BYTES) { this.stop("unavailable"); return; }
    this.pendingOutbound++;
    this.pendingOutboundBytes += size;
    this.outbound = this.outbound.then(async () => {
      if (this.closed || this.dependencies.now() >= this.deadline) { this.stop("expired"); return; }
      const message = await this.cipher.seal(payload);
      if (this.closed || this.socket.readyState !== 1) { this.stop("ended"); return; }
      const wire = JSON.stringify(message);
      if ((this.socket.bufferedAmount ?? 0) + utf8Length(wire) > MAX_PENDING_BYTES) {
        this.stop("unavailable"); return;
      }
      this.socket.send(wire);
    }).catch(() => this.stop("unavailable"))
      .finally(() => { this.pendingOutbound--; this.pendingOutboundBytes -= size; });
  }

  remainingSeconds() { return this.closed || !this.ready ? null : Math.max(0, Math.ceil((this.deadline - this.dependencies.now()) / 1_000)); }

  // Called by the actual media element, not by peer negotiation. A connected transport
  // alone says nothing about decoded playback or browser autoplay permission.
  setPlaybackActive(active) {
    if (this.closed || !this.ready) return;
    if (this.dependencies.now() >= this.deadline) { this.stop("expired"); return; }
    this.playbackActive = active === true;
    this.callbacks.status(this.playbackActive && this.peer?.connectionState === "connected" ? "listening" : "waiting");
  }

  stop(reason = "ended") {
    if (this.closed) return;
    this.closed = true;
    this.playbackActive = false;
    this.dependencies.clearTimeout(this.authTimer);
    this.dependencies.clearTimeout(this.deadlineTimer);
    this.candidates.length = 0;
    this.link.secret.fill(0);
    this.cipher?.close();
    this.peer?.getReceivers().forEach((receiver) => receiver.track?.stop());
    this.peer?.close();
    try { this.socket?.close(1000, "closed"); } catch { /* already closed */ }
    this.callbacks.stop();
    this.callbacks.status(reason);
  }
}
