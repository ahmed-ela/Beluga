// Actual actor Owner Stop202/105 regressions through the existing inert service.
// The DEBUG Stop opt-in uses the real actor slot, never a simulated publication
// fixture. Nil native sidecars/resources are truthful constructor-derived scope.
import Foundation
import XCTest
@testable import CaptureCore
@testable import CaptureServer

@MainActor
final class WorldwideScreenServiceNativeOwnerStorageTests: XCTestCase {
    private typealias Observation = WorldwideScreenService.NativeOwnerStorageInertObservation
    private typealias Snapshot = WorldwideScreenService.NativeOwnerPublicationSnapshotObservation
    private typealias StopFault = WorldwideScreenService.NativeOwnerStopPublicationFault

    private var profiles: [(WorldwideScreenServiceFeatureProfile, Int)] {
        [(.fullPrimary, 8_000_000), (.secondaryTest, 4_000_000)]
    }

    func testActualInertServiceOwnerConstructorAndRealStop() async throws {
        try assertTerminalInactiveSourceFence()
        try assertBeginActiveSourceFence()
        try assertStopOwnershipSourceFence()
        try assertEpochOwnershipSourceFence()
        try assertResetOwnershipSourceFence()
        try await assertActualEpochPublication(faults: [.none])
        try await assertActualResetPublication(faults: [.none, .epochRefused])
        try await assertPreviousNonOptInStopBaseline()
        for (profile, effectiveCap) in profiles {
            try await runActualStop(profile: profile, effectiveCap: effectiveCap, faults: [])
        }
    }

    // Source controls for the unwired actual701 publication cut only. They do
    // not create a native Peer/Prepared receipt or prove actual actor publication.
    private func assertBeginActiveSourceFence() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "macOS/Sources/CaptureServer/WorldwideScreenService.swift"), encoding: .utf8)
        let codec = try String(contentsOf: root.appendingPathComponent(
            "macOS/Sources/CaptureServer/BelugaNetworkAdaptationOwnerCodec.swift"), encoding: .utf8)
        func tokens(_ s: String) -> String { s.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        func count(_ s: String, _ needle: String) -> Int { s.components(separatedBy: needle).count - 1 }
        func region(_ text: String, _ start: String, _ end: String) -> Range<String.Index>? {
            guard count(text, start) == 1, let lower = text.range(of: start)?.lowerBound,
                  let upper = text.range(of: end, range: lower..<text.endIndex)?.lowerBound else { return nil }
            return lower..<upper
        }
        func slice(_ text: String, _ start: String, _ end: String) -> String? {
            guard let r = region(text, start, end) else { return nil }
            return tokens(String(text[r]))
        }
        let adapterStart = "    func beginActive("
        let adapterEnd = "    private func beginActiveHeld("
        let packetStart = "struct BelugaNetworkAdaptationActualBeginActiveCommit {"
        let packetEnd = "\nextension BelugaNetworkAdaptationOwnerBoundary {"
        let factoryStart = "    func networkAdaptationBeginActiveEntry("
        let recaptureStart = "    func networkAdaptationBeginActiveRecapture("
        let commitStart = "    func networkAdaptationBeginActiveCommit("
        let commitEnd = "\n}\n"
        let compareStart = "    private static func samePublicationSource("
        let compareEnd = "    // SAME held scope as zero/clocked/terminal501."
        let burnStart = "    private func withPreparedGuard("
        let burnEnd = "    func propose("
        let nativeEntryStart = "final class BelugaNetworkAdaptationNativeBeginActiveEntry {"
        let nativeEntryEnd = "\nextension WorldwideScreenService {\n    func networkAdaptationBeginActiveEntry("

        let expectedPacket = tokens("""
        struct BelugaNetworkAdaptationActualBeginActiveCommit {
            let entry: BelugaNetworkAdaptationNativeBeginActiveEntry
            let boundary: BelugaNetworkAdaptationOwnerBoundary
            let replacement: BelugaNetworkAdaptationOwnerSnapshot
            fileprivate init(entry: BelugaNetworkAdaptationNativeBeginActiveEntry,
                boundary: BelugaNetworkAdaptationOwnerBoundary,
                replacement: BelugaNetworkAdaptationOwnerSnapshot) {
                self.entry = entry; self.boundary = boundary; self.replacement = replacement
            }
        }
        """)
        let expectedFactory = tokens("""
        func networkAdaptationBeginActiveEntry(_ preparation: BelugaNetworkAdaptationNativeGeneralPrepareEntry,
            boundary: BelugaNetworkAdaptationOwnerBoundary) -> BelugaNetworkAdaptationNativeBeginActiveEntry? {
            // These are issuer/custody checks, NOT a replacement of the original
            // synchronous continuation with another peer/revision/active-use vote.
            guard preparation.owner === self, preparation.boundary === boundary,
                  screenVideoAdaptationOwnerBoundary === boundary else { return nil }
            return .init(preparation: preparation, value: screenVideoAdaptationOwner,
                source: captureSource, sink: captureSink, captureAuthorization: captureAuthorization,
                forwardingAuthorization: captureForwardingAuthorization, baseDimensions: captureVideoBaseDimensions,
                capturer: preparation.peer.externalVideoCapturer)
        }
        """)
        // Includes all six real-resource identities and issuer custody. Absence
        // is legitimate here; resource existence is voted once by Rust701.
        let expectedRecapture = tokens("""
        func networkAdaptationBeginActiveRecapture(_ entry: BelugaNetworkAdaptationNativeBeginActiveEntry,
            boundary: BelugaNetworkAdaptationOwnerBoundary,
            retainingAnchor: ContinuousClock.Instant?) throws -> BelugaNetworkAdaptationOwnerSnapshot {
            guard entry.preparation.owner === self, entry.preparation.boundary === boundary,
                  screenVideoAdaptationOwnerBoundary === boundary,
                  captureSource === entry.source, captureSink === entry.sink,
                  captureAuthorization === entry.captureAuthorization,
                  captureForwardingAuthorization === entry.forwardingAuthorization,
                  captureVideoBaseDimensions == entry.baseDimensions,
                  entry.preparation.peer.externalVideoCapturer === entry.capturer else {
                throw BelugaNetworkAdaptationOwnerError.refused
            }
            return try BelugaNetworkAdaptationOwnerSnapshot.capture(screenVideoAdaptationOwner,
                retainingAnchor: retainingAnchor)
        }
        // Constructor-sealed packet from the same held codec call. No callback,
        // recapture, clock, native effect, await or throwing work follows the store.
        """)
        let expectedCommit = tokens("""
        func networkAdaptationBeginActiveCommit(_ packet: BelugaNetworkAdaptationActualBeginActiveCommit) {
            precondition(packet.entry.preparation.owner === self
                && packet.entry.preparation.boundary === packet.boundary
                && screenVideoAdaptationOwnerBoundary === packet.boundary)
            screenVideoAdaptationOwner = packet.replacement.value
        }
        """)
        let expectedComparison = tokens("""
        private static func samePublicationSource(_ a: BelugaNetworkAdaptationOwnerSnapshot,
            _ b: BelugaNetworkAdaptationOwnerSnapshot) -> Bool {
            BelugaNetworkAdaptationOwnerSnapshot.equalAtoms(a.atoms, b.atoms)
                && a.times == b.times && a.anchor == b.anchor && a.route == b.route
        }
        """)
        let expectedBurn = tokens("""
        private func withPreparedGuard(_ use: BelugaNetworkAdaptationPreparedUse,
            _ body: (HeldScope) throws -> GuardedProposal) throws -> GuardedProposal {
            // Even a swallowed replay/wrong-origin spend failure poisons an outer
            // invocation. Consumption still happens before busy/exhaustion refusal.
            if busy { poisoned = true }
            try use.spend(by: self)
            return try withGuard(body)
        }
        """)
        let expectedAdapter = tokens("""
        func beginActive(_ receipt: BelugaNetworkAdaptationGeneralPreparedReceipt,
            on owner: isolated WorldwideScreenService) throws -> BelugaNetworkAdaptationBeginActiveReceipt? {
            let result = try withPreparedGuard(receipt.use) { scope in
                guard let entry = owner.networkAdaptationBeginActiveEntry(receipt.entry, boundary: self) else {
                    throw BelugaNetworkAdaptationOwnerError.refused
                }
                let current = try BelugaNetworkAdaptationOwnerSnapshot.capture(entry.value,
                    retainingAnchor: receipt.value.source.anchor)
                let proposal = try beginActiveHeld(current: current, prepared: receipt.value,
                    resourceFlags: entry.resourceFlags, scope: scope)
                let recaptured = try owner.networkAdaptationBeginActiveRecapture(entry, boundary: self,
                    retainingAnchor: current.anchor)
                guard Self.samePublicationSource(current, recaptured) else {
                    throw BelugaNetworkAdaptationOwnerError.refused
                }
                let successor: BelugaNetworkAdaptationBeginActiveReceipt? = proposal.disposition == .returned ? nil :
                    .init(entry: entry, proposal: proposal, boundary: self, invocation: scope.invocation)
                let result = GuardedProposal.beginActive(successor)
                let packet = BelugaNetworkAdaptationActualBeginActiveCommit(entry: entry,
                    boundary: self, replacement: proposal.replacement)
                guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }
                owner.networkAdaptationBeginActiveCommit(packet)
                return result
            }
            switch result {
            case let .beginActive(receipt): return receipt
            default: preconditionFailure("beginActive returned an impossible guarded result")
            }
        }
        """)
        func valid(_ s: String, _ c: String) -> Bool {
            guard slice(c, packetStart, packetEnd) == expectedPacket,
                  slice(c, adapterStart, adapterEnd) == expectedAdapter,
                  slice(c, compareStart, compareEnd) == expectedComparison,
                  slice(c, burnStart, burnEnd) == expectedBurn,
                  slice(s, factoryStart, recaptureStart) == expectedFactory,
                  slice(s, recaptureStart, commitStart) == expectedRecapture,
                  slice(s, commitStart, commitEnd) == expectedCommit,
                  let entry = slice(s, nativeEntryStart, nativeEntryEnd),
                  count(entry, "fileprivate init(preparation: BelugaNetworkAdaptationNativeGeneralPrepareEntry,") == 1,
                  count(entry, "fileprivate let preparation: BelugaNetworkAdaptationNativeGeneralPrepareEntry") == 1,
                  entry.contains("resourceFlags = (source == nil ? 0 : 1) | (sink == nil ? 0 : 2) | (captureAuthorization == nil ? 0 : 4) | (forwardingAuthorization == nil ? 0 : 8) | (baseDimensions == nil ? 0 : 16) | (capturer == nil ? 0 : 32)"),
                  count(s, "private static let allNetworkAdaptationOwnerWritersAreEnrolled = false") == 1,
                  count(s, "private static let ownedStopPublicationIsEnrolled = false") == 1 else { return false }
            return true
        }
        XCTAssertTrue(valid(source, codec), "unwired actual701 publication source contract")

        // Each change is scoped to one closed lexical body. A missing or
        // duplicated anchor fails rather than silently yielding a no-op mutant.
        typealias Control = (label: String, codec: Bool, start: String, end: String, old: String, new: String)
        let controls: [Control] = [
            ("burn consumption", true, burnStart, burnEnd, "try use.spend(by: self)", ""),
            ("busy prepoison", true, burnStart, burnEnd, "if busy { poisoned = true }", ""),
            ("burn before guard", true, burnStart, burnEnd, "try use.spend(by: self)\n        return try withGuard(body)", "return try withGuard(body)\n        try use.spend(by: self)"),
            ("mandatory isolated owner", true, adapterStart, adapterEnd, "on owner: isolated WorldwideScreenService", "on owner: WorldwideScreenService"),
            ("same issuer guard", true, adapterStart, adapterEnd, "withPreparedGuard(receipt.use)", "withGuard"),
            ("actual current tuple", true, adapterStart, adapterEnd, "Snapshot.capture(entry.value,", "Snapshot.capture(receipt.value.source.value,"),
            ("exact raw701 current", true, adapterStart, adapterEnd, "beginActiveHeld(current: current, prepared: receipt.value,", "beginActiveHeld(current: receipt.value.source, prepared: receipt.value,"),
            ("fresh recapture", true, adapterStart, adapterEnd, "let recaptured = try owner.networkAdaptationBeginActiveRecapture(entry, boundary: self,", "let recaptured = current // owner.networkAdaptationBeginActiveRecapture(entry, boundary: self,"),
            ("retained anchor", true, adapterStart, adapterEnd, "retainingAnchor: current.anchor)", "retainingAnchor: nil)"),
            ("full current comparison", true, adapterStart, adapterEnd, "guard Self.samePublicationSource(current, recaptured) else", "guard true else"),
            ("Return nil preconstructed", true, adapterStart, adapterEnd, "proposal.disposition == .returned ? nil :", "false ? nil :"),
            ("sealed successor provenance", true, adapterStart, adapterEnd, ".init(entry: entry, proposal: proposal, boundary: self, invocation: scope.invocation)", ".init(entry: entry, proposal: proposal, boundary: foreignBoundary, invocation: scope.invocation)"),
            ("closed result preconstructed", true, adapterStart, adapterEnd, "let result = GuardedProposal.beginActive(successor)", ""),
            ("whole replacement packet", true, adapterStart, adapterEnd, "replacement: proposal.replacement)", "replacement: current)"),
            ("final poison", true, adapterStart, adapterEnd, "guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }", ""),
            ("all dispositions store", true, adapterStart, adapterEnd, "owner.networkAdaptationBeginActiveCommit(packet)", "if proposal.disposition != .returned { owner.networkAdaptationBeginActiveCommit(packet) }"),
            ("missing actor store", true, adapterStart, adapterEnd, "owner.networkAdaptationBeginActiveCommit(packet)", ""),
            ("poststore throwing extraction", true, adapterStart, adapterEnd, "default: preconditionFailure(\"beginActive returned an impossible guarded result\")", "default: throw BelugaNetworkAdaptationOwnerError.invalidResult"),
            ("second501 gate", true, adapterStart, adapterEnd, "let recaptured = try owner.networkAdaptationBeginActiveRecapture", "guard owner.networkAdaptationGeneralPrepareIsCurrent() else { return .beginActive(nil) }\n            let recaptured = try owner.networkAdaptationBeginActiveRecapture"),
            ("mutable packet", true, packetStart, packetEnd, "let replacement: BelugaNetworkAdaptationOwnerSnapshot", "var replacement: BelugaNetworkAdaptationOwnerSnapshot"),
            ("unsealed packet initializer", true, packetStart, packetEnd, "fileprivate init(", "init("),
            ("factory owner", false, factoryStart, recaptureStart, "preparation.owner === self,", ""),
            ("factory issuer", false, factoryStart, recaptureStart, "preparation.boundary === boundary,", ""),
            ("factory actual tuple", false, factoryStart, recaptureStart, "value: screenVideoAdaptationOwner,", "value: cachedOwner,"),
            ("recapture owner", false, recaptureStart, commitStart, "entry.preparation.owner === self,", ""),
            ("recapture issuer", false, recaptureStart, commitStart, "entry.preparation.boundary === boundary,", ""),
            ("recapture actual boundary", false, recaptureStart, commitStart, "screenVideoAdaptationOwnerBoundary === boundary,", ""),
            ("source identity", false, recaptureStart, commitStart, "captureSource === entry.source,", ""),
            ("sink identity", false, recaptureStart, commitStart, "captureSink === entry.sink,", ""),
            ("capture authority identity", false, recaptureStart, commitStart, "captureAuthorization === entry.captureAuthorization,", ""),
            ("forwarding authority identity", false, recaptureStart, commitStart, "captureForwardingAuthorization === entry.forwardingAuthorization,", ""),
            ("dimension identity", false, recaptureStart, commitStart, "captureVideoBaseDimensions == entry.baseDimensions,", ""),
            ("original capturer identity", false, recaptureStart, commitStart, "entry.preparation.peer.externalVideoCapturer === entry.capturer", "true"),
            ("no authorization health vote", false, recaptureStart, commitStart, "captureAuthorization === entry.captureAuthorization,", "captureAuthorization === entry.captureAuthorization, entry.captureAuthorization?.isValid == true,"),
            ("no peer generation vote", false, recaptureStart, commitStart, "entry.preparation.owner === self,", "entry.preparation.owner === self, peerGeneration == entry.preparation.generation,"),
            ("no revision vote", false, recaptureStart, commitStart, "entry.preparation.boundary === boundary,", "entry.preparation.boundary === boundary, screenVideoAdaptationOwner.revision == entry.preparation.revision,"),
            ("capture actual storage", false, recaptureStart, commitStart, "Snapshot.capture(screenVideoAdaptationOwner,", "Snapshot.capture(entry.value,"),
            ("store owner custody", false, commitStart, commitEnd, "packet.entry.preparation.owner === self", "true"),
            ("final whole store", false, commitStart, commitEnd, "screenVideoAdaptationOwner = packet.replacement.value", ""),
            ("no poststore callback", false, commitStart, commitEnd, "screenVideoAdaptationOwner = packet.replacement.value", "screenVideoAdaptationOwner = packet.replacement.value; callback()"),
            ("all13 native times", true, compareStart, compareEnd, "&& a.times == b.times", ""),
            ("same anchor", true, compareStart, compareEnd, "&& a.anchor == b.anchor", ""),
            ("whole Optional route", true, compareStart, compareEnd, "&& a.route == b.route", ""),
            ("closed native initializer", false, nativeEntryStart, nativeEntryEnd, "fileprivate init(preparation:", "init(preparation:"),
        ]
        XCTAssertGreaterThanOrEqual(controls.count, 16)
        for control in controls {
            let text = control.codec ? codec : source
            let r = try XCTUnwrap(region(text, control.start, control.end), control.label)
            let body = String(text[r])
            XCTAssertEqual(count(body, control.old), 1, control.label)
            let found = try XCTUnwrap(count(body, control.old) == 1 ? text.range(of: control.old, range: r) : nil,
                control.label)
            var changed = text
            changed.replaceSubrange(found, with: control.new)
            XCTAssertNotEqual(changed, text, control.label)
            XCTAssertFalse(valid(control.codec ? source : changed, control.codec ? changed : codec), control.label)
        }
        // Whole contiguous blocks preserve order as well as presence. Move a
        // store, rather than delete it, to ensure the fence catches both.
        let finalBlock = [
            "            guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }",
            "            owner.networkAdaptationBeginActiveCommit(packet)",
            "            return result",
        ].joined(separator: "\n")
        let movedStore = [
            "            owner.networkAdaptationBeginActiveCommit(packet)",
            "            guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }",
            "            return result",
        ].joined(separator: "\n")
        let resultBlock = [
            "            let result = GuardedProposal.beginActive(successor)",
            "            let packet = BelugaNetworkAdaptationActualBeginActiveCommit(entry: entry,",
            "                boundary: self, replacement: proposal.replacement)",
            "            guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }",
            "            owner.networkAdaptationBeginActiveCommit(packet)",
        ].joined(separator: "\n")
        let lateResult = [
            "            let packet = BelugaNetworkAdaptationActualBeginActiveCommit(entry: entry,",
            "                boundary: self, replacement: proposal.replacement)",
            "            guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }",
            "            owner.networkAdaptationBeginActiveCommit(packet)",
            "            let result = GuardedProposal.beginActive(successor)",
        ].joined(separator: "\n")
        for (label, old, new) in [("store before final poison", finalBlock, movedStore),
                                  ("result constructed after store", resultBlock, lateResult)] {
            let r = try XCTUnwrap(region(codec, adapterStart, adapterEnd), label)
            XCTAssertEqual(count(String(codec[r]), old), 1, label)
            let found = try XCTUnwrap(codec.range(of: old, range: r), label)
            var changed = codec
            changed.replaceSubrange(found, with: new)
            XCTAssertNotEqual(changed, codec, label)
            XCTAssertFalse(valid(source, changed), label)
        }
    }

    // Structural custody controls supplement the actual601 copied-import tests;
    // this is NOT a genuine actor receipt/publication or live-resource oracle.
    private func assertTerminalInactiveSourceFence() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "macOS/Sources/CaptureServer/WorldwideScreenService.swift"), encoding: .utf8)
        let codec = try String(contentsOf: root.appendingPathComponent(
            "macOS/Sources/CaptureServer/BelugaNetworkAdaptationOwnerCodec.swift"), encoding: .utf8)
        func valid(_ s: String, _ c: String) -> Bool {
            func cut(_ text: String, _ start: String, _ end: String) -> String? {
                guard let a = text.range(of: start), let b = text.range(of: end, range: a.upperBound..<text.endIndex) else { return nil }
                return text[a.lowerBound..<b.lowerBound].split(whereSeparator: \.isWhitespace).joined(separator: " ")
            }
            guard let burn = cut(c, "private func withPreparedGuard(", "func propose("),
                  burn.contains("try use.spend(by: self) return try withGuard(body)"),
                  burn.contains("if busy { poisoned = true } try use.spend(by: self)"),
                  let publish = cut(c, "func publishPreparedInactive(", "private func inactiveTerminalHeld("),
                  publish.contains("on owner: isolated WorldwideScreenService"),
                  publish.contains("withPreparedGuard(receipt.use)"),
                  publish.contains("entry.owner === owner, entry.boundary === self"),
                  publish.contains("!entry.active, !prepared.tail.captureActive, entry.allowsResume"),
                  publish.contains("let current = try owner.networkAdaptationTerminalInactiveCapture(entry, original: prepared.source)"),
                  publish.contains("guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry } guard try owner.networkAdaptationTerminalPrepareIsCurrent(entry, original: current) else { return .publication(.refused) } guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry } owner.networkAdaptationTerminalInactiveCommit(.init(entry: entry, replacement: replacement))"),
                  publish.components(separatedBy: "owner.networkAdaptationTerminalInactiveCommit(").count == 2,
                  !publish.contains("await "),
                  let entry = cut(s, "func networkAdaptationTerminalPrepareEntry(", "// Rebuild from the actual current actor state"),
                  entry.contains("screenVideoAdaptationOwnerBoundary === boundary"),
                  entry.contains("peer === sourcePeer, peerGeneration == generation"),
                  entry.contains("screenVideoAdaptationOwner.revision == revision"),
                  entry.contains("return .init(owner: self, boundary: boundary"),
                  let fresh = cut(s, "func networkAdaptationTerminalPrepareIsCurrent(", "// Capture ACTUAL storage again"),
                  fresh.contains("entry.owner === self, screenVideoAdaptationOwnerBoundary === entry.boundary"),
                  fresh.contains("captured.times == original.times && captured.anchor == original.anchor && captured.route == original.route"),
                  let capture = cut(s, "func networkAdaptationTerminalInactiveCapture(", "// Codec-file sealed packet"),
                  capture.contains(".capture(screenVideoAdaptationOwner, retainingAnchor: original.anchor)"),
                  let store = cut(s, "func networkAdaptationTerminalInactiveCommit(", "\n}"),
                  store.contains("precondition(packet.entry.owner === self)"),
                  store.contains("precondition(screenVideoAdaptationOwnerBoundary === packet.entry.boundary)"),
                  store.contains("screenVideoAdaptationOwner = packet.replacement.value"),
                  !store.contains("await "), !store.contains("try "),
                  c.contains("fileprivate init(entry: BelugaNetworkAdaptationNativePrepareEntry,"),
                  s.contains("allNetworkAdaptationOwnerWritersAreEnrolled = false"),
                  s.contains("ownedStopPublicationIsEnrolled = false") else { return false }
            return true
        }
        XCTAssertTrue(valid(source, codec))
        for token in ["try use.spend(by: self)", "if busy { poisoned = true }", "withPreparedGuard(receipt.use)",
            "entry.owner === owner, entry.boundary === self,", "!entry.active, !prepared.tail.captureActive, entry.allowsResume,",
            "guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }",
            "owner.networkAdaptationTerminalPrepareIsCurrent(entry, original: current)"] {
            XCTAssertTrue(codec.contains(token), token)
            XCTAssertFalse(valid(source, codec.replacingOccurrences(of: token, with: "")), token)
        }
        for token in ["screenVideoAdaptationOwnerBoundary === boundary,",
            "peer === sourcePeer, peerGeneration == generation,", "screenVideoAdaptationOwner.revision == revision",
            "return .init(owner: self, boundary: boundary", "captured.times == original.times",
            "captured.anchor == original.anchor", "captured.route == original.route",
            "precondition(packet.entry.owner === self)", "screenVideoAdaptationOwner = packet.replacement.value"] {
            XCTAssertTrue(source.contains(token), token)
            XCTAssertFalse(valid(source.replacingOccurrences(of: token, with: ""), codec), token)
        }
    }

    // Source-order coverage is additive to the unchanged actual-Stop scenarios.
    // These controls do not claim a real pending native stop/watchdog schedule.
    private func assertStopOwnershipSourceFence() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "macOS/Sources/CaptureServer/WorldwideScreenService.swift"), encoding: .utf8)
        let codec = try String(contentsOf: root.appendingPathComponent(
            "macOS/Sources/CaptureServer/BelugaNetworkAdaptationOwnerCodec.swift"), encoding: .utf8)
        XCTAssertTrue(stopOwnershipSourceFence(source))
        XCTAssertTrue(stopOriginSourceFence(source, codec: codec))
        let controls: [(String, String)] = [
            ("private struct ServiceStopPlan: ~Copyable", "private struct ServiceStopPlan"),
            ("await finishStop(consume plan)", "return"),
            ("await waitForStopToFinish()", ""),
            ("captureSink?.stopForwarding()", ""),
            ("audioSink?.stopForwarding()", ""),
            ("screenVideoAdaptationTask?.cancel()", "applyNativeOwnerStopPublication(.stopSampling, origin: ownerStopOrigin)"),
            ("defer { finishStopping() }", "finishStopping()"),
            ("await plan.teardownWatchdog?.value", ""),
        ]
        for (original, replacement) in controls {
            XCTAssertTrue(source.contains(original), original)
            XCTAssertFalse(stopOwnershipSourceFence(source.replacingOccurrences(
                of: original, with: replacement)), original)
        }
        // A moved rather than deleted forwarding closure must also be rejected.
        let moved = source.replacingOccurrences(of: "captureSink?.stopForwarding()", with: "")
            .replacingOccurrences(of: "await plan.coordinator?.cancel()",
                with: "await plan.coordinator?.cancel(); captureSink?.stopForwarding()")
        XCTAssertFalse(stopOwnershipSourceFence(moved))
        let yieldedPrefix = source.replacingOccurrences(of: "isStopped = true\n        stopIsInProgress = true",
            with: "isStopped = true\n        stopIsInProgress = true\n        await Task.yield()")
        XCTAssertFalse(stopOwnershipSourceFence(yieldedPrefix))
        for (original, replacement) in [
            ("allNetworkAdaptationOwnerWritersAreEnrolled = false", "allNetworkAdaptationOwnerWritersAreEnrolled = true"),
            ("ownedStopPublicationIsEnrolled = false", "ownedStopPublicationIsEnrolled = true"),
            ("Self.allNetworkAdaptationOwnerWritersAreEnrolled && Self.ownedStopPublicationIsEnrolled", "Self.ownedStopPublicationIsEnrolled"),
            ("guard Self.allNetworkAdaptationOwnerWritersAreEnrolled,", "guard true,"),
            ("Self.ownedStopPublicationIsEnrolled else { return false }", "true else { return false }"),
            ("guard pendingNativeOwnerStopEntry == nil else { return }", ""),
            ("let entry = networkAdaptationActualStopEntry(cut, origin: origin)", "let entry = cachedEntry"),
            ("entry.phase = .retired\n            pendingNativeOwnerStopEntry = nil", "pendingNativeOwnerStopEntry = nil"),
            ("case .nativeShutdown:", "case .inertFixture:"),
            ("case .endShow: nativeOwnerStopPublicationStage = .stopSampling", "case .endShow: nativeOwnerStopPublicationStage = .finished"),
            ("case .endShow: return nativeOwnerStopPublicationStage == .endShow", "case .endShow: return true"),
            ("nativeOwnerStopPublicationEnabled else { return false }", "true else { return false }"),
            ("entry.permitsInertNegativeControls, let before", "let before"),
            ("switch try screenVideoAdaptationOwnerBoundary.publishActualStop(entry, on: self)", "switch try screenVideoAdaptationOwnerBoundary.publishActualStop(cachedEntry, on: self)"),
        ] {
            XCTAssertTrue(source.contains(original), original)
            XCTAssertFalse(stopOriginSourceFence(source.replacingOccurrences(of: original,
                with: replacement), codec: codec), original)
        }
        let witnessStart = try XCTUnwrap(source.range(of:
            "    private func networkAdaptationActualStopNativeWitnessIsCurrent(")?.lowerBound)
        let witnessEnd = try XCTUnwrap(source.range(of:
            "    func networkAdaptationActualStopIsCurrent(",
            range: witnessStart..<source.endIndex)?.lowerBound)
        for gate in [
            "pendingNativeOwnerStopEntry === entry,", "entry.owner === self,",
            "entry.boundary === screenVideoAdaptationOwnerBoundary,", "entry.generation == peerGeneration,",
            "entry.sourcePeer === peer,", "entry.coordinator === recoveryCoordinator,",
            "entry.source === captureSource,", "entry.sink === captureSink,",
            "entry.authorization === captureAuthorization,", "entry.forwarding === captureForwardingAuthorization,",
            "entry.audioSource === audioSource,", "entry.audioSink === audioSink,",
            "entry.audioAuthorization === audioAuthorization,",
            "entry.visibilityEpoch == screenVisibilityCommandEpoch,", "entry.recoveryEpoch == recoveryProofEpoch",
        ] {
            XCTAssertNotNil(source.range(of: gate, range: witnessStart..<witnessEnd), gate)
            XCTAssertFalse(stopOriginSourceFence(source.replacingOccurrences(of: gate,
                with: "", range: witnessStart..<witnessEnd), codec: codec), gate)
        }
        for (original, replacement) in [
            ("isPublishingActualStop = entry.permitsInertNegativeControls", "isPublishingActualStop = true"),
            ("#if DEBUG\n    private func publishFixtureHeld(", "private func publishFixtureHeld("),
            ("func publishActualStop(", "#if DEBUG\n    func publishActualStop("),
        ] {
            XCTAssertTrue(codec.contains(original), original)
            XCTAssertFalse(stopOriginSourceFence(source, codec: codec.replacingOccurrences(
                of: original, with: replacement)), original)
        }
    }

    private func stopOriginSourceFence(_ source: String, codec: String) -> Bool {
        func tokens(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        func body(_ start: String, _ end: String) -> String? {
            guard let a = source.range(of: start),
                  let b = source.range(of: end, range: a.upperBound..<source.endIndex) else { return nil }
            return tokens(String(source[a.lowerBound..<b.lowerBound]))
        }
        guard source.contains("private static let allNetworkAdaptationOwnerWritersAreEnrolled = false"),
              source.contains("private static let ownedStopPublicationIsEnrolled = false"),
              let origin = body("    private func networkAdaptationActualStopPublicationOrigin()",
                                "    private func applyNativeOwnerStopPublication("),
              let apply = body("    private func applyNativeOwnerStopPublication(",
                               "    private func networkAdaptationActualStopEntry("),
              let witness = body("    private func networkAdaptationActualStopNativeWitnessIsCurrent(",
                                 "    func networkAdaptationActualStopIsCurrent("),
              origin.contains("if Self.allNetworkAdaptationOwnerWritersAreEnrolled && Self.ownedStopPublicationIsEnrolled { return .nativeShutdown }"),
              origin.contains("#if DEBUG if nativeOwnerStopPublicationEnabled { return .inertFixture } #endif return nil"),
              apply.contains("guard pendingNativeOwnerStopEntry == nil else { return } let entry = networkAdaptationActualStopEntry(cut, origin: origin) pendingNativeOwnerStopEntry = entry defer { entry.phase = .retired pendingNativeOwnerStopEntry = nil"),
              apply.contains("switch cut { case .endShow: nativeOwnerStopPublicationStage = .stopSampling case .stopSampling: nativeOwnerStopPublicationStage = .finished }"),
              apply.contains("switch try screenVideoAdaptationOwnerBoundary.publishActualStop(entry, on: self)"),
              apply.contains("if entry.permitsInertNegativeControls, let before"),
              !apply.contains("screenVideoAdaptationOwner ="), !apply.contains("await "),
              witness.contains("case .nativeShutdown: guard Self.allNetworkAdaptationOwnerWritersAreEnrolled, Self.ownedStopPublicationIsEnrolled else { return false }"),
              witness.contains("nativeOwnerStopPublicationEnabled else { return false }"),
              witness.contains("case .endShow: return nativeOwnerStopPublicationStage == .endShow"),
              witness.contains("nativeOwnerStopPublicationStage == .stopSampling && screenVideoAdaptationTask == nil"),
              !source.contains("#if DEBUG\n/// Constructor sealed to the actor's original Stop cuts."),
              !codec.contains("#if DEBUG\n    func publishActualStop("),
              codec.contains("#if DEBUG\n            isPublishingActualStop = entry.permitsInertNegativeControls"),
              codec.contains("#if DEBUG\n    private func publishFixtureHeld(") else { return false }
        for clause in [
            "pendingNativeOwnerStopEntry === entry,", "entry.owner === self,",
            "entry.boundary === screenVideoAdaptationOwnerBoundary,", "entry.generation == peerGeneration,",
            "entry.sourcePeer === peer,", "entry.coordinator === recoveryCoordinator,",
            "entry.source === captureSource,", "entry.sink === captureSink,",
            "entry.authorization === captureAuthorization,", "entry.forwarding === captureForwardingAuthorization,",
            "entry.audioSource === audioSource,", "entry.audioSink === audioSink,",
            "entry.audioAuthorization === audioAuthorization,",
            "entry.visibilityEpoch == screenVisibilityCommandEpoch,", "entry.recoveryEpoch == recoveryProofEpoch",
        ] {
            guard witness.components(separatedBy: clause).count == 2 else { return false }
        }
        return true
    }

    private func assertEpochOwnershipSourceFence() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "macOS/Sources/CaptureServer/WorldwideScreenService.swift"), encoding: .utf8)
        let codec = try String(contentsOf: root.appendingPathComponent(
            "macOS/Sources/CaptureServer/BelugaNetworkAdaptationOwnerCodec.swift"), encoding: .utf8)
        XCTAssertTrue(epochOwnershipSourceFence(source, codec: codec))
        for (old, replacement) in [
            ("allNetworkAdaptationOwnerWritersAreEnrolled = false", "allNetworkAdaptationOwnerWritersAreEnrolled = true"),
            ("ownedStopPublicationIsEnrolled = false", "ownedStopPublicationIsEnrolled = true"),
            ("nativeOwnerEpochPublicationEnabled else { return false }", "true else { return false }"),
            ("guard pendingNativeOwnerEpochEntry == nil,", "guard true,"),
            ("entry.phase == .admitted, case .unread = entry.payload,", "entry.phase == .admitted,"),
            ("let minimum = entry.sourcePeer?.minimumNextStatisticsCollectionSequence()", "let minimum = cachedMinimum"),
            ("let minimum = entry.sourcePeer?.minimumNextStatisticsCollectionSequence()", "let minimum = peer?.minimumNextStatisticsCollectionSequence()"),
            ("let minimum = entry.sourcePeer?.minimumNextStatisticsCollectionSequence()", "let minimum = entry.sourcePeer?.minimumNextStatisticsCollectionSequence(); _ = entry.sourcePeer?.minimumNextStatisticsCollectionSequence()"),
            ("entry.payload = .sealed(minimum)", "entry.payload = .sealed(nil)"),
            ("minimum == nil ? 0 : 1", "minimum == 0 ? 0 : 1"),
            ("pendingNativeOwnerEpochEntry === entry else { return }", "true else { return }"),
            ("if entry.phase != .published { entry.phase = .retired }", ""),
            ("precondition(pendingNativeOwnerEpochEntry === packet.entry)", ""),
            ("screenVideoAdaptationOwner = packet.replacement.value", "screenVideoAdaptationOwner = packet.replacement.value; callback()"),
        ] {
            XCTAssertTrue(source.contains(old), old)
            XCTAssertFalse(epochOwnershipSourceFence(source.replacingOccurrences(of: old, with: replacement), codec: codec), old)
        }
        let start = try XCTUnwrap(source.range(of:
            "    private func networkAdaptationActualEpochNativeWitnessIsCurrent(")?.lowerBound)
        let end = try XCTUnwrap(source.range(of:
            "    func networkAdaptationActualEpochSealMinimum(", range: start..<source.endIndex)?.lowerBound)
        for clause in epochWitnessClauses {
            XCTAssertNotNil(source.range(of: clause, range: start..<end), clause)
            for replacement in ["", clause + clause] {
                XCTAssertFalse(epochOwnershipSourceFence(source.replacingOccurrences(of: clause,
                    with: replacement, range: start..<end), codec: codec), clause)
            }
        }
        let postRead = [
            "        let minimum = entry.sourcePeer?.minimumNextStatisticsCollectionSequence()",
            "        guard networkAdaptationActualEpochNativeWitnessIsCurrent(entry) else {",
            "            throw BelugaNetworkAdaptationOwnerError.invalidResult", "        }",
        ].joined(separator: "\n")
        let movedPostRead = [
            "        guard networkAdaptationActualEpochNativeWitnessIsCurrent(entry) else {",
            "            throw BelugaNetworkAdaptationOwnerError.invalidResult", "        }",
            "        let minimum = entry.sourcePeer?.minimumNextStatisticsCollectionSequence()",
        ].joined(separator: "\n")
        // Indentation is exact at this actor-owned method, not another family's gate.
        XCTAssertTrue(source.contains(postRead))
        XCTAssertFalse(epochOwnershipSourceFence(source.replacingOccurrences(
            of: postRead, with: movedPostRead), codec: codec))
        for (old, replacement) in [
            ("defer { owner.networkAdaptationActualEpochRetire(entry) }", ""),
            ("guard owner.networkAdaptationActualEpochAdmit(entry, boundary: self) else", "guard true else"),
            ("let minimum = try owner.networkAdaptationActualEpochSealMinimum(entry)", "let minimum: UInt64? = nil"),
            ("let minimum = try owner.networkAdaptationActualEpochSealMinimum(entry)", "let minimum = try owner.networkAdaptationActualEpochSealMinimum(entry); _ = try owner.networkAdaptationActualEpochSealMinimum(entry)"),
            ("case .admit: throw BelugaNetworkAdaptationOwnerError.invalidResult", "case .admit: return .admission(nil)"),
            ("isPublishingActualEpoch = entry.permitsInertNegativeControls", "isPublishingActualEpoch = true"),
            ("owner.networkAdaptationActualEpochCommit(.init(entry: entry, replacement: packet.replacement))", "callback(packet)"),
        ] {
            XCTAssertTrue(codec.contains(old), old)
            XCTAssertFalse(epochOwnershipSourceFence(source, codec: codec.replacingOccurrences(of: old, with: replacement)), old)
        }
        let finalStoreGuard = [
            "            case let .ready(packet):",
            "                guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }",
            "                owner.networkAdaptationActualEpochCommit(.init(entry: entry, replacement: packet.replacement))",
        ].joined(separator: "\n")
        XCTAssertTrue(codec.contains(finalStoreGuard))
        XCTAssertFalse(epochOwnershipSourceFence(source, codec: codec.replacingOccurrences(
            of: finalStoreGuard, with: finalStoreGuard.replacingOccurrences(
                of: "guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }", with: ""))))
    }

    private var epochWitnessClauses: [String] {
        ["pendingNativeOwnerEpochEntry === entry,", "entry.owner === self,",
         "entry.boundary === screenVideoAdaptationOwnerBoundary,", "entry.generation == peerGeneration,",
         "entry.sourcePeer === peer,", "entry.coordinator === recoveryCoordinator,",
         "entry.source === captureSource,", "entry.sink === captureSink,",
         "entry.authorization === captureAuthorization,", "entry.forwarding === captureForwardingAuthorization,",
         "entry.audioSource === audioSource,", "entry.audioSink === audioSink,",
         "entry.audioAuthorization === audioAuthorization,",
         "entry.visibilityEpoch == screenVisibilityCommandEpoch,", "entry.recoveryEpoch == recoveryProofEpoch"]
    }

    private func epochOwnershipSourceFence(_ source: String, codec: String) -> Bool {
        func tokens(_ s: String) -> String { s.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        func body(_ s: String, _ start: String, _ end: String) -> String? {
            guard let a = s.range(of: start), let b = s.range(of: end, range: a.upperBound..<s.endIndex) else { return nil }
            return tokens(String(s[a.lowerBound..<b.lowerBound]))
        }
        func count(_ s: String, _ needle: String) -> Int { s.components(separatedBy: needle).count - 1 }
        func ordered(_ s: String, _ needles: [String]) -> Bool {
            var at = s.startIndex
            for n in needles {
                guard let r = s.range(of: n, range: at..<s.endIndex) else { return false }
                at = r.upperBound
            }
            return true
        }
        guard source.contains("allNetworkAdaptationOwnerWritersAreEnrolled = false"),
              source.contains("ownedStopPublicationIsEnrolled = false"),
              count(source, "beginPostResumeScreenVideoAdaptationEpoch()") == 9,
              let origin = body(source, "    private func networkAdaptationActualEpochPublicationOrigin()",
                  "    private func networkAdaptationActualEpochEntry()"),
              let factory = body(source, "    private func networkAdaptationActualEpochEntry()",
                  "    func networkAdaptationActualEpochAdmit("),
              let admission = body(source, "    func networkAdaptationActualEpochAdmit(",
                  "    private func networkAdaptationActualEpochNativeWitnessIsCurrent("),
              let witness = body(source, "    private func networkAdaptationActualEpochNativeWitnessIsCurrent(",
                  "    func networkAdaptationActualEpochSealMinimum("),
              let minimum = body(source, "    func networkAdaptationActualEpochSealMinimum(",
                  "    func networkAdaptationActualEpochIsCurrent("),
              let matches = body(source, "    func networkAdaptationActualEpochMatches(",
                  "    func networkAdaptationActualEpochCapture("),
              let retire = body(source, "    func networkAdaptationActualEpochRetire(",
                  "    func networkAdaptationActualEpochCommit("),
              let commit = body(source, "    func networkAdaptationActualEpochCommit(",
                  "\n}\n\n// Append to WorldwideScreenService.swift."),
              let adapter = body(codec, "    func publishActualEpoch(", "    #if DEBUG\n    func testSwallowedActualEpochOuterReentry("),
              let prefix = body(codec, "    private func preparePublicationHeld(",
                  "    private func prepareAlreadyAdmittedPublicationHeld("),
              let remainder = body(codec, "    private func prepareAlreadyAdmittedPublicationHeld(",
                  "    func publishCommittedResume(") else { return false }
        guard origin.contains("if Self.allNetworkAdaptationOwnerWritersAreEnrolled && Self.ownedStopPublicationIsEnrolled { return .nativeEpoch }"),
              origin.contains("#if DEBUG if nativeOwnerEpochPublicationEnabled { return .inertFixture } #endif return nil"),
              factory.contains("guard pendingNativeOwnerEpochEntry == nil, let origin = networkAdaptationActualEpochPublicationOrigin()"),
              admission.contains("let fresh = entry.phase == .fresh entry.phase = .retired guard fresh, entry.owner === self, entry.boundary === boundary,"),
              witness.contains("case .nativeEpoch: guard Self.allNetworkAdaptationOwnerWritersAreEnrolled, Self.ownedStopPublicationIsEnrolled else { return false }"),
              witness.contains("nativeOwnerEpochPublicationEnabled else { return false }"),
              !witness.contains("isStopped"), !witness.contains("isValid"),
              minimum.contains("entry.phase == .admitted, case .unread = entry.payload,"),
              count(minimum, "entry.sourcePeer?.minimumNextStatisticsCollectionSequence()") == 1,
              count(minimum, "networkAdaptationActualEpochNativeWitnessIsCurrent(entry)") == 2,
              ordered(minimum, ["entry.phase == .admitted, case .unread = entry.payload,",
                  "networkAdaptationActualEpochNativeWitnessIsCurrent(entry)",
                  "let minimum = entry.sourcePeer?.minimumNextStatisticsCollectionSequence()",
                  "guard networkAdaptationActualEpochNativeWitnessIsCurrent(entry)",
                  "entry.payload = .sealed(minimum)", "entry.phase = .sealed", "return minimum"]),
              minimum.contains("entry.payload = .sealed(minimum) entry.phase = .sealed return minimum"),
              matches.contains("key == [216, 0, 0, minimum ?? 0, 0, minimum == nil ? 0 : 1]"),
              retire.contains("entry.owner === self, entry.boundary === screenVideoAdaptationOwnerBoundary, pendingNativeOwnerEpochEntry === entry else { return } pendingNativeOwnerEpochEntry = nil"),
              retire.contains("if entry.phase != .published { entry.phase = .retired }"),
              commit.contains("precondition(pendingNativeOwnerEpochEntry === packet.entry)"),
              ordered(commit, ["packet.entry.phase = .published", "pendingNativeOwnerEpochEntry = nil", "screenVideoAdaptationOwner = packet.replacement.value"]),
              commit.hasSuffix("screenVideoAdaptationOwner = packet.replacement.value }"),
              count(adapter, "owner.networkAdaptationActualEpochAdmit(entry, boundary: self)") == 1,
              count(adapter, "owner.networkAdaptationActualEpochSealMinimum(entry)") == 1,
              adapter.contains("case .admit: throw BelugaNetworkAdaptationOwnerError.invalidResult"),
              adapter.contains("isPublishingActualEpoch = entry.permitsInertNegativeControls"),
              adapter.contains("case let .ready(packet): guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry } owner.networkAdaptationActualEpochCommit(.init(entry: entry, replacement: packet.replacement))"),
              ordered(adapter, ["defer { owner.networkAdaptationActualEpochRetire(entry) }", "let result = try withGuard",
                  "owner.networkAdaptationActualEpochAdmit(entry, boundary: self)", "!poisoned",
                  "owner.networkAdaptationActualEpochSealMinimum(entry)", "!poisoned", "let event = OwnerPublicationEvent.clocked",
                  "let witness = OwnerPublicationWitness", "prepareAlreadyAdmittedPublicationHeld(",
                  "owner.networkAdaptationActualEpochCommit(.init(entry: entry, replacement: packet.replacement))"]),
              !adapter.contains("await "), !adapter.contains("preparePublicationHeld("),
              count(prefix, "read(.admit(key: event.key))") == 1,
              prefix.contains("guard let witness else { return .refused } return try prepareAlreadyAdmittedPublicationHeld(event: event, witness: witness,"),
              !remainder.contains("read(.admit("), !remainder.contains("await ") else { return false }
        for clause in epochWitnessClauses where count(witness, clause) != 1 { return false }
        return true
    }

    private func stopOwnershipSourceFence(_ source: String) -> Bool {
        func tokens(_ value: String) -> String {
            value.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }.joined(separator: " ")
        }
        func slice(_ start: String, _ end: String) -> String? {
            guard let lower = source.range(of: start)?.upperBound,
                  let upper = source.range(of: end, range: lower..<source.endIndex)?.lowerBound
            else { return nil }
            return tokens(String(source[lower..<upper]))
        }
        func ordered(_ body: String, _ needles: [String]) -> Bool {
            var cursor = body.startIndex
            for needle in needles {
                guard let found = body.range(of: needle, range: cursor..<body.endIndex)
                else { return false }
                cursor = found.upperBound
            }
            return true
        }
        guard let wrapper = slice("    func stop() async {", "    private struct ServiceStopPlan:"),
              let begin = slice("    private func beginStop() -> ServiceStopPlan {",
                                "    private func finishStop(_ plan: consuming ServiceStopPlan) async {"),
              let finish = slice("    private func finishStop(_ plan: consuming ServiceStopPlan) async {",
                                 "    private func waitForStopToFinish() async {")
        else { return false }
        guard source.contains("private struct ServiceStopPlan: ~Copyable"),
              !begin.contains("await "), !begin.contains("defer "),
              wrapper.contains("let plan = beginStop() await finishStop(consume plan) }"),
              ordered(wrapper, ["guard !isStopped else {", "await waitForStopToFinish()",
                  "try await stopScreenCapture()", "await stopSystemAudio()", "return", "let plan = beginStop()"]),
              ordered(begin, ["let teardownWatchdog = makeServiceTeardownWatchdog()", "isStopped = true",
                  "stopIsInProgress = true", "let ownerStopOrigin = networkAdaptationActualStopPublicationOrigin()",
                  "applyNativeOwnerStopPublication(.endShow, origin: ownerStopOrigin)",
                  "screenVideoAdaptationTask?.cancel()", "applyNativeOwnerStopPublication(.stopSampling, origin: ownerStopOrigin)",
                  "recoveryProofAuthorization?.revoke()", "revokeCaptureAuthorization()",
                  "revokeSystemAudioAuthorization()", "captureSink?.stopForwarding()",
                  "audioSink?.stopForwarding()",
                  "return ServiceStopPlan(coordinator: coordinator, teardownWatchdog: teardownWatchdog)"]),
              finish.hasPrefix("defer { finishStopping() } await plan.coordinator?.cancel()"),
              ordered(finish, ["try await stopScreenCapture()", "await stopSystemAudio()",
                  "await peer.close(reason: .hostStopped)", "self.peer = nil",
                  "if nativeScreenStopNeedsRetry", "try await stopScreenCapture()",
                  "if nativeSystemAudioStopNeedsRetry", "await stopSystemAudio()",
                  "await signaling.close()", "completionContinuation.yield(())",
                  "completionContinuation.finish()", "plan.teardownWatchdog?.cancel()",
                  "await plan.teardownWatchdog?.value"])
        else { return false }
        return true
    }

    func testActualInertServiceOwnerRepeatedStopIsIdempotent() async throws {
        try await assertActualEpochPublication(faults: [.refused, .malformed, .wrongBoundary, .invocationExhausted])
        try await assertActualResetPublication(faults: [.refused, .malformed, .wrongBoundary, .invocationExhausted])
        let endShow: [StopFault] = [.init(operation: 202, kind: .refused),
                                   .init(operation: 202, kind: .malformed)]
        let sampling: [StopFault] = [.init(operation: 105, kind: .refused),
                                    .init(operation: 105, kind: .malformed)]
        let scenarios = endShow.map { [$0] } + sampling.map { [$0] }
            + endShow.flatMap { first in sampling.map { [first, $0] } }
        XCTAssertEqual(scenarios.count, 8)
        for (profile, effectiveCap) in profiles {
            for faults in scenarios {
                try await runActualStop(profile: profile, effectiveCap: effectiveCap, faults: faults)
            }
        }
    }

    func testActualInertServiceIsolatedPublicationRetainsRustAndStickyReentryGuard() async throws {
        try await assertActualEpochPublication(faults: [.swallowedReentry, .outerReentry])
        try await assertActualResetPublication(faults: [.swallowedReentry, .outerReentry])
        try await assertPreviousIsolatedPublicationAssay()
        let endShow: [StopFault] = [.init(operation: 202, kind: .refused),
                                   .init(operation: 202, kind: .malformed),
                                   .init(operation: 202, kind: .swallowedReentry)]
        let sampling: [StopFault] = [.init(operation: 105, kind: .refused),
                                    .init(operation: 105, kind: .malformed),
                                    .init(operation: 105, kind: .swallowedReentry)]
        var scenarios: [[StopFault]] = [[endShow[2]], [sampling[2]]]
        for first in endShow {
            for second in sampling where isReentry(first) || isReentry(second) {
                scenarios.append([first, second])
            }
        }
        XCTAssertEqual(scenarios.count, 7)
        for (profile, effectiveCap) in profiles {
            for faults in scenarios {
                try await runActualStop(profile: profile, effectiveCap: effectiveCap, faults: faults)
            }
        }
    }

    // Keep the default/non-opt-in actual Stop baseline alongside opt-in adoption.
    // Release remains on this original path until the all-writer barrier is closed.
    private func assertPreviousNonOptInStopBaseline() async throws {
        for (profile, effectiveCap) in profiles {
            // This existing fixture supplies every audio-routing dependency;
            // neither a default .live() initializer nor start/startPeer is used.
            let f = try BatchAActualServiceFixture(profile: profile)
            let initial = await f.service.nativeOwnerStorageInertObservationForTesting()
            assertInitial(initial, effectiveCap: effectiveCap)
            XCTAssertTrue(f.hal.inputWrites.isEmpty)
            XCTAssertEqual(f.hal.listenerCount, 0)

            await f.service.stop() // Actual production stop; not a copied reducer.
            let stopped = await f.service.nativeOwnerStorageInertObservationForTesting()
            XCTAssertEqual(stopped.policy, initial.policy)
            XCTAssertEqual(stopped.revision, 1)
            XCTAssertFalse(stopped.fastStatisticsAvailable)
            XCTAssertNil(stopped.laneRawValue)
            XCTAssertNil(stopped.evidenceTime)
            XCTAssertNil(stopped.minimumCollectionSequence)
            XCTAssertNil(stopped.applied)
            assertAbsentPolicySidecars(stopped)
            let lifecycle = await f.service.batchAICERecoveryPolicyReceiverSnapshotForTesting()
            XCTAssertTrue(lifecycle.stopped)
            XCTAssertFalse(lifecycle.stopInProgress)
            XCTAssertFalse(lifecycle.peerIsPresent || lifecycle.coordinatorIsPresent)
            XCTAssertFalse(lifecycle.captureAuthorizationIsValid || lifecycle.audioAuthorizationIsValid)
            await assertClean(f)
        }

        let f = try BatchAActualServiceFixture(profile: .fullPrimary)
        let initial = await f.service.nativeOwnerStorageInertObservationForTesting()
        assertInitial(initial, effectiveCap: 8_000_000)
        await f.service.stop()
        let stopped = await f.service.nativeOwnerStorageInertObservationForTesting()
        XCTAssertEqual(stopped.revision, 1)
        await assertClean(f)
        let events = f.trace.events

        await f.service.stop() // Existing already-stopped native-resource retry branch.
        let repeated = await f.service.nativeOwnerStorageInertObservationForTesting()
        XCTAssertEqual(repeated, stopped)
        XCTAssertEqual(f.trace.events, events)
        XCTAssertEqual(f.trace.count("media.stop"), 1)
        await assertClean(f)
    }

    private func assertActualEpochPublication(faults: [WorldwideScreenService.NativeOwnerEpochPublicationFault]) async throws {
        for (profile, _) in profiles {
            for fault in faults {
                let f = try BatchAActualServiceFixture(profile: profile)
                do {
                    let v = try await f.service.nativeOwnerEpochPublicationInertObservationForTesting(fault: fault)
                    var expected = v.before.atoms
                    let accepted = fault == .none
                    if accepted { expected[168] = .init(kind: 1, present: 1, high: 0, low: 1) }
                    assertSnapshot(v.after, atoms: expected, retaining: v.before)
                    assertSnapshot(v.afterReplay, atoms: expected, retaining: v.before)
                    XCTAssertEqual(v.before.atoms.count, 179)
                    XCTAssertEqual(v.before.times.count, 13)
                    XCTAssertTrue(v.before.times.allSatisfy { $0 == nil })
                    XCTAssertNil(v.before.anchor); XCTAssertNil(v.before.route)
                    XCTAssertEqual(v.before.atoms[168], .init(kind: 1, present: 1, high: 0, low: 0))
                    XCTAssertEqual(v.before.atoms[172], .init(kind: 1, present: 0, high: 0, low: 0))
                    XCTAssertEqual(v.peerGetterCalls, 0) // nil peer is NOT a real getter call.
                    let bodyCases: [WorldwideScreenService.NativeOwnerEpochPublicationFault] = [.none, .refused, .malformed, .swallowedReentry]
                    let entersBody = bodyCases.contains(fault)
                    XCTAssertEqual(v.minimumResolutions, entersBody ? 1 : 0)
                    XCTAssertEqual(v.rawCalls, entersBody ? 1 : 0)
                    let clockCases: [WorldwideScreenService.NativeOwnerEpochPublicationFault] = [.none, .malformed, .swallowedReentry]
                    let readsClock = clockCases.contains(fault)
                    XCTAssertEqual(v.clockReads, readsClock ? 1 : 0)
                    XCTAssertEqual(v.stores, accepted ? 1 : 0)
                    XCTAssertTrue(v.consumedBeforeReplay)
                    XCTAssertTrue(v.pendingCleared)
                    XCTAssertFalse(v.replayAccepted)
                    XCTAssertFalse(v.replayDidWork)
                    let disposition: String
                    switch fault {
                    case .none: disposition = "accepted"
                    case .refused, .wrongBoundary: disposition = "refused"
                    case .malformed: disposition = "malformed"
                    case .swallowedReentry, .outerReentry: disposition = "reentry"
                    case .invocationExhausted: disposition = "exhausted"
                    }
                    XCTAssertEqual(v.disposition, disposition)
                    XCTAssertEqual(v.operation, accepted ? 216 : nil)
                    XCTAssertEqual(v.invocation, accepted ? 1 : nil)
                    if fault == .invocationExhausted { XCTAssertNil(v.afterFresh) }
                    else {
                        let fresh = try XCTUnwrap(v.afterFresh)
                        expected[168] = .init(kind: 1, present: 1, high: 0, low: accepted ? 2 : 1)
                        assertSnapshot(fresh, atoms: expected, retaining: v.before)
                    }
                    await f.service.stop()
                    await assertClean(f)
                } catch {
                    await f.service.stop()
                    await assertClean(f)
                    throw error
                }
            }
        }
    }

    private func assertActualResetPublication(faults: [WorldwideScreenService.NativeOwnerResetPublicationFault]) async throws {
        for (profile, _) in profiles {
            for initial in WorldwideScreenService.NativeOwnerResetInitialContext.allCases {
                for fault in faults {
                    let f = try BatchAActualServiceFixture(profile: profile)
                    do {
                        let v = try await f.service.nativeOwnerResetPublicationInertObservationForTesting(initial: initial, fault: fault)
                        let absent = initial == .absent
                        let failed = initial == .pending
                        let primaryAccepted = !absent && (fault == .none || fault == .epochRefused)
                        let primaryOperation: UInt32 = failed ? 218 : 107
                        let epochAccepted = primaryAccepted && !failed && fault != .epochRefused
                        var expected = v.before.atoms
                        if primaryAccepted && failed {
                            expected[4] = .init(kind: 7, present: 1, high: 0, low: 7)
                            expected[168] = .init(kind: 1, present: 1, high: 0, low: 1)
                        }
                        if primaryAccepted {
                            assertSnapshot(try XCTUnwrap(v.afterPrimary), atoms: expected, retaining: v.before)
                        } else { XCTAssertNil(v.afterPrimary) }
                        if epochAccepted { expected[168] = .init(kind: 1, present: 1, high: 0, low: 1) }
                        assertSnapshot(v.after, atoms: expected, retaining: v.before)
                        XCTAssertEqual(v.before.atoms.count, 179); XCTAssertEqual(v.before.times.count, 13)
                        // Original and Rust tier-demand bootstrap at survival (wire tier 5),
                        // independently of the reset operation and either fixture bitrate cap.
                        XCTAssertEqual(v.before.atoms[4], .init(kind: 7, present: 1, high: 0, low: 5))
                        XCTAssertEqual(v.before.atoms[168], .init(kind: 1, present: 1, high: 0, low: 0))
                        XCTAssertTrue(v.before.times.allSatisfy { $0 == nil })
                        XCTAssertNil(v.before.anchor); XCTAssertNil(v.before.route)
                        XCTAssertTrue(v.cancelledOnce); XCTAssertTrue(v.contextCleared); XCTAssertTrue(v.pendingCleared)
                        XCTAssertFalse(v.repeatClaim); XCTAssertEqual(v.latchCommitted, initial == .committed)
                        XCTAssertTrue(v.bindingWasOlder)
                        XCTAssertEqual(v.operations, absent ? [] : (primaryAccepted && !failed ? [primaryOperation, 216] : [primaryOperation]))
                        let entersProducer = !absent && [.none, .epochRefused, .refused, .malformed, .swallowedReentry].contains(fault)
                        XCTAssertEqual(v.rawCalls, entersProducer ? 1 : 0)
                        XCTAssertEqual(v.clockReads, entersProducer && failed && fault != .refused ? 1 : 0)
                        let disposition: String
                        if absent || fault == .none || (failed && fault == .epochRefused) { disposition = "accepted" }
                        else {
                            switch fault {
                            case .refused, .wrongBoundary, .epochRefused: disposition = "refused"
                            case .malformed: disposition = "malformed"
                            case .swallowedReentry, .outerReentry: disposition = "reentry"
                            case .invocationExhausted: disposition = "exhausted"
                            case .none: disposition = "accepted"
                            }
                        }
                        XCTAssertEqual(v.disposition, disposition)
                        await f.service.stop()
                        await assertClean(f)
                    } catch {
                        await f.service.stop()
                        await assertClean(f)
                        throw error
                    }
                }
            }
        }
    }

    private func assertResetOwnershipSourceFence() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "macOS/Sources/CaptureServer/WorldwideScreenService.swift"), encoding: .utf8)
        let codec = try String(contentsOf: root.appendingPathComponent(
            "macOS/Sources/CaptureServer/BelugaNetworkAdaptationOwnerCodec.swift"), encoding: .utf8)
        XCTAssertTrue(resetOwnershipSourceFence(source, codec: codec))
        for (old, replacement) in [
            ("defer { retireOriginalResumeResetContext(original, suspension: suspension) }", ""),
            ("let claimed = context.finalAcknowledgementCommit.claimFailure()", "let claimed = context.finalAcknowledgementCommit.isCommitted"),
            ("let claimed = context.finalAcknowledgementCommit.claimFailure()", "let claimed = context.finalAcknowledgementCommit.claimFailure(); _ = context.finalAcknowledgementCommit.claimFailure()"),
            ("if entry.operation == 107 {", "if true {"),
            ("context.ownerResetEntryID == ObjectIdentifier(entry),", ""),
            ("entry.generation == peerGeneration, n.sourcePeer === peer,", "entry.binding.peerGeneration == peerGeneration, n.sourcePeer === peer,"),
            ("original.probeAuthorization?.revoke()", ""),
            ("original.forwardingAuthorization?.revoke()", ""),
            ("current.finalAcknowledgementCommit === original.finalAcknowledgementCommit,", ""),
            ("precondition(pendingNativeOwnerResetEntry === packet.entry)", ""),
            ("let fresh = entry.phase == .fresh\n        entry.phase = .retired", "let fresh = entry.phase == .fresh"),
            ("guard case .accepted = try boundary.publishActualReset(entry, on: self) else", "guard true else"),
            ("screenVideoAdaptationOwner = packet.replacement.value", "screenVideoAdaptationOwner = packet.replacement.value; callback()"),
        ] {
            XCTAssertTrue(source.contains(old), old)
            XCTAssertFalse(resetOwnershipSourceFence(source.replacingOccurrences(of: old, with: replacement), codec: codec), old)
        }
        for (old, replacement) in [
            ("defer { owner.networkAdaptationActualResetRetire(entry) }", ""),
            ("owner.networkAdaptationActualResetAdmit(entry, boundary: self, key: key)", "true"),
            ("isPublishingActualReset = entry.permitsInertNegativeControls", "isPublishingActualReset = true"),
            ("owner.networkAdaptationActualResetCommit(.init(entry: entry, replacement: packet.replacement))", "callback(packet)"),
        ] {
            XCTAssertTrue(codec.contains(old), old)
            XCTAssertFalse(resetOwnershipSourceFence(source, codec: codec.replacingOccurrences(of: old, with: replacement)), old)
        }
        let cancelThenClaim = "cancelAutomaticScreenMediaResumeTimeout()"
        let wrapperStart = try XCTUnwrap(source.range(of: "    private func publishActualResetOwner()")?.lowerBound)
        let wrapperEnd = try XCTUnwrap(source.range(of: "    private func retireOriginalResumeResetContext(",
            range: wrapperStart..<source.endIndex)?.lowerBound)
        let wrapper = String(source[wrapperStart..<wrapperEnd])
        let movedCancel = wrapper.replacingOccurrences(of: cancelThenClaim, with: "")
            .replacingOccurrences(of: "let claimed = context.finalAcknowledgementCommit.claimFailure()",
                with: "let claimed = context.finalAcknowledgementCommit.claimFailure(); " + cancelThenClaim)
        XCTAssertFalse(resetOwnershipSourceFence(source.replacingOccurrences(of: wrapper, with: movedCancel), codec: codec))
        let finalStoreGuard = [
            "            case let .ready(packet):",
            "                guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }",
            "                owner.networkAdaptationActualResetCommit(.init(entry: entry, replacement: packet.replacement))",
        ].joined(separator: "\n")
        XCTAssertTrue(codec.contains(finalStoreGuard))
        XCTAssertFalse(resetOwnershipSourceFence(source, codec: codec.replacingOccurrences(of: finalStoreGuard,
            with: finalStoreGuard.replacingOccurrences(of: "guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry }", with: ""))))
    }

    private func resetOwnershipSourceFence(_ source: String, codec: String) -> Bool {
        func tokens(_ s: String) -> String { s.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        func body(_ s: String, _ a: String, _ b: String) -> String? {
            guard let lo = s.range(of: a), let hi = s.range(of: b, range: lo.upperBound..<s.endIndex) else { return nil }
            return tokens(String(s[lo.lowerBound..<hi.lowerBound]))
        }
        func count(_ s: String, _ n: String) -> Int { s.components(separatedBy: n).count - 1 }
        func ordered(_ s: String, _ needles: [String]) -> Bool {
            var cursor = s.startIndex
            for needle in needles {
                guard let p = s.range(of: needle, range: cursor..<s.endIndex) else { return false }
                cursor = p.upperBound
            }
            return true
        }
        guard let wrapper = body(source, "    private func publishActualResetOwner()", "    private func retireOriginalResumeResetContext("),
              let cleanup = body(source, "    private func retireOriginalResumeResetContext(", "    private func networkAdaptationActualResetWitness("),
              let witness = body(source, "    private func networkAdaptationActualResetWitness(", "    func networkAdaptationActualResetAdmit("),
              let admission = body(source, "    func networkAdaptationActualResetAdmit(", "    func networkAdaptationActualResetIsCurrent("),
              let origin = body(source, "    private func networkAdaptationActualResetOrigin()", "    // The cancellation and latch claim"),
              let commit = body(source, "    func networkAdaptationActualResetCommit(", "\n}\n\n// Append to WorldwideScreenService.swift."),
              let adapter = body(codec, "    func publishActualReset(", "    #if DEBUG\n    func testSwallowedActualResetOuterReentry(") else { return false }
        return source.contains("allNetworkAdaptationOwnerWritersAreEnrolled = false")
            && source.contains("ownedStopPublicationIsEnrolled = false")
            && count(wrapper, "context.finalAcknowledgementCommit.claimFailure()") == 1
            && wrapper.contains(": (context.finalAcknowledgementCommit.isCommitted ? .alreadyCommitted : .alreadyFailureClaimed)")
            && origin.contains("if Self.allNetworkAdaptationOwnerWritersAreEnrolled && Self.ownedStopPublicationIsEnrolled { return .nativeReset }")
            && ordered(wrapper, ["defer { retireOriginalResumeResetContext(original, suspension: suspension) }",
                "cancelAutomaticScreenMediaResumeTimeout()", "context.finalAcknowledgementCommit.claimFailure()",
                "let entry = BelugaNetworkAdaptationActualResetEntry", "pendingNativeOwnerResetEntry = entry",
                "defer { networkAdaptationActualResetRetire(entry) }", "boundary.publishActualReset(entry, on: self)",
                "if entry.operation == 107 {", "let epoch = try networkAdaptationActualEpochEntry()", "publishActualEpoch(epoch, on: self)"])
            && wrapper.contains("guard case .accepted = try boundary.publishActualReset(entry, on: self) else")
            && !wrapper.contains("await ") && !wrapper.contains("screenVideoAdaptationOwner =")
            && witness.contains("Self.allNetworkAdaptationOwnerWritersAreEnrolled, Self.ownedStopPublicationIsEnrolled")
            && witness.contains("context.ownerResetEntryID == ObjectIdentifier(entry),")
            && witness.contains("entry.generation == peerGeneration, n.sourcePeer === peer,")
            && !witness.contains("entry.binding.peerGeneration == peerGeneration")
            && !witness.contains("isStopped") && !witness.contains("isValid")
            && ordered(admission, ["let fresh = entry.phase == .fresh", "entry.phase = .retired",
                "guard fresh, entry.boundary === boundary, key == entry.key,", "networkAdaptationActualResetWitness(entry)", "entry.phase = .admitted"])
            && ordered(cleanup, ["screenMediaSuspension.snapshot == suspension", "current.finalAcknowledgementCommit === original.finalAcknowledgementCommit",
                "original.probeAuthorization?.revoke()", "original.forwardingAuthorization?.revoke()",
                "automaticScreenMediaResumeContext = nil", "screenMediaSuspension.retire()"])
            && !cleanup.contains("screenVideoAdaptationOwner =") && !cleanup.contains("await ")
            && commit.contains("precondition(pendingNativeOwnerResetEntry === packet.entry)")
            && commit.hasSuffix("packet.entry.phase = .published pendingNativeOwnerResetEntry = nil screenVideoAdaptationOwner = packet.replacement.value }")
            && ordered(adapter, ["defer { owner.networkAdaptationActualResetRetire(entry) }", "let result = try withGuard",
                "isPublishingActualReset = entry.permitsInertNegativeControls", "preparePublicationHeld(event: event",
                "owner.networkAdaptationActualResetAdmit(entry, boundary: self, key: key)", "owner.networkAdaptationActualResetCommit("])
            && adapter.contains("case let .ready(packet): guard !poisoned else { throw BelugaNetworkAdaptationOwnerError.reentry } owner.networkAdaptationActualResetCommit(")
            && count(adapter, "owner.networkAdaptationActualResetAdmit(entry, boundary: self, key: key)") == 1
            && !adapter.contains("claimFailure") && !adapter.contains("await ")
    }

    // Preserve the previously qualified same-actor simulated-slot assay as
    // additive coverage. This helper is not an actual Owner adoption claim.
    private func assertPreviousIsolatedPublicationAssay() async throws {
        for profile in [WorldwideScreenServiceFeatureProfile.fullPrimary, .secondaryTest] {
            let f = try BatchAActualServiceFixture(profile: profile)
            let v = try await f.service.nativeOwnerPublicationIsolatedInertObservationForTesting()
            XCTAssertTrue(v.nestedReentryRejected)
            XCTAssertTrue(v.outerReentryRejected)
            XCTAssertEqual(v.rejectedPublications, 0)
            XCTAssertEqual(v.rejected, v.actualBefore)
            XCTAssertEqual(v.acceptedPublications, 1)
            XCTAssertEqual(v.operation, 105)
            XCTAssertEqual(v.invocation, 2)
            XCTAssertFalse(v.collectorEnabled)
            XCTAssertEqual(v.rawInvocations, [1, 2])
            XCTAssertEqual(v.actualAfter, v.actualBefore)
            XCTAssertEqual(v.actualBefore.atoms.count, 179)
            XCTAssertEqual(v.actualBefore.times.count, 13)
            XCTAssertTrue(v.actualBefore.times.allSatisfy { $0 == nil })
            XCTAssertNil(v.actualBefore.anchor)
            XCTAssertNil(v.actualBefore.route)
            var expected = v.actualBefore.atoms
            expected[168] = .init(kind: 1, present: 1, high: 0, low: 1)
            XCTAssertEqual(v.accepted.atoms, expected)
            XCTAssertEqual(v.accepted.times, v.actualBefore.times)
            XCTAssertEqual(v.accepted.anchor, v.actualBefore.anchor)
            XCTAssertEqual(v.accepted.route, v.actualBefore.route)
            XCTAssertEqual(v.trace, ["admission", "sourceRead", "afterImport", "precommit",
                "admission", "sourceRead", "afterImport", "precommit", "finalWitness", "recapture"])
            await f.service.stop()
            await assertClean(f)
        }
    }

    private func isReentry(_ fault: StopFault) -> Bool {
        switch fault.kind {
        case .swallowedReentry: true
        case .refused, .malformed: false
        }
    }

    private func runActualStop(profile: WorldwideScreenServiceFeatureProfile,
                              effectiveCap: Int, faults: [StopFault]) async throws {
        // Every IO dependency comes from the existing inert fixture. Never call
        // start/startPeer or inject an arbitrary Owner or native capture resource.
        let f = try BatchAActualServiceFixture(profile: profile)
        do {
            let initial = await f.service.nativeOwnerStorageInertObservationForTesting()
            assertInitial(initial, effectiveCap: effectiveCap)
            try await f.service.enableNativeOwnerStopPublicationForTesting(faults: faults)
            let enabled = try await f.service.nativeOwnerStopPublicationObservationForTesting()
            XCTAssertTrue(enabled.cuts.isEmpty)
            XCTAssertTrue(enabled.attemptedOperations.isEmpty)
            let original = enabled.current
            XCTAssertEqual(original.atoms.count, 179)
            XCTAssertEqual(original.times.count, 13)
            XCTAssertTrue(original.times.allSatisfy { $0 == nil })
            XCTAssertNil(original.anchor)
            XCTAssertNil(original.route)
            let initialRevision = try XCTUnwrap(original.atoms.indices.contains(168)
                ? original.atoms[168] : nil)
            XCTAssertEqual(initialRevision, .init(kind: 1, present: 1, high: 0, low: 0))
            XCTAssertTrue(f.hal.inputWrites.isEmpty)
            XCTAssertEqual(f.hal.listenerCount, 0)

            // This creates real monitor ownership over fake HAL operations; Stop must
            // still remove/join it when either Rust publication refuses or reenters.
            await f.service.batchAStartOnlyInertRoutingMonitorForTesting()
            XCTAssertEqual(f.hal.listenerCount, profile == .fullPrimary ? 3 : 0)
            let afterMonitor = try await f.service.nativeOwnerStopPublicationObservationForTesting()
            XCTAssertEqual(afterMonitor.current, original)
            XCTAssertTrue(afterMonitor.cuts.isEmpty)
            XCTAssertTrue(afterMonitor.attemptedOperations.isEmpty)

            let finished = expectation(description: "actual Stop completes despite Owner publication denial")
            let completion = Task {
                var count = 0
                for await _ in f.service.completion { count += 1 }
                XCTAssertEqual(count, 1)
                finished.fulfill()
            }
            await f.service.stop() // SAME actual native cleanup method for every case.
            await fulfillment(of: [finished], timeout: 1)
            completion.cancel()
            await completion.value
            await assertClean(f)

            let stopped = try await f.service.nativeOwnerStopPublicationObservationForTesting()
            XCTAssertEqual(stopped.attemptedOperations, [202, 105])
            XCTAssertEqual(stopped.cuts.count, 2)
            guard stopped.cuts.count == 2 else { return }
            var expectedAtoms = original.atoms
            for (cut, operation) in zip(stopped.cuts, [UInt32(202), UInt32(105)]) {
                XCTAssertEqual(cut.operation, operation)
                assertSnapshot(cut.before, atoms: expectedAtoms, retaining: original)
                if let fault = faults.first(where: { $0.operation == operation }) {
                    switch fault.kind {
                    case .refused: XCTAssertEqual(cut.disposition, .refused)
                    case .malformed: XCTAssertEqual(cut.disposition, .malformed)
                    case .swallowedReentry: XCTAssertEqual(cut.disposition, .reentry)
                    }
                    // No failed draft or handwritten Swift fallback may change even
                    // one field. A later cut starts from this exact accepted tuple.
                } else {
                    XCTAssertEqual(cut.disposition, .accepted)
                    // Constructor-derived EndShow is a truthful zero-read/no-change
                    // branch. Only accepted105 advances the existing revision.
                    if operation == 105 {
                        expectedAtoms[168] = .init(kind: 1, present: 1, high: 0, low: 1)
                    }
                }
                assertSnapshot(cut.after, atoms: expectedAtoms, retaining: original)
            }
            assertSnapshot(stopped.current, atoms: expectedAtoms, retaining: original)
            let stored = await f.service.nativeOwnerStorageInertObservationForTesting()
            XCTAssertEqual(stored.policy, initial.policy)
            XCTAssertEqual(stored.revision, expectedAtoms[168].low)
            XCTAssertFalse(stored.fastStatisticsAvailable)
            XCTAssertNil(stored.laneRawValue)
            XCTAssertNil(stored.evidenceTime)
            XCTAssertNil(stored.minimumCollectionSequence)
            XCTAssertNil(stored.applied)
            assertAbsentPolicySidecars(stored)
            let lifecycle = await f.service.batchAICERecoveryPolicyReceiverSnapshotForTesting()
            XCTAssertTrue(lifecycle.stopped)
            XCTAssertFalse(lifecycle.stopInProgress)
            XCTAssertFalse(lifecycle.peerIsConnected || lifecycle.iceIsConnected || lifecycle.controlChannelIsOpen)
            XCTAssertFalse(lifecycle.peerIsPresent || lifecycle.coordinatorIsPresent)
            XCTAssertFalse(lifecycle.captureAuthorizationIsValid || lifecycle.audioAuthorizationIsValid)
            let driver = await f.service.iPhoneMicrophoneForwardingSnapshot()
            XCTAssertEqual(driver.phase, .stopped)
            XCTAssertFalse(driver.transportAuthorized || driver.queueRunning)
            XCTAssertEqual(f.trace.count("devices.remove"), profile == .fullPrimary ? 1 : 0)
            XCTAssertEqual(f.trace.count("output.remove"), profile == .fullPrimary ? 2 : 0)
            XCTAssertEqual(f.trace.count("media.stop"), profile == .fullPrimary ? 1 : 0)

            let events = f.trace.events
            await f.service.stop() // Actual repeated-Stop join/retry, not another test path.
            let repeated = try await f.service.nativeOwnerStopPublicationObservationForTesting()
            XCTAssertEqual(repeated.current, stopped.current)
            XCTAssertEqual(repeated.attemptedOperations, stopped.attemptedOperations)
            XCTAssertEqual(repeated.cuts.count, stopped.cuts.count)
            for (again, first) in zip(repeated.cuts, stopped.cuts) {
                XCTAssertEqual(again.operation, first.operation)
                XCTAssertEqual(again.disposition, first.disposition)
                XCTAssertEqual(again.before, first.before)
                XCTAssertEqual(again.after, first.after)
            }
            let repeatedStored = await f.service.nativeOwnerStorageInertObservationForTesting()
            XCTAssertEqual(repeatedStored, stored)
            XCTAssertEqual(f.trace.events, events)
            await assertClean(f)
        } catch {
            // A regressed observation/import must not abandon the real monitor
            // or observer ownership installed earlier in this scenario.
            await f.service.stop()
            await assertClean(f)
            throw error
        }
    }

    private func assertSnapshot(_ value: Snapshot,
                                atoms: [WorldwideScreenService.NativeOwnerPublicationAtomObservation],
                                retaining source: Snapshot) {
        XCTAssertEqual(value.atoms, atoms) // Complete179 comparison, not selected fields.
        XCTAssertEqual(value.times, source.times) // All13 actual native Instant slots.
        XCTAssertEqual(value.anchor, source.anchor)
        XCTAssertEqual(value.route, source.route) // Whole Optional route, not presence.
    }

    private func assertInitial(_ v: Observation, effectiveCap: Int) {
        XCTAssertEqual(v.policy.configuredTotalRTPBitrateBps, effectiveCap)
        XCTAssertEqual(v.policy.baseFramesPerSecond, 30)
        XCTAssertNil(v.policy.peerGeneration)
        XCTAssertEqual(v.revision, 0)
        XCTAssertFalse(v.fastStatisticsAvailable)
        XCTAssertNil(v.laneRawValue)
        XCTAssertNil(v.evidenceTime)
        XCTAssertNil(v.minimumCollectionSequence)
        XCTAssertNil(v.applied)
        assertAbsentPolicySidecars(v)
    }

    private func assertAbsentPolicySidecars(_ v: Observation) {
        XCTAssertNil(v.policy.selectedRoute)
        let times = v.policy.networkAdaptationOwnerNativeTimes
        XCTAssertEqual(times.count, 13)
        XCTAssertTrue(times.allSatisfy { $0 == nil })
    }

    private func assertClean(_ f: BatchAActualServiceFixture) async {
        await f.service.batchADrainOwnedInertRoutingObserversForTesting()
        let joined = await f.service.batchAObserverJoinSnapshotForTesting()
        XCTAssertEqual(joined.retainedHandleCount, 0)
        XCTAssertEqual(joined.totalRetainedByKind, joined.totalJoinedByKind)
        XCTAssertEqual(f.hal.listenerCount, 0)
        XCTAssertTrue(f.hal.inputWrites.isEmpty)
        XCTAssertEqual(f.hal.inputUID, "BuiltInMic_UID")
        XCTAssertFalse(f.gate.isOpen)
        XCTAssertEqual(f.listenerCleanup.retainedJobCount, 0)
        XCTAssertEqual(f.inputCleanup.retainedJobCount, 0)
        XCTAssertEqual(f.serviceCleanup.retainedJobCount, 0)
        for unexpected in ["output.write.UNEXPECTED", "cleanup.schedule.UNEXPECTED",
                           "inventory.retry.UNEXPECTED", "media.start.UNEXPECTED",
                           "media.refresh.UNEXPECTED"] {
            XCTAssertEqual(f.trace.count(unexpected), 0, unexpected)
        }
    }
}
