import test from "node:test";
import assert from "node:assert/strict";
import { createCipheriv, hkdfSync } from "node:crypto";
import {
  AUDIO_SHARE_LIMITS, candidateMatchesDescription, decodeBase64URL, encodeBase64URL,
  encodeShareLocator, freshShareLocator, joinableShareLocator,
  shareLocatorBirthMilliseconds, shareLocatorRetirementMilliseconds,
  inspectAudioOnlySDP, parseAuthentication, parseClientMessage, parseLinkFragment,
} from "../public/protocol.js";
import { createSignalCipher, deriveAdmission, hashAdmission, makeListenerURL, newShareMaterial } from "../public/crypto.js";

const bytes = (length, value) => new Uint8Array(length).fill(value);
const id = (value) => encodeBase64URL(bytes(16, value));
const proof = (value) => encodeBase64URL(bytes(32, value));
const context = { shareID: id(1), generation: id(2), listenerID: id(3), expiresAt: 1_800_000_000_000 };
export const audioSDP = (direction) => `v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=mid:0\r\na=ice-ufrag:fixtureUfrag\r\na=${direction}\r\na=rtpmap:111 opus/48000/2\r\n`;
const payload = { kind: "offer", sdp: audioSDP("sendonly") };

test("link secrets exist only in exact, canonical fragments", () => {
  const url = new URL(makeListenerURL("https://share.example", id(1), bytes(32, 4)));
  assert.equal(url.pathname, "/audio-share");
  assert.equal(url.search, "");
  assert.deepEqual(parseLinkFragment(url.hash), { shareID: id(1), secret: bytes(32, 4) });
  for (const suffix of ["&v=1", "&id=x", "&k=x", "&other=x"]) assert.equal(parseLinkFragment(url.hash + suffix), null);
  assert.equal(parseLinkFragment("#v=1&id=" + id(1) + "&k=" + proof(4) + "="), null);
  assert.equal(parseLinkFragment("#v=2&id=" + id(1) + "&k=" + proof(4)), null);
  for (const origin of ["http://share.example", "https://u:p@share.example", "https://share.example?a=b"]) {
    assert.throws(() => makeListenerURL(origin, id(1), bytes(32, 4)));
  }
});

test("materials independently generate owner and listener roots", () => {
  const a = newShareMaterial();
  const b = newShareMaterial();
  assert.notEqual(a.shareID, b.shareID);
  assert.notDeepEqual(a.ownerSecret, a.listenerSecret);
  assert.notDeepEqual(a.ownerSecret, b.ownerSecret);
  assert.equal(decodeBase64URL(a.shareID, 16).length, 16);
  assert.equal(freshShareLocator(a.shareID), true);
});

test("share locators bind big-endian birth plus 96 random bits and finite safe retirement", () => {
  const now = 1_800_000_000_000;
  const locator = encodeShareLocator(bytes(12, 9), now + 999);
  const decoded = decodeBase64URL(locator, 16);
  assert.equal(new DataView(decoded.buffer).getUint32(0, false), now / 1_000);
  assert.deepEqual(decoded.slice(4), bytes(12, 9));
  assert.equal(shareLocatorBirthMilliseconds(locator), now);
  assert.equal(freshShareLocator(locator, now + 180_000), true);
  assert.equal(freshShareLocator(locator, now + 180_001), false);
  assert.equal(freshShareLocator(locator, now - 30_000), true);
  assert.equal(freshShareLocator(locator, now - 30_001), false);
  const retirement = now + 86_400_000 + 180_000 + 30_000;
  assert.equal(shareLocatorRetirementMilliseconds(locator), retirement);
  assert.equal(joinableShareLocator(locator, retirement - 1), true);
  assert.equal(joinableShareLocator(locator, retirement), false);
  assert.equal(freshShareLocator(id(0), now), false);
  assert.equal(joinableShareLocator(id(0), now), false);
  assert.equal(shareLocatorBirthMilliseconds("invalid"), null);
  for (const invalidNow of [0, 999, -1, NaN, Infinity, 1.5, 0x100000000 * 1_000]) {
    assert.throws(() => encodeShareLocator(bytes(12, 9), invalidNow));
  }
  assert.throws(() => encodeShareLocator(bytes(16, 9), now));
});

test("retire-listener is an exact bounded command; role authority belongs to the Worker", () => {
  const command = { type: "retire-listener", v: 1, listenerID: id(3) };
  assert.deepEqual(parseClientMessage(JSON.stringify(command)), command);
  for (const mutation of [{ v: 2 }, { listenerID: "invalid" }, { extra: 1 }, { reason: "revoked" }]) {
    assert.equal(parseClientMessage(JSON.stringify({ ...command, ...mutation })), null);
  }
});

test("authentication is bounded, exact, distinct-role and binary rejecting", () => {
  const valid = { type: "register", v: 1, ownerProof: proof(1), listenerProof: proof(2),
    ttlSeconds: 86_400, maxListeners: 8 };
  assert.deepEqual(parseAuthentication(JSON.stringify(valid)), valid);
  for (const mutation of [{ ttlSeconds: 86_401 }, { ttlSeconds: 0 }, { ttlSeconds: 1.5 },
    { maxListeners: 9 }, { maxListeners: 0 }, { ownerProof: proof(2) }, { extra: 1 }]) {
    assert.equal(parseAuthentication(JSON.stringify({ ...valid, ...mutation })), null);
  }
  assert.equal(parseAuthentication(bytes(16, 1)), null);
  assert.equal(parseAuthentication(" ".repeat(2_049)), null);
  assert.equal(parseClientMessage(JSON.stringify({ type: "revoke", v: 1, extra: 1 })), null);
});

test("admission and directional AES-GCM match independent Node HKDF/AES vectors", async () => {
  const root = bytes(32, 4);
  const salt = decodeBase64URL(context.shareID, 16);
  const admission = Buffer.from(hkdfSync("sha256", root, salt,
    Buffer.from("Beluga.AudioShare.v1\0admission\0listener"), 32));
  assert.equal(await deriveAdmission(root, "listener", context.shareID), admission.toString("base64url"));
  assert.notEqual(await deriveAdmission(root, "owner", context.shareID), admission.toString("base64url"));
  assert.notEqual(await hashAdmission(admission.toString("base64url")), admission.toString("base64url"));
  const owner = await createSignalCipher(root, context, "owner");
  const sealed = await owner.seal(payload);
  const key = Buffer.from(hkdfSync("sha256", root, salt, Buffer.from(
    `Beluga.AudioShare.v1\0signal\0${context.generation}\0${context.listenerID}\0${context.expiresAt}\0ownerToListener`), 32));
  const cipher = createCipheriv("aes-256-gcm", key, Buffer.alloc(12));
  cipher.setAAD(Buffer.from(`Beluga.AudioShare.v1\0${context.shareID}\0${context.generation}\0${context.listenerID}\0${context.expiresAt}\0ownerToListener\0${0}`));
  const expected = Buffer.concat([cipher.update(JSON.stringify(payload)), cipher.final(), cipher.getAuthTag()]);
  assert.equal(sealed.ciphertext, expected.toString("base64url"));
  const listener = await createSignalCipher(root, context, "listener");
  assert.deepEqual(await listener.open({ ...sealed, from: "owner" }), payload);
  await assert.rejects(listener.open({ ...sealed, from: "owner" }));
});

test("every context field and direction authenticates the ciphertext", async () => {
  const root = bytes(32, 4);
  const owner = await createSignalCipher(root, context, "owner");
  const sealed = await owner.seal(payload);
  for (const changed of [{ shareID: id(5) }, { generation: id(5) }, { listenerID: id(5) },
    { expiresAt: context.expiresAt + 1 }]) {
    const wrong = await createSignalCipher(root, { ...context, ...changed }, "listener");
    await assert.rejects(wrong.open({ ...sealed, from: "owner", listenerID: changed.listenerID ?? context.listenerID }));
  }
  const wrongRoot = await createSignalCipher(bytes(32, 5), context, "listener");
  await assert.rejects(wrongRoot.open({ ...sealed, from: "owner" }));
  const listener = await createSignalCipher(root, context, "listener");
  const corrupted = decodeBase64URL(sealed.ciphertext, 17, AUDIO_SHARE_LIMITS.maxCiphertextBytes);
  corrupted[0] ^= 1;
  await assert.rejects(listener.open({ ...sealed, from: "owner", ciphertext: encodeBase64URL(corrupted) }));
  await assert.rejects(listener.open({ ...sealed, from: "owner" }));
});

test("concurrent sealing never reuses a sequence nonce; explicit close blocks delivery", async () => {
  const owner = await createSignalCipher(bytes(32, 4), context, "owner");
  const packets = await Promise.all(Array.from({ length: 8 }, () => owner.seal(payload)));
  assert.deepEqual(packets.map((packet) => packet.seq), [0, 1, 2, 3, 4, 5, 6, 7]);
  assert.equal(new Set(packets.map((packet) => packet.ciphertext)).size, 8);
  owner.close();
  await assert.rejects(owner.seal(payload));
});

test("concurrent receives cannot deliver after an earlier authentication failure", async () => {
  const owner = await createSignalCipher(bytes(32, 4), context, "owner");
  const listener = await createSignalCipher(bytes(32, 4), context, "listener");
  const first = await owner.seal(payload);
  const second = await owner.seal(payload);
  const corrupted = decodeBase64URL(first.ciphertext, 17, AUDIO_SHARE_LIMITS.maxCiphertextBytes);
  corrupted[0] ^= 1;
  const settled = await Promise.allSettled([
    listener.open({ ...first, from: "owner", ciphertext: encodeBase64URL(corrupted) }),
    listener.open({ ...second, from: "owner" }),
  ]);
  assert.deepEqual(settled.map((value) => value.status), ["rejected", "rejected"]);
});

test("browser accepts exactly audio-only Opus sendonly offers and fenced ICE", () => {
  const description = inspectAudioOnlySDP(audioSDP("sendonly"), "sendonly");
  assert.deepEqual(description, { sdpMid: "0", sdpMLineIndex: 0, usernameFragment: "fixtureUfrag" });
  for (const mutant of [audioSDP("sendrecv"), audioSDP("recvonly"), audioSDP("sendonly") + "m=video 9 UDP/TLS/RTP/SAVPF 96\r\n",
    audioSDP("sendonly").replace("m=audio 9", "m=audio 0"), audioSDP("sendonly").replace("opus/48000/2", "PCMU/8000")]) {
    assert.throws(() => inspectAudioOnlySDP(mutant, "sendonly"));
  }
  const candidate = { candidate: "candidate:fixture 1 udp 1 192.0.2.1 1234 typ host", ...description };
  assert.equal(candidateMatchesDescription(candidate, description), true);
  for (const mutant of [{ ...candidate, usernameFragment: "old" }, { ...candidate, sdpMid: "1" },
    { ...candidate, sdpMLineIndex: 1 }, { ...candidate, extra: 1 }]) {
    assert.equal(candidateMatchesDescription(mutant, description), false);
  }
});
