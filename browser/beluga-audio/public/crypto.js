import {
  AUDIO_SHARE_LIMITS, decodeBase64URL, encodeBase64URL, encodeShareLocator, exactKeys,
  validProof, validShareID, validSequence, validSignalPayload,
} from "./protocol.js";

const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { fatal: true });
const domain = "Beluga.AudioShare.v1";

async function derive(root, shareID, label, length) {
  if (!(root instanceof Uint8Array) || root.byteLength !== 32 || !validShareID(shareID)) {
    throw new Error("invalid_key_material");
  }
  const key = await crypto.subtle.importKey("raw", root, "HKDF", false, ["deriveBits"]);
  return new Uint8Array(await crypto.subtle.deriveBits({
    name: "HKDF", hash: "SHA-256", salt: decodeBase64URL(shareID, 16),
    info: encoder.encode(`${domain}\0${label}`),
  }, key, length));
}

export async function deriveAdmission(root, role, shareID) {
  if (role !== "owner" && role !== "listener") throw new Error("invalid_role");
  return encodeBase64URL(await derive(root, shareID, `admission\0${role}`, 256));
}

export async function hashAdmission(proof) {
  if (!validProof(proof)) throw new Error("invalid_proof");
  return encodeBase64URL(new Uint8Array(await crypto.subtle.digest("SHA-256",
    encoder.encode(`${domain}\0verifier\0${proof}`))));
}

export function constantTimeProofsEqual(left, right) {
  const a = decodeBase64URL(left, 32);
  const b = decodeBase64URL(right, 32);
  if (!a || !b) return false;
  let difference = 0;
  for (let index = 0; index < a.length; index += 1) difference |= a[index] ^ b[index];
  return difference === 0;
}

export function newShareMaterial() {
  const shareID = encodeShareLocator(crypto.getRandomValues(new Uint8Array(12)));
  const ownerSecret = crypto.getRandomValues(new Uint8Array(32));
  let listenerSecret;
  do { listenerSecret = crypto.getRandomValues(new Uint8Array(32)); }
  while (constantTimeProofsEqual(encodeBase64URL(ownerSecret), encodeBase64URL(listenerSecret)));
  return { shareID, ownerSecret, listenerSecret };
}

export function makeListenerURL(origin, shareID, listenerSecret) {
  const url = new URL(origin);
  if (url.protocol !== "https:" || url.username || url.password || url.search || url.hash ||
      !validShareID(shareID) || !(listenerSecret instanceof Uint8Array) || listenerSecret.length !== 32) {
    throw new Error("invalid_link_origin");
  }
  url.pathname = "/audio-share";
  url.hash = new URLSearchParams({ v: "1", id: shareID, k: encodeBase64URL(listenerSecret) }).toString();
  return url.href;
}

export async function createSignalCipher(root, context, role) {
  if (!exactKeys(context, ["shareID", "generation", "listenerID", "expiresAt"]) ||
      !validShareID(context.shareID) || !validShareID(context.generation) ||
      !validShareID(context.listenerID) || !Number.isSafeInteger(context.expiresAt) || context.expiresAt <= 0 ||
      !["owner", "listener"].includes(role)) throw new Error("invalid_signal_context");
  context = Object.freeze({ ...context });
  const contextLabel = `${context.generation}\0${context.listenerID}\0${context.expiresAt}`;
  const keys = {};
  for (const direction of ["ownerToListener", "listenerToOwner"]) {
    const raw = await derive(root, context.shareID, `signal\0${contextLabel}\0${direction}`, 256);
    keys[direction] = await crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt", "decrypt"]);
    raw.fill(0);
  }
  const outbound = role === "owner" ? "ownerToListener" : "listenerToOwner";
  const inbound = role === "owner" ? "listenerToOwner" : "ownerToListener";
  let sendSequence = 0;
  let receiveSequence = 0;
  let closed = false;
  let receiveQueue = Promise.resolve();
  const nonce = (sequence) => {
    const bytes = new Uint8Array(12);
    new DataView(bytes.buffer).setUint32(8, sequence, false);
    return bytes;
  };
  const aad = (direction, sequence) => encoder.encode(
    `${domain}\0${context.shareID}\0${context.generation}\0${context.listenerID}\0${context.expiresAt}\0${direction}\0${sequence}`,
  );
  return {
    async seal(payload) {
      if (closed || !validSequence(sendSequence) || !validSignalPayload(payload)) throw new Error("invalid_signal");
      const plaintext = encoder.encode(JSON.stringify(payload));
      if (plaintext.length > AUDIO_SHARE_LIMITS.maxPlaintextBytes) throw new Error("invalid_signal");
      // Consume before awaiting: concurrent sends never reuse an AES-GCM nonce.
      const sequence = sendSequence++;
      const ciphertext = await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce(sequence),
        additionalData: aad(outbound, sequence), tagLength: 128 }, keys[outbound], plaintext);
      if (closed) throw new Error("signal_closed");
      return { type: "signal", v: 1, listenerID: context.listenerID, seq: sequence,
        ciphertext: encodeBase64URL(new Uint8Array(ciphertext)) };
    },
    open(message) {
      const operation = receiveQueue.then(async () => {
        if (closed || !exactKeys(message, ["type", "v", "from", "listenerID", "seq", "ciphertext"]) ||
            message.type !== "signal" || message.v !== 1 || message.from === role ||
            message.from !== (role === "owner" ? "listener" : "owner") ||
            message.listenerID !== context.listenerID || message.seq !== receiveSequence ||
            !validSequence(message.seq)) { closed = true; throw new Error("invalid_signal"); }
        const ciphertext = decodeBase64URL(message.ciphertext, 17, AUDIO_SHARE_LIMITS.maxCiphertextBytes);
        if (!ciphertext) { closed = true; throw new Error("invalid_signal"); }
        const sequence = receiveSequence++;
        try {
          const plaintext = await crypto.subtle.decrypt({ name: "AES-GCM", iv: nonce(sequence),
            additionalData: aad(inbound, sequence), tagLength: 128 }, keys[inbound], ciphertext);
          if (closed || plaintext.byteLength > AUDIO_SHARE_LIMITS.maxPlaintextBytes) throw new Error();
          const payload = JSON.parse(decoder.decode(plaintext));
          if (!validSignalPayload(payload)) throw new Error();
          return payload;
        } catch {
          closed = true;
          throw new Error("invalid_signal");
        }
      });
      receiveQueue = operation.catch(() => {});
      return operation;
    },
    close() { closed = true; keys.ownerToListener = null; keys.listenerToOwner = null; },
  };
}
