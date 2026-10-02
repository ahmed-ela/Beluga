# Beluga native Android preview — format checking only

This isolated first slice contains a native Kotlin/Compose screen, manual code
entry, explicit Google Code Scanner QR launch, and the existing wire-compatible
invitation parser. **A valid invitation format is not a pairing.** There is no
identity/catalog, authenticated signaling, network, media, microphone, remote
control, saved Mac or transport capability. The UI says so explicitly.

The initial isolated source built a debug APK and passed the 19 model tests plus
the shared 3-vector/79-assertion invitation test, including a strict offline
forced-task repeat with identical APK bytes. The repository integration reuses
`shared/ProtocolFixtures` directly for both app and protocol tests, avoiding
independent copies that could drift. No device installation or runtime test
has been performed. This is not complete Android support or a distributed app.

## Admission and privacy

- Only the user’s Scan button launches the scanner. Google Play services owns
  its camera UI. No app camera, microphone or Internet permission is granted;
  manifest merge removal rules also reject those transitive permissions.
- Google Play services and its unbundled scanner module are required. First use
  can download the module through Play services. SDK failure shows a fixed
  unavailable message and manual entry stays available; no fallback fabricates
  a scan. Non-GMS devices can use manual entry only in this slice.
- QR input uses only the exact non-URL `BELUGA-PAIRING-V1\n<canonical code>`
  envelope. Manual input keeps the deployed ASCII aliases/separators/checksum.
  URL, null, Unicode look-alike, overlength, noncanonical and wrong-format
  payloads are refused before any network work (there is no network work).
- There is one SDK task owner at a time. Opaque attempt identity and a monotonic
  120-second result-admission window refuse duplicate, stale, cancelled or
  superseded callbacks. Expiry/clear revokes result admission but retains SDK
  ownership until the task ends, so another scanner is not launched over it.
- Entered text is memory-only, masked, bounded to 256 characters, cleared on
  validation/clear/background/destruction, and never logged or saved in Bundle,
  preferences, clipboard, files or crash messages. Scanner payloads and parsed
  invitations are discarded after format checking. Managed-runtime erasure is
  not guaranteed; this is bounded logical retention, not a zeroization claim.
- Android backups/transfers are disabled and the activity sets FLAG_SECURE.
  There is no automatic clipboard read and no invitation-bearing intent/deep link.

## Exact dependency selection

| Component | Pin | Rationale |
| --- | --- | --- |
| Gradle | 9.3.1 | AGP’s documented compatible version; ZIP SHA-256 pinned in wrapper properties. |
| AGP | 9.1.1 | API36 / Build Tools36.0.0 / JDK17 compatible; uses built-in KGP2.2.10. |
| Compose compiler | 2.2.10 | Must match that built-in Kotlin version; no old kotlin-android plugin. |
| Compose BOM | 2025.06.01 | Google Maven POM pins UI/Foundation1.8.3 and Material3 1.3.2; conservative stable API36-compatible graph instead of new SDK37+ requirements. |
| Activity Compose | 1.11.0 | Documented compiled API36, stable, minimum API23. |
| Google Code Scanner | 16.1.0 | Official Google scanner dependency; delegated explicit camera UI with no app camera permission. |
| JUnit | 4.13.2 | Stable host-unit-test runner. |

Compile/target SDK36, Build Tools36.0.0, minimum API23, Java17 app and Java11
protocol bytecode are explicit. Direct versions are pinned; all configurations
use strict Gradle dependency locking for the resolved graph and artifact
checksum verification. Gradle rejects combining locking with its alternative
fail-on-dynamic-version mode, so those incompatible flags are not combined.
No SDK/JDK auto-download is authorized or configured.

Primary provenance:

- [AGP9.1 compatibility](https://developer.android.com/build/releases/agp-9-1-0-release-notes)
- [Built-in Kotlin](https://developer.android.com/build/migrate-to-built-in-kotlin)
- [Compose compiler setup](https://developer.android.com/develop/ui/compose/compiler)
- [Exact Google Maven BOM POM](https://dl.google.com/dl/android/maven2/androidx/compose/compose-bom/2025.06.01/compose-bom-2025.06.01.pom)
- [Activity1.11 release](https://developer.android.com/jetpack/androidx/releases/activity#1.11.0)
- [Google Code Scanner](https://developers.google.com/ml-kit/vision/barcode-scanning/code-scanner)
- [Gradle distribution/wrapper checksums](https://gradle.org/release-checksums/)
- [Dependency verification](https://docs.gradle.org/9.3.1/userguide/dependency_verification.html)

## Root-owned build and verification

Supply the already verified JDK17 and SDK36 via JAVA_HOME and ANDROID_HOME.
Use an isolated GRADLE_USER_HOME outside any production checkout. Root generated
the wrapper using the verified Gradle9.3.1 distribution and checked its JAR
against the separately retrieved official checksum below. Dependency locks and
verification metadata have been bootstrapped. A strict offline repeat with all
47 tasks forced to execute also passes, including all 19 model tests and 79
protocol assertions. Its APK hash matches the first successful build. The
independent provenance audit compared all 786 exact cached files to their declared
SHA-256 and official repository sidecars: 386 published SHA-256 matches and 400
explicit SHA-1 fallback matches, with no missing or mismatched file. SHA-1 is
weaker provenance; this is not publisher-signature or malware-free evidence.
The 115-component plugin/buildscript graph is locked separately from app/protocol
graphs. Never regenerate verification metadata automatically in CI.

Using the independently verified Gradle9.3.1 executable:

```sh
gradle --project-dir <scratch-project> --gradle-user-home <private-gradle-cache> \
  --no-daemon --console=plain --write-locks --write-verification-metadata sha256 \
  :protocol:invitationInteropTest :app:testDebugUnitTest :app:assembleDebug
```

This is a **bootstrap observation**, not trusted dependency verification:
review every generated checksum/lock against primary artifact provenance before
accepting `gradle/verification-metadata.xml` and `gradle.lockfile` files. Then run
the same tasks using `--dependency-verification strict` and no write flags.
Do not turn verification off or silently approve changed hashes.

Generate wrapper scripts/JAR only with the verified local Gradle9.3.1:

```sh
gradle --project-dir <scratch-project> --gradle-user-home <private-gradle-cache> \
  --no-daemon wrapper --gradle-version 9.3.1 --distribution-type bin \
  --gradle-distribution-sha256-sum b266d5ff6b90eada6dc3b20cb090e3731302e553a27c5d3e4df1f0d76beaff06
```

Verify generated wrapper JAR SHA-256 equals the official9.3.1 value
`b3a875ddc1f044746e1b1a55f645584505f4a10438c1afea9f15e92a7c42ec13`.
Inspect the merged manifest/APK for permission, backup and capability boundaries.
Root's initial APK readback has no CAMERA, RECORD_AUDIO or INTERNET permission;
transitive ACCESS_NETWORK_STATE and the signature-scoped dynamic-receiver
permission remain. The standard profile-installer receiver is exported behind
android.permission.DUMP; the launcher is the only unprotected exported component.
Debug v1/v2 APK signature verification passes. This is not release signing.
The 19 model unit tests and shared 3-vector/79-assertion parser test are host
proof only. Physical QR UI, Play-service availability, lifecycle and package
behavior still require independent Android validation.

Before actual pairing, finish the host multi-phone catalog integration and
cross-language identity/AEAD/commit/reconnect vectors. Do not replace the iPhone
binding or infer pairing from this preview’s format-valid status.
