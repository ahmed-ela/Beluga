import test from "node:test";
import assert from "node:assert/strict";
import { AudioShareListener, readAndClearLink } from "../public/core.js";
import { createSignalCipher, makeListenerURL } from "../public/crypto.js";
import { encodeBase64URL, parseLinkFragment, preferStereoReception } from "../public/protocol.js";

const id = (value) => encodeBase64URL(new Uint8Array(16).fill(value));
const root = new Uint8Array(32).fill(7);
const sdp = (direction) => `v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=mid:0\r\na=ice-ufrag:fixtureUfrag\r\na=${direction}\r\na=rtpmap:111 opus/48000/2\r\n`;
class Socket extends EventTarget {
  static latest;
  constructor(url, protocol) { super(); this.url = url; this.protocol = protocol; this.sent = []; this.readyState = 1; Socket.latest = this; }
  send(value) { this.sent.push(JSON.parse(value)); }
  close() { this.readyState = 3; }
  open() { this.dispatchEvent(new Event("open")); }
  message(value) { const event = new Event("message"); event.data = JSON.stringify(value); this.dispatchEvent(event); }
}
class Peer extends EventTarget {
  static latest;
  constructor(config) {
    super(); this.config = config; this.closed = false; this.received = [];
    this.track = { kind: "audio", stop: () => { this.track.stopped = true; } };
    this.transceiver = { receiver: { track: this.track }, sender: { track: null }, direction: "recvonly" };
    Peer.latest = this;
  }
  async setRemoteDescription(value) { this.remote = value; }
  getTransceivers() { return [this.transceiver]; }
  async createAnswer() { return { type: "answer", sdp: sdp("recvonly") }; }
  async setLocalDescription(value) { this.local = value; }
  async addIceCandidate(value) { this.received.push(value); }
  getReceivers() { return [this.transceiver.receiver]; }
  close() { this.closed = true; }
}

async function fixture() {
  const link = parseLinkFragment(new URL(makeListenerURL("https://share.example", id(1), root)).hash);
  const callbacks = { states: [], stopCount: 0, status(value) { this.states.push(value); }, track() {}, stop() { this.stopCount++; } };
  const timers = new Map();
  let nextTimer = 0;
  let now = 100;
  const listener = new AudioShareListener(link, "https://share.example", callbacks, {
    WebSocket: Socket, RTCPeerConnection: Peer, now: () => now,
    setTimeout: (callback, delay) => { const token = nextTimer++; timers.set(token, { callback, delay }); return token; },
    clearTimeout: (token) => timers.delete(token),
  });
  await listener.start();
  const socket = Socket.latest;
  socket.open();
  const ready = { type: "listener-ready", v: 1, role: "listener", shareID: id(1), generation: id(2), listenerID: id(3),
    expiresAt: 1_800_000_030_000, serverTime: 1_800_000_000_000, iceServers: [{ urls: ["stun:stun.example:3478"] }] };
  socket.message(ready);
  await listener.inbound;
  const cipher = await createSignalCipher(root, { shareID: ready.shareID, generation: ready.generation,
    listenerID: ready.listenerID, expiresAt: ready.expiresAt }, "owner");
  return { listener, socket, ready, cipher, peer: Peer.latest, callbacks, timers, advance: (milliseconds) => { now += milliseconds; } };
}

test("fragment is cleared even on malformed links before any connection is constructed", () => {
  const url = new URL(makeListenerURL("https://share.example", id(1), root));
  const calls = [];
  const history = { replaceState: (...arguments_) => calls.push(arguments_) };
  assert.equal(readAndClearLink(url, history).shareID, id(1));
  assert.deepEqual(calls, [[null, "", "/audio-share"]]);
  url.search = "?leak=forbidden";
  assert.equal(readAndClearLink(url, history), null);
  url.search = "";
  url.hash = "#bad";
  assert.equal(readAndClearLink(url, history), null);
  assert.equal(calls.length, 3);
});

test("query rejection survives real history replacement mutating the current location", () => {
  const url = new URL(makeListenerURL("https://share.example", id(1), root));
  url.search = "?unexpected=1";
  const history = { replaceState(_state, _title, path) { url.href = new URL(path, url.origin).href; } };
  assert.equal(readAndClearLink(url, history), null);
  assert.equal(url.search, "");
  assert.equal(url.hash, "");
  url.hash = new URL(makeListenerURL("https://share.example", id(1), root)).hash;
  assert.equal(readAndClearLink(url, history).shareID, id(1));
  assert.equal(url.hash, "");
});

test("default timers preserve the Window receiver when called through dependencies", () => {
  const originalSetTimeout = globalThis.setTimeout;
  const originalClearTimeout = globalThis.clearTimeout;
  const calls = [];
  try {
    globalThis.setTimeout = function(callback, milliseconds) {
      assert.equal(this, globalThis, "browser Window timer receiver must be preserved");
      assert.equal(typeof callback, "function");
      calls.push(["set", milliseconds]);
      return 73;
    };
    globalThis.clearTimeout = function(handle) {
      assert.equal(this, globalThis, "browser Window cancellation receiver must be preserved");
      calls.push(["clear", handle]);
    };
    const link = parseLinkFragment(new URL(makeListenerURL("https://share.example", id(1), root)).hash);
    const listener = new AudioShareListener(link, "https://share.example", {});
    const handle = listener.dependencies.setTimeout(() => {}, 5_000);
    listener.dependencies.clearTimeout(handle);
    assert.deepEqual(calls, [["set", 5_000], ["clear", 73]]);
  } finally {
    globalThis.setTimeout = originalSetTimeout;
    globalThis.clearTimeout = originalClearTimeout;
  }
});

test("no connection before explicit start; proof is in first frame, never URL/subprotocol", async () => {
  const { listener, socket, callbacks } = await fixture();
  assert.equal(socket.url, `wss://share.example/v3/audio-share/${id(1)}`);
  assert.equal(socket.protocol, "beluga.audio-share.v1");
  assert.equal(socket.sent[0].type, "authenticate");
  assert.equal(new URL(socket.url).search, "");
  assert.equal(socket.sent.length, 1);
  assert.equal(listener.link.secret.every((byte) => byte === 0), true);
  listener.stop();
  assert.equal(callbacks.stopCount, 1);
});

test("encrypted offer yields a receive-only answer, no microphone or data channel", async () => {
  const { listener, socket, cipher, peer } = await fixture();
  socket.message({ ...await cipher.seal({ kind: "offer", sdp: sdp("sendonly") }), from: "owner" });
  await listener.inbound;
  await listener.outbound;
  assert.equal(peer.remote.type, "offer");
  assert.equal(peer.transceiver.direction, "recvonly");
  assert.equal(peer.transceiver.sender.track, null);
  assert.equal(socket.sent[1].type, "signal");
  const stereoAnswer = sdp("recvonly") + "a=fmtp:111 stereo=1\r\n";
  assert.deepEqual(await cipher.open({ ...socket.sent[1], from: "listener" }), { kind: "answer", sdp: stereoAnswer });
  assert.deepEqual(peer.local, { type: "answer", sdp: stereoAnswer });
  peer.dispatchEvent(new Event("datachannel"));
  assert.equal(peer.closed, true);
});

test("stereo preference preserves negotiated payload and unrelated Opus parameters", () => {
  const original = sdp("recvonly").replaceAll("111", "109") + "a=fmtp:109 minptime=10;useinbandfec=1;stereo=0\r\n";
  const result = preferStereoReception(original);
  assert.equal(result, original.replace("stereo=0", "stereo=1"));
  assert.equal(preferStereoReception(result), result);
  assert.equal(preferStereoReception(original.replace(";stereo=0", "")), result);
});

test("stereo preference rejects ambiguous codec/parameter maps instead of guessing", () => {
  for (const malformed of [
    sdp("recvonly") + "a=fmtp:111 stereo=0;stereo=1\r\n",
    sdp("recvonly") + "a=fmtp:111 stereo=0;Stereo=1\r\n",
    sdp("recvonly") + "a=fmtp:111 stereo=0\r\na=fmtp:111 stereo=1\r\n",
    sdp("recvonly") + "a=rtpmap:112 opus/48000/2\r\n",
    sdp("recvonly").replace("SAVPF 111", "SAVPF 112"),
    sdp("recvonly").replace("SAVPF 111", "SAVPF 111 112"),
    sdp("sendonly"),
  ]) assert.throws(() => preferStereoReception(malformed), /invalid_audio_description/);
});

test("expiry, signaling loss, and ended state synchronously stop tracks and peer", async () => {
  for (const boundary of ["expiry", "close", "ended"]) {
    const { listener, socket, peer, callbacks, timers, advance } = await fixture();
    assert.equal(listener.remainingSeconds(), 30);
    advance(2_001);
    assert.equal(listener.remainingSeconds(), 28);
    if (boundary === "expiry") [...timers.values()].find((timer) => timer.delay === 30_000).callback();
    else if (boundary === "close") socket.dispatchEvent(new Event("close"));
    else { socket.message({ type: "ended", v: 1, reason: "revoked" }); await listener.inbound; }
    assert.equal(listener.closed, true);
    assert.equal(peer.closed, true);
    assert.equal(peer.track.stopped, true);
    assert.equal(socket.readyState, 3);
    assert.equal(callbacks.stopCount, 1);
    assert.equal(timers.size, 0);
  }
});

test("connected transport is not labeled live until the media element reports playback", async () => {
  const { listener, peer, callbacks } = await fixture();
  peer.connectionState = "connected";
  peer.dispatchEvent(new Event("connectionstatechange"));
  assert.equal(callbacks.states.at(-1), "waiting");
  listener.setPlaybackActive(true);
  assert.equal(callbacks.states.at(-1), "listening");
  listener.setPlaybackActive(false);
  assert.equal(callbacks.states.at(-1), "waiting");
  listener.stop();
  listener.setPlaybackActive(true);
  assert.equal(callbacks.states.at(-1), "ended");
  assert.equal(listener.playbackActive, false);
});

test("video offers and superseded ICE fail closed instead of creating a sending track", async () => {
  for (const payload of [
    { kind: "offer", sdp: sdp("sendonly") + "m=video 9 UDP/TLS/RTP/SAVPF 96\r\n" },
    { kind: "ice", candidate: { candidate: "candidate:fixture 1 udp 1 192.0.2.1 1234 typ host",
      sdpMid: "0", sdpMLineIndex: 0, usernameFragment: "superseded" } },
  ]) {
    const { listener, socket, cipher, peer } = await fixture();
    if (payload.kind === "ice") {
      socket.message({ ...await cipher.seal({ kind: "offer", sdp: sdp("sendonly") }), from: "owner" });
      await listener.inbound;
    }
    socket.message({ ...await cipher.seal(payload), from: "owner" });
    await listener.inbound;
    assert.equal(listener.closed, true);
    assert.equal(peer.closed, true);
  }
});
