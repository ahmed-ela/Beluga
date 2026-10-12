import BelugaCore
import CaptureCore
import Foundation
import RemoteSessionCore
import XCTest
@testable import CaptureServer

// Runs the real supervisor with inert transports, never availabilityLoopOverride.
final class WorldwideAvailabilityRetryCoordinatorTests: XCTestCase {
    func testAvailabilityUpgradeThenServerErrorBackoffUsesOneActualFailureProposal() async throws {
        let trace = RetryCoordinatorTrace()
        let failed = (0..<7).map { RetryCoordinatorClient(id: "failed-\($0)",
            behavior: .open([.serverError(.roleConflict)]), trace: trace) }
        let waiting = RetryCoordinatorClient(id: "waiting", behavior: .open([]), trace: trace)
        let sleeps = RetryCoordinatorSleeper(gates: (0..<7).map { _ in RetryCoordinatorGate() }, trace: trace)
        let probe = RetryCoordinatorProducerProbe(trace: trace)
        let fixture = try RetryCoordinatorFixture(clients: failed + [waiting], sleeper: sleeps,
                                                  producer: probe.producer, trace: trace)
        do {
            _ = try await fixture.coordinator.start(resetPairing: false)
            let expected = [1, 2, 4, 8, 16, 30, 30]
            for index in expected.indices {
                try await requireEventually { sleeps.delays.count == index + 1 }
                XCTAssertEqual(sleeps.delays, Array(expected.prefix(index + 1)))
                XCTAssertEqual(probe.observations.map(\.opcode), Array(repeating: 1, count: index + 1))
                XCTAssertEqual(failed[index].closeEnteredCount, 1)
                XCTAssertEqual(failed[index].closeReturnedCount, 1)
                XCTAssertEqual(fixture.factory.attemptCount, index + 1)
                XCTAssertTrue(fixture.logger.onlineMessages.isEmpty)
                XCTAssertNil(fixture.completion.value)
                assertPrecedes("close-return:failed-\(index)", "proposal:1:\(index)", in: trace)
                sleeps.release(index)
            }
            try await requireEventually { waiting.connectReturnedCount == 1 }
            XCTAssertEqual(fixture.factory.attemptCount, 8)
            XCTAssertEqual(sleeps.delays, expected)
            XCTAssertTrue(fixture.logger.onlineMessages.isEmpty, "Upgrade is not a policy reset")
            waiting.emit(.waiting)
            try await requireEventually { fixture.logger.onlineMessages.count == 1 }
            XCTAssertEqual(probe.observations.map(\.opcode), [1, 1, 1, 1, 1, 1, 1, 0])
            XCTAssertEqual(probe.observations.last?.priorDelay, 30)
            XCTAssertEqual(probe.observations.last?.priorValidated, 0)
            XCTAssertEqual(waiting.closeEnteredCount, 0)
        } catch { await fixture.cleanup(); throw error }
        await fixture.cleanup()
        XCTAssertEqual(fixture.completion.value, .normal)
    }

    func testAvailabilityWaitingAndReadyResetOnlyAfterNativeHandling() async throws {
        let exchange = try RemoteAvailabilityExchangeID(wireValue: "AAECAwQFBgcICQoLDA0ODw")
        let replacementExchange = try RemoteAvailabilityExchangeID(wireValue: "EBESExQVFhcYGRobHB0eHw")
        for validEvent in [PairedAvailabilitySignalingEvent.waiting,
                           .ready(role: .host, exchangeID: exchange)] {
            let trace = RetryCoordinatorTrace()
            let first = RetryCoordinatorClient(id: "first", behavior: .open([.serverError(.roleConflict)]), trace: trace)
            let second = RetryCoordinatorClient(id: "second", behavior: .transportCancellation, trace: trace)
            let current = RetryCoordinatorClient(id: "current", behavior: .open([]), trace: trace)
            let successor = RetryCoordinatorClient(id: "successor", behavior: .open([]), trace: trace)
            let sleeps = RetryCoordinatorSleeper(gates: (0..<3).map { _ in RetryCoordinatorGate() }, trace: trace)
            let probe = RetryCoordinatorProducerProbe(trace: trace)
            let fixture = try RetryCoordinatorFixture(clients: [first, second, current, successor],
                sleeper: sleeps, producer: probe.producer, trace: trace)
            do {
                _ = try await fixture.coordinator.start(resetPairing: false)
                try await requireEventually { sleeps.delays.count == 1 }; sleeps.release(0)
                try await requireEventually { sleeps.delays.count == 2 }; sleeps.release(1)
                try await requireEventually { current.connectReturnedCount == 1 }
                XCTAssertEqual(sleeps.delays, [1, 2])
                XCTAssertEqual(probe.observations.map(\.opcode), [1, 1])
                XCTAssertTrue(fixture.logger.onlineMessages.isEmpty)
                current.emit(validEvent)
                try await requireEventually { fixture.logger.onlineMessages.count == 1 }
                // Waiting is repeatable. A second ready must have a new exchange:
                // the existing lifecycle deliberately rejects duplicate ready.
                current.emit(validEvent == .waiting ? .waiting
                    : .ready(role: .host, exchangeID: replacementExchange))
                try await requireEventually { probe.observations.count == 4 }
                _ = try await fixture.coordinator.pairedPhones()
                XCTAssertEqual(probe.observations.map(\.opcode), [1, 1, 0, 0])
                XCTAssertEqual(probe.observations[2].priorDelay, 4)
                XCTAssertEqual(probe.observations[2].priorValidated, 0)
                XCTAssertEqual(probe.observations[3].priorDelay, 1)
                XCTAssertEqual(probe.observations[3].priorValidated, 1)
                XCTAssertEqual(fixture.logger.onlineMessages.count, 1)
                // Genuine signed response, but invalid in the host's native event direction.
                current.emit(.signal(.reconnectResponse(fixture.rejectedHostPayload)))
                try await requireEventually { sleeps.delays.count == 3 }
                XCTAssertEqual(probe.observations.map(\.opcode), [1, 1, 0, 0, 1])
                XCTAssertEqual(sleeps.delays, [1, 2, 1])
                XCTAssertEqual(current.closeReturnedCount, 1)
                XCTAssertEqual(fixture.logger.onlineMessages.count, 1)
                let stages = fixture.telemetry.drafts.map(\.stage)
                XCTAssertEqual(stages.filter { $0 == .hostWorkerWaitingForViewer }.count,
                               validEvent == .waiting ? 2 : 0)
                XCTAssertEqual(stages.filter { $0 == .availabilityReady }.count,
                               validEvent == .waiting ? 0 : 2)
                sleeps.release(2)
                try await requireEventually { successor.connectReturnedCount == 1 }
                XCTAssertNil(fixture.completion.value)
            } catch { await fixture.cleanup(); throw error }
            await fixture.cleanup()
            XCTAssertEqual(fixture.completion.value, .normal)
        }
    }

    func testDuplicateReadyRefusesBeforeResetAndRetriesOnlyAfterExactClose() async throws {
        let exchange = try RemoteAvailabilityExchangeID(wireValue: "AAECAwQFBgcICQoLDA0ODw")
        let trace = RetryCoordinatorTrace()
        let close = RetryCoordinatorGate()
        let current = RetryCoordinatorClient(id: "duplicate-ready", behavior: .open([]), closeGate: close, trace: trace)
        let successor = RetryCoordinatorClient(id: "after-duplicate", behavior: .open([]), trace: trace)
        let sleeps = RetryCoordinatorSleeper(gates: [RetryCoordinatorGate()], trace: trace)
        let probe = RetryCoordinatorProducerProbe(trace: trace)
        let fixture = try RetryCoordinatorFixture(clients: [current, successor], sleeper: sleeps,
                                                  producer: probe.producer, trace: trace)
        do {
            _ = try await fixture.coordinator.start(resetPairing: false)
            try await requireEventually { current.connectReturnedCount == 1 }
            current.emit(.ready(role: .host, exchangeID: exchange))
            try await requireEventually { fixture.logger.onlineMessages.count == 1 }
            XCTAssertEqual(probe.observations.map(\.opcode), [0])
            current.emit(.ready(role: .host, exchangeID: exchange))
            try await requireEventually { current.closeEnteredCount == 1 }
            XCTAssertEqual(current.closeReturnedCount, 0)
            XCTAssertEqual(probe.observations.map(\.opcode), [0],
                           "Rejected native event cannot reset or consume retry before exact close")
            XCTAssertTrue(sleeps.delays.isEmpty)
            XCTAssertEqual(fixture.factory.attemptCount, 1)
            XCTAssertEqual(fixture.logger.onlineMessages.count, 1)
            XCTAssertNil(fixture.completion.value)
            close.release()
            try await requireEventually { sleeps.delays.count == 1 }
            XCTAssertEqual(probe.observations.map(\.opcode), [0, 1])
            XCTAssertEqual(probe.observations[1].priorDelay, 1)
            XCTAssertEqual(probe.observations[1].priorValidated, 1)
            XCTAssertEqual(sleeps.delays, [1])
            XCTAssertEqual(current.closeReturnedCount, 1)
            assertPrecedes("close-return:duplicate-ready", "proposal:1:1", in: trace)
            sleeps.release(0)
            try await requireEventually { successor.connectReturnedCount == 1 }
            XCTAssertEqual(fixture.factory.attemptCount, 2)
            XCTAssertNil(fixture.completion.value)
        } catch { await fixture.cleanup(); throw error }
        await fixture.cleanup()
        XCTAssertEqual(fixture.completion.value, .normal)
    }

    func testMalformedValidStateProposalClosesExactClientBeforeDistinctTerminalError() async throws {
        let trace = RetryCoordinatorTrace()
        let close = RetryCoordinatorGate()
        let client = RetryCoordinatorClient(id: "invalid-valid", behavior: .open([.waiting]), closeGate: close, trace: trace)
        let sleeps = RetryCoordinatorSleeper(gates: [], trace: trace)
        let probe = RetryCoordinatorProducerProbe(corruptOpcode: 0, trace: trace)
        let fixture = try RetryCoordinatorFixture(clients: [client], sleeper: sleeps,
                                                  producer: probe.producer, trace: trace)
        do {
            _ = try await fixture.coordinator.start(resetPairing: false)
            try await requireEventually { client.closeEnteredCount == 1 }
            XCTAssertEqual(client.closeReturnedCount, 0)
            XCTAssertNil(fixture.completion.value, "Terminal error must wait for exact close return")
            XCTAssertEqual(fixture.factory.attemptCount, 1)
            XCTAssertEqual(probe.observations.map(\.opcode), [0])
            XCTAssertTrue(sleeps.delays.isEmpty)
            XCTAssertTrue(fixture.logger.onlineMessages.isEmpty)
            XCTAssertFalse(fixture.telemetry.drafts.contains { $0.stage == .retryScheduled })
            close.release()
            try await requireEventually { fixture.completion.value != nil }
            await fixture.completionObserver.value
            XCTAssertEqual(client.closeReturnedCount, 1)
            XCTAssertEqual(client.closeEnteredCount, 1)
            XCTAssertEqual(fixture.completion.value, .invalidBridge)
            XCTAssertEqual(probe.observations.map(\.opcode), [0])
            XCTAssertTrue(sleeps.delays.isEmpty)
            XCTAssertEqual(fixture.presentations.value.last, .stopped)
            XCTAssertEqual(fixture.logger.errorMessages,
                           ["Worldwide availability retry policy bridge invalid; host stopped"])
            XCTAssertFalse(fixture.telemetry.drafts.contains { $0.stage == .availabilityLoopUnexpectedlyEnded })
            XCTAssertFalse(fixture.telemetry.drafts.contains { $0.stage == .retryScheduled })
            assertPrecedes("close-return:invalid-valid", "completion:invalidBridge", in: trace)
        } catch { await fixture.cleanup(); throw error }
        await fixture.cleanup()
    }

    func testMalformedFailureProposalClosesExactClientThenStopsWithoutSleeping() async throws {
        let trace = RetryCoordinatorTrace()
        let client = RetryCoordinatorClient(id: "invalid-failure", behavior: .transportCancellation, trace: trace)
        let sleeps = RetryCoordinatorSleeper(gates: [], trace: trace)
        let probe = RetryCoordinatorProducerProbe(corruptOpcode: 1, trace: trace)
        let fixture = try RetryCoordinatorFixture(clients: [client], sleeper: sleeps,
                                                  producer: probe.producer, trace: trace)
        do {
            _ = try await fixture.coordinator.start(resetPairing: false)
            try await requireEventually { fixture.completion.value != nil }
            await fixture.completionObserver.value
            XCTAssertEqual(client.connectObservedOwnerCancellation, false)
            XCTAssertEqual(client.closeEnteredCount, 1)
            XCTAssertEqual(client.closeReturnedCount, 1)
            XCTAssertEqual(probe.observations.map(\.opcode), [1])
            XCTAssertEqual(fixture.factory.attemptCount, 1)
            XCTAssertTrue(sleeps.delays.isEmpty)
            XCTAssertEqual(fixture.completion.value, .invalidBridge)
            XCTAssertFalse(fixture.telemetry.drafts.contains { $0.stage == .retryScheduled })
            XCTAssertFalse(fixture.telemetry.drafts.contains { $0.stage == .availabilityLoopUnexpectedlyEnded })
            assertPrecedes("close-return:invalid-failure", "proposal:1:0", in: trace)
            assertPrecedes("proposal:1:0", "completion:invalidBridge", in: trace)
        } catch { await fixture.cleanup(); throw error }
        await fixture.cleanup()
    }

    func testCancellationOrOwnerReplacementDuringExactCloseCannotStopSuccessor() async throws {
        // Fault-close cancellation is public-API reachable; catalog replacement at that point is not.
        do {
            let trace = RetryCoordinatorTrace()
            let close = RetryCoordinatorGate()
            let old = RetryCoordinatorClient(id: "cancelled-fault", behavior: .open([.waiting]), closeGate: close, trace: trace)
            let sleeps = RetryCoordinatorSleeper(gates: [], trace: trace)
            let probe = RetryCoordinatorProducerProbe(corruptOpcode: 0, trace: trace)
            let fixture = try RetryCoordinatorFixture(clients: [old], sleeper: sleeps,
                                                      producer: probe.producer, trace: trace)
            do {
                _ = try await fixture.coordinator.start(resetPairing: false)
                try await requireEventually { old.closeEnteredCount == 1 }
                XCTAssertEqual(old.closeReturnedCount, 0)
                XCTAssertEqual(fixture.startedSupervisorCount, 1)
                XCTAssertEqual(fixture.endedSupervisorCount, 0)
                await fixture.coordinator.stop()
                await fixture.completionObserver.value
                XCTAssertEqual(fixture.completion.value, .normal)
                XCTAssertEqual(fixture.endedSupervisorCount, 0, "Stop completion alone is not worker-exit proof")
                close.release()
                try await requireEventually { fixture.endedSupervisorCount == 1 }
                XCTAssertEqual(old.closeReturnedCount, 1)
                XCTAssertEqual(fixture.endedSupervisorCount, fixture.startedSupervisorCount)
                assertPrecedes("close-return:cancelled-fault", "supervisor-ended:1", in: trace)
                do { _ = try await fixture.coordinator.phoneCatalogAction(); XCTFail("Stopped owner must deny admission") }
                catch { XCTAssertEqual(error as? WorldwidePhoneCatalogRuntimeError, .notQuiet) }
                XCTAssertEqual(probe.observations.map(\.opcode), [0])
                XCTAssertEqual(fixture.factory.attemptCount, 1)
                XCTAssertTrue(sleeps.delays.isEmpty)
                XCTAssertFalse(fixture.telemetry.drafts.contains { $0.stage == .attemptFailed })
                XCTAssertEqual(old.closeEnteredCount, 1)
            } catch { await fixture.cleanup(); throw error }
            await fixture.cleanup()
        }

        // Real normal-retirement replacement: selectPhone joins the exact old child before mutation.
        do {
            let trace = RetryCoordinatorTrace()
            let close = RetryCoordinatorGate()
            let old = RetryCoordinatorClient(id: "old-selected", behavior: .open([.waiting]), closeGate: close, trace: trace)
            let successor = RetryCoordinatorClient(id: "new-selected", behavior: .open([.waiting]), trace: trace)
            let sleeps = RetryCoordinatorSleeper(gates: [], trace: trace)
            let probe = RetryCoordinatorProducerProbe(trace: trace)
            let fixture = try RetryCoordinatorFixture(clients: [old, successor], sleeper: sleeps,
                producer: probe.producer, trace: trace, addSecondPhone: true)
            var selection: Task<Void, Error>?
            do {
                _ = try await fixture.coordinator.start(resetPairing: false)
                try await requireEventually { probe.observations.count == 1 }
                let action = try await fixture.coordinator.phoneCatalogAction()
                let phoneID = try XCTUnwrap(fixture.secondPhoneID)
                let selecting = Task { try await fixture.coordinator.selectPhone(phoneID, action: action) }
                selection = selecting
                try await requireEventually { old.closeEnteredCount == 1 }
                XCTAssertEqual(old.closeReturnedCount, 0)
                XCTAssertEqual(fixture.factory.attemptCount, 1)
                XCTAssertEqual(successor.closeEnteredCount, 0)
                old.emit(.waiting)
                close.release()
                try await selecting.value
                selection = nil
                XCTAssertEqual(fixture.endedSupervisorCount, 1, "Selection joined the exact retired child")
                try await requireEventually { probe.observations.count == 2 }
                // A fresh current waiting event must actually authorize a new ticket, not merely increment a fake count.
                _ = try await fixture.coordinator.phoneCatalogAction()
                let catalog = try await fixture.coordinator.pairedPhones()
                XCTAssertEqual(catalog.selectedPhoneID, phoneID)
                XCTAssertEqual(old.closeEnteredCount, 1)
                XCTAssertEqual(old.closeReturnedCount, 1)
                XCTAssertEqual(successor.closeEnteredCount, 0)
                XCTAssertEqual(fixture.factory.attemptCount, 2)
                XCTAssertEqual(fixture.startedSupervisorCount, 2)
                XCTAssertEqual(probe.observations.map(\.opcode), [0, 0])
                XCTAssertEqual(probe.observations.map(\.priorValidated), [0, 0])
                XCTAssertTrue(sleeps.delays.isEmpty)
                XCTAssertNil(fixture.completion.value)
                XCTAssertFalse(fixture.telemetry.drafts.contains { $0.stage == .attemptFailed })
            } catch {
                close.release()
                if let selection { _ = await selection.result }
                await fixture.cleanup()
                throw error
            }
            await fixture.cleanup()
            XCTAssertEqual(successor.closeReturnedCount, 1)
            XCTAssertEqual(fixture.completion.value, .normal)
        }
    }

    func testRetrySleepFailureDoesNotConsumeSecondPolicyProposalForSameFailure() async throws {
        let trace = RetryCoordinatorTrace()
        let failed = RetryCoordinatorClient(id: "sleep-failed", behavior: .transportCancellation, trace: trace)
        let current = RetryCoordinatorClient(id: "after-sleep-error", behavior: .open([]), trace: trace)
        let sleeps = RetryCoordinatorSleeper(gates: [], throwAt: 0, trace: trace)
        let probe = RetryCoordinatorProducerProbe(trace: trace)
        let fixture = try RetryCoordinatorFixture(clients: [failed, current], sleeper: sleeps,
                                                  producer: probe.producer, trace: trace)
        do {
            _ = try await fixture.coordinator.start(resetPairing: false)
            try await requireEventually {
                fixture.telemetry.drafts.last?.stage == .availabilitySocketOpened && fixture.factory.attemptCount == 2
            }
            XCTAssertEqual(failed.closeEnteredCount, 1)
            XCTAssertEqual(failed.closeReturnedCount, 1)
            XCTAssertEqual(probe.observations.map(\.opcode), [1])
            XCTAssertEqual(sleeps.delays, [1])
            XCTAssertEqual(current.connectReturnedCount, 1)
            XCTAssertEqual(current.closeEnteredCount, 0)
            XCTAssertNil(fixture.completion.value)
            XCTAssertEqual(fixture.telemetry.drafts.filter { $0.stage == .retryScheduled }.count, 1)
            XCTAssertTrue(fixture.logger.errorMessages.contains(
                "Worldwide availability retry delay failed without owner cancellation; retrying immediately"))
            assertPrecedes("close-return:sleep-failed", "proposal:1:0", in: trace)
            assertPrecedes("sleep-throw:0", "connect-return:after-sleep-error", in: trace)
        } catch { await fixture.cleanup(); throw error }
        await fixture.cleanup()
        XCTAssertEqual(probe.observations.map(\.opcode), [1])
        XCTAssertEqual(fixture.completion.value, .normal)
    }

    private func requireEventually(_ condition: @escaping @Sendable () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw RetryCoordinatorTestError.observationTimedOut
    }

    private func assertPrecedes(_ first: String, _ second: String, in trace: RetryCoordinatorTrace,
                                file: StaticString = #filePath, line: UInt = #line) {
        guard let before = trace.events.firstIndex(of: first), let after = trace.events.firstIndex(of: second) else {
            return XCTFail("Missing ordered native evidence: \(first), \(second)", file: file, line: line)
        }
        XCTAssertLessThan(before, after, file: file, line: line)
    }
}

private enum RetryCoordinatorTestError: Error { case exhaustedFactory, observationTimedOut, sleepFailed, unexpectedSend }
private enum RetryCoordinatorCompletion: Equatable, Sendable { case normal, invalidBridge, unexpectedLoopEnd, otherError }
private struct RetryCoordinatorObservation: Sendable {
    let opcode: UInt32
    let priorDelay: UInt32
    let priorValidated: UInt32
}

private final class RetryCoordinatorProducerProbe: @unchecked Sendable {
    private let values = RetryCoordinatorLocked<[RetryCoordinatorObservation]>([])
    private let corruptOpcode: UInt32?
    private let trace: RetryCoordinatorTrace
    init(corruptOpcode: UInt32? = nil, trace: RetryCoordinatorTrace) {
        self.corruptOpcode = corruptOpcode; self.trace = trace
    }
    var observations: [RetryCoordinatorObservation] { values.value }
    var producer: BelugaRustAvailabilityRetryProducer {
        BelugaRustAvailabilityRetryProducer { [self] abi, before, event in
            var output = BelugaRustAvailabilityRetryProducer.actual.step(abi, before, event)
            let index = values.modify { storage in
                let index = storage.count
                storage.append(.init(opcode: event.opcode, priorDelay: before.next_delay_seconds,
                                     priorValidated: before.has_validated_connection))
                return index
            }
            trace.append("proposal:\(event.opcode):\(index)")
            if event.opcode == corruptOpcode { output.reserved = 1 }
            return output
        }
    }
}

private final class RetryCoordinatorFixture: @unchecked Sendable {
    let coordinator: WorldwideHostCoordinator
    let factory: RetryCoordinatorFactory
    let completion: RetryCoordinatorLocked<RetryCoordinatorCompletion?>
    private let supervisorEnds: RetryCoordinatorLocked<Int>
    let presentations: RetryCoordinatorLocked<[BelugaHostPresentationPhase]>
    let telemetry: RetryCoordinatorTelemetry
    let logger: RetryCoordinatorLogger
    let rejectedHostPayload: RemoteReconnectResponse
    let secondPhoneID: UUID?
    let completionObserver: Task<Void, Never>
    private let clients: [RetryCoordinatorClient]
    private let sleeper: RetryCoordinatorSleeper

    init(clients: [RetryCoordinatorClient], sleeper: RetryCoordinatorSleeper,
         producer: BelugaRustAvailabilityRetryProducer, trace: RetryCoordinatorTrace,
         addSecondPhone: Bool = false) throws {
        self.clients = clients; self.sleeper = sleeper
        let completion = RetryCoordinatorLocked<RetryCoordinatorCompletion?>(nil)
        let supervisorEnds = RetryCoordinatorLocked<Int>(0)
        let presentations = RetryCoordinatorLocked<[BelugaHostPresentationPhase]>([])
        let telemetry = RetryCoordinatorTelemetry()
        let logger = RetryCoordinatorLogger()
        self.completion = completion
        self.supervisorEnds = supervisorEnds
        self.presentations = presentations
        self.telemetry = telemetry
        self.logger = logger
        let store = WorldwidePairingStore(dataStore: RetryCoordinatorMemoryStore())
        let host = try store.loadOrCreateHostIdentity(displayName: "Test Mac")
        let pair = try Self.makeActivePair(host: host)
        try store.savePairedViewer(pair.hostRecord, for: host)
        if addSecondPhone {
            let second = try Self.makeActivePair(host: host)
            let before = try store.phoneCatalog.loadOrMigrate(for: host)
            _ = try store.phoneCatalog.addPairedPhone(second.hostRecord, for: host, expectedToken: before.token)
            secondPhoneID = second.hostRecord.remoteDeviceID
        } else { secondPhoneID = nil }
        var viewerCopy = pair.viewerRecord
        var hostCopy = pair.hostRecord
        let request = try viewerCopy.beginReconnect(using: pair.viewer).request
        rejectedHostPayload = try hostCopy.respond(to: request, using: host).response
        let factory = RetryCoordinatorFactory(clients: clients, trace: trace)
        self.factory = factory
        let coordinator = WorldwideHostCoordinator(
            endpoint: URL(string: "wss://example.invalid")!, forceRelay: false,
            screenDisplayID: nil, systemAudioDisplayID: nil, maximumWidth: 1_280,
            framesPerSecond: 30, maximumVideoBitrate: 4_000_000,
            remoteInputController: MacRemoteInputController(allowRemoteControl: false),
            store: store, hostDisplayName: "Test Mac",
            availabilityClientFactory: { _, _ in try factory.next() },
            availabilityRetrySleep: { try await sleeper.sleep($0) }, availabilityRetryProducer: producer,
            availabilityLoopDidEndObserver: {
                supervisorEnds.modify { count in
                    count += 1
                    trace.append("supervisor-ended:\(count)")
                }
            },
            connectionTelemetry: telemetry,
            presentation: { value in presentations.modify { $0.append(value.phase) } },
            catalogMutationIsAuthorized: { true }, catalogOwnerIsValid: { true },
            pairingClientFactory: { _, _ in throw RetryCoordinatorTestError.exhaustedFactory },
            logger: logger)
        self.coordinator = coordinator
        completionObserver = Task {
            let outcome: RetryCoordinatorCompletion
            do {
                var count = 0
                for try await _ in coordinator.completion { count += 1 }
                outcome = count == 1 ? .normal : .otherError
            } catch WorldwideAvailabilityRetryError.invalidBridge { outcome = .invalidBridge }
            catch WorldwideHostCoordinatorError.availabilityLoopEndedUnexpectedly { outcome = .unexpectedLoopEnd }
            catch { outcome = .otherError }
            trace.append("completion:\(outcome)")
            completion.modify { $0 = outcome }
        }
    }

    var startedSupervisorCount: Int {
        telemetry.drafts.filter { $0.stage == .availabilityLoopStarted }.count
    }
    var endedSupervisorCount: Int { supervisorEnds.value }

    func cleanup(file: StaticString = #filePath, line: UInt = #line) async {
        let stopping = Task { await coordinator.stop() }
        // Stop retires the generation synchronously before awaiting a close; release only afterward.
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while presentations.value.last != .stopped && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        sleeper.releaseAll()
        for client in clients { client.releaseClose() }
        _ = await stopping.value
        await completionObserver.value
        let expectedEnds = startedSupervisorCount
        let exitDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while endedSupervisorCount < expectedEnds && ContinuousClock.now < exitDeadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(endedSupervisorCount, expectedEnds,
                       "Every started worker must finish the actual supervisor guards", file: file, line: line)
    }

    private static func makeActivePair(host: RemoteDeviceIdentity) throws
        -> (hostRecord: RemotePairedDeviceRecord, viewer: RemoteDeviceIdentity, viewerRecord: RemotePairedDeviceRecord) {
        // Explicitly duplicated real existing transcript; no private cross-file fixture or authored trust bytes.
        let viewer = try RemoteDeviceIdentity.generate(role: .viewer, displayName: "Test iPhone")
        let invitation = try RemoteInvitationCode.generate()
        let hostParticipant = try RemotePairingParticipant(identity: host, invitation: invitation)
        let viewerParticipant = try RemotePairingParticipant(identity: viewer, invitation: invitation)
        let hostAgreement = try hostParticipant.accept(viewerParticipant.hello)
        let viewerAgreement = try viewerParticipant.accept(hostParticipant.hello)
        var hostRecord = try hostAgreement.makePendingRecord(peerConfirmation: viewerAgreement.makeConfirmation())
        var viewerRecord = try viewerAgreement.makePendingRecord(peerConfirmation: hostAgreement.makeConfirmation())
        let proposal = try hostRecord.prepareProposal(using: host)
        let acknowledgement = try viewerRecord.prepareAcknowledgement(after: proposal, using: viewer)
        try hostRecord.acceptAcknowledgement(acknowledgement)
        let completion = try hostRecord.prepareCompletion(using: host)
        let activation = try viewerRecord.acceptCompletion(completion, using: viewer)
        try hostRecord.acceptActivationAcknowledgement(activation)
        return (hostRecord, viewer, viewerRecord)
    }
}

private final class RetryCoordinatorClient: WorldwideHostAvailabilityTransport, @unchecked Sendable {
    enum Behavior: Sendable { case transportCancellation, open([PairedAvailabilitySignalingEvent]) }
    private struct Storage {
        var continuation: PairedAvailabilitySignalingClient.EventStream.Continuation?
        var connectReturns = 0
        var closeEntries = 0
        var closeReturns = 0
        var ownerCancelled: Bool?
    }
    private let state = RetryCoordinatorLocked(Storage())
    private let id: String
    private let behavior: Behavior
    private let closeGate: RetryCoordinatorGate?
    private let trace: RetryCoordinatorTrace
    init(id: String, behavior: Behavior, closeGate: RetryCoordinatorGate? = nil, trace: RetryCoordinatorTrace) {
        self.id = id; self.behavior = behavior; self.closeGate = closeGate; self.trace = trace
    }
    func connect() async throws -> PairedAvailabilitySignalingClient.EventStream {
        switch behavior {
        case .transportCancellation:
            state.modify { $0.ownerCancelled = Task.isCancelled }
            trace.append("connect-throw:\(id)")
            throw CancellationError()
        case .open(let events):
            let pair = PairedAvailabilitySignalingClient.EventStream.makeStream()
            state.modify { $0.continuation = pair.continuation; $0.connectReturns += 1 }
            for event in events { pair.continuation.yield(event) }
            trace.append("connect-return:\(id)")
            return pair.stream
        }
    }
    func send(_: RemoteAvailabilityPayload) async throws { throw RetryCoordinatorTestError.unexpectedSend }
    func close() async {
        let continuation = state.modify { storage in
            storage.closeEntries += 1
            defer { storage.continuation = nil }
            return storage.continuation
        }
        trace.append("close-enter:\(id)")
        continuation?.finish()
        await closeGate?.wait()
        trace.append("close-return:\(id)")
        state.modify { $0.closeReturns += 1 }
    }
    func emit(_ event: PairedAvailabilitySignalingEvent) { state.value.continuation?.yield(event) }
    func releaseClose() { closeGate?.release() }
    var connectReturnedCount: Int { state.value.connectReturns }
    var closeEnteredCount: Int { state.value.closeEntries }
    var closeReturnedCount: Int { state.value.closeReturns }
    var connectObservedOwnerCancellation: Bool? { state.value.ownerCancelled }
}

private final class RetryCoordinatorFactory: @unchecked Sendable {
    private struct Storage { var clients: [RetryCoordinatorClient]; var attempts = 0 }
    private let state: RetryCoordinatorLocked<Storage>
    private let trace: RetryCoordinatorTrace
    init(clients: [RetryCoordinatorClient], trace: RetryCoordinatorTrace) {
        state = RetryCoordinatorLocked(Storage(clients: clients)); self.trace = trace
    }
    func next() throws -> any WorldwideHostAvailabilityTransport {
        try state.modify { storage in
            storage.attempts += 1
            trace.append("factory:\(storage.attempts)")
            guard !storage.clients.isEmpty else { throw RetryCoordinatorTestError.exhaustedFactory }
            return storage.clients.removeFirst()
        }
    }
    var attemptCount: Int { state.value.attempts }
}

private final class RetryCoordinatorSleeper: @unchecked Sendable {
    private let values = RetryCoordinatorLocked<[Int]>([])
    private let gates: [RetryCoordinatorGate]
    private let unexpectedGate = RetryCoordinatorGate()
    private let throwAt: Int?
    private let trace: RetryCoordinatorTrace
    init(gates: [RetryCoordinatorGate], throwAt: Int? = nil, trace: RetryCoordinatorTrace) {
        self.gates = gates; self.throwAt = throwAt; self.trace = trace
    }
    func sleep(_ delay: Int) async throws {
        let index = values.modify { storage in let index = storage.count; storage.append(delay); return index }
        trace.append("sleep-enter:\(index)")
        if index == throwAt { trace.append("sleep-throw:\(index)"); throw RetryCoordinatorTestError.sleepFailed }
        if gates.indices.contains(index) { await gates[index].wait() }
        else { await unexpectedGate.wait(); throw RetryCoordinatorTestError.exhaustedFactory }
        try Task.checkCancellation()
        trace.append("sleep-return:\(index)")
    }
    var delays: [Int] { values.value }
    func release(_ index: Int) { gates[index].release() }
    func releaseAll() { gates.forEach { $0.release() }; unexpectedGate.release() }
}

private final class RetryCoordinatorGate: @unchecked Sendable {
    private struct Storage { var released = false; var waiters: [CheckedContinuation<Void, Never>] = [] }
    private let state = RetryCoordinatorLocked(Storage())
    func wait() async {
        await withCheckedContinuation { continuation in
            let resume = state.modify { storage in
                if storage.released { return true }
                storage.waiters.append(continuation); return false
            }
            if resume { continuation.resume() }
        }
    }
    func release() {
        let waiters = state.modify { storage in
            storage.released = true
            defer { storage.waiters.removeAll() }
            return storage.waiters
        }
        waiters.forEach { $0.resume() }
    }
}

private final class RetryCoordinatorTrace: @unchecked Sendable {
    private let storage = RetryCoordinatorLocked<[String]>([])
    func append(_ event: String) { storage.modify { $0.append(event) } }
    var events: [String] { storage.value }
}

private final class RetryCoordinatorTelemetry: ConnectionTelemetryRecording, @unchecked Sendable {
    private let storage = RetryCoordinatorLocked<[ConnectionTelemetryDraft]>([])
    func record(_ draft: ConnectionTelemetryDraft) -> ConnectionTelemetrySnapshot {
        storage.modify { $0.append(draft) }; return .empty
    }
    func snapshot() -> ConnectionTelemetrySnapshot { .empty }
    var drafts: [ConnectionTelemetryDraft] { storage.value }
}

private final class RetryCoordinatorLogger: Logger, @unchecked Sendable {
    private let information = RetryCoordinatorLocked<[String]>([])
    private let errors = RetryCoordinatorLocked<[String]>([])
    func info(_ value: String) { information.modify { $0.append(value) } }
    func debug(_: String) {}
    func error(_ value: String) { errors.modify { $0.append(value) } }
    var onlineMessages: [String] { information.value.filter { $0.hasPrefix("Worldwide paired-device availability is online") } }
    var errorMessages: [String] { errors.value }
}

private final class RetryCoordinatorMemoryStore: WorldwidePairingDataStore, @unchecked Sendable {
    private let values = RetryCoordinatorLocked<[String: Data]>([:])
    func data(for account: String) throws -> Data? { values.value[account] }
    func set(_ data: Data, for account: String) throws { values.modify { $0[account] = data } }
    func removeData(for account: String) throws { values.modify { _ = $0.removeValue(forKey: account) } }
}

private final class RetryCoordinatorLocked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value
    init(_ value: Value) { storage = value }
    var value: Value { lock.lock(); defer { lock.unlock() }; return storage }
    @discardableResult func modify<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock(); defer { lock.unlock() }; return try body(&storage)
    }
}
