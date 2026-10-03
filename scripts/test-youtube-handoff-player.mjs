// Exercises the production embedded script with a provider double, not YouTube/network playback.
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {runInNewContext} from 'node:vm';
import assert from 'node:assert/strict';
import test from 'node:test';

const path = fileURLToPath(new URL('../iOS/opensteamer/Sources/MediaHandoff/YouTubeHandoffPlayer.swift', import.meta.url));
const source = readFileSync(path, 'utf8');
const match = source.match(/<\/head><body><div id="player"><\/div><script>\n([\s\S]*?)\n\s*<\/script>/);
assert.ok(match, 'exact production script must be found');
let script = match[1];
for (const [expression, value] of [
  ['request.operationID.uuidString.lowercased()', '00000000-0000-0000-0000-000000000001'],
  ['pageID.uuidString.lowercased()', '00000000-0000-0000-0000-000000000002'],
  ['request.videoID', 'dQw4w9WgXcQ'], ['request.positionSeconds', '20.0'],
  ['request.playbackRate', '1.0'], ['origin', 'https://org.example.audiostreamer.dev'],
]) script = script.replaceAll(`\\(${expression})`, value);
assert.ok(!script.includes('\\('), 'unhandled Swift interpolation must fail the oracle');

// Deliberately regress the extracted production script in memory, never the checkout.
// Each named mutation must make the same behavioral assertions fail (exit 1).
const mutation = process.env.BELUGA_HANDOFF_SCRIPT_MUTANT;
if (mutation) {
  const mutations = {
    identity: ["? ids[0] : '';", "? expected : '';"],
    visibility: ["if(!ready || !visible || retired || document.visibilityState==='hidden') return;\n            const rates=", "if(!ready || retired) return;\n            const rates="],
    cleanup: ["clearInterval(timer);if(player)player.destroy();", "if(player)player.pauseVideo();"],
  };
  const change = mutations[mutation];
  assert.ok(change, 'known mutation required');
  assert.equal(script.split(change[0]).length, 2, 'mutation must target exactly one production boundary');
  script = script.replace(change[0], change[1]);
}

function fixture() {
  const messages = [], actions = [], events = {}, timers = new Map();
  let options, milliseconds = 0;
  const player = {
    videoURL: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ', time: 20, state: 2, rate: 1,
    getVideoUrl() { return this.videoURL; }, getCurrentTime() { return this.time; },
    getDuration() { return 200; }, getPlaybackRate() { return this.rate; },
    getPlayerState() { return this.state; }, getAvailablePlaybackRates() { return [1, 2]; },
    seekTo(...args) { actions.push(['seek', ...args]); }, setPlaybackRate(value) { actions.push(['rate', value]); },
    playVideo() { actions.push(['play']); }, pauseVideo() { actions.push(['pause']); },
    cueVideoById(value) { actions.push(['cue', value.videoId, value.startSeconds]); },
    destroy() { actions.push(['destroy']); },
  };
  const document = {visibilityState: 'visible', addEventListener(name, callback) { events[name] = callback; },
    createElement() { return {}; }, head: {appendChild(node) { assert.equal(node.src, 'https://www.youtube.com/iframe_api'); }}};
  const window = {webkit: {messageHandlers: {belugaYouTubeHandoff: {postMessage(value) { messages.push(value); }}}},
    addEventListener(name, callback) { events[name] = callback; }};
  const context = {window, document, URL, performance: {now: () => milliseconds},
    YT: {Player: function (_, value) { options = value; return player; }},
    setInterval(callback) { timers.set(1, callback); return 1; }, clearInterval(id) { timers.delete(id); }};
  runInNewContext(script, context, {timeout: 1000});
  window.belugaHandoffTimeline(20);
  window.onYouTubeIframeAPIReady();
  return {player, window, document, messages, actions, events, timers,
    options, advance(seconds) { milliseconds += seconds * 1000; },
    ready() { options.events.onReady(); }, sample() { timers.get(1)?.(); }};
}

test('loading and user-play delay follow the advancing Mac timeline without widening drift', () => {
  const f = fixture(); f.window.belugaHandoffVisibility(true); f.advance(8); f.ready();
  assert.deepEqual(f.actions.find(a => a[0] === 'seek'), ['seek', 28, true]);
  f.options.events.onAutoplayBlocked(); f.advance(4);
  f.player.state = 1; f.options.events.onStateChange();
  assert.deepEqual(f.actions.filter(a => a[0] === 'seek').at(-1), ['seek', 32, true]);
  const seeks = f.actions.filter(a => a[0] === 'seek').length;
  f.player.state = 2; f.options.events.onStateChange();
  f.advance(10); f.player.state = 1; f.options.events.onStateChange();
  assert.equal(f.actions.filter(a => a[0] === 'seek').length, seeks,
    'normal local pause and play must not reseek or create new handoff authority');
});

test('production script keeps native controls, real identity and finite start position', () => {
  const f = fixture();
  assert.equal(f.options.playerVars.controls, 1);
  assert.equal(f.options.playerVars.autoplay, 0);
  assert.equal(f.options.playerVars.origin, 'https://org.example.audiostreamer.dev');
  f.ready();
  assert.deepEqual(f.actions, [['cue', 'dQw4w9WgXcQ', 20]]);
  assert.deepEqual(f.messages.map(m => m.kind), ['ready']);
  f.window.belugaHandoffVisibility(true);
  assert.deepEqual(f.actions.slice(1), [['seek', 20, true], ['rate', 1], ['play']]);
});

test('visible-before-provider-ready starts only when provider is ready', () => {
  const f = fixture();
  f.window.belugaHandoffVisibility(true);
  assert.equal(f.actions.length, 0);
  f.ready();
  assert.equal(f.actions.at(-1)[0], 'play');
});

test('blocked autoplay and provider samples are observations, never a success claim', () => {
  const f = fixture(); f.ready(); f.window.belugaHandoffVisibility(true);
  f.options.events.onAutoplayBlocked();
  assert.equal(f.messages.at(-1).kind, 'blocked');
  f.player.state = 1; f.player.time = 20.3; f.sample();
  assert.equal(f.messages.at(-1).kind, 'sample');
  assert.equal(f.messages.at(-1).position, 20.3);
  assert.equal(f.messages.at(-1).video, 'dQw4w9WgXcQ');
  assert.ok(f.messages.every((m, i) => m.sequence === i + 1));
});

test('wrong/ambiguous provider identity is not replaced with the expected video', () => {
  const f = fixture(); f.ready(); f.window.belugaHandoffVisibility(true);
  f.player.videoURL = 'https://www.youtube.com/watch?v=aaaaaaaaaaa'; f.sample();
  assert.equal(f.messages.at(-1).video, 'aaaaaaaaaaa');
  for (const url of ['https://evil.example/watch?v=dQw4w9WgXcQ',
    'https://www.youtube.com/watch?v=dQw4w9WgXcQ&v=aaaaaaaaaaa']) {
    f.player.videoURL = url; f.sample(); assert.equal(f.messages.at(-1).video, '');
  }
});

test('hidden page tears down player and timer and cannot emit after reappearance', () => {
  const f = fixture(); f.ready(); f.window.belugaHandoffVisibility(true);
  f.document.visibilityState = 'hidden'; f.events.visibilitychange();
  assert.equal(f.actions.at(-1)[0], 'destroy');
  assert.equal(f.timers.size, 0);
  const count = f.messages.length;
  f.document.visibilityState = 'visible'; f.window.belugaHandoffVisibility(true); f.sample();
  assert.equal(f.messages.length, count);
});
