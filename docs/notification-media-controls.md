# Multi-source notification controls

The iPhone app owns the existing authenticated WebRTC session. Its notification
content extension presents at most two sources (browser and Music), with shared
Play/Pause and backward/forward 30-second buttons. Selecting a source affects these
buttons only; it does not redirect native Now Playing or interrupt either player.
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
the same delivered notification after dismissal remains an explicit, non-skipped
test and roadmap item until the integrated build demonstrates it.
