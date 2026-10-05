// Browser-safe scalar proof. Candidate identities remain private to this epoch.
const exact = (value, keys) => value !== null && typeof value === "object" && !Array.isArray(value) &&
  Object.keys(value).sort().join(",") === [...keys].sort().join(",");
const count = (value) => Number.isSafeInteger(value) && value >= 0 && value <= Number.MAX_SAFE_INTEGER;
const keys = ["status", "observations", "elapsedMs", "pairBytesReceivedDelta", "audioBytesReceivedDelta"];
export function validRelayReport(value, requireVerified = false) {
  if (!exact(value, keys) || !["pending", "verified", "failed"].includes(value.status) ||
      !Number.isInteger(value.observations) || value.observations < 0 || value.observations > 64 ||
      !Number.isInteger(value.elapsedMs) || value.elapsedMs < 0 || value.elapsedMs > 90_000 ||
      !count(value.pairBytesReceivedDelta) || !count(value.audioBytesReceivedDelta)) return false;
  if (requireVerified && value.status !== "verified") return false;
  return value.status === "verified"
    ? value.observations >= 2 && value.elapsedMs >= 100 && value.pairBytesReceivedDelta > 0 && value.audioBytesReceivedDelta > 0
    : value.observations <= 1 && value.elapsedMs === 0 && value.pairBytesReceivedDelta === 0 && value.audioBytesReceivedDelta === 0;
}
const empty = (status = "pending") => ({ status, observations: 0, elapsedMs: 0,
  pairBytesReceivedDelta: 0, audioBytesReceivedDelta: 0 });
export function createRelayProof() {
  let first = null, previous = null, evidence = empty();
  const fail = () => { evidence = empty("failed"); return { ...evidence }; };
  return {
    snapshot: () => ({ ...evidence }), fail,
    observe(stats, receivedAt, waveform) {
      if (evidence.status === "failed") return { ...evidence };
      try {
        // Startup silence cannot count as proof; a later bad window is sticky.
        if (!waveform) return previous ? fail() : { ...evidence };
        if (!Number.isFinite(receivedAt) || !stats?.values) return fail();
        const entries = [...stats.values()];
        if (entries.length > 128 || entries.some((entry) => !entry || typeof entry.id !== "string") ||
            new Set(entries.map((entry) => entry.id)).size !== entries.length) return fail();
        const audioReports = entries.filter((entry) => entry.type === "inbound-rtp" &&
          (entry.kind === "audio" || entry.mediaType === "audio"));
        const transports = entries.filter((entry) => entry.type === "transport");
        if (audioReports.length !== 1 || transports.length !== 1) return fail();
        const audio = audioReports[0], transport = transports[0];
        const pair = entries.find((entry) => entry.id === transport.selectedCandidatePairId);
        const local = entries.find((entry) => entry.id === pair?.localCandidateId);
        if (audio.transportId !== transport.id || pair?.type !== "candidate-pair" || pair.state !== "succeeded" ||
            pair.transportId !== transport.id || local?.type !== "local-candidate" || local.candidateType !== "relay" ||
            local.transportId !== transport.id ||
            !count(pair.bytesReceived) || !count(audio.bytesReceived) || pair.bytesReceived === 0 || audio.bytesReceived === 0 ||
            [audio, transport, pair].some((entry) => !Number.isFinite(entry.timestamp) ||
              entry.timestamp > receivedAt || receivedAt - entry.timestamp > 1_500)) return fail();
        const observation = { audio: audio.id, transport: transport.id, pair: pair.id, local: local.id,
          receivedAt, timestamp: pair.timestamp, audioTimestamp: audio.timestamp,
          transportTimestamp: transport.timestamp, pairBytes: pair.bytesReceived, audioBytes: audio.bytesReceived };
        if (previous) {
          if (["audio", "transport", "pair", "local"].some((key) => observation[key] !== previous[key]) ||
              receivedAt - previous.receivedAt < 100 || receivedAt - first.receivedAt > 90_000 ||
              ["timestamp", "audioTimestamp", "transportTimestamp", "pairBytes", "audioBytes"].some((key) =>
                observation[key] <= previous[key]) || evidence.observations >= 64) return fail();
          evidence = { status: "verified", observations: evidence.observations + 1,
            elapsedMs: Math.floor(receivedAt - first.receivedAt),
            pairBytesReceivedDelta: observation.pairBytes - first.pairBytes,
            audioBytesReceivedDelta: observation.audioBytes - first.audioBytes };
        } else { first = observation; evidence.observations = 1; }
        previous = observation;
        return { ...evidence };
      } catch { return fail(); }
    },
  };
}

export function failRelayEpoch(epoch, proof) {
  epoch.relay = proof.fail(); epoch.decoded = false; epoch.failure = "relay";
}
export function validRelayEpochReport(epoch) {
  return validRelayReport(epoch.relay, epoch.decoded) &&
    (epoch.relay.status !== "failed" || (epoch.failure === "relay" && epoch.decoded === false));
}
export function relayEpochsPass(epochs) {
  return Array.isArray(epochs) && epochs.length === 3 && epochs.every((epoch, index) =>
    epoch.epoch === index + 1 && epoch.phase === ["revoke", "revoke", "expiry"][index] &&
    epoch.decoded === true && epoch.closed === true && epoch.topology === true && epoch.failure === null &&
    epoch.sampleRate === 48_000 && epoch.microphoneCalls === 0 && validRelayReport(epoch.relay, true));
}
export function finishRelayResult(result, interrupted) {
  if (interrupted) result.failure = "interrupted";
  result.passed = result.passed === true && !interrupted && !result.failure &&
    result.ownedChildrenReaped === true && result.ownedProcessGroupsGone === true &&
    result.browser?.failure === null && relayEpochsPass(result.browser?.epochs);
  result.relayVerified = result.passed;
  result.systemAudioVerified = false; result.deployedWorkerVerified = false;
  result.unrelatedNetworksVerified = false; result.physicalDeviceVerified = false;
  return result;
}
