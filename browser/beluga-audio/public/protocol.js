export const AUDIO_SHARE_PROTOCOL = "beluga.audio-share.v1";
export const AUDIO_SHARE_LIMITS = Object.freeze({
  maxTTLSeconds: 86_400,
  maxListeners: 8,
  maxLifetimeIssuances: 64,
  creationPastMs: 180_000,
  creationFutureMs: 30_000,
  maxPendingSockets: 16,
  authenticationMs: 5_000,
  ownerLeaseMs: 15_000,
  maxAuthenticationBytes: 2_048,
  maxWireBytes: 90_000,
  maxPendingMessages: 32,
  maxPendingMessageBytes: 524_288,
  maxCiphertextBytes: 65_536,
  maxPlaintextBytes: 49_152,
  maxSequence: 2_147_483_647,
  messagesPerMinute: 300,
  maxBufferedCandidates: 256,
});

const encoder = new TextEncoder();
export const utf8Length = (value) => encoder.encode(value).byteLength;
export const exactKeys = (value, expected) => {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return false;
  const actual = Object.keys(value).sort();
  const sorted = [...expected].sort();
  return actual.length === sorted.length && actual.every((key, index) => key === sorted[index]);
};

export function encodeBase64URL(bytes) {
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += 8_192) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 8_192));
  }
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

export function decodeBase64URL(value, minimum, maximum = minimum) {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]+$/.test(value)) return null;
  if (value.length > Math.ceil(maximum * 4 / 3)) return null;
  try {
    const binary = atob(value.replaceAll("-", "+").replaceAll("_", "/"));
    const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
    if (bytes.length < minimum || bytes.length > maximum || encodeBase64URL(bytes) !== value) return null;
    return bytes;
  } catch {
    return null;
  }
}

export const validShareID = (value) => decodeBase64URL(value, 16) !== null;
// Only share locators have this creation fence. Generation/listener IDs stay fully random.
// The public locator has 96 random bits; its independent bearer root still has 256 bits.
export function encodeShareLocator(entropy, now = Date.now()) {
  const seconds = Math.floor(now / 1_000);
  if (!(entropy instanceof Uint8Array) || entropy.byteLength !== 12 ||
      !Number.isSafeInteger(now) || now <= 0 || seconds < 1 || seconds > 0xffffffff) {
    throw new Error("invalid_share_locator");
  }
  const bytes = new Uint8Array(16);
  new DataView(bytes.buffer).setUint32(0, seconds, false);
  bytes.set(entropy, 4);
  return encodeBase64URL(bytes);
}
export function shareLocatorBirthMilliseconds(locator) {
  const bytes = decodeBase64URL(locator, 16);
  if (!bytes) return null;
  const seconds = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(0, false);
  return seconds > 0 ? seconds * 1_000 : null;
}
export function freshShareLocator(locator, now = Date.now()) {
  const birth = shareLocatorBirthMilliseconds(locator);
  return birth !== null && Number.isSafeInteger(now) && now > 0 &&
    birth <= now + AUDIO_SHARE_LIMITS.creationFutureMs &&
    birth >= now - AUDIO_SHARE_LIMITS.creationPastMs;
}
export function shareLocatorRetirementMilliseconds(locator) {
  const birth = shareLocatorBirthMilliseconds(locator);
  return birth === null ? null : birth + AUDIO_SHARE_LIMITS.maxTTLSeconds * 1_000 +
    AUDIO_SHARE_LIMITS.creationPastMs + AUDIO_SHARE_LIMITS.creationFutureMs;
}
export function joinableShareLocator(locator, now = Date.now()) {
  const birth = shareLocatorBirthMilliseconds(locator);
  const retirement = shareLocatorRetirementMilliseconds(locator);
  return birth !== null && Number.isSafeInteger(now) && now > 0 &&
    birth <= now + AUDIO_SHARE_LIMITS.creationFutureMs && now < retirement;
}
export const validProof = (value) => decodeBase64URL(value, 32) !== null;
export const validSequence = (value) => Number.isSafeInteger(value) &&
  value >= 0 && value <= AUDIO_SHARE_LIMITS.maxSequence;

export function parseAuthentication(wire) {
  if (typeof wire !== "string" || utf8Length(wire) > AUDIO_SHARE_LIMITS.maxAuthenticationBytes) return null;
  let value;
  try { value = JSON.parse(wire); } catch { return null; }
  if (value?.v !== 1) return null;
  if (value.type === "register" && exactKeys(value,
    ["type", "v", "ownerProof", "listenerProof", "ttlSeconds", "maxListeners"])) {
    if (!validProof(value.ownerProof) || !validProof(value.listenerProof) ||
        value.ownerProof === value.listenerProof || !Number.isSafeInteger(value.ttlSeconds) ||
        value.ttlSeconds < 1 || value.ttlSeconds > AUDIO_SHARE_LIMITS.maxTTLSeconds ||
        !Number.isSafeInteger(value.maxListeners) || value.maxListeners < 1 ||
        value.maxListeners > AUDIO_SHARE_LIMITS.maxListeners) return null;
    return value;
  }
  if (value.type === "authenticate" && exactKeys(value, ["type", "v", "proof"]) && validProof(value.proof)) {
    return value;
  }
  return null;
}

export function parseClientMessage(wire) {
  if (typeof wire !== "string" || utf8Length(wire) > AUDIO_SHARE_LIMITS.maxWireBytes) return null;
  let value;
  try { value = JSON.parse(wire); } catch { return null; }
  if (value?.v !== 1) return null;
  if (value.type === "signal" && exactKeys(value, ["type", "v", "listenerID", "seq", "ciphertext"]) &&
      validShareID(value.listenerID) && validSequence(value.seq) &&
      decodeBase64URL(value.ciphertext, 17, AUDIO_SHARE_LIMITS.maxCiphertextBytes)) return value;
  if (value.type === "probe" && exactKeys(value, ["type", "v", "nonce"]) && validShareID(value.nonce)) return value;
  if (value.type === "revoke" && exactKeys(value, ["type", "v"])) return value;
  if (value.type === "retire-listener" && exactKeys(value, ["type", "v", "listenerID"]) &&
      validShareID(value.listenerID)) return value;
  return null;
}

export function parseLinkFragment(fragment) {
  if (typeof fragment !== "string" || fragment.length > 160 || !fragment.startsWith("#")) return null;
  const parameters = new URLSearchParams(fragment.slice(1));
  const keys = [...parameters.keys()];
  if (keys.length !== 3 || !["v", "id", "k"].every((key) => parameters.getAll(key).length === 1) ||
      parameters.get("v") !== "1" || !validShareID(parameters.get("id")) ||
      !validProof(parameters.get("k"))) return null;
  return { shareID: parameters.get("id"), secret: decodeBase64URL(parameters.get("k"), 32) };
}

export function validSignalPayload(value) {
  if (value?.kind === "offer" || value?.kind === "answer") {
    return exactKeys(value, ["kind", "sdp"]) && typeof value.sdp === "string" &&
      value.sdp.length > 0 && utf8Length(value.sdp) <= AUDIO_SHARE_LIMITS.maxPlaintextBytes;
  }
  if (value?.kind !== "ice" || !exactKeys(value, ["kind", "candidate"])) return false;
  const candidate = value.candidate;
  return exactKeys(candidate, ["candidate", "sdpMid", "sdpMLineIndex", "usernameFragment"]) &&
    typeof candidate.candidate === "string" && candidate.candidate.startsWith("candidate:") &&
    utf8Length(candidate.candidate) <= 2_048 && !/[\u0000-\u001f\u007f]/.test(candidate.candidate) &&
    typeof candidate.sdpMid === "string" &&
    /^[A-Za-z0-9_-]{1,64}$/.test(candidate.sdpMid) && candidate.sdpMLineIndex === 0 &&
    typeof candidate.usernameFragment === "string" &&
    /^[A-Za-z0-9+/]{1,256}$/.test(candidate.usernameFragment);
}

export function inspectAudioOnlySDP(sdp, expectedDirection) {
  if (typeof sdp !== "string" || utf8Length(sdp) > AUDIO_SHARE_LIMITS.maxPlaintextBytes ||
      !["sendonly", "recvonly"].includes(expectedDirection)) throw new Error("invalid_audio_description");
  const lines = sdp.split(/\r?\n/);
  const media = lines.filter((line) => line.startsWith("m="));
  if (media.length !== 1 || !/^m=audio [1-9][0-9]* UDP\/TLS\/RTP\/SAVPF /.test(media[0])) {
    throw new Error("invalid_audio_description");
  }
  const mids = lines.filter((line) => line.startsWith("a=mid:"));
  const directions = lines.filter((line) => /^a=(?:sendonly|recvonly|sendrecv|inactive)$/.test(line));
  const ufrags = lines.filter((line) => line.startsWith("a=ice-ufrag:"));
  if (mids.length !== 1 || !/^a=mid:[A-Za-z0-9_-]{1,64}$/.test(mids[0]) ||
      directions.length !== 1 || directions[0] !== `a=${expectedDirection}` ||
      ufrags.length < 1 || !ufrags.every((line) => line === ufrags[0]) ||
      !/^a=ice-ufrag:[A-Za-z0-9+/]{1,256}$/.test(ufrags[0]) ||
      !lines.some((line) => /^a=rtpmap:\d+ opus\/48000\/2$/i.test(line))) {
    throw new Error("invalid_audio_description");
  }
  return { sdpMid: mids[0].slice(6), sdpMLineIndex: 0, usernameFragment: ufrags[0].slice(12) };
}

export function candidateMatchesDescription(candidate, description) {
  return validSignalPayload({ kind: "ice", candidate }) && candidate.sdpMid === description.sdpMid &&
    candidate.sdpMLineIndex === 0 && candidate.usernameFragment === description.usernameFragment;
}

// RFC 7587: opus/48000/2 alone still defaults to mono. This local receive-only
// answer must explicitly prefer stereo; do not invent a sending track or change
// bitrate/FEC/ICE/fingerprint parameters while expressing that preference.
export function preferStereoReception(sdp) {
  inspectAudioOnlySDP(sdp, "recvonly");
  const lines = sdp.split(/\r?\n/);
  const mappings = lines.flatMap((line, index) => {
    const match = /^a=rtpmap:(\d+) opus\/48000\/2$/i.exec(line);
    return match ? [{ payload: match[1], index }] : [];
  });
  if (mappings.length !== 1) throw new Error("invalid_audio_description");
  const { payload, index } = mappings[0];
  const media = lines.find((line) => line.startsWith("m=audio ")).split(" ").slice(3);
  if (media.length !== 1 || media[0] !== payload) throw new Error("invalid_audio_description");
  const prefix = `a=fmtp:${payload} `;
  const formats = lines.flatMap((line, index) => line.startsWith(prefix) ? [index] : []);
  if (formats.length > 1) throw new Error("invalid_audio_description");
  if (formats.length === 0) lines.splice(index + 1, 0, `${prefix}stereo=1`);
  else {
    const parameters = lines[formats[0]].slice(prefix.length).split(";").map((value) => value.trim());
    const names = parameters.map((value) => value.split("=", 1)[0].toLowerCase());
    if (parameters.some((value) => !/^[A-Za-z0-9_-]+=[^;\s\u0000-\u001f\u007f]+$/.test(value)) ||
        new Set(names).size !== names.length) throw new Error("invalid_audio_description");
    lines[formats[0]] = prefix + [...parameters.filter((_, index) => names[index] !== "stereo"), "stereo=1"].join(";");
  }
  const answer = lines.join("\r\n");
  inspectAudioOnlySDP(answer, "recvonly");
  return answer;
}
