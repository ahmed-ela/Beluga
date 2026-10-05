import { AudioShareListener, readAndClearLink } from "/public/core.js";
import { AUDIO_SHARE_PROTOCOL } from "/public/protocol.js";
import { createRelayProof, failRelayEpoch } from "/oracle/relay-contract.js";

let revision = 0, epoch = 0, client = null, record = null, context = null, node = null, source = null, player = null;
let microphoneCalls = 0;
const starts = new WeakMap();
const errorCodes = new Set(["unknown", "invalid_key_material", "invalid_role", "invalid_proof", "invalid_link_origin",
  "invalid_signal_context", "invalid_signal", "signal_closed", "invalid_link", "invalid_message", "candidate_overflow",
  "unexpected_answer", "invalid_ready", "offer_overlap", "unexpected_media", "stale_candidate", "invalid_audio_description",
  "socket_error", "socket_closed", "connect_src", "OperationError", "NotSupportedError", "InvalidAccessError",
  "InvalidStateError", "SecurityError", "SyntaxError", "AbortError", "TypeError"]);
function diagnostic(currentRecord, stage, error = null) {
  if (record !== currentRecord) return;
  currentRecord.stage = stage;
  currentRecord.elapsedMs = Math.min(90_000, Math.max(0, Math.round(performance.now() - starts.get(currentRecord))));
  if (error && currentRecord.errorCode === null) {
    currentRecord.errorStage = stage;
    // Never serialize exception payloads. Only fixed product codes/DOM exception names.
    currentRecord.errorCode = errorCodes.has(error.message) ? error.message : errorCodes.has(error.name) ? error.name : "unknown";
  }
  report();
}
function probeOriginalWindowTimerReceiver() {
  let handle;
  try {
    // Exactly the plain-object receiver used by the default listener dependency;
    // this independent no-op probe does NOT replace/bind the product's timers.
    const receiver = { setTimeout: globalThis.setTimeout };
    handle = receiver.setTimeout(() => {}, 0);
    return { timerBindingRejected: false, timerBindingCode: null };
  } catch (error) {
    return { timerBindingRejected: true, timerBindingCode: error.name === "TypeError" ? "TypeError" : "unknown" };
  } finally { if (handle !== undefined) globalThis.clearTimeout(handle); }
}
class OracleListener extends AudioShareListener {
  async observe(stage, operation) {
    this.diagnose(stage);
    try { return await operation(); } catch (error) { this.diagnose(stage, error); throw error; }
  }
  async handleWire(wire) { return this.observe("wire", () => super.handleWire(wire)); }
  async acceptReady(message) {
    return this.observe("ready", async () => {
      await super.acceptReady(message);
      const cipher = this.cipher;
      if (cipher) this.cipher = {
        open: (message) => this.observe("cipher_open", () => cipher.open(message)),
        seal: (payload) => this.observe("cipher_seal", () => cipher.seal(payload)), close: () => cipher.close(),
      };
    });
  }
  async acceptOffer(sdp) { return this.observe("offer", () => super.acceptOffer(sdp)); }
  async acceptCandidate(candidate) { return this.observe("candidate", () => super.acceptCandidate(candidate)); }
  stop(reason = "ended") { this.diagnoseStop?.(reason, this.ready, this.closed); super.stop(reason); }
}
globalThis.addEventListener("securitypolicyviolation", (event) => {
  if (record && event.effectiveDirective === "connect-src") diagnostic(record, "csp", { message: "connect_src" });
});
// Do not fake successful permission: an accidental capture request is counted and rejected.
if (navigator.mediaDevices) navigator.mediaDevices.getUserMedia = async () => { microphoneCalls++; throw new Error("microphone_forbidden"); };
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
let reportQueue = Promise.resolve();
async function sampleStats(currentClient, currentRecord) {
  if (record !== currentRecord || currentRecord.closed || currentClient.closed || currentClient.oracleStatsPending) return;
  currentClient.oracleStatsPending = true;
  try {
    const stats = await currentClient.peer?.getStats();
    if (record !== currentRecord || currentRecord.closed || currentClient.closed) return;
    currentRecord.peerState = currentClient.peer?.connectionState ?? "new";
    currentRecord.trackMuted = currentClient.oracleTrack?.muted ?? null;
    currentRecord.trackReadyState = currentClient.oracleTrack?.readyState ?? "none";
    const inbound = [...(stats?.values() ?? [])].filter((entry) => entry.type === "inbound-rtp" &&
      (entry.kind === "audio" || entry.mediaType === "audio"));
    currentRecord.inboundAudioReports = Math.min(8, inbound.length);
    const audio = inbound.length === 1 ? inbound[0] : null;
    for (const key of ["packetsReceived", "bytesReceived", "totalSamplesReceived", "concealedSamples", "audioLevel", "totalAudioEnergy"]) {
      currentRecord[key] = Number.isFinite(audio?.[key]) && audio[key] >= 0 && audio[key] <= 9_007_199_254_740_991 ? audio[key] : null;
    }
    if (currentClient.oracleRelay) {
      currentRecord.relay = currentClient.oracleRelay.observe(stats,
        performance.timeOrigin + performance.now(), currentClient.oracleWaveformGood);
      if (currentRecord.relay.status === "failed") {
        failRelayEpoch(currentRecord, currentClient.oracleRelay); currentClient.stop("unavailable");
      }
      else if (currentRecord.relay.status === "verified") {
        currentRecord.decoded = true; currentClient.setPlaybackActive(true);
      }
    }
    report();
  } catch {
    if (currentClient.oracleRelay && record === currentRecord && !currentRecord.closed && !currentClient.closed) {
      failRelayEpoch(currentRecord, currentClient.oracleRelay);
      currentClient.stop("unavailable"); report();
    }
    // Direct-mode statistics remain optional diagnostics.
  }
  finally { currentClient.oracleStatsPending = false; }
}
function report() {
  if (!record) return;
  const snapshot = { ...record, microphoneCalls };
  reportQueue = reportQueue.then(() => fetch("/oracle/report", { method: "POST",
    headers: { "Content-Type": "application/json" }, body: JSON.stringify(snapshot), cache: "no-store" }))
    .then((response) => { if (!response.ok) throw new Error(); }).catch(() => {});
}
function topology(peer) {
  const transceivers = peer?.getTransceivers() ?? [];
  return transceivers.length === 1 && transceivers[0].direction === "recvonly" &&
    transceivers[0].currentDirection === "recvonly" && transceivers[0].sender.track === null &&
    transceivers[0].receiver.track.kind === "audio" && peer.getSenders().every((sender) => sender.track === null);
}
function closed() {
  if (!record || record.closed) return;
  if (player) { player.pause(); player.srcObject = null; player.remove(); player = null; }
  node?.port.close(); node?.disconnect(); source?.disconnect();
  if (context) void context.close().catch(() => {});
  record.closed = client?.closed === true && client.peer?.connectionState === "closed" &&
    client.peer?.getReceivers().every((receiver) => receiver.track.readyState === "ended");
  report();
}
async function join(config) {
  if (client) { client.stop("ended"); closed(); await reportQueue; }
  const url = new URL(config.url);
  // Exercise production fragment parsing/clearing without ever navigating a bearer URL.
  history.replaceState(null, "", `${location.pathname}${url.hash}`);
  const link = readAndClearLink(location, history);
  if (!link || location.hash) throw new Error("fragment");
  record = { epoch: ++epoch, phase: config.phase, shareID: link.shareID, decoded: false, closed: false,
    topology: false, rmsLeft: 0, rmsRight: 0, leftRatio: 0, rightRatio: 0, sampleRate: 0, windows: 0,
    microphoneCalls, failure: null, stage: "start", errorStage: null, errorCode: null, socketCloseCode: 0,
    protocolMatches: null, openReadyState: 0, elapsedMs: 0, stopReason: null, stopStage: null,
    stopClosed: null, stopReady: null, ...probeOriginalWindowTimerReceiver(), peerState: "new", trackMuted: null,
    trackReadyState: "none", inboundAudioReports: 0, packetsReceived: null, bytesReceived: null,
    totalSamplesReceived: null, concealedSamples: null, audioLevel: null, totalAudioEnergy: null };
  const currentRecord = record;
  const relay = config.relay === true ? createRelayProof() : null;
  if (relay) currentRecord.relay = relay.snapshot();
  if (config.challenge) currentRecord.challengeNonce = config.challenge.nonce;
  starts.set(currentRecord, performance.now());
  class OracleSocket extends WebSocket {
    constructor(...arguments_) {
      super(...arguments_);
      this.addEventListener("open", () => {
        currentRecord.protocolMatches = this.protocol === AUDIO_SHARE_PROTOCOL;
        currentRecord.openReadyState = this.readyState;
        diagnostic(currentRecord, "socket_open");
      });
      this.addEventListener("error", () => diagnostic(currentRecord, "socket_error", { message: "socket_error" }));
      this.addEventListener("close", (event) => {
        if (record !== currentRecord) return;
        currentRecord.socketCloseCode = event.code;
        diagnostic(currentRecord, "socket_close", currentRecord.decoded ? null : { message: "socket_closed" });
      });
    }
  }
  let currentClient;
  class RelayPeer extends RTCPeerConnection {
    constructor(configuration) { super({ ...configuration, iceTransportPolicy: "relay" }); }
  }
  currentClient = new OracleListener(link, location.origin, {
    status(status) { if (["unavailable"].includes(status) && !currentRecord.decoded) { currentRecord.failure ??= "browser"; report(); } },
    track(track) { void (async () => {
      currentClient.oracleTrack = track;
      const currentContext = new AudioContext({ sampleRate: 48_000 });
      await currentContext.audioWorklet.addModule("/oracle/waveform-worklet.js");
      if (currentClient.closed || record !== currentRecord) { await currentContext.close(); return; }
      context = currentContext;
      const stream = new MediaStream([track]);
      // Match the real listener's media-element playback, which drives Chromium's
      // remote-audio renderer. The owned browser's --disable-audio-output still
      // prevents hardware playback; the parallel worklet proves decoded samples.
      player = document.createElement("audio");
      player.srcObject = stream;
      document.body.append(player);
      source = context.createMediaStreamSource(stream);
      node = new AudioWorkletNode(context, "beluga-waveform-probe", { numberOfInputs: 1, numberOfOutputs: 1,
        outputChannelCount: [2], channelCount: 2, channelCountMode: "explicit", channelInterpretation: "discrete",
        ...(config.challenge ? { processorOptions: { challenge: config.challenge } } : {}) });
      node.port.onmessage = ({ data }) => {
        if (record !== currentRecord || currentRecord.closed || currentClient.closed) return;
        Object.assign(currentRecord, data); currentRecord.windows++;
        currentRecord.topology = topology(currentClient.peer);
        currentClient.oracleWaveformGood = data.sampleRate === 48_000 && data.rmsLeft > 0.01 && data.rmsRight > 0.01 &&
          data.leftRatio > 8 && data.rightRatio > 8 && currentRecord.topology;
        if (!relay && data.rmsLeft > 0.01 && data.rmsRight > 0.01 && data.leftRatio > 8 && data.rightRatio > 8 && currentRecord.topology) {
          currentRecord.decoded = true; currentClient.setPlaybackActive(true);
        }
        report(); void sampleStats(currentClient, currentRecord);
      };
      source.connect(node); node.connect(context.destination); await context.resume();
      if (currentClient.closed || record !== currentRecord) return;
      await player.play();
    })().catch((error) => {
      // Closing a media element deliberately aborts an in-flight play() promise.
      // A retired epoch must not turn that expected cancellation into a new failure.
      if (record !== currentRecord || currentRecord.closed || currentClient.closed) return;
      diagnostic(currentRecord, "worklet", error); currentRecord.failure = "decode"; report();
    }); },
    stop() { if (record === currentRecord) closed(); },
  }, { WebSocket: OracleSocket, ...(relay ? { RTCPeerConnection: RelayPeer } : {}) });
  currentClient.oracleRelay = relay;
  currentClient.diagnose = (stage, error) => diagnostic(currentRecord, stage, error);
  currentClient.diagnoseStop = (reason, ready, wasClosed) => {
    if (record !== currentRecord || currentRecord.stopReason !== null) return;
    currentRecord.stopReason = ["ended", "unavailable", "expired"].includes(reason) ? reason : "unknown";
    currentRecord.stopStage = currentRecord.stage;
    currentRecord.stopReady = ready === true; currentRecord.stopClosed = wasClosed === true;
    diagnostic(currentRecord, currentRecord.stage);
  };
  client = currentClient; await client.start(); report();
}

const deadline = performance.now() + 55_000;
try {
  while (performance.now() < deadline) {
    const response = await fetch("/oracle/config", { cache: "no-store" });
    const config = await response.json();
    if (config.revision > revision) {
      revision = config.revision;
      if (config.action === "complete") break;
      if (["join", "rejoin"].includes(config.action)) await join(config);
    }
    await sleep(100);
  }
} catch { if (record) { record.failure = "browser"; report(); } }
finally { client?.stop("ended"); closed(); await reportQueue; }
