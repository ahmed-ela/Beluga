# Beluga Mac distribution

The versioned client builder, verifier, and packager in `macOS/scripts` prepare a
signed, notarized, stapled DMG and a signed Sparkle 2.10 appcast. They do not publish,
install, launch a host, install an audio driver, or prove physical microphone PCM.
The historical host tools keep their separate protected-runtime contracts.

## Stable update channel

The Mac feed is pinned to the `mac-update-stable` release asset:

`https://github.com/ahmed-ela/Beluga/releases/download/mac-update-stable/appcast.xml`

It must not use repository-wide `releases/latest`, which unrelated iOS or other
releases can displace. The signed appcast points to the immutable versioned DMG
under `mac-v<version>`; it does not redirect its payload through the stable channel.

After the normal release gates and explicit publication authority:

1. Publish the exact verified DMG under its versioned release tag. Never replace
   that payload with different bytes under the same URL.
2. Read back its byte length, digest, and public availability against `package.json`.
3. Promote the exact signed `appcast.xml` to `mac-update-stable` **last**, then read
   back and verify its signature, digest, version, and versioned enclosure URL.

The stable channel is deliberately mutable metadata, not an immutable release.
Asset replacement can briefly make the feed unavailable; do not remove the old
feed before the new versioned payload is available. Never edit signed XML after
signing. An unavailable or invalid feed must fail closed, not fall back to another
repository release or unsigned metadata. `package.json` reports both destinations;
its distribution-ready status does not mean published or locally installed.

## Conservative update ownership

The release updater must own the same per-user kernel lock used by CLI/service
hosts in a separate broker that survives target replacement. The broker publishes
an exact-target durable operation before starting Sparkle and durably marks it
possibly armed before forwarding the first install choice. `willExtractUpdate`
is a later invariant check, not a safe place to attempt a throwing veto.

Cancellation, errors, a bare no-update result and an idle SDK do not prove that a
previous installer is gone. They must not clear uncertain durable state. Installed
updates require positive installed-artifact verification and authenticated new-menu
readiness. Only a newly owned, explicitly verified broker-only lineage may retire a
still-prepared no-update cycle, using both matching native callbacks and fresh
unchanged-predecessor readback. That same live owner may also retire a fresh initial
check cancellation or explicit Skip/dismiss of its exact not-yet-downloaded offer:
the accepted UI intent, exact native callback sequence and actual completed idle
cycle must agree, with no installation attempt ever admitted. A downloaded/resumed
offer, post-install cancellation, error, crash or reconstructed marker never borrows
that authority. Quit/reopen alone is not uncertainty recovery.

Shared core and driver components now include strict signed candidate metadata
and a native installed-artifact reader with matching full-tree hashing. Their
focused tests do not prove a genuine signed update or authorize live deployment.
Static broker staging and kernel-token-authenticated communication are now
implemented and tested with private fixtures/local sockets. Packaging expects a
separate `BelugaUpdater` executable, now connected as a product and AppKit entrypoint.
The menu is now its authenticated client, not an in-process Sparkle owner. The broker
survives target termination, verifies installed bytes and challenges the new menu
before releasing ownership. A terminal receipt/EOF handshake avoids exiting during
the menu's final identity check. Initial update admission requires quitting/reopening
idle; an active stream is never cancelled to update. Positive signed staging/handshake,
uncertain-attempt recovery and genuine signed old-to-new replacement remain release
blockers. The 320 passing focused tests and help-only executable smoke are not those
native installation proofs. See
`UPDATE_BROKER_DESIGN.md`. Do not describe in-app updates as deployment-ready
until those boundaries pass. No fixed delay or process polling substitutes for them.
