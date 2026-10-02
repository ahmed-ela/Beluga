import AppKit
import BelugaUpdateCore
import BelugaUpdateDriver
import Darwin
import Foundation

@main
struct BelugaUpdaterMain {
    @MainActor static func main() {
        if CommandLine.arguments == [CommandLine.arguments[0], "--help"] {
            print("BelugaUpdater is launched only by the signed Beluga menu application.")
            return
        }
        guard let launch = try? BelugaUpdateBrokerLaunch(arguments: CommandLine.arguments) else { Darwin.exit(64) }
        let app = NSApplication.shared
        let delegate = BrokerApplication(launch: launch)
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

/// Mutable session is prepared on one worker, then handed to the main actor once.
/// Its only later worker use is the terminal path after SDK activity has ended.
private final class Prepared: @unchecked Sendable {
    let launch: BelugaUpdateBrokerLaunch
    let context: BelugaUpdateRuntimeContext
    let verification: BelugaUpdateInstalledArtifact.Verification
    let session: BelugaUpdateBrokerSession
    let channel: BelugaUpdateIPCChannel
    let predecessorPeer: BelugaUpdatePeerIdentity.Peer
    let readiness: BelugaUpdateIPCEndpoint.Listener

    init(launch: BelugaUpdateBrokerLaunch, context: BelugaUpdateRuntimeContext,
         verification: BelugaUpdateInstalledArtifact.Verification, session: BelugaUpdateBrokerSession,
         channel: BelugaUpdateIPCChannel, peer: BelugaUpdatePeerIdentity.Peer,
         readiness: BelugaUpdateIPCEndpoint.Listener) {
        self.launch = launch; self.context = context; self.verification = verification
        self.session = session; self.channel = channel; predecessorPeer = peer; self.readiness = readiness
    }

    static func prepare(_ launch: BelugaUpdateBrokerLaunch, ownBundleURL: URL) throws -> Prepared {
        let lease = try WorldwideHostProcessLock.acquire()
        var transferred = false
        defer { if !transferred { lease.release() } }
        guard let bundle = Bundle(path: launch.target.canonicalPath),
              let context = try BelugaUpdateRuntimeContext.resolve(bundle: bundle), context.target == launch.target else {
            throw BrokerApplication.Failure.invalidTarget
        }
        try BelugaUpdateBrokerLaunch.requireWritableInstallation(context)
        let verification = try BelugaUpdateInstalledArtifact.readback(context: context)
        try requireLineage(verification)
        let directory = try BelugaUpdateIPCEndpoint.directoryURL(operationID: launch.operationID,
                                                                 effectiveUID: launch.target.effectiveUID)
        let embedded = try BelugaUpdateBrokerArtifact.readbackEmbedded(context: context,
                                                                       configuration: verification.configuration)
        let binding = try BelugaUpdateOperation.BrokerBinding(artifact: embedded.identity,
                                                              nativeCDHash: embedded.nativeCDHash)
        let staged = try BelugaUpdateBrokerArtifact.readbackExistingStaged(operationID: launch.operationID,
            target: launch.target, expectedBroker: binding, configuration: verification.configuration,
            stagingParentURL: directory)
        guard ownBundleURL.path + "/Contents/MacOS/BelugaUpdater" == staged.executableURL.path else {
            throw BrokerApplication.Failure.invalidTarget
        }
        let expected = try BelugaUpdatePeerIdentity.Expectation(role: .main,
            canonicalExecutablePath: launch.target.canonicalPath + "/Contents/MacOS/CaptureServer",
            effectiveUID: launch.target.effectiveUID, nativeCDHash: verification.nativeCDHash)
        let channel = try BelugaUpdateIPCChannel.acceptingOwnedSocket(BelugaUpdateIPCEndpoint.connect(
            operationID: launch.operationID, effectiveUID: launch.target.effectiveUID, timeout: 30),
            operationID: launch.operationID, target: launch.target, expectedPeer: expected, timeout: 30)
        do {
            guard case .beginCheck(let menuID) = try channel.receive() else { throw BrokerApplication.Failure.protocolViolation }
            let peer = try channel.authenticatedPeer()
            let readiness = try BelugaUpdateIPCEndpoint.create(operationID: launch.operationID,
                effectiveUID: launch.target.effectiveUID, purpose: .readiness)
            let session = try BelugaUpdateBrokerSession(context: context, acquireOwnership: { lease })
            try session.prepare(operationID: launch.operationID, predecessorMenuInstanceID: menuID,
                controlledHistory: .init(verify: { operationID, target, predecessor in
                    guard operationID == launch.operationID, target == launch.target,
                          predecessor == verification.identity else { throw BrokerApplication.Failure.invalidTarget }
                    let current = try BelugaUpdateInstalledArtifact.readback(context: context, expected: predecessor)
                    try requireLineage(current)
                }), verifyPredecessor: { _ in
                    try BelugaUpdateInstalledArtifact.verify(context: context, expected: verification.identity)
                })
            transferred = true
            try session.bindBroker(binding, operationID: launch.operationID, target: launch.target)
            try channel.send(.checkAccepted)
            return Prepared(launch: launch, context: context, verification: verification,
                session: session, channel: channel, peer: peer, readiness: readiness)
        } catch { channel.close(); throw error }
    }

    static func requireLineage(_ value: BelugaUpdateInstalledArtifact.Verification) throws {
        // Producer protocol1 means every SDK start in the first-shipped lineage
        // (beginning100) is broker-fenced. Release must prove that lineage; old,
        // unpublished/uncontrolled or missing-protocol installs are not enrolled.
        guard value.updateOwnershipProtocol == 1, value.identity.build >= 100 else {
            throw BrokerApplication.Failure.unknownLineage
        }
    }

    func complete(candidate: BelugaUpdateOperation.ArtifactIdentity) throws -> BelugaUpdateIPCChannel {
        guard let bundle = Bundle(path: launch.target.canonicalPath),
              let fresh = try BelugaUpdateRuntimeContext.resolve(bundle: bundle), fresh.target == launch.target else {
            throw BrokerApplication.Failure.invalidTarget
        }
        let installed = BelugaUpdateOperation.InstalledCompletion(operationID: launch.operationID,
            target: launch.target, candidate: candidate)
        try session.acceptInstalledCompletion(installed, freshContext: fresh) { completion, context in
            _ = try BelugaUpdateInstalledArtifact.verify(context: context, expected: completion.candidate)
        }
        let current = try BelugaUpdateInstalledArtifact.readback(context: fresh, expected: candidate)
        let expectation = try BelugaUpdatePeerIdentity.Expectation(role: .main,
            canonicalExecutablePath: launch.target.canonicalPath + "/Contents/MacOS/CaptureServer",
            effectiveUID: launch.target.effectiveUID, nativeCDHash: current.nativeCDHash)
        let channel = try BelugaUpdateIPCChannel.acceptingOwnedSocket(readiness.accept(timeout: 30),
            operationID: launch.operationID, target: launch.target, expectedPeer: expectation, timeout: 30)
        do {
            guard case .requestReadiness(let menuID) = try channel.receive() else { throw BrokerApplication.Failure.protocolViolation }
            let peer = try channel.authenticatedPeer()
            guard peer.processIdentifier != predecessorPeer.processIdentifier ||
                    peer.processVersion != predecessorPeer.processVersion else { throw BrokerApplication.Failure.oldMenu }
            func authenticate() throws {
                guard try channel.authenticatedPeer() == peer else { throw BrokerApplication.Failure.oldMenu }
                _ = try BelugaUpdateInstalledArtifact.verify(context: fresh, expected: candidate)
            }
            let challenge = try session.issueReadinessChallenge(operationID: launch.operationID,
                target: launch.target, menuInstanceID: menuID, nonce: UUID(), authenticateMenu: { _, _, _ in try authenticate() })
            try channel.send(.readinessChallenge(menuInstanceID: menuID, candidate: candidate, nonce: challenge.nonce))
            guard case .menuReady(let response) = try channel.receive(timeout: 30), response.menuInstanceID == menuID else {
                throw BrokerApplication.Failure.protocolViolation
            }
            try session.acceptReadiness(response) { _ in try authenticate() }
            try session.clearAndRelease(operationID: launch.operationID, target: launch.target) { _, _, _ in try authenticate() }
            return channel
        } catch { channel.close(); throw error }
    }
}

@MainActor
private final class BrokerApplication: NSObject, NSApplicationDelegate {
    enum Failure: Error { case invalidTarget, protocolViolation, unknownLineage, oldMenu, incomplete, unarmedProof }
    private let launch: BelugaUpdateBrokerLaunch
    private var prepared: Prepared?
    private var sparkle: BelugaUpdateSparkleSession?
    private var candidate: BelugaUpdateOperation.ArtifactIdentity?
    private var heartbeat: Task<Void, Never>?
    private var finishing = false
    init(launch: BelugaUpdateBrokerLaunch) { self.launch = launch }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launch = launch, ownURL = Bundle.main.bundleURL
        Task {
            do {
                let owned = try await Task.detached { try Prepared.prepare(launch, ownBundleURL: ownURL) }.value
                prepared = owned
                try start(owned)
            } catch { await fail() }
        }
    }

    // The broker must not accept ordinary application quit while an installer may
    // remain armed. Terminal paths explicitly exit only after their bounded cleanup.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { .terminateCancel }

    private func start(_ owned: Prepared) throws {
        guard let bundle = Bundle(path: launch.target.canonicalPath) else { throw Failure.invalidTarget }
        let id = launch.operationID, target = launch.target, session = owned.session
        let authority = BelugaUpdateSparkleSession.Authority(
            withPreparedAuthority: { _, body in try session.startUpdater(operationID: id, target: target, body) },
            isRetained: { $0 == id && session.ownsLease && session.state == .started },
            bindCandidate: { [weak self] _, candidate in
                try session.bindCandidate(candidate, operationID: id, target: target)
                self?.candidate = candidate
            }, authorizeInstallation: { request in
                guard request.operationID == id else { return false }
                return try session.authorizeInstall(operationID: id, target: target, authorize: { true })
            }, mayTerminateTarget: { $0 == id && session.ownsLease && session.state == .started },
            retirePreparedUnarmed: { [weak self] completion in
                try session.retirePreparedUnarmed(completion, verifyCompletion: { value in
                    guard self?.sparkle?.isCurrentUnarmedCompletion(value) == true else { throw Failure.unarmedProof }
                }, verifyPredecessor: { _ in try BelugaUpdateInstalledArtifact.verify(context: owned.context,
                                                                                      expected: owned.verification.identity) })
            })
        sparkle = try BelugaUpdateSparkleSession(targetBundle: bundle,
            verifiedFeedURL: owned.verification.configuration.feedURL, operationID: id,
            authority: authority, observe: { [weak self] value in self?.observed(value) })
        heartbeat = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(10))
                    try Task.checkCancellation()
                    try await Task.detached { try owned.channel.send(.waiting) }.value
                } catch { return } // Old target exit does not retire the broker/marker.
            }
        }
        try sparkle?.startManualCheck()
    }

    private func observed(_ observation: BelugaUpdateSparkleSession.Observation) {
        guard observation.operationID == launch.operationID, !finishing else { return }
        switch observation.event {
        case .installed:
            finishing = true
            Task {
                await drainHeartbeat()
                do {
                    guard let prepared, let candidate else { throw Failure.incomplete }
                    let channel = try await Task.detached { try prepared.complete(candidate: candidate) }.value
                    try await released(channel)
                } catch { await fail() }
            }
        case .unarmedRetired:
            finishing = true
            Task {
                await drainHeartbeat()
                do {
                    guard let prepared else { throw Failure.incomplete }
                    try await released(prepared.channel)
                } catch { await fail() }
            }
        case .cycleFinished:
            // The driver performs unarmed retirement synchronously after this
            // observation. Inspect only once that exact callback has returned.
            Task { if !finishing { await fail() } }
        case .startupFailed, .unarmedRetirementFailed, .extractionInvariantFailed,
             .unexpectedInstallOnQuit, .resumedInstallation, .resumePossible:
            Task { await fail() }
        default: break
        }
    }

    private func drainHeartbeat() async {
        heartbeat?.cancel()
        await heartbeat?.value
        heartbeat = nil
    }

    private func released(_ channel: BelugaUpdateIPCChannel) async throws {
        try await Task.detached {
            try channel.send(.released)
            guard try channel.receive(timeout: 30) == .releaseObserved else { throw Failure.protocolViolation }
            try channel.waitForPeerClosure(timeout: 5)
        }.value
        prepared?.readiness.close()
        Darwin.exit(0)
    }

    private func fail() async {
        finishing = true
        await drainHeartbeat()
        if let prepared {
            try? await Task.detached { try prepared.channel.send(.refused(.installationUncertain)) }.value
            prepared.channel.close(); prepared.readiness.close()
        }
        // Exiting drops the process lock, never its durable target fence.
        Darwin.exit(1)
    }
}
