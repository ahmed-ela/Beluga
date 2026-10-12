# Beluga browser audio sharing — additive v1 protocol

Status: **source implementation only; production disabled and not deployed**.
The Worker registry, browser receiver, native audio-only sender, and menu-bar
coordinator are implemented. Production capture uses the real system-audio callback;
there is no synthetic PCM/clock or microphone capture in the product path. Tests use
explicitly isolated fixture audio only. Native expiry/lease and teardown unit tests
pass. The opt-in native-to-Chrome oracle also passes real stereo decoding with an
explicit synthetic fixture source and a loopback broker. System-audio capture,
phone coexistence, and deployed end-to-end validation remain separate requirements.

The existing phone `/v1/rendezvous` and `/v2/availability` contracts, native headers,
subprotocols, crypto, Durable Object schema, and ownership are unchanged.

## Access and deployment boundaries

- A link is a reusable **listen-only bearer capability**, not an identity or an
  invitation to control the Mac. Anyone it is forwarded to can listen until expiry
  or revoke. This cannot prevent recipients from forwarding or recording audio.
- The 16-byte public share ID is a locator, not authentication: four big-endian
  Unix-second birth bytes plus 12 random bytes (96 random bits). The independently
  random 256-bit listener root exists only in the URL **fragment** and client memory.
  The independent 256-bit owner root is never part of a listener link.
- No secrets in URL query/path, WebSocket subprotocol, logs, analytics, local
  storage, or error strings. The page clears its fragment immediately. No third-party
  scripts, discovery/index endpoint, microphone, camera, or display-capture permission.
- Production `AUDIO_SHARE_ENABLED="false"` keeps **all** new routes and assets dark.
  `run_worker_first=true` prevents direct static-asset bypass. Test configuration alone
  enables the local protocol. Do not change the flag or deploy until native integration,
  independent review, and end-to-end expiry/revoke/current-phone coexistence tests pass.
- Additive `AudioShareSession` uses its own `AUDIO_SHARE` binding and migration
  `v2-audio-share`. The separate `AUDIO_SHARE_BUDGET` binding/migration
  `v3-audio-share-budget` owns one global admission authority, not a phone object.
  Never reuse the phone's `RENDEZVOUS` objects or occupy its viewer.
- Hosts register a fresh birth-fenced ID before publishing a link. There is no resume,
  renewal, replacement owner, or reconnect of an ended share. A new share gets new ID
  and roots. Birth-window admission forbids old IDs even after safe tombstone
  collection; account/WAF quotas and storage cost still need production review.

## Anonymous-sharing resource containment

Private bearer-link access does not require accounts. Creation is anonymous and
therefore still subject to denial of service by callers exhausting the finite
global allowance. These source controls bound creation and issuance, not user
identity or billable TURN bandwidth. Production remains disabled.

- Registration accepts locator births only within server-now minus 180 seconds
  through server-now plus 30 seconds. Ordinary random/timeless IDs are not a
  registration mode. Terminal tombstones are collected only at birth + 24 hours
  + 180 seconds + 30 seconds, including when sharing is disabled. That exceeds
  every admitted original lifetime. The old locator is then too old to register,
  so deleting its tombstone cannot resurrect its old bearer link.
- One fixed `AudioShareBudget("global-v1")` serializes reservations before durable
  share registration. Default rolling-day creation cap is 100 (configuration
  `AUDIO_SHARE_DAILY_CREATION_LIMIT`, range 1–1,000); active grant cap is 32
  (`AUDIO_SHARE_ACTIVE_GRANT_LIMIT`, range 1–128). Entries retain only locator,
  server-created time and immutable server expiry, at most the daily cap, and
  are pruned after their rolling-day window. Clock regression, corrupt storage,
  invalid configuration, or unavailable authority fails closed.
- Reservations are **not** released when a share/socket closes. They occupy
  active capacity until their originally granted expiry, avoiding stale-release
  races. Failed/uncertain reservations may spend an allowance without creating
  a share; retry uses fresh material. This conservative behavior is intentional.
- Each share spends at most 64 cumulative authenticated listener/ICE issuances,
  including failed upstream requests, separately from the eight active listener
  maximum. Wrong proofs and full active slots spend no issuance. The counter is
  durable across listener churn/hibernation.
- Sharing uses only `AUDIO_SHARE_TURN_KEY_ID` and
  `AUDIO_SHARE_TURN_API_TOKEN`, plus `AUDIO_SHARE_TURN_CREDENTIAL_TTL_SECONDS`
  and `AUDIO_SHARE_TURN_FETCH_TIMEOUT_MS`. It never falls through to phone TURN
  credentials/configuration. With neither sharing secret present it uses STUN;
  a partial/invalid sharing secret pair fails closed. Credentials never exceed
  the remaining immutable share life. Separate sharing-key billing controls must
  be verified before enablement. Defaults bound aggregate issuance to 100
  creations × 64 attempts per rolling day, not aggregate media bytes.
- Incoming session messages reserve a bounded 32-task/512-KiB queue before
  appending async work; wire length is checked before UTF-8 allocation. Owner
  overflow immediately revokes the in-memory admission gate and closes sockets,
  then persists terminal state serially. A held TURN completion cannot admit a
  listener afterward. Listener overflow retires that listener only. The global
  reservation authority separately bounds its pending work to 32 requests.

Pre-enable review still needs WAF/bot rules, sharing TURN bandwidth/billing
limits, and nonsensitive operational counters. No credentials, bearer roots,
media payloads or private source identities belong in diagnostics. Per-edge
actor/channel throttling is defense in depth, not a replacement for the
consistent global creation budget.

Verify budget exhaustion/refill, actor/ID rotation, listener churn, failed TURN
requests, and registry growth before enabling. The native/live expiry, revoke,
coexistence, and audio-reception gates below remain independently required.

## Exact wire contract

All messages are bounded UTF-8 JSON with version `v:1`. IDs are canonical unpadded
base64url encodings of 16 bytes; roots/proofs are canonical encodings of 32 bytes.
Use `GET WSS /v3/audio-share/<publicShareID>` with exact fixed subprotocol
`beluga.audio-share.v1`; no query, Authorization header, or capability subprotocol.
Browser Origin must match its served origin (or an explicitly configured
`AUDIO_SHARE_BROWSER_ORIGIN`). Native requests may omit Origin.

The unauthenticated upgrade is not admission. Its first frame must arrive within
5 seconds, contain at most 2,048 bytes, and be exactly one of:

```json
{"type":"register","v":1,"ownerProof":"<32 bytes>","listenerProof":"<different 32 bytes>","ttlSeconds":600,"maxListeners":8}
{"type":"authenticate","v":1,"proof":"<listener admission proof>"}
```

Register creates an immutable server deadline from a TTL of 1–86,400 seconds and
listener bound 1–8. Only proof hashes are stored. Authentication precedes listener
occupancy, random listener-ID allocation, or TURN provisioning. At most 16 pending
sockets exist. Owner registration does not provision TURN. Authenticated listener
joins provision only bounded ICE credentials whose TTL does not exceed the remaining
share life; configured managed TURN rejects joins with under 60 seconds remaining.
Direct-STUN-only development does not prove worldwide reachability.

Successful owner registration:

```json
{"type":"registered","v":1,"shareID":"...","generation":"...","expiresAt":1800000600000,"serverTime":1800000000000,"leaseExpiresAt":1800000015000,"maxListeners":8}
```

Each admitted listener yields the same context to owner and listener, with their
respective `role`. ICE credentials are ephemeral and never persisted:

```json
{"type":"listener-ready","v":1,"role":"owner|listener","shareID":"...","generation":"...","listenerID":"...","expiresAt":1800000600000,"serverTime":1800000000000,"iceServers":[]}
```

Host-only bounded probes keep an application lease current (recommended every
5 seconds, hard server lease 15 seconds), independently of immutable share expiry:

```json
{"type":"probe","v":1,"nonce":"<16 bytes>"}
{"type":"probe-ack","v":1,"nonce":"<same bytes>","serverTime":1800000005000,"leaseExpiresAt":1800000020000}
{"type":"revoke","v":1}
{"type":"retire-listener","v":1,"listenerID":"<16 bytes>"}
```

Only the current authenticated owner socket can revoke, probe, or retire a
listener. Retirement closes exactly the matching current-generation listener and
returns `listener-left` to the owner; unknown/stale IDs only acknowledge that
target. It does not end the share or release a creation/issuance budget, and
listeners cannot use it to affect siblings. Revoke persists the
tombstone before closing all admitted and pending sockets. Expiry applies to
**already admitted** listeners, not only bootstrap. Owner disappearance, stale
application lease, failed owner delivery, or corrupt durable state fail closed.
Alarm, join, and message paths all enforce deadlines; delayed TURN completion
cannot install a grant after a deadline or owner loss.

```json
{"type":"ended","v":1,"reason":"expired|revoked|owner_lost"}
{"type":"error","v":1,"error":"<fixed code>"}
{"type":"listener-left","v":1,"listenerID":"..."}
```

Only owner-to-that-listener or that-listener-to-owner encrypted signals are routed.
Each direction starts at sequence zero and advances by exactly one per listener:

```json
{"type":"signal","v":1,"listenerID":"...","seq":0,"ciphertext":"<AES-GCM bytes in canonical base64url>"}
{"type":"signal","v":1,"from":"owner|listener","listenerID":"...","seq":0,"ciphertext":"<unchanged bytes>"}
```

Wire limit is 90,000 bytes; ciphertext is 17–65,536 bytes; plaintext is at most
49,152 bytes; maximum sequence is 2,147,483,647; connection rate is 300 messages/minute.
Native send queues must serialize encryption and WSS writes so sequence assignment
cannot reorder packets. A listener cannot target another listener, revoke, issue
controls, receive phone microphone audio, or cause phone/viewer eviction.

## Byte-exact crypto (Swift counterpart)

`\0` below denotes one NUL byte; all labels/decimal numbers use UTF-8 with no BOM,
padding, trailing separators, or JSON canonicalization. All secret roots are 32
random bytes. The same crypto code is imported by browser and Worker; the Worker
receives admission proofs, **never** a signaling encryption root.

Admission proof for role `owner`/`listener`:

```text
HKDF-SHA256(input: role's independently random root,
            salt: raw shareID[16],
            info: "Beluga.AudioShare.v1\0admission\0" + role,
            output: 32 bytes)
stored verifier = SHA256(UTF8("Beluga.AudioShare.v1\0verifier\0" + base64url(proof)))
```

Signaling uses the **listener root**, not the admission proof. For each directional
key, derive a fresh 32-byte AES-256-GCM key:

```text
HKDF-SHA256(input: listener root,
            salt: raw shareID[16],
            info: "Beluga.AudioShare.v1\0signal\0" + generation + "\0" +
                  listenerID + "\0" + expiresAtDecimal + "\0" + direction,
            output: 32 bytes)
direction = "ownerToListener" or "listenerToOwner"
IV = 8 zero bytes || sequence as unsigned big-endian UInt32
AAD = UTF8("Beluga.AudioShare.v1\0" + shareID + "\0" + generation + "\0" +
           listenerID + "\0" + expiresAtDecimal + "\0" + direction + "\0" + sequenceDecimal)
ciphertext = encrypted UTF8 JSON || 16-byte GCM tag
```

Generation/listener IDs are fresh server randomness; role keys differ; each context
admits one strictly increasing nonce sequence. Any schema, role, context, sequence,
tag, or decrypted-payload error ends that peer. No plaintext candidate/SDP is logged.
JSON signal payloads are only `{"kind":"offer|answer","sdp":"..."}` or
`{"kind":"ice","candidate":{"candidate":"candidate:...","sdpMid":"0","sdpMLineIndex":0,"usernameFragment":"..."}}`.

The browser permits exactly one audio-only Opus/48k/stereo sendonly offer, answers
recvonly with an explicit `stereo=1` preference, never obtains local media, rejects data channels/video/additional media,
and fences ICE to the effective mid/m-line/ice-ufrag. At most 256 pre-offer candidates
are retained. Overlap/restart and signaling loss are terminal in this first slice.

## Native integration and release gate

**Closing WSS does not stop already established DTLS-SRTP.** The native owner must
bind each sender to this exact share/generation/listener/expiry and a monotonic local
deadline calculated from `expiresAt-serverTime`. Missing current nonce-probe ACK,
WSS uncertainty, disconnect, expired lease, expired share, or revoke must synchronously
revoke that listener's PCM gate, disable its track, and close its peer. Never rely on
the browser countdown/JavaScript timer for access control. No new expiry can extend
an existing authorization.

The intended smallest native slice owns one separate `SystemAudioCaptureSource`
for all browser listeners, independent of the phone source. Deliver each complete
borrowed callback synchronously on that source's existing serialized clock to at
most eight per-listener revocable sinks. Keep the native custom ADM's stereo render
copy, raw AEC/NS/AGC/HPF-off, native StartRecording generation proof, existing mirroring
exclusion and real-output clock guards. Never introduce PCM queues, padding, timers,
fake clocks, default-route writes, microphone leases, video, or remote controls.
Share teardown must not use process-wide WebRTC audio gates or close phone factories.
Two simultaneous real capture taps are an explicit bounded overhead tradeoff.

Required before enabling/deployment: native/JS cross-language crypto vectors, exact
sender generation admission and callback-size tests, real audio received by a browser,
active expiry/revoke/owner-WSS-loss stopping actual audio, forced-TURN unrelated-network
coverage, source-start failure and resource/churn coverage, and unchanged phone
peer/audio/microphone/routes during listener join/leave/revoke. The native/browser
fixture proves encoded/decoded stereo and teardown, not the remaining live properties.

## Local source verification

```sh
cd browser/beluga-audio
npm test
cd ../../services/RendezvousWorker
npm ci
npm test
WRANGLER_SEND_METRICS=false npm run check
```

Browser tests use pure protocol code, independent Node HKDF/AES vectors and a
mock RTC boundary. Worker tests use real local Durable Objects, hibernation, admission,
expiry, revoke, owner leases, fan-out bounds and mocked TURN. `check` is a production
bundle **dry run**, not deployment. There is intentionally no fake audio fallback.

### Opt-in native-to-browser final-sample oracle

See [`test/native-oracle/README.md`](test/native-oracle/README.md). The fixture is
deliberately separate from ordinary unit tests and product capture. It must be
invoked explicitly with an exact compiled XCTest bundle; a skipped XCTest is not
a passing browser oracle.
