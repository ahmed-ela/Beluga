// Executes the exact production Chrome script with an explicit DOM boundary double.
// This is not permissioned live Chrome, YouTube playback or a phone handoff oracle.
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import {randomUUID} from 'node:crypto';
import test from 'node:test';
import assert from 'node:assert/strict';

const swift = readFileSync(new URL('../macOS/Sources/CaptureServer/MacChromeMediaScript.swift', import.meta.url), 'utf8');
const match = swift.match(/static let source = #"""\n([\s\S]*?)\n\s*"""#/);
assert.ok(match, 'exact raw production script required');
let script = match[1];
if (process.env.BELUGA_NATIVE_HANDOFF_MUTANT) {
  const mutations = {
    timeline: ['!handoffMatches(request.handoff,fence.snapshot)', 'false'],
    events: ['s.playbackContinuityID = crypto.randomUUID(); };', 's.playbackContinuityID = s.playbackContinuityID; };'],
  };
  const change = mutations[process.env.BELUGA_NATIVE_HANDOFF_MUTANT];
  assert.ok(change, 'known mutation required');
  assert.equal(script.split(change[0]).length, 2, 'mutation must match one actual boundary');
  script = script.replace(...change);
}

function fixture() {
  let pageTime = 50000, wallTime = 1000000, pauses = 0, finalObservation, finalValidation;
  class Element extends EventTarget {
    isConnected = true;
    getAttribute(name) { return name === 'video-id' ? 'abcdefghijk' : null; }
    click() {}
  }
  class Media extends Element {
    _time = 15;
    paused = false;
    ended = false;
    readyState = 4;
    duration = 120;
    playbackRate = 1;
    currentSrc = 'https://media.example/video';
    seekable = {length: 1, start() { return 0; }, end() { return 120; }};
    get currentTime() { return this._time; }
    set currentTime(value) { this._time = value; this.dispatchEvent(new Event('seeking')); }
    pause() { pauses++; this.paused = true; this.dispatchEvent(new Event('pause')); }
    play() { this.paused = false; this.dispatchEvent(new Event('play')); return Promise.resolve(); }
  }
  class Video extends Media {}
  const video = new Video(), player = new Element(), watch = new Element(), document = new EventTarget();
  player.querySelectorAll = name => name === 'video' ? [video] : [];
  player.querySelector = name => name === 'video.html5-main-video' ? video : null;
  let observations = 0;
  document.querySelectorAll = name => {
    if (name !== '#movie_player') return [];
    // A full observe reads querySelectorAll twice. Inject a change at the final
    // second observe, after the first command observation but before native Pause.
    observations++;
    if (observations === 3 && finalObservation) finalObservation();
    if (observations === 4 && finalValidation) finalValidation();
    return [player];
  };
  document.querySelector = name => name === '#movie_player' ? player : name === 'ytd-watch-flexy' ? watch : null;
  const globalEvents = new EventTarget();
  const context = {TextEncoder, URL, AbortController, crypto: {randomUUID}, Event,
    HTMLMediaElement: Media, HTMLVideoElement: Video, HTMLElement: Element,
    document, navigator: {mediaSession: {metadata: {title: 'Video'}}},
    location: {href: 'https://www.youtube.com/watch?v=abcdefghijk'},
    Date: {now: () => wallTime}, performance: {now: () => pageTime},
    addEventListener: globalEvents.addEventListener.bind(globalEvents)};
  const invoke = runInNewContext('(' + script + ')', context, {timeout: 1000});
  function send(request) { observations = 0; return JSON.parse(invoke({schemaVersion: 1, ...request})); }
  const read = () => send({operation: 'read'}).snapshot;
  const initial = read();
  function request(source = initial, phonePositionSeconds = 15, command = 'pause') {
    return {operation: 'command', commandID: randomUUID(), expected: {
      documentID: source.documentID, itemID: source.itemID, itemGeneration: source.itemGeneration}, command,
      handoff: {continuityID: source.playbackContinuityID, videoID: source.videoID,
        positionSeconds: source.elapsedTime, durationSeconds: source.duration, playbackRate: source.playbackRate,
        observedAtPageMilliseconds: source.observedAtPageMilliseconds, phonePositionSeconds},
      expiresAtPageMilliseconds: pageTime + 1500, expiresAtUnixMilliseconds: wallTime + 1500};
  }
  return {video, initial, read, request, send, pauses: () => pauses,
    advance(seconds) { pageTime += seconds * 1000; wallTime += seconds * 1000; video._time += seconds; },
    atFinalObservation(callback) { finalObservation = callback; },
    atFinalValidation(callback) { finalValidation = callback; }};
}

test('exact playing timeline pauses once and returns actual paused readback', () => {
  const f = fixture(); f.advance(1);
  const request = f.request(f.initial, 16);
  const result = f.send(request);
  assert.equal(result.status, 'ok'); assert.equal(result.snapshot.paused, true);
  assert.equal(f.pauses(), 1);
  assert.equal(f.send(request).status, 'ok'); assert.equal(f.pauses(), 1);
  const conflict = structuredClone(request); conflict.handoff.phonePositionSeconds = 40;
  assert.equal(f.send(conflict).status, 'staleContext'); assert.equal(f.pauses(), 1);
});

test('same-item pause-resume, seek-return, rate-return and buffering retire the old timeline', () => {
  for (const change of [
    v => { v.dispatchEvent(new Event('pause')); v.dispatchEvent(new Event('play')); },
    v => { v.currentTime = 40; v.currentTime = 15; },
    v => { v.dispatchEvent(new Event('ratechange')); },
    v => { v.dispatchEvent(new Event('waiting')); },
  ]) {
    const f = fixture(); change(f.video);
    const next = f.read();
    assert.equal(next.itemID, f.initial.itemID);
    assert.notEqual(next.playbackContinuityID, f.initial.playbackContinuityID);
    assert.equal(f.send(f.request()).status, 'staleContext'); assert.equal(f.pauses(), 0);
  }
});

test('late native timeline changes cannot hide behind an earlier successful observation', () => {
  for (const change of [v => { v._time = 80; }, v => { v.paused = true; },
    v => { v.playbackRate = 2; }, v => { v.duration = 60; },
    v => { v.dispatchEvent(new Event('pause')); v.dispatchEvent(new Event('play')); }]) {
    const f = fixture(); f.atFinalObservation(() => change(f.video));
    assert.equal(f.send(f.request()).status, 'staleContext'); assert.equal(f.pauses(), 0);
  }
});

test('wrong video, expired anchor, changed timeline and far-away phone positions fail closed', () => {
  for (const key of ['videoID', 'positionSeconds', 'durationSeconds', 'playbackRate',
    'observedAtPageMilliseconds', 'phonePositionSeconds']) {
    const f = fixture(), request = f.request();
    request.handoff[key] = key === 'videoID' ? 'lmnopqrstuv' :
      key === 'playbackRate' ? 2 : key === 'observedAtPageMilliseconds' ? 0 : 80;
    assert.notEqual(f.send(request).status, 'ok', key); assert.equal(f.pauses(), 0);
  }
});

test('an event during final validation cannot reuse the already-created snapshot continuity', () => {
  const f = fixture();
  f.atFinalValidation(() => {
    f.video.dispatchEvent(new Event('pause')); f.video.dispatchEvent(new Event('play'));
  });
  assert.equal(f.send(f.request()).status, 'staleContext'); assert.equal(f.pauses(), 0);
});

test('handoff is pause-only, strict and does not change ordinary command support', () => {
  const f = fixture();
  assert.equal(f.send(f.request(f.initial, 15, 'play')).status, 'failed');
  const invalid = f.request(); invalid.handoff.extra = true;
  assert.equal(f.send(invalid).status, 'failed'); assert.equal(f.pauses(), 0);
  for (const [key, value] of [['videoID', 12345678901], ['observedAtPageMilliseconds', Number.MAX_VALUE],
    ['positionSeconds', '15'], ['phonePositionSeconds', -1], ['durationSeconds', null]]) {
    const invalidField = f.request(); invalidField.handoff[key] = value;
    assert.equal(f.send(invalidField).status, 'failed', key); assert.equal(f.pauses(), 0);
  }
  const normal = f.request(); delete normal.handoff;
  assert.equal(f.send(normal).status, 'ok'); assert.equal(f.pauses(), 1);
});
