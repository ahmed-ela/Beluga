import test from "node:test";
import assert from "node:assert/strict";
import { AudioShareListener } from "../public/core.js";
import { encodeBase64URL } from "../public/protocol.js";

function fixture() {
  let stopped = 0;
  const listener = new AudioShareListener({ shareID: encodeBase64URL(new Uint8Array(16).fill(1)),
    secret: new Uint8Array(32).fill(7) }, "https://share.example", {
    status() {}, stop() { stopped++; }, track() {},
  }, { now: () => 1, clearTimeout() {} });
  listener.deadline = 10_000;
  let sent = 0;
  listener.socket = { readyState: 1, bufferedAmount: 0, send() { sent++; }, close() {} };
  listener.cipher = { async seal() { return { type: "signal" }; }, close() {} };
  return { listener, stopped: () => stopped, sent: () => sent };
}

test("inbound count and byte budgets reject before stalled native work resumes", async () => {
  for (const wire of ["{}", " ".repeat(89_999)]) {
    const { listener, stopped } = fixture();
    let resume;
    listener.inbound = new Promise((resolve) => { resume = resolve; });
    for (let index = 0; index < 1_000; index++) listener.queueWire(wire);
    assert.equal(listener.closed, true);
    assert.equal(stopped(), 1);
    assert.ok(listener.pendingInbound <= 64);
    assert.ok(listener.pendingInboundBytes <= 524_288);
    resume();
    await listener.inbound;
    assert.equal(listener.pendingInbound, 0);
    assert.equal(listener.pendingInboundBytes, 0);
  }
});

test("outbound count and byte budgets cannot retain an unbounded crypto queue", async () => {
  for (const payload of [{ kind: "ice" }, { kind: "offer", sdp: "x".repeat(49_000) }]) {
    const { listener, stopped, sent } = fixture();
    let resume;
    listener.outbound = new Promise((resolve) => { resume = resolve; });
    for (let index = 0; index < 1_000; index++) listener.sendPayload(payload);
    assert.equal(listener.closed, true);
    assert.equal(stopped(), 1);
    assert.ok(listener.pendingOutbound <= 64);
    assert.ok(listener.pendingOutboundBytes <= 524_288);
    resume();
    await listener.outbound;
    assert.equal(sent(), 0);
    assert.equal(listener.pendingOutbound, 0);
    assert.equal(listener.pendingOutboundBytes, 0);
  }
});

test("oversized frames and buffered socket writes fail closed without enqueue or send", async () => {
  for (const wire of [new Uint8Array(1), "x".repeat(90_001), "🦭".repeat(30_000)]) {
    const { listener } = fixture();
    listener.queueWire(wire);
    assert.equal(listener.closed, true);
    assert.equal(listener.pendingInbound, 0);
  }
  const { listener, sent } = fixture();
  listener.socket.bufferedAmount = 524_288;
  listener.sendPayload({ kind: "ice" });
  await listener.outbound;
  assert.equal(listener.closed, true);
  assert.equal(sent(), 0);
  assert.equal(listener.pendingOutboundBytes, 0);
});
