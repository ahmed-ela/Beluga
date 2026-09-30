# Multi-source notification controls

The iPhone app owns the existing authenticated WebRTC session. Its notification
content extension presents at most two sources (browser and Music), with shared
Previous/Next, Play/Pause and backward/forward 30-second buttons. A finite seekable
timeline also enables a draggable progress slider. Selecting a source affects these
controls only; it does not redirect native Now Playing or interrupt either player.
The first playing browser tab remains selected until it stops playing, then another
playing tab may take over. Starting another tab does not steal the current selection.

## Authority and lifecycle

- A separately negotiated catalog capability carries the secondary item. Legacy
  peers retain the existing single-item protocol. The complete encoded control
  envelope stays within 4 KiB; optional descriptive text is shortened when needed,
  never context, timing, capabilities, or transport authority.
- The extension does not create a second peer or audio session. A private App Group
  mailbox carries absolute, source-bound intents to the app. The app's existing
  owner/negotiation gate and the host's final admission still decide whether to act.
- Snapshots expire after five seconds, requests after two seconds. An elapsed-time
  revision advance does not invalidate an otherwise current context and capability;
  future revisions, unavailable sources, changed epochs and missing authority fail
  closed. There is no fallback from an unknown selected source to the primary item.
- Commands are durably claimed once. Only a matching host acknowledgement reports
  success; a contended mailbox retries the acknowledgement, never the command. A
  copied prepared native command also shares a one-shot execution latch.
- Successful same-item seeks preserve the source context; ambiguous outcomes and
  replacement still retire it. This keeps subsequent shared buttons on the selected
  source without permitting relative-command replay.
  On an actual track/context replacement the shared buttons require explicit source
  reselection; they never silently fall back to the other player.
- Journal history is bounded to 1,024 consumed IDs per epoch. At capacity the owner
  waits past the last command's deadline and acknowledgement window, then replaces
  the notification with a new epoch rather than evicting replay history under an old
  card. Transport, pairing, native Now Playing and audio routes are not restarted.
- Genuine application audio playback provides background eligibility. The extension
  adds no keepalive audio, VoIP mode, or workaround for system authentication.

## Packaging and tests

Both app and extension require the same explicit environment-specific App Group.
The extension explicitly links UserNotificationsUI: importing the module alone did
not load its extension-context class in the simulator. Release validation checks the
exact embedded extension, its executable/version/category, signing identities,
provisioning entitlement, and system-framework linkage.

The DEBUG simulator route `--beluga-notification-loopback` is restricted to the
development bundle and bypasses normal runtime construction. Two local native
WebRTC peers carry actual catalog, commands and acknowledgements while the real
notification extension uses the production mailbox. It neither contacts the user's
host nor operates a physical phone.

Source, mailbox, native backend, simulator UI, signed archive, upload, installed
host and physical Lock Screen results are separate evidence. A simulator pass is
not proof of physical locked behavior or actual Mac Chrome/Music effects. Reopening
the same delivered notification after dismissal is an explicit, non-skipped
simulator test; the physical locked release validation remains a roadmap item.

### Notification Center follow-up, 2026-09-30

The build-90 simulator tests passed fresh-banner controls, a real timeline-thumb
drag, and exact receiver acknowledgements. The follow-up same-delivered-notification
test now passes through the system's actual swipe-left → View action on the
dedicated iPhone 15 simulator (iOS 26.5). No production app or extension behavior
change was needed for this test-path correction.

Bounded diagnostic controls also failed to expand (1) a Beluga notification opened
for the first time directly from Notification Center, without opening its banner,
and (2) a plain system notification with one inert standard action and no content
extension. A subsequent positive-control check showed that plain notification's
standard action successfully in its fresh expanded banner, then failed to show
the action after opening the same card from Notification Center. The plain control
and original reopening test also failed after one restart of only the dedicated
simulator. Alternate title presses, unstacking,
backdrop dismissal and exposed simulator accessibility actions did not establish
expansion. Receiver logging subsequently showed SpringBoard recognizing a tap on
the intended card but hinting a side swipe instead of executing its default
action. Swiping left and tapping the visible system View button expanded the
plain notification and displayed its standard action. That diagnostic's cleanup
failed, so it is presentation evidence, not a whole-test pass. These observations
do not identify the cause of the long-press behavior or establish physical behavior.

The integrated reopening test uses that observed View path for three cycles. Before
source selection it requires current source labels, the shared controls and timeline.
After explicit selection it requires the current timeline and correct Play/Pause
state, then sends exactly one command: +30 seconds, Play and Pause respectively.
The native WebRTC loopback host must return the exact cumulative eight-command
ledger with revision 9, Browser paused at 90 seconds and Music paused at 300 seconds.
Fresh read-only inspections of the OS-delivered card must retain the same identifier,
delivery timestamp, epoch and category across all cycles. The test ends by proving
the isolated peers stopped. The focused run passed 1/1 in 145.714 seconds. After
removing temporary diagnostic-card cleanup, the final three-test suite passed
3/3 in 225.047 seconds: fresh controls (45.902 s), same-card reopening (147.497 s),
and real timeline drag plus track buttons (31.648 s), with zero skips or failures.

Evidence is retained under
`/Volumes/t7/beluga-notification-integration.WdpLEu/notification-controls90-reopen-view1.{log,xcresult}`,
with exported screenshots and accessibility snapshots beside it. The cleanup-free
suite is `notification-controls90-reopen-final.{log,xcresult}` in the same directory.
Earlier failed
diagnostics and their temporary patches remain in that private evidence directory;
temporary probes were removed from source. Only the simulator fixture's read-only
delivery inspector and the strengthened XCTest remain. No assertion was skipped,
no notification was replaced to manufacture reopening, and no new TestFlight build
was uploaded for these test-only changes. Physical locked-device validation and
real browser/Music effects remain separate requirements.

### External-pause follow-up, 2026-09-30

The user identified the stale state as the custom expanded notification with the
±30-second buttons, not the native Now Playing player. No deployed fix is claimed.

The isolated fixture now supports one bounded, cancellable, unsolicited host-side
pause of the exact Browser context. This uses the existing native WebRTC state lane,
real app coordinator/mailbox, and content extension; it does not send a notification
command or contact the live Mac. The task is fenced to its original host, viewer,
operation and context, and is canceled by fixture teardown. A 30-second delay allows
bounded system expansion and initial Playing/Pause evidence before the state change.

`testExternalHostPauseUpdatesExpandedCardBeforeNextPlayCommand` passed 1/1, with
zero failures or skips, in 66.003 seconds on the dedicated iOS 26.5 simulator.
While the same delivered card remained expanded, Browser changed from Playing/Pause
to Paused/Play without any notification control press. One subsequent Play press
restored Playing/Pause. Exact host evidence was revision 3, one command `A:play`,
and one separate external change at revision 2. The source context, timeline and
OS-delivered identifier/date/epoch/category remained unchanged. Screenshot pixels
and accessibility snapshots were inspected for all three states.

Evidence: `/Volumes/t7/beluga-notification-external-pause.zVpHUK/external-pause-1.{log,xcresult}`,
with exported attachments in the same private directory. Only simulator test code
and documentation changed; no production app/extension/host change or deployment
occurred. This does not exercise the real Mac player adapter, the production viewer
view model, physical background eligibility, or the user's iOS 27 notification
lifecycle. The missing diagnostic is a correlated production host revision, viewer
admission, App Group snapshot and expanded-card read/render. Reopening the same card
after an external pause is a useful discriminator between stale extension display
and upstream state, not a substitute for that evidence.

#### Mac observer starvation follow-up

The user confirmed the notification title matches the exact video being paused.
The bidirectional path exists: Mac player observation → controller state revision
→ WebRTC publication → viewer admission → App Group snapshot → extension UI.
The isolated simulator proof starts after Mac player observation; it did not test
that upstream boundary.

A new deterministic test using the production `MacChromeAppleEventsBackend` with
a fake native client reproduced an upstream defect before product edits: the exact
selected player freshly reads paused, then unrelated window inventory exhausts the
1.5-second caller deadline and discards that pause as `timedOut`. The failing
baseline was 1 test / 1 expected assertion failure. Live host logs also repeatedly
report `chrome=timedOut`, but lack the correlation needed to prove this is the
exclusive cause of the user's physical notification symptom.

The source patch reserves 350 ms of the existing caller budget for publication
after a fresh exact paused-owner read, bounding speculative census and successor
scanning without extending the overall deadline. Only speculative census timeout
may fall back to that fresh read; selected-read failure cannot borrow a cached
hint. Final owner, permission and overall-deadline checks remain, as does the
selected-owner reread before handing off to another playing source.

121 focused Mac Chrome/composite/controller/protocol tests passed with zero
failures. Added coverage includes permission/owner changes during census, outer
deadline overrun, healthy successor handoff, resumed-owner retention, and an
external pause through the actual backend → runtime → composite → controller
pipeline. That pipeline publishes paused revision 2 with the same context and
`canPlay`, with zero playback commands. Independent read-only review found no
blocking issue in the focused patch.

Evidence: `/Volumes/t7/beluga-mac-pause-observer.TXQmV9/RESULTS.md`,
`paused-observation-red.log`, and `focused-green.log`. The live host, browser,
phones and audio routes were untouched. This is not deployed-host or physical
iPhone proof; the production notification issue remains open pending that check.

#### Production iOS consumer isolation follow-up

The Mac-only observer repair subsequently reached guarded `COMMITTED_CANDIDATE`
on September 30 at 18:04:54Z. The user still reported stale notification state in
TestFlight build 90. No production iOS fix was included in that Mac deployment.

The earlier native-loopback notification fixture bypasses
`WorldwideSessionViewModel`. A new hosted Simulator regression feeds its actual
ordered event consumer, production BackgroundPlaybackCoordinator, and configured
App Group store. While the statistics path's native audio read is deliberately
held, an unsolicited same-context pause revision cannot reach the mailbox: it
remains revision 2 / Playing instead of revision 3 / Paused. The failing baseline
cleanly releases the held reader. This proves a scheduling defect, not exclusive
causation of the remote physical-phone report.

The repair keeps immediate statistics/journal publication on the event consumer,
but isolates suspending proof work in one retained worker plus one latest-pending
sample. Original collection timestamps and sequence are retained. Cancellation,
peer/session, audio policy and transport fences reject retired results; a canceled
native read keeps its slot until actual return. No audio-route, capture-permission,
user-intent, or notification-command authority is broadened.

Focused red evidence: `/Volumes/t7/beluga-notification-live-state.mUyXI6/blocked-statistics-red-2.xcresult`.
The first attempt in that directory failed fixture endpoint validation and is not
defect evidence. `audio-notification-green.xcresult` passes 485 tests with zero
failures and 22 existing physical/opt-in skips on the dedicated signed iOS 26.5
Simulator. All three new regressions pass: held-read pause publication, latest-only
statistics coalescing, and transport revocation rejecting pending/late proof.
The pinned Rust audio contract also passes 35 tests.

`expanded-notification-green.xcresult` separately passes the actual expanded-card
external-pause test (1/1, zero skips, 65.071 seconds). Its screenshots show Pause
→ Play after the unsolicited pause and Pause after one explicit Play; native test
host evidence records one command `A:play`, one external change, and final revision
3. This fixture still bypasses the production view model; the hosted regression
above covers that formerly missing boundary. Neither is remote physical-iPhone
proof. Build 91 is the intended iOS release; distribution and the user's phone
verification remain separate evidence stages.
