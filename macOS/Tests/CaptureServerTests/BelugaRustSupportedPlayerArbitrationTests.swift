import BelugaCore
import Foundation
import WebRTCTransport
import XCTest
@testable import CaptureServer

// Every default/spy producer calls the production C boundary.
// Inert child runtimes never invoke platform APIs; the Chrome fixture explicitly
// injects an inert backend into the real Chrome runtime to obtain a real descriptor.
final class BelugaRustSupportedPlayerArbitrationTests: XCTestCase {
    private typealias Boundary = BelugaRustSupportedPlayerArbitrationBoundary
    private typealias Input = Boundary.Input
    private typealias Output = Boundary.Output

    func testActualCopiedABIAndAll48LiteralOriginalDecisions() {
        XCTAssertEqual(MemoryLayout<Input>.size, 20)
        XCTAssertEqual(MemoryLayout<Input>.stride, 20)
        XCTAssertEqual(MemoryLayout<Input>.alignment, 4)
        XCTAssertEqual(MemoryLayout<Output>.size, 16)
        XCTAssertEqual(MemoryLayout<Output>.stride, 16)
        XCTAssertEqual(MemoryLayout<Output>.alignment, 4)
        var count = 0
        for hold in UInt32(0)...2 {
            for browser in UInt32(0)...3 {
                for music in UInt32(0)...3 {
                    let input = Input(abi_version: 1, selected_source: hold,
                        browser_observation: browser, music_observation: music, reserved: 0)
                    let output = beluga_core_supported_player_arbitrate(input)
                    let expected = SupportedPlayerArbitrationOriginalReference.answer(
                        hold: hold, browser: browser, music: music)
                    XCTAssertEqual(output.abi_version, 1)
                    XCTAssertEqual(output.reserved, 0)
                    XCTAssertEqual(output.action, expected.action, "hold=\(hold) browser=\(browser) music=\(music)")
                    XCTAssertEqual(output.primary_or_hold, expected.primaryOrHold)
                    XCTAssertNotNil(Boundary.decision(input: input, output: output))
                    count += 1
                }
            }
        }
        XCTAssertEqual(count, 48)
    }

    func testAll48CurrentNativeHistoriesMatchIndependentOriginalAndRetainedHold() throws {
        var count = 0
        for hold in UInt32(0)...2 {
            for browserObservation in UInt32(0)...3 {
                for musicObservation in UInt32(0)...3 {
                    let fixture = try seeded(hold)
                    fixture.spy.clear()
                    fixture.browser.result = observation(browserObservation, snapshot: fixture.browserItem)
                    fixture.music.result = observation(musicObservation, snapshot: fixture.musicItem)
                    let expected = SupportedPlayerArbitrationOriginalReference.answer(
                        hold: hold, browser: browserObservation, music: musicObservation)
                    let actual = try fetch(fixture.runtime)
                    assert(actual, equals: expected, browser: browserObservation, music: musicObservation)
                    XCTAssertEqual(fixture.spy.inputs.read().count, 1)
                    let input = try XCTUnwrap(fixture.spy.inputs.read().first)
                    XCTAssertEqual(input.selected_source, hold)
                    XCTAssertEqual(input.browser_observation, browserObservation)
                    XCTAssertEqual(input.music_observation, musicObservation)
                    XCTAssertEqual(input.abi_version, 1)
                    XCTAssertEqual(input.reserved, 0)

                    // Only publication changes hold. Retry clears authority but preserves it.
                    fixture.browser.result = .snapshot(withRate(fixture.browserItem, 0))
                    fixture.music.result = .snapshot(withRate(fixture.musicItem, 0))
                    let following = try catalog(fixture.runtime)
                    let nextHold = expected.action == 1 ? hold : expected.primaryOrHold
                    XCTAssertEqual(fixture.spy.inputs.read().last?.selected_source, nextHold)
                    XCTAssertEqual(following.primary.sourceName, nextHold == 2 ? "Music" : "YouTube")
                    count += 1
                }
            }
        }
        XCTAssertEqual(count, 48)
    }

    func testAll48StaleNativeHistoriesCannotCallCoreOrRetireCurrentAuthority() throws {
        var count = 0
        for hold in UInt32(0)...2 {
            for browserObservation in UInt32(0)...3 {
                for musicObservation in UInt32(0)...3 {
                    let fixture = try seeded(hold)
                    fixture.spy.clear()
                    fixture.browser.deferred = true; fixture.music.deferred = true
                    let old = ArbitrationBox<[MacNowPlayingRuntimeCatalogResult]>([])
                    let current = ArbitrationBox<[MacNowPlayingRuntimeCatalogResult]>([])
                    fixture.runtime.fetchCatalog { value in old.update { $0.append(value) } }
                    fixture.runtime.fetchCatalog { value in current.update { $0.append(value) } }
                    fixture.browser.deliver(1, .noActiveMedia)
                    fixture.music.deliver(1, .snapshot(fixture.musicItem))
                    let publication = try unwrapCatalog(try XCTUnwrap(current.read().first))
                    let reportCount = fixture.reports.read().count
                    let command = send(fixture.runtime, publication.primary)

                    // A hypothetical invalid producer is armed after the valid publication.
                    // Stale callbacks must not invoke it at all, even when one child retries.
                    fixture.spy.invalidOutput.update { $0 = true }
                    fixture.browser.deliver(0, observation(browserObservation, snapshot: fixture.browserItem))
                    fixture.music.deliver(0, observation(musicObservation, snapshot: fixture.musicItem))
                    XCTAssertEqual(old.read().count, 1)
                    if let value = old.read().first { assertRetry(value) }
                    XCTAssertEqual(current.read().count, 1)
                    XCTAssertEqual(fixture.spy.inputs.read().count, 1)
                    XCTAssertEqual(fixture.reports.read().count, reportCount)
                    fixture.music.releaseOrdinary()
                    XCTAssertEqual(command.read(), .applied)
                    XCTAssertEqual(fixture.music.effects, [1])
                    XCTAssertTrue(fixture.browser.effects.isEmpty)
                    count += 1
                }
            }
        }
        XCTAssertEqual(count, 48)
    }

    func testEveryBoundedCopiedOutputCorruptionRetriesRevokesAndCanRecover() throws {
        var count = 0
        for corruption in ArbitrationCorruption.all {
            let browser = ArbitrationChild(), music = ArbitrationChild()
            let browserItem = item("YouTube", "browser"), musicItem = item("Music", "music")
            let reports = ArbitrationBox<[String]>([])
            let corrupt = ArbitrationBox(false)
            let observed = ArbitrationBox<[Input]>([])
            let producer = BelugaRustSupportedPlayerArbitrationProducer { input in
                observed.update { $0.append(input) }
                var output = BelugaRustSupportedPlayerArbitrationProducer.actual.arbitrate(input)
                if corrupt.read() { corruption.change(&output) }
                return output
            }
            let runtime = MacSupportedNowPlayingRuntime(browser: browser, music: music,
                arbitrationProducer: producer, diagnostics: { value in reports.update { $0.append(value) } })
            browser.result = .noActiveMedia; music.result = .snapshot(musicItem)
            let original = try catalog(runtime).primary
            let queued = send(runtime, original)
            let queuedAcrossRecovery = send(runtime, original)
            browser.result = observation(corruption.browser, snapshot: browserItem)
            music.result = observation(corruption.music, snapshot: musicItem)
            corrupt.update { $0 = true }
            assertRetry(try fetch(runtime), corruption.name)
            XCTAssertEqual(observed.read().last?.selected_source, 2, corruption.name)
            music.releaseOrdinary()
            XCTAssertEqual(queued.read(), .staleContext, corruption.name)
            XCTAssertEqual(send(runtime, original).read(), .staleContext, corruption.name)
            XCTAssertTrue(music.effects.isEmpty, corruption.name)
            XCTAssertEqual(reports.read().last,
                "source=unavailable reason=invalid-supported-player-arbitration-bridge", corruption.name)
            let diagnosticsBeforeRepeat = reports.read().count
            assertRetry(try fetch(runtime), corruption.name)
            XCTAssertEqual(reports.read().count, diagnosticsBeforeRepeat, corruption.name)
            corrupt.update { $0 = false }
            browser.result = .snapshot(withRate(browserItem, 0)); music.result = .snapshot(withRate(musicItem, 0))
            let recovered = try catalog(runtime).primary
            XCTAssertEqual(recovered.sourceName, "Music", corruption.name)
            XCTAssertFalse(recovered.client === original.client, corruption.name)
            XCTAssertEqual(send(runtime, original).read(), .staleContext, corruption.name)
            // This admission was queued BEFORE the fault and remains held across
            // valid recovery. Reusing the same child/client/item cannot revive it.
            music.releaseOrdinary()
            XCTAssertEqual(queuedAcrossRecovery.read(), .staleContext, corruption.name)
            XCTAssertTrue(music.effects.isEmpty, corruption.name)
            let fresh = send(runtime, recovered)
            music.releaseOrdinary()
            XCTAssertEqual(fresh.read(), .applied, corruption.name)
            count += 1
        }
        XCTAssertEqual(count, 18)
    }

    func testUnselectedChildRetryRevokesBothCatalogCommandsAndActualHandoff() throws {
        let chrome = try chromeFixture()
        let browser = ArbitrationChild(forwarding: chrome.runtime), music = ArbitrationChild()
        browser.result = .snapshot(chrome.snapshot)
        music.result = .snapshot(item("Music", "music", rate: 0))
        let runtime = MacSupportedNowPlayingRuntime(browser: browser, music: music)
        let before = try catalog(runtime)
        let ordinary = send(runtime, before.primary)
        let secondary = send(runtime, try XCTUnwrap(before.additional.first))
        let handoff = try pause(runtime, before.primary)
        music.result = .retry
        assertRetry(try fetch(runtime))
        browser.releaseOrdinary(); browser.releaseHandoff(); music.releaseOrdinary()
        XCTAssertEqual(ordinary.read(), .staleContext)
        XCTAssertEqual(secondary.read(), .staleContext)
        XCTAssertEqual(handoff.read(), .staleContext)
        XCTAssertEqual(chrome.backend.ordinaryEffects, 0)
        XCTAssertEqual(chrome.backend.handoffEffects, 0)
        XCTAssertTrue(music.effects.isEmpty)
        XCTAssertEqual(browser.forwardedOrdinary, 0)
        XCTAssertEqual(browser.forwardedHandoff, 0)
    }

    func testMusicHoldSurvivesAbsentRetryAndBothPausedRecovery() throws {
        let fixture = try seeded(2)
        fixture.browser.result = .retry; fixture.music.result = .noActiveMedia
        assertRetry(try fetch(fixture.runtime))
        fixture.browser.result = .snapshot(withRate(fixture.browserItem, 0))
        fixture.music.result = .snapshot(withRate(fixture.musicItem, 0))
        XCTAssertEqual(try catalog(fixture.runtime).primary.sourceName, "Music")
        XCTAssertEqual(fixture.spy.inputs.read().last?.selected_source, 2)
    }

    func testFirstRetryCallbackCannotBeOverwrittenByDuplicateSnapshot() throws {
        let fixture = try seeded(1)
        let original = try catalog(fixture.runtime).primary
        let queued = send(fixture.runtime, original)
        fixture.spy.clear(); fixture.browser.deferred = true; fixture.music.deferred = true
        let results = ArbitrationBox<[MacNowPlayingRuntimeCatalogResult]>([])
        fixture.runtime.fetchCatalog { value in results.update { $0.append(value) } }
        fixture.browser.deliver(0, .retry)
        fixture.browser.deliver(0, .snapshot(fixture.browserItem))
        XCTAssertTrue(results.read().isEmpty)
        fixture.music.deliver(0, .snapshot(fixture.musicItem))
        fixture.browser.deliver(0, .snapshot(fixture.browserItem))
        fixture.music.deliver(0, .noActiveMedia)
        XCTAssertEqual(results.read().count, 1)
        assertRetry(try XCTUnwrap(results.read().first))
        XCTAssertEqual(fixture.spy.inputs.read().count, 1)
        XCTAssertEqual(fixture.spy.inputs.read().first?.browser_observation, 3)
        fixture.browser.releaseOrdinary()
        XCTAssertEqual(queued.read(), .staleContext)
    }

    func testStopThenFreshPublicationCannotBeClearedByOldRetryJoin() throws {
        let fixture = try seeded(1)
        fixture.spy.clear(); fixture.browser.deferred = true; fixture.music.deferred = true
        let old = ArbitrationBox<[MacNowPlayingRuntimeCatalogResult]>([])
        fixture.runtime.fetchCatalog { value in old.update { $0.append(value) } }
        fixture.runtime.stop()
        let fresh = ArbitrationBox<[MacNowPlayingRuntimeCatalogResult]>([])
        fixture.runtime.fetchCatalog { value in fresh.update { $0.append(value) } }
        fixture.browser.deliver(1, .snapshot(fixture.browserItem)); fixture.music.deliver(1, .noActiveMedia)
        let publication = try unwrapCatalog(try XCTUnwrap(fresh.read().first))
        let queued = send(fixture.runtime, publication.primary)
        let reportsBeforeOld = fixture.reports.read().count
        fixture.browser.deliver(0, .retry); fixture.music.deliver(0, .retry)
        assertRetry(try XCTUnwrap(old.read().first))
        XCTAssertEqual(fixture.spy.inputs.read().count, 1)
        XCTAssertEqual(fixture.spy.inputs.read().first?.selected_source, 0)
        XCTAssertEqual(fixture.reports.read().count, reportsBeforeOld)
        fixture.browser.releaseOrdinary()
        XCTAssertEqual(queued.read(), .applied)
        XCTAssertEqual(fixture.browser.stopCount, 1)
        XCTAssertEqual(fixture.music.stopCount, 1)
    }

    func testStartingNewFetchDoesNotRevokeQueuedOrdinaryOrActualHandoff() throws {
        let chrome = try chromeFixture()
        let browser = ArbitrationChild(forwarding: chrome.runtime), music = ArbitrationChild()
        browser.result = .snapshot(chrome.snapshot)
        let runtime = MacSupportedNowPlayingRuntime(browser: browser, music: music)
        let published = try catalog(runtime).primary
        let ordinary = send(runtime, published)
        let handoff = try pause(runtime, published)
        browser.deferred = true; music.deferred = true
        let pending = ArbitrationBox<[MacNowPlayingRuntimeCatalogResult]>([])
        runtime.fetchCatalog { value in pending.update { $0.append(value) } }

        // The wrapper held two composite admissions. The actual Chrome runtime
        // receives them sequentially, never two concurrent native admissions.
        browser.releaseOrdinary()
        awaitResult(ordinary)
        XCTAssertEqual(ordinary.read(), .applied)
        browser.releaseHandoff()
        awaitResult(handoff)
        XCTAssertEqual(handoff.read(), .applied)
        XCTAssertTrue(pending.read().isEmpty)
        XCTAssertEqual(chrome.backend.ordinaryEffects, 1)
        XCTAssertEqual(chrome.backend.handoffEffects, 1)
        browser.deliver(0, .snapshot(chrome.snapshot)); music.deliver(0, .noActiveMedia)
        XCTAssertEqual(pending.read().count, 1)
    }

    func testInvalidCurrentOutputRetiresActualHandoffBeforeNativePauseEffect() throws {
        let chrome = try chromeFixture()
        let browser = ArbitrationChild(forwarding: chrome.runtime), music = ArbitrationChild()
        let spy = ArbitrationSpy()
        browser.result = .snapshot(chrome.snapshot)
        let runtime = MacSupportedNowPlayingRuntime(browser: browser, music: music, arbitrationProducer: spy.producer)
        let original = try catalog(runtime).primary
        let handoff = try pause(runtime, original)
        spy.invalidOutput.update { $0 = true }
        assertRetry(try fetch(runtime))
        browser.releaseHandoff()
        XCTAssertEqual(handoff.read(), .staleContext)
        XCTAssertEqual(browser.forwardedHandoff, 0)
        XCTAssertEqual(chrome.backend.handoffEffects, 0)
        spy.invalidOutput.update { $0 = false }
        let recovered = try catalog(runtime).primary
        XCTAssertFalse(original.client === recovered.client)
        let fresh = try pause(runtime, recovered)
        browser.releaseHandoff(); awaitResult(fresh)
        XCTAssertEqual(fresh.read(), .applied)
        XCTAssertEqual(chrome.backend.handoffEffects, 1)
    }

    func testWrappedSnapshotsPreserveExactNativeValuesCapabilitiesAndHandoffReference() throws {
        let chrome = try chromeFixture()
        let browser = ArbitrationChild(), music = ArbitrationChild()
        browser.result = .snapshot(chrome.snapshot)
        let musicItem = item("Music", "music", rate: 0, commands: [0, 5])
        music.result = .snapshot(musicItem)
        let runtime = MacSupportedNowPlayingRuntime(browser: browser, music: music)
        let result = try catalog(runtime)
        XCTAssertEqual(result.primary.metadata, chrome.snapshot.metadata)
        XCTAssertEqual(result.primary.enabledCommands, chrome.snapshot.enabledCommands)
        XCTAssertTrue(result.primary.handoffSource === chrome.snapshot.handoffSource)
        XCTAssertFalse(result.primary.client === chrome.snapshot.client)
        let additional = try XCTUnwrap(result.additional.first)
        XCTAssertEqual(additional.metadata, musicItem.metadata)
        XCTAssertEqual(additional.enabledCommands, [0, 5])
        XCTAssertEqual(result.additional.map(\.sourceName), ["Music"])
    }

    func testSameNativeClientAndItemRetainTokensAcrossRateChanges() throws {
        let fixture = try seeded(1)
        let original = try catalog(fixture.runtime).primary
        let queued = send(fixture.runtime, original)
        fixture.browser.result = .snapshot(withRate(fixture.browserItem, 0))
        fixture.music.result = .noActiveMedia
        let paused = try catalog(fixture.runtime).primary
        XCTAssertTrue(paused.client === original.client)
        XCTAssertEqual(paused.metadata.playbackRate, 0)
        fixture.browser.releaseOrdinary()
        XCTAssertEqual(queued.read(), .applied)
    }

    func testReplacementNativeClientOrItemRetiresQueuedOrdinaryAuthority() throws {
        for replaceClient in [true, false] {
            let fixture = try seeded(1)
            let original = try catalog(fixture.runtime).primary
            let queued = send(fixture.runtime, original)
            let replacement = replaceClient ? item("YouTube", "browser")
                : withRate(fixture.browserItem, 1, content: "replacement-item")
            fixture.browser.result = .snapshot(replacement)
            let current = try catalog(fixture.runtime).primary
            XCTAssertFalse(current.client === original.client)
            fixture.browser.releaseOrdinary()
            XCTAssertEqual(queued.read(), .staleContext)
            XCTAssertEqual(send(fixture.runtime, original).read(), .staleContext)
            XCTAssertTrue(fixture.browser.effects.isEmpty)
        }
    }

    func testNoMediaClearsHoldBeforePausedFallbackAndRetiresQueuedCommand() throws {
        let fixture = try seeded(2)
        let before = try catalog(fixture.runtime).primary
        let queued = send(fixture.runtime, before)
        fixture.browser.result = .noActiveMedia; fixture.music.result = .noActiveMedia
        assertNoMedia(try fetch(fixture.runtime))
        fixture.music.releaseOrdinary()
        XCTAssertEqual(queued.read(), .staleContext)
        fixture.browser.result = .snapshot(withRate(fixture.browserItem, 0))
        fixture.music.result = .snapshot(withRate(fixture.musicItem, 0))
        XCTAssertEqual(try catalog(fixture.runtime).primary.sourceName, "YouTube")
        XCTAssertEqual(fixture.spy.inputs.read().last?.selected_source, 0)
    }

    func testOriginalRateGreaterThanZeroComparisonIsNotNewNumericValidation() throws {
        for rate in [0.0, -0.0, -1.0, Double.nan, Double.infinity, 0.125] {
            let fixture = try seeded(2)
            fixture.browser.result = .snapshot(withRate(fixture.browserItem, rate))
            fixture.music.result = .snapshot(withRate(fixture.musicItem, 0))
            let result = try catalog(fixture.runtime)
            XCTAssertEqual(fixture.spy.inputs.read().last?.browser_observation, rate > 0 ? 2 : 1)
            XCTAssertEqual(result.primary.sourceName, rate > 0 ? "YouTube" : "Music")
            // Native metadata is copied, not normalized or reconstructed from Rust.
            let browser = result.primary.sourceName == "YouTube" ? result.primary : try XCTUnwrap(result.additional.first)
            XCTAssertEqual(browser.metadata.playbackRate.bitPattern, rate.bitPattern)
        }
    }

    func testNativeProjectionRequiresExactSlotsAndValidHold() {
        let browser = item("YouTube", "browser"), music = item("Music", "music")
        XCTAssertNil(Boundary.project(results: [:], selected: nil))
        XCTAssertNil(Boundary.project(results: [0: .snapshot(browser)], selected: nil))
        XCTAssertNil(Boundary.project(results: [0: .snapshot(browser), 2: .snapshot(music)], selected: nil))
        XCTAssertNil(Boundary.project(results: [0: .snapshot(browser), 1: .snapshot(music), 2: .retry], selected: nil))
        for hold in [-1, 2, Int.max] {
            XCTAssertNil(Boundary.project(results: [0: .snapshot(browser), 1: .snapshot(music)], selected: hold))
        }
        XCTAssertNotNil(Boundary.project(results: [0: .retry, 1: .noActiveMedia], selected: 1))
    }

    func testActualRawInvalidInputsReturnInvalidAndNativeDecoderRejectsThem() {
        let valid = Input(abi_version: 1, selected_source: 0, browser_observation: 2, music_observation: 1, reserved: 0)
        var inputs: [Input] = []
        for value in [UInt32(0), 2, UInt32.max] { var input = valid; input.abi_version = value; inputs.append(input) }
        for value in [UInt32(3), UInt32.max] { var input = valid; input.selected_source = value; inputs.append(input) }
        for value in [UInt32(4), UInt32.max] { var input = valid; input.browser_observation = value; inputs.append(input) }
        for value in [UInt32(4), UInt32.max] { var input = valid; input.music_observation = value; inputs.append(input) }
        for value in [UInt32(1), UInt32.max] { var input = valid; input.reserved = value; inputs.append(input) }
        XCTAssertEqual(inputs.count, 11)
        for input in inputs {
            let output = beluga_core_supported_player_arbitrate(input)
            XCTAssertEqual(output.abi_version, 1)
            XCTAssertEqual(output.action, 0)
            XCTAssertEqual(output.primary_or_hold, 0)
            XCTAssertEqual(output.reserved, 0)
            XCTAssertNil(Boundary.decision(input: input, output: output))
        }
    }

    func testAdditionalBrowserCannotHandoffWhenMusicIsSelected() throws {
        let chrome = try chromeFixture()
        let browser = ArbitrationChild(forwarding: chrome.runtime), music = ArbitrationChild()
        music.result = .snapshot(item("Music", "music"))
        let runtime = MacSupportedNowPlayingRuntime(browser: browser, music: music)
        XCTAssertEqual(try catalog(runtime).primary.sourceName, "Music")
        browser.result = .snapshot(chrome.snapshot)
        let both = try catalog(runtime)
        XCTAssertEqual(both.primary.sourceName, "Music")
        let additional = try XCTUnwrap(both.additional.first)
        XCTAssertNotNil(additional.handoffSource)
        let rejected = try pause(runtime, additional)
        XCTAssertEqual(rejected.read(), .staleContext)
        XCTAssertEqual(browser.pendingHandoff, 0)
        XCTAssertEqual(chrome.backend.handoffEffects, 0)
        let ordinary = send(runtime, additional)
        browser.releaseOrdinary(); awaitResult(ordinary)
        XCTAssertEqual(ordinary.read(), .applied)
        XCTAssertEqual(chrome.backend.ordinaryEffects, 1)
    }

    func testDistinctInvalidDiagnosticIsThrottledAndContainsNoNativeContent() throws {
        let fixture = try seeded(1)
        fixture.spy.invalidOutput.update { $0 = true }
        assertRetry(try fetch(fixture.runtime))
        let before = fixture.reports.read().count
        assertRetry(try fetch(fixture.runtime))
        XCTAssertEqual(fixture.reports.read().count, before)
        let fault = try XCTUnwrap(fixture.reports.read().last)
        XCTAssertEqual(fault, "source=unavailable reason=invalid-supported-player-arbitration-bridge")
        for secret in ["Private fixture title", "Private fixture artist", "Private fixture album", "browser", "content-a"] {
            XCTAssertFalse(fault.contains(secret))
        }
        fixture.spy.invalidOutput.update { $0 = false }
        fixture.browser.result = .retry
        assertRetry(try fetch(fixture.runtime))
        XCTAssertNotEqual(fixture.reports.read().last, fault)
        XCTAssertTrue(fixture.reports.read().last?.contains("source=unavailable chrome=adapter music=adapter") == true)
    }

    func testExternalRevocationAndStopRejectBothHeldOrdinaryAndHandoff() throws {
        for shouldStop in [false, true] {
            let chrome = try chromeFixture()
            let browser = ArbitrationChild(forwarding: chrome.runtime), music = ArbitrationChild()
            browser.result = .snapshot(chrome.snapshot)
            let runtime = MacSupportedNowPlayingRuntime(browser: browser, music: music)
            let publication = try catalog(runtime).primary
            let authorization = WebRTCControlAuthorization()
            let ordinary = send(runtime, publication, isAuthorized: { authorization.isValid })
            let handoff = try pause(runtime, publication, isAuthorized: { authorization.isValid })
            if shouldStop { runtime.stop() } else { authorization.revoke() }
            browser.releaseOrdinary(); browser.releaseHandoff()
            XCTAssertEqual(ordinary.read(), .staleContext)
            XCTAssertEqual(handoff.read(), .staleContext)
            XCTAssertEqual(chrome.backend.ordinaryEffects, 0)
            XCTAssertEqual(chrome.backend.handoffEffects, 0)
        }
    }

    private func seeded(_ hold: UInt32) throws -> ArbitrationFixture {
        let fixture = ArbitrationFixture(browserItem: item("YouTube", "browser"), musicItem: item("Music", "music"))
        if hold == 1 { fixture.browser.result = .snapshot(fixture.browserItem) }
        if hold == 2 { fixture.music.result = .snapshot(fixture.musicItem) }
        if hold != 0 { _ = try catalog(fixture.runtime) }
        return fixture
    }
    private func observation(_ value: UInt32, snapshot: MacNowPlayingRuntimeSnapshot) -> MacNowPlayingRuntimeSnapshotResult {
        switch value {
        case 0: return .noActiveMedia
        case 1: return .snapshot(withRate(snapshot, 0))
        case 2: return .snapshot(withRate(snapshot, 1))
        case 3: return .retry
        default: preconditionFailure("Invalid test observation")
        }
    }
    private func item(_ source: String, _ identity: String, rate: Double = 1, commands: Set<Int> = [0, 1, 4, 5]) -> MacNowPlayingRuntimeSnapshot {
        .init(client: MacNowPlayingClientToken(object: NSObject(), clientIdentity: identity), sourceName: source,
            metadata: .init(title: "Private fixture title", artist: "Private fixture artist", album: "Private fixture album",
                duration: 90, elapsedTime: 12, playbackRate: rate, timestamp: Date(timeIntervalSince1970: 100),
                contentIdentifier: "content-a", uniqueIdentifier: nil), enabledCommands: commands)
    }
    private func withRate(_ snapshot: MacNowPlayingRuntimeSnapshot, _ rate: Double, content: String? = nil) -> MacNowPlayingRuntimeSnapshot {
        let metadata = snapshot.metadata
        return .init(client: snapshot.client, sourceName: snapshot.sourceName,
            metadata: .init(title: metadata.title, artist: metadata.artist, album: metadata.album,
                duration: metadata.duration, elapsedTime: metadata.elapsedTime, playbackRate: rate,
                timestamp: metadata.timestamp, contentIdentifier: content ?? metadata.contentIdentifier,
                uniqueIdentifier: metadata.uniqueIdentifier, artwork: metadata.artwork),
            enabledCommands: snapshot.enabledCommands, handoffSource: snapshot.handoffSource)
    }
    private func fetch(_ runtime: MacSupportedNowPlayingRuntime) throws -> MacNowPlayingRuntimeCatalogResult {
        let value = ArbitrationBox<MacNowPlayingRuntimeCatalogResult?>(nil)
        runtime.fetchCatalog { result in value.update { $0 = result } }
        return try XCTUnwrap(value.read())
    }
    private func catalog(_ runtime: MacSupportedNowPlayingRuntime) throws -> MacNowPlayingRuntimeCatalog { try unwrapCatalog(fetch(runtime)) }
    private func unwrapCatalog(_ result: MacNowPlayingRuntimeCatalogResult) throws -> MacNowPlayingRuntimeCatalog {
        guard case .snapshot(let catalog) = result else { throw ArbitrationFixtureError.missingCatalog }
        return catalog
    }
    private func assertRetry(_ result: MacNowPlayingRuntimeCatalogResult, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        guard case .retry = result else { return XCTFail("Expected retry \(message)", file: file, line: line) }
    }
    private func assertNoMedia(_ result: MacNowPlayingRuntimeCatalogResult, file: StaticString = #filePath, line: UInt = #line) {
        guard case .noActiveMedia = result else { return XCTFail("Expected no media", file: file, line: line) }
    }
    private func assert(_ result: MacNowPlayingRuntimeCatalogResult,
                        equals expected: SupportedPlayerArbitrationOriginalReference.Answer,
                        browser: UInt32, music: UInt32, file: StaticString = #filePath, line: UInt = #line) {
        if expected.action == 1 { assertRetry(result, file: file, line: line); return }
        if expected.primaryOrHold == 0 { assertNoMedia(result, file: file, line: line); return }
        guard case .snapshot(let catalog) = result else { return XCTFail("Expected publication", file: file, line: line) }
        XCTAssertEqual(catalog.primary.sourceName, expected.primaryOrHold == 1 ? "YouTube" : "Music", file: file, line: line)
        let available = [(UInt32(1), browser), (UInt32(2), music)].filter { $0.1 == 1 || $0.1 == 2 }
        let names = available.filter { $0.0 != expected.primaryOrHold }.map { $0.0 == 1 ? "YouTube" : "Music" }
        XCTAssertEqual(catalog.additional.map(\.sourceName), names, file: file, line: line)
    }
    private func send(_ runtime: MacSupportedNowPlayingRuntime, _ snapshot: MacNowPlayingRuntimeSnapshot,
                      isAuthorized: @escaping @Sendable () -> Bool = { true }) -> ArbitrationBox<WebRTCRemoteMediaCommandResult?> {
        let result = ArbitrationBox<WebRTCRemoteMediaCommandResult?>(nil)
        runtime.send(rawCommand: 1, snapshot: snapshot, isAuthorized: isAuthorized) { value in result.update { $0 = value } }
        return result
    }
    private func pause(_ runtime: MacSupportedNowPlayingRuntime, _ snapshot: MacNowPlayingRuntimeSnapshot,
                       isAuthorized: @escaping @Sendable () -> Bool = { true }) throws -> ArbitrationBox<WebRTCRemoteMediaCommandResult?> {
        let source = try XCTUnwrap(snapshot.handoffSource)
        let result = ArbitrationBox<WebRTCRemoteMediaCommandResult?>(nil)
        runtime.sendHandoffPause(source: source, phonePositionSeconds: source.positionSeconds, snapshot: snapshot,
            isAuthorized: isAuthorized) { value in result.update { $0 = value } }
        return result
    }
    private func awaitResult(_ result: ArbitrationBox<WebRTCRemoteMediaCommandResult?>) {
        let completed = expectation(description: "Inert backend command completed")
        result.whenNonNil { completed.fulfill() }
        wait(for: [completed], timeout: 2)
    }
    private func chromeFixture() throws -> (runtime: MacChromeNowPlayingRuntime, backend: ArbitrationChromeBackend, snapshot: MacNowPlayingRuntimeSnapshot) {
        let backend = ArbitrationChromeBackend()
        let runtime = MacChromeNowPlayingRuntime(backend: backend,
            queue: DispatchQueue(label: "test.supported-player.inert-chrome"), now: { 10 })
        let completed = expectation(description: "Inert Chrome descriptor")
        let result = ArbitrationBox<MacNowPlayingRuntimeSnapshotResult?>(nil)
        runtime.fetchSnapshot { value in result.update { $0 = value }; completed.fulfill() }
        wait(for: [completed], timeout: 2)
        guard case .snapshot(let snapshot) = try XCTUnwrap(result.read()) else { throw ArbitrationFixtureError.missingCatalog }
        XCTAssertNotNil(snapshot.handoffSource)
        XCTAssertEqual(backend.permissionAttempts, 0)
        return (runtime, backend, snapshot)
    }
}

private enum ArbitrationFixtureError: Error { case missingCatalog }

private final class ArbitrationBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    private var observer: (@Sendable () -> Void)?
    init(_ value: Value) { self.value = value }
    func read() -> Value { lock.withLock { value } }
    func update(_ body: (inout Value) -> Void) {
        let notify = lock.withLock { () -> (@Sendable () -> Void)? in body(&value); return observer }
        notify?()
    }
    // Used only for optional command result values. Observe after or before completion,
    // atomically, and fulfill once; this is not polling/timing-based positive evidence.
    func whenNonNil<Wrapped>(_ callback: @escaping @Sendable () -> Void) where Value == Wrapped? {
        let once = ArbitrationBox<Bool>(false)
        let notify: @Sendable () -> Void = { [weak self] in
            guard let self, self.read() != nil else { return }
            let first = once.lock.withLock { () -> Bool in
                if once.value { return false }; once.value = true; return true
            }
            if first { callback() }
        }
        lock.withLock { observer = notify }
        notify()
    }
}

private final class ArbitrationSpy: @unchecked Sendable {
    let inputs = ArbitrationBox<[BelugaRustSupportedPlayerArbitrationBoundary.Input]>([])
    let invalidOutput = ArbitrationBox(false)
    var producer: BelugaRustSupportedPlayerArbitrationProducer {
        .init(arbitrate: { [self] input in
            inputs.update { $0.append(input) }
            var output = BelugaRustSupportedPlayerArbitrationProducer.actual.arbitrate(input)
            if invalidOutput.read() { output.abi_version = 0 }
            return output
        })
    }
    func clear() { inputs.update { $0.removeAll() } }
}

private final class ArbitrationFixture {
    let browser = ArbitrationChild(), music = ArbitrationChild()
    let spy = ArbitrationSpy()
    let reports = ArbitrationBox<[String]>([])
    let browserItem: MacNowPlayingRuntimeSnapshot, musicItem: MacNowPlayingRuntimeSnapshot
    let runtime: MacSupportedNowPlayingRuntime
    init(browserItem: MacNowPlayingRuntimeSnapshot, musicItem: MacNowPlayingRuntimeSnapshot) {
        self.browserItem = browserItem; self.musicItem = musicItem
        let capture = reports
        runtime = MacSupportedNowPlayingRuntime(browser: browser, music: music, arbitrationProducer: spy.producer,
            diagnostics: { value in capture.update { $0.append(value) } })
    }
}

private final class ArbitrationChild: MacSystemNowPlayingRuntime, @unchecked Sendable {
    private struct Ordinary {
        let rawCommand: Int, position: TimeInterval?
        let snapshot: MacNowPlayingRuntimeSnapshot
        let authorized: @Sendable () -> Bool
        let completion: @Sendable (WebRTCRemoteMediaCommandResult) -> Void
    }
    private struct Handoff {
        let source: MacYouTubeHandoffSource, position: Double, snapshot: MacNowPlayingRuntimeSnapshot
        let authorized: @Sendable () -> Bool
        let completion: @Sendable (WebRTCRemoteMediaCommandResult) -> Void
    }
    private let lock = NSLock()
    private let forwarding: (any MacSystemNowPlayingRuntime)?
    private var storedResult: MacNowPlayingRuntimeSnapshotResult = .noActiveMedia
    private var storedDeferred = false
    private var fetches: [@Sendable (MacNowPlayingRuntimeSnapshotResult) -> Void] = []
    private var ordinary: [Ordinary] = [], handoffs: [Handoff] = []
    private var executed: [Int] = [], stopped = 0, ordinaryForwards = 0, handoffForwards = 0
    init(forwarding: (any MacSystemNowPlayingRuntime)? = nil) { self.forwarding = forwarding }
    var isAvailable: Bool { true }
    var result: MacNowPlayingRuntimeSnapshotResult {
        get { lock.withLock { storedResult } }
        set { lock.withLock { storedResult = newValue } }
    }
    var deferred: Bool {
        get { lock.withLock { storedDeferred } }
        set { lock.withLock { storedDeferred = newValue } }
    }
    var effects: [Int] { lock.withLock { executed } }
    var stopCount: Int { lock.withLock { stopped } }
    var pendingHandoff: Int { lock.withLock { handoffs.count } }
    var forwardedOrdinary: Int { lock.withLock { ordinaryForwards } }
    var forwardedHandoff: Int { lock.withLock { handoffForwards } }
    func fetchSnapshot(completion: @escaping @Sendable (MacNowPlayingRuntimeSnapshotResult) -> Void) {
        let immediate = lock.withLock { () -> MacNowPlayingRuntimeSnapshotResult? in
            if storedDeferred { fetches.append(completion); return nil }; return storedResult
        }
        if let immediate { completion(immediate) }
    }
    func deliver(_ index: Int, _ value: MacNowPlayingRuntimeSnapshotResult) {
        let callback = lock.withLock { fetches.indices.contains(index) ? fetches[index] : nil }
        guard let callback else { return XCTFail("Missing bounded fetch callback") }; callback(value)
    }
    func send(rawCommand: Int, snapshot: MacNowPlayingRuntimeSnapshot, isAuthorized: @escaping @Sendable () -> Bool,
              completion: @escaping @Sendable (WebRTCRemoteMediaCommandResult) -> Void) {
        send(rawCommand: rawCommand, positionSeconds: nil, snapshot: snapshot, isAuthorized: isAuthorized, completion: completion)
    }
    func send(rawCommand: Int, positionSeconds: TimeInterval?, snapshot: MacNowPlayingRuntimeSnapshot,
              isAuthorized: @escaping @Sendable () -> Bool, completion: @escaping @Sendable (WebRTCRemoteMediaCommandResult) -> Void) {
        lock.withLock { ordinary.append(.init(rawCommand: rawCommand, position: positionSeconds, snapshot: snapshot,
            authorized: isAuthorized, completion: completion)) }
    }
    func sendHandoffPause(source: MacYouTubeHandoffSource, phonePositionSeconds: Double, snapshot: MacNowPlayingRuntimeSnapshot,
                          isAuthorized: @escaping @Sendable () -> Bool, completion: @escaping @Sendable (WebRTCRemoteMediaCommandResult) -> Void) {
        lock.withLock { handoffs.append(.init(source: source, position: phonePositionSeconds, snapshot: snapshot,
            authorized: isAuthorized, completion: completion)) }
    }
    func releaseOrdinary() {
        let pending = lock.withLock { ordinary.isEmpty ? nil : ordinary.removeFirst() }
        guard let pending else { return XCTFail("No held ordinary admission") }
        guard pending.authorized() else { pending.completion(.staleContext); return }
        if let forwarding {
            lock.withLock { ordinaryForwards += 1 }
            forwarding.send(rawCommand: pending.rawCommand, positionSeconds: pending.position, snapshot: pending.snapshot,
                isAuthorized: pending.authorized, completion: pending.completion)
        } else {
            lock.withLock { executed.append(pending.rawCommand) }; pending.completion(.applied)
        }
    }
    func releaseHandoff() {
        let pending = lock.withLock { handoffs.isEmpty ? nil : handoffs.removeFirst() }
        guard let pending else { return XCTFail("No held handoff admission") }
        guard pending.authorized() else { pending.completion(.staleContext); return }
        guard let forwarding else { pending.completion(.unsupported); return }
        lock.withLock { handoffForwards += 1 }
        forwarding.sendHandoffPause(source: pending.source, phonePositionSeconds: pending.position, snapshot: pending.snapshot,
            isAuthorized: pending.authorized, completion: pending.completion)
    }
    func stop() { lock.withLock { stopped += 1 }; forwarding?.stop() }
}

private struct ArbitrationCorruption: Sendable {
    typealias Output = BelugaRustSupportedPlayerArbitrationBoundary.Output
    let name: String, browser: UInt32, music: UInt32
    let change: @Sendable (inout Output) -> Void
    static let all: [Self] = [
        .init(name: "abi-zero", browser: 2, music: 2, change: { $0.abi_version = 0 }),
        .init(name: "abi-two", browser: 2, music: 2, change: { $0.abi_version = 2 }),
        .init(name: "abi-max", browser: 2, music: 2, change: { $0.abi_version = .max }),
        .init(name: "reserved-one", browser: 2, music: 2, change: { $0.reserved = 1 }),
        .init(name: "reserved-max", browser: 2, music: 2, change: { $0.reserved = .max }),
        .init(name: "action-invalid", browser: 2, music: 2, change: { $0.action = 0 }),
        .init(name: "action-three", browser: 2, music: 2, change: { $0.action = 3 }),
        .init(name: "action-max", browser: 2, music: 2, change: { $0.action = .max }),
        .init(name: "source-three", browser: 2, music: 2, change: { $0.primary_or_hold = 3 }),
        .init(name: "source-max", browser: 2, music: 2, change: { $0.primary_or_hold = .max }),
        .init(name: "none-with-available", browser: 2, music: 2, change: { $0.primary_or_hold = 0 }),
        .init(name: "absent-browser", browser: 0, music: 2, change: { $0.primary_or_hold = 1 }),
        .init(name: "absent-music", browser: 2, music: 0, change: { $0.primary_or_hold = 2 }),
        .init(name: "retry-without-retry", browser: 2, music: 2, change: { $0.action = 1 }),
        .init(name: "retry-loses-hold", browser: 3, music: 2, change: { $0.primary_or_hold = 0 }),
        .init(name: "publish-with-retry", browser: 3, music: 2, change: { $0.action = 2; $0.primary_or_hold = 2 }),
        .init(name: "none-with-retry", browser: 3, music: 0, change: { $0.action = 2; $0.primary_or_hold = 0 }),
        .init(name: "retry-transfers-hold", browser: 2, music: 3, change: { $0.primary_or_hold = 1 }),
    ]
}

/// Inert backend: real native runtime gates execute, but counters are the only effects.
/// No default Apple Events backend/client is created or any platform API invoked.
private final class ArbitrationChromeBackend: MacChromeNowPlayingBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var ordinary = 0, handoff = 0, permission = 0
    var ordinaryEffects: Int { lock.withLock { ordinary } }
    var handoffEffects: Int { lock.withLock { handoff } }
    var permissionAttempts: Int { lock.withLock { permission } }
    let native: MacChromePlayerSnapshot = .init(
        tab: .init(owner: .init(processID: 42, launchDate: Date(timeIntervalSince1970: 100)), windowID: "1", tabID: "2"),
        media: .init(documentID: "00000000-0000-0000-0000-000000000001",
            itemID: "00000000-0000-0000-0000-000000000002", itemGeneration: 1,
            videoID: "abcdefghijk", title: "Private fixture title", artist: "Private fixture artist",
            duration: 120, elapsedTime: 15, playbackRate: 1, paused: false,
            observedAtUnixMilliseconds: 1_000_000, observedAtPageMilliseconds: 50_000,
            canPlay: false, canPause: true, canNext: true, canPrevious: true, canSeek: true,
            playbackContinuityID: "00000000-0000-0000-0000-000000000003"), receivedAtUptime: 10)
    func readSnapshots(deadline: TimeInterval) throws -> [MacChromePlayerSnapshot] { [native] }
    func readSelection(preferred: MacChromePlayerSnapshot?, deadline: TimeInterval) -> MacChromeSelectionRead { .selected(native) }
    func requestAutomationPermission() throws {
        lock.withLock { permission += 1 }; XCTFail("Tests must not request platform permission")
        throw MacChromeBackendError.permissionRequired
    }
    func send(_ command: MacChromeCommand, positionSeconds: TimeInterval?, expected: MacChromePlayerSnapshot,
              deadline: TimeInterval, isAuthorized: @escaping @Sendable () -> Bool) throws -> WebRTCRemoteMediaCommandResult {
        guard isAuthorized() else { return .staleContext }
        XCTAssertTrue(expected.hasSameItem(as: native))
        lock.withLock { ordinary += 1 }; return .applied
    }
    func sendHandoffPause(expected: MacChromePlayerSnapshot, condition: MacChromeHandoffPauseCondition,
                          deadline: TimeInterval, isAuthorized: @escaping @Sendable () -> Bool) throws -> WebRTCRemoteMediaCommandResult {
        guard isAuthorized() else { return .staleContext }
        XCTAssertTrue(expected.hasSameItem(as: native))
        XCTAssertTrue(condition.matches(native.media))
        lock.withLock { handoff += 1 }; return .applied
    }
}
