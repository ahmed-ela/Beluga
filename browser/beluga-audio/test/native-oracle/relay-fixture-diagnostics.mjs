// Fixed scalar projection only. Never retain the child report, signaling or IDs.
import { RELAY_FAILURE_CODES } from "./relay-contract.js";
const boundaries = new Set(["report_invalid", "forced_termination", "cleanup", "runner", "native_exit",
  "browser_incomplete", "browser", "relay_proof", "stereo_or_lifecycle", "none"]);
const runnerFailures = new Set(["interrupted", "relay_credentials_refused", "deadline", "runner_or_native_boundary", "cleanup"]);
const browserFailures = new Set(["decode", "topology", "browser", "deadline", "relay"]);
const phases = new Set(["revoke", "expiry"]);
const stages = new Set(["start", "socket_open", "socket_error", "socket_close", "wire", "ready", "offer",
  "candidate", "cipher_open", "cipher_seal", "worklet", "csp", "relay_proof"]);
const codes = new Set(["unknown", "invalid_key_material", "invalid_role", "invalid_proof", "invalid_link_origin",
  "invalid_signal_context", "invalid_signal", "signal_closed", "invalid_link", "invalid_message", "candidate_overflow",
  "unexpected_answer", "invalid_ready", "offer_overlap", "unexpected_media", "stale_candidate", "invalid_audio_description",
  "socket_error", "socket_closed", "connect_src", "OperationError", "NotSupportedError", "InvalidAccessError",
  "InvalidStateError", "SecurityError", "SyntaxError", "AbortError", "TypeError", ...RELAY_FAILURE_CODES]);
const peerStates = new Set(["new", "connecting", "connected", "disconnected", "failed", "closed"]);
const relayStates = new Set(["pending", "verified", "failed"]);
const nativePhases = new Set(["before_revoke", "after_revoke", "after_expiry", "after_owner_loss", "failure_before_cleanup", "success"]);
const record = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const enumeration = (value, allowed) => value === null || value === undefined ? null :
  typeof value === "string" && allowed.has(value) ? value : "unknown";
const integer = (value, maximum, minimum = 0) => Number.isSafeInteger(value) && value >= minimum && value <= maximum ? value : null;
const boolean = (value) => typeof value === "boolean" ? value : null;
const enumFields = {
  runnerFailure: runnerFailures, browserFailure: browserFailures, phase: phases, stage: stages, errorStage: stages,
  errorCode: codes, peerState: peerStates, relayStatus: relayStates, nativePhase: nativePhases,
};
const integerFields = {
  nativeExitCode: [0, 255], epochCount: [0, 4], epoch: [1, 4], relayObservations: [0, 64],
  inboundAudioReports: [0, 8], bytesReceived: [0, Number.MAX_SAFE_INTEGER], windows: [0, 999_999],
};
const booleanFields = ["browserComplete", "decoded", "closed", "topology", "waveformPass"];
const keys = ["boundary", ...Object.keys(enumFields), ...Object.keys(integerFields), ...booleanFields].sort();

function waveform(epoch) {
  if (!epoch || !["sampleRate", "rmsLeft", "rmsRight", "leftRatio", "rightRatio"].every((key) =>
    Number.isFinite(epoch[key]) && epoch[key] >= 0 && epoch[key] < 1_000_000)) return null;
  return epoch.sampleRate === 48_000 && epoch.rmsLeft > 0.01 && epoch.rmsRight > 0.01 &&
    epoch.leftRatio > 8 && epoch.rightRatio > 8;
}

export function summarizeFixtureDiagnostics(value, boundary) {
  const report = record(value) ? value : null;
  const browser = record(report?.browser) ? report.browser : null;
  // Reject oversized arrays as diagnostic input rather than traversing/truncating
  // them and making an arbitrary selected epoch appear authoritative.
  const epochs = Array.isArray(browser?.epochs) && browser.epochs.length <= 4 ? browser.epochs : null;
  const records = epochs?.filter(record) ?? [];
  const epoch = records.find((item) => typeof item.failure === "string" || item.relay?.status === "failed") ??
    records.find((item) => item.decoded !== true || item.topology !== true || item.closed !== true) ?? records.at(-1);
  const relay = record(epoch?.relay) ? epoch.relay : null;
  const snapshots = Array.isArray(browser?.nativeSnapshots) && browser.nativeSnapshots.length <= 8
    ? browser.nativeSnapshots : null;
  const native = snapshots?.filter(record).at(-1);
  return {
    boundary: boundaries.has(boundary) ? boundary : "report_invalid",
    runnerFailure: enumeration(report?.failure, runnerFailures),
    nativeExitCode: integer(report?.nativeExitCode, 255),
    browserComplete: boolean(browser?.complete),
    browserFailure: enumeration(browser?.failure, browserFailures),
    epochCount: epochs === null ? null : epochs.length,
    epoch: integer(epoch?.epoch, 4, 1),
    phase: enumeration(epoch?.phase, phases),
    stage: enumeration(epoch?.stage, stages),
    errorStage: enumeration(epoch?.errorStage, stages),
    errorCode: enumeration(epoch?.errorCode, codes),
    peerState: enumeration(epoch?.peerState, peerStates),
    decoded: boolean(epoch?.decoded),
    closed: boolean(epoch?.closed),
    topology: boolean(epoch?.topology),
    waveformPass: waveform(epoch),
    relayStatus: enumeration(relay?.status, relayStates),
    relayObservations: integer(relay?.observations, 64),
    inboundAudioReports: integer(epoch?.inboundAudioReports, 8),
    bytesReceived: integer(epoch?.bytesReceived, Number.MAX_SAFE_INTEGER),
    windows: integer(epoch?.windows, 999_999),
    nativePhase: enumeration(native?.phase, nativePhases),
  };
}

export function validFixtureDiagnostics(value) {
  if (!record(value) || Object.keys(value).sort().join(",") !== keys.join(",") || !boundaries.has(value.boundary)) return false;
  for (const [key, allowed] of Object.entries(enumFields)) {
    if (value[key] !== null && value[key] !== "unknown" && !(typeof value[key] === "string" && allowed.has(value[key]))) return false;
  }
  for (const [key, [minimum, maximum]] of Object.entries(integerFields)) {
    if (value[key] !== null && integer(value[key], maximum, minimum) === null) return false;
  }
  return booleanFields.every((key) => value[key] === null || typeof value[key] === "boolean");
}
