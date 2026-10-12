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
export const RELAY_FAILURE_CODES = Object.freeze([
  "relay_forced", "relay_waveform", "relay_received_at", "relay_stats_unavailable",
  "relay_entry_count", "relay_entry_id", "relay_duplicate_id", "relay_audio_count", "relay_transport_count",
  "relay_audio_binding", "relay_pair_missing", "relay_pair_state", "relay_pair_binding",
  "relay_local_missing", "relay_local_not_relay", "relay_local_binding", "relay_pair_counter", "relay_audio_counter",
  "relay_pair_zero", "relay_audio_zero", "relay_timestamp_missing", "relay_timestamp_future", "relay_timestamp_stale",
  "relay_identity_changed", "relay_interval", "relay_deadline", "relay_nonprogress", "relay_observation_limit",
  "relay_exception", "relay_stats_exception",
]);
export function createRelayProof() {
  let first = null, previous = null, evidence = empty(), failureReason = null;
  const fail = (reason) => {
    if (failureReason === null) failureReason = reason;
    evidence = empty("failed"); return { ...evidence };
  };
  return {
    snapshot: () => ({ ...evidence }), failureReason: () => failureReason,
    // External callers cannot supply a diagnostic payload or replace its cause.
    fail: () => fail("relay_forced"),
    observe(stats, receivedAt, waveform) {
      if (evidence.status === "failed") return { ...evidence };
      try {
        // Startup silence cannot count as proof; a later bad window is sticky.
        if (!waveform) return previous ? fail("relay_waveform") : { ...evidence };
        if (!Number.isFinite(receivedAt)) return fail("relay_received_at");
        if (!stats?.values) return fail("relay_stats_unavailable");
        const entries = [...stats.values()];
        if (entries.length > 128) return fail("relay_entry_count");
        if (entries.some((entry) => !entry || typeof entry.id !== "string")) return fail("relay_entry_id");
        if (new Set(entries.map((entry) => entry.id)).size !== entries.length) return fail("relay_duplicate_id");
        const audioReports = entries.filter((entry) => entry.type === "inbound-rtp" &&
          (entry.kind === "audio" || entry.mediaType === "audio"));
        const transports = entries.filter((entry) => entry.type === "transport");
        if (audioReports.length !== 1) return fail("relay_audio_count");
        if (transports.length !== 1) return fail("relay_transport_count");
        const audio = audioReports[0], transport = transports[0];
        const pair = entries.find((entry) => entry.id === transport.selectedCandidatePairId);
        const local = entries.find((entry) => entry.id === pair?.localCandidateId);
        if (audio.transportId !== transport.id) return fail("relay_audio_binding");
        if (pair?.type !== "candidate-pair") return fail("relay_pair_missing");
        if (pair.state !== "succeeded") return fail("relay_pair_state");
        if (pair.transportId !== transport.id) return fail("relay_pair_binding");
        if (local?.type !== "local-candidate") return fail("relay_local_missing");
        if (local.candidateType !== "relay") return fail("relay_local_not_relay");
        if (local.transportId !== transport.id) return fail("relay_local_binding");
        if (!count(pair.bytesReceived)) return fail("relay_pair_counter");
        if (!count(audio.bytesReceived)) return fail("relay_audio_counter");
        if (pair.bytesReceived === 0) return fail("relay_pair_zero");
        if (audio.bytesReceived === 0) return fail("relay_audio_zero");
        for (const entry of [audio, transport, pair]) {
          if (!Number.isFinite(entry.timestamp)) return fail("relay_timestamp_missing");
          if (entry.timestamp > receivedAt) return fail("relay_timestamp_future");
          if (receivedAt - entry.timestamp > 1_500) return fail("relay_timestamp_stale");
        }
        const observation = { audio: audio.id, transport: transport.id, pair: pair.id, local: local.id,
          receivedAt, timestamp: pair.timestamp, audioTimestamp: audio.timestamp,
          transportTimestamp: transport.timestamp, pairBytes: pair.bytesReceived, audioBytes: audio.bytesReceived };
        if (previous) {
          if (["audio", "transport", "pair", "local"].some((key) => observation[key] !== previous[key])) return fail("relay_identity_changed");
          if (receivedAt - previous.receivedAt < 100) return fail("relay_interval");
          if (receivedAt - first.receivedAt > 90_000) return fail("relay_deadline");
          if (["timestamp", "audioTimestamp", "transportTimestamp", "pairBytes", "audioBytes"].some((key) =>
            observation[key] <= previous[key])) return fail("relay_nonprogress");
          if (evidence.observations >= 64) return fail("relay_observation_limit");
          evidence = { status: "verified", observations: evidence.observations + 1,
            elapsedMs: Math.floor(receivedAt - first.receivedAt),
            pairBytesReceivedDelta: observation.pairBytes - first.pairBytes,
            audioBytesReceivedDelta: observation.audioBytes - first.audioBytes };
        } else { first = observation; evidence.observations = 1; }
        previous = observation;
        return { ...evidence };
      } catch { return fail("relay_exception"); }
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
