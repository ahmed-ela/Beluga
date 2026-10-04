# Beluga Cloudflare rendezvous

This Worker is the public signaling control plane for Beluga's direct WebRTC path. It deploys to a stable `workers.dev` hostname and routes each unguessable channel to one SQLite-backed Durable Object. The Worker and Durable Object never relay media or decrypt signaling envelopes.

The public surface is deliberately small:

- `GET /healthz` returns `{"ok":true}` and no session data.
- `WSS /v1/rendezvous` carries one-use invitation bootstrap and fresh one-use media-session signaling. New durable-pairing bootstrap clients must negotiate `audiostreamer.pairing.v1`; their Durable Object key uses a `pairing:` namespace disjoint from legacy v1 rendezvous.
- `WSS /v2/availability` carries only persistent paired-device availability. The distinct path makes new clients fail closed against an old Worker instead of being interpreted as invitation traffic.
- Channel, role, and the joining role's proof are accepted only in bounded `X-AudioStreamer-Channel`, `X-AudioStreamer-Role`, and `X-AudioStreamer-Admission` upgrade headers. Availability hosts additionally register the independently derived viewer capability in `X-AudioStreamer-Viewer-Admission`, send exact mode `availability`, and require the Worker to echo `Sec-WebSocket-Protocol: audiostreamer.availability.v1`; viewers never send the registration header. Pairing clients require an exact `audiostreamer.pairing.v1` echo. Query strings, missing/unknown required subprotocols, role-swapped proofs, availability headers on v1, and alternate paths are rejected.

The additive browser audio-share registry and static receiver are **production disabled**
(`AUDIO_SHARE_ENABLED="false"`), undeployed, and not a native audio sender. They use a
separate `/v3/audio-share/<publicID>` first-frame-authenticated protocol and
`AudioShareSession` Durable Object and fixed global `AudioShareBudget` authority,
never the phone invitation/availability modes. Creation defaults to 100 per
rolling day and 32 unexpired grants; each share allows at most 64 cumulative
listener/ICE issuances and eight active listeners. Birth-fenced public locators
permit safe finite tombstone collection without admitting an old link again.
See [the exact protocol and integration gates](../../browser/beluga-audio/README.md).
Do not enable/deploy these routes before native sender integration and live expiry,
revocation, and phone-coexistence validation. Existing v1/v2 joins remain unchanged.

The `X-AudioStreamer-*`, `audiostreamer.pairing.v1`, and
`audiostreamer.availability.v1` spellings are deployed v1 compatibility ABI. They intentionally
retain the former product name so Beluga clients remain compatible with existing releases.

Invitation Durable Objects store the first host's admission proof, expiration, consumed bit, and a bounded tombstone. They compare the viewer's 32-byte proof before checking viewer occupancy, consuming the invitation, or provisioning TURN. Availability Durable Objects use a separate `availability:<channel>` namespace and retain distinct host and viewer capabilities so one host can coordinate a sequence of viewer reconnections without either proof claiming the opposite role. Hibernating WebSocket attachments retain mode, role, generation, active exchange ID, next sequence, last activity, and rate-window state. No source path logs channels, proofs, payloads, TURN identifiers, tokens, or credentials.

## Paired-device availability

Availability mode is an opaque coordination path, not device authentication. The Worker checks only possession of the appropriate role-specific 32-byte capability. The Mac and iPhone remain responsible for authenticating their persistent device identities, verifying signed pairing/session transcripts, deriving the availability channel and capabilities, and encrypting every payload.

The first capability-authorized host creates the persistent availability record and normally remains connected while viewers join one at a time. A later same-role host with the same capability replaces a stale host socket and receives a fresh exchange with the current viewer. A replacement viewer can retire an unresponsive exchange and force the host to register again before the viewer retries. Each accepted pair gets a fresh server-generated canonical 128-bit exchange ID. Join, replacement, and departure mutations are serialized and fenced so a delayed stale callback cannot clear a newer exchange.

Availability mode never provisions or returns TURN credentials. It carries only bounded encrypted coordination envelopes used by endpoints to establish a fresh one-use media rendezvous. Each envelope must bind the availability channel, server exchange ID, sender direction, and monotonic per-exchange sequence outside the opaque ciphertext, and endpoints must authenticate those fields as encryption AAD; mismatches fail closed.

After a valid waiting or ready state, the Mac sends periodic host-only application probes in addition to WebSocket ping/pong. The Worker echoes the nonce only for the current capability-authorized host connection. Missing acknowledgements make the Mac close and reconnect its socket; probes count toward the message-rate limit but never change exchange or encrypted signaling sequence state.

```text
server -> {"type":"availability-waiting"}
server -> {"type":"availability-ready","role":"host|viewer","exchangeID":"<128-bit Base64URL>"}
client -> {"type":"availability-signal","exchangeID":"...","seq":0,"envelope":"<canonical Base64URL>"}
server -> {"type":"availability-signal","from":"host|viewer","exchangeID":"...","seq":0,"envelope":"<unchanged Base64URL>"}
host -> {"type":"availability-probe","nonce":"<128-bit canonical Base64URL>"}
server -> {"type":"availability-probe-ack","nonce":"<same value>"}
server -> {"type":"availability-peer-left","role":"host|viewer","exchangeID":"..."}
```

## Local verification

Requires Node.js 20 or newer.

```sh
npm ci
npm test
npm run check
npm run dev
```

The pinned Vitest/Workers pool runs the tests in the Workers runtime with a real local Durable Object. Tests cover strict paths/headers/envelopes, viewer-before-host retry safety, role-swapped and replacement-proof rejection, direct-STUN readiness, unchanged forwarding, hibernation recovery, peer departure, consume-once rejection, and non-disclosure through application logs. `npm run check` performs a local Wrangler production bundle dry run and does not deploy.

## TURN modes

With neither TURN secret configured, `ready` contains only the `STUN_URLS` configured in `wrangler.toml`. This is useful for direct ICE and development, but it does **not** provide worldwide reliability: restrictive NAT, CGNAT, and firewalls still require TURN.

For production, create a Cloudflare Realtime TURN key and set both server-side secrets:

```sh
npx wrangler secret put CLOUDFLARE_TURN_KEY_ID
npx wrangler secret put CLOUDFLARE_TURN_API_TOKEN
```

If exactly one secret is present, or credential provisioning times out or returns an invalid response, the viewer is rejected with `turn_unavailable`; the invitation is not consumed. The Worker accepts only a bounded `201 application/json` response, restricts provisioned ICE URLs to Cloudflare's expected `stun.cloudflare.com` and `turn.cloudflare.com` hosts and STUN/TURN transports, normalizes strict password-credential schemas, and never persists generated credentials. `.dev.vars.example` documents local secret names; `.dev.vars` is ignored.

Sharing uses **separate** server-side `AUDIO_SHARE_TURN_KEY_ID` and
`AUDIO_SHARE_TURN_API_TOKEN` secrets and `AUDIO_SHARE_TURN_*` configuration. It
never reuses the existing phone TURN secrets. Without both sharing secrets,
sharing stays direct-STUN-only; a partial configuration rejects listener grants.
Review the sharing key's relay bandwidth/billing ceiling independently before
enabling the feature. Anonymous global capacity exhaustion remains possible; the
conservative budget protects bounded aggregate work, not per-user fairness.

## Deployment

The default production Worker name preserves the existing installed-client origin.
Do not override it with a renamed Worker: existing pairing and media clients do not
discover a second origin. Before any deployment or secret write, verify the personal
Cloudflare account and TURN billing configuration; do not select a different organization.
Account selection and credentials remain private deployment inputs, not source files.

After the sharing integration gates above pass, deploy explicitly:

```sh
npm ci
npm test
npm run check
npm run deploy
```

Wrangler's migrations retain `RendezvousSession` and add the separate sharing classes.
Keep existing bindings, stored objects and phone TURN secrets intact. The production
default remains sharing-disabled until the separately authorized enablement step.
For the existing installation, the stable endpoint is:

```text
wss://audiostreamer-rendezvous.elaminahmed03.workers.dev
```

Configure the Mac and iOS clients with that origin only; their shared Swift clients append `/v1/rendezvous` for invitation/media sessions and `/v2/availability` for durable paired reconnect coordination. Do not put a channel, role, proof, or pairing code in the URL. Deploy this Worker contract before the matching Mac and iOS clients. The media path prefers direct WebRTC ICE and uses TURN only when direct connectivity fails.

For an existing installation, a Worker-name change is an infrastructure migration, not a wire
protocol migration. During a staggered client rollout, deploy the updated contract at the existing
stable origin whenever possible. If both old and new origins must run temporarily, switch each
paired Mac and iPhone to the same origin as one coordinated rollout and keep both Workers available
until every deployed endpoint has moved. Each client uses one configured origin; it does not
discover or retry a second origin. Retiring the existing Worker too early makes
otherwise compatible old and new clients unable to rendezvous.

The included `JOIN_RATE_LIMITER` binding limits syntactically valid upgrades per edge-observed actor and per channel before a Durable Object is invoked. Its numeric namespace must remain unique within the Cloudflare account; change `namespace_id` before deployment if `1001001` is already used. Cloudflare's binding is intentionally local and eventually consistent, so account-level WAF/bot rules remain useful defense in depth. Per-connection message limits are enforced inside each Durable Object, while the one-object-per-channel design serializes role occupancy and consume-once state.

## Wire behavior

The control messages match the Node rendezvous implementation:

```text
server -> {"type":"waiting","invitationExpiresAt":"..."}
server -> {"type":"ready","role":"host|viewer","invitationExpiresAt":"...","iceServers":[...]}
client -> {"type":"signal","seq":0,"envelope":"<canonical Base64URL>"}
server -> {"type":"signal","from":"host|viewer","seq":0,"envelope":"<unchanged Base64URL>"}
server -> {"type":"peer-left","role":"host|viewer"}
server -> {"type":"error","error":"<bounded_code>"}
```

Signals must start at sequence zero and increase by exactly one for each sender. The outer message, decoded sealed-envelope schema, channel, direction, inner sequence, ciphertext encoding, total wire size, and message rate are all bounded before forwarding.
