import BelugaUpdateCore
import Darwin
import Foundation

/// Blocking work confined to the controller's worker. Never starts Sparkle or clears a fence.
enum BelugaUpdateMenuClient {
    enum Failure: Error { case invalidTarget, unsupportedLineage, unexpectedMessage, recoveryRequired, wrongProcess }

    final class Check: @unchecked Sendable {
        let channel: BelugaUpdateIPCChannel
        let process: Process
        let context: BelugaUpdateRuntimeContext
        let predecessor: BelugaUpdateOperation.ArtifactIdentity
        init(channel: BelugaUpdateIPCChannel, process: Process, context: BelugaUpdateRuntimeContext,
             predecessor: BelugaUpdateOperation.ArtifactIdentity) {
            self.channel = channel; self.process = process; self.context = context; self.predecessor = predecessor
        }
        deinit { channel.close() } // Never terminate a broker that may own an installer.

        func waitForRelease() throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(1_800))
            while ContinuousClock.now < deadline {
                switch try channel.receive(timeout: 30) {
                case .waiting: continue
                case .released:
                    try BelugaUpdateMenuClient.verifyReleased(context: context, expected: predecessor)
                    // Terminal receipt is transport cleanup, not reversible authority.
                    // Local fresh readback already verified irreversible clearance.
                    try? channel.send(.releaseObserved)
                    return
                default: throw Failure.unexpectedMessage
                }
            }
            throw Failure.recoveryRequired
        }
    }

    static func context(bundleURL: URL) throws -> BelugaUpdateRuntimeContext {
        guard let bundle = Bundle(url: bundleURL), let context = try BelugaUpdateRuntimeContext.resolve(bundle: bundle) else {
            throw Failure.invalidTarget
        }
        return context
    }

    static func hasFence(bundleURL: URL) throws -> Bool {
        let context = try context(bundleURL: bundleURL)
        return try BelugaUpdateFenceStore(directoryURL: context.fenceDirectoryURL)
            .read(expectedTarget: context.target) != nil
    }

    static func begin(bundleURL: URL, menuInstanceID: UUID) throws -> Check {
        let lease = try WorldwideHostProcessLock.acquire()
        defer { lease.release() }
        let context = try context(bundleURL: bundleURL)
        try BelugaUpdateBrokerLaunch.requireWritableInstallation(context)
        guard try BelugaUpdateFenceStore(directoryURL: context.fenceDirectoryURL)
            .read(expectedTarget: context.target) == nil else { throw Failure.recoveryRequired }
        let verification = try BelugaUpdateInstalledArtifact.readback(context: context)
        // Signed first-distributed broker-only producer contract, not build-number enrollment.
        guard verification.updateOwnershipProtocol == 1, verification.identity.build >= 100 else {
            throw Failure.unsupportedLineage
        }
        let operationID = UUID()
        let listener = try BelugaUpdateIPCEndpoint.create(operationID: operationID,
                                                         effectiveUID: context.target.effectiveUID)
        defer { listener.close() }
        let staged = try BelugaUpdateBrokerArtifact.stage(context: context,
            parentConfiguration: verification.configuration, operationID: operationID,
            stagingParentURL: listener.directoryURL)
        let expectation = try BelugaUpdatePeerIdentity.Expectation(role: .broker,
            canonicalExecutablePath: staged.executableURL.path, effectiveUID: context.target.effectiveUID,
            nativeCDHash: staged.nativeCDHash)
        let launch = try BelugaUpdateBrokerLaunch(operationID: operationID, target: context.target)
        let binding = try BelugaUpdateIPCProtocol.Binding(operationID: operationID,
            target: context.target, channelNonce: UUID())
        let process = Process()
        process.executableURL = staged.executableURL
        process.arguments = launch.arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try BelugaUpdateBrokerArtifact.verifyStaged(context: context,
            parentConfiguration: verification.configuration, staged: staged)
        // No descriptor handoff. Broker must win the ordinary lock itself; a competing host wins safely.
        lease.release()
        try process.run()
        let channel = try BelugaUpdateIPCChannel(takingOwnedSocket: listener.accept(timeout: 30),
            binding: binding, localRole: .menu, expectedPeer: expectation)
        do {
            guard try channel.authenticatedPeer().processIdentifier == process.processIdentifier else {
                throw Failure.wrongProcess
            }
            try channel.send(.beginCheck(menuInstanceID: menuInstanceID))
            guard try channel.receive(timeout: 30) == .checkAccepted else { throw Failure.unexpectedMessage }
            return Check(channel: channel, process: process, context: context, predecessor: verification.identity)
        } catch { channel.close(); throw error }
    }

    /// Only after fresh menu UI construction, before runtime activation.
    static func becomeReady(bundleURL: URL, menuInstanceID: UUID) throws {
        let context = try context(bundleURL: bundleURL)
        let store = try BelugaUpdateFenceStore(directoryURL: context.fenceDirectoryURL)
        guard let snapshot = try store.read(expectedTarget: context.target),
              let candidate = snapshot.operation.candidate,
              let broker = snapshot.operation.brokerBinding else { throw Failure.recoveryRequired }
        let verification = try BelugaUpdateInstalledArtifact.readback(context: context, expected: candidate)
        let predecessor = snapshot.operation.predecessor
        let configuration = try verification.configuration.predecessor(version: predecessor.version, build: predecessor.build)
        let operationID = snapshot.operation.operationID
        let directory = try BelugaUpdateIPCEndpoint.directoryURL(operationID: operationID,
                                                                 effectiveUID: context.target.effectiveUID)
        let staged = try BelugaUpdateBrokerArtifact.readbackExistingStaged(operationID: operationID,
            target: context.target, expectedBroker: broker, configuration: configuration, stagingParentURL: directory)
        let expectation = try BelugaUpdatePeerIdentity.Expectation(role: .broker,
            canonicalExecutablePath: staged.executableURL.path, effectiveUID: context.target.effectiveUID,
            nativeCDHash: staged.nativeCDHash)
        let binding = try BelugaUpdateIPCProtocol.Binding(operationID: operationID,
            target: context.target, channelNonce: UUID())
        let channel = try BelugaUpdateIPCChannel(takingOwnedSocket: BelugaUpdateIPCEndpoint.connect(
            operationID: operationID, effectiveUID: context.target.effectiveUID, purpose: .readiness, timeout: 30),
            binding: binding, localRole: .menu, expectedPeer: expectation)
        defer { channel.close() }
        try channel.send(.requestReadiness(menuInstanceID: menuInstanceID))
        guard case .readinessChallenge(let menu, let expected, let nonce) = try channel.receive(timeout: 30),
              menu == menuInstanceID, expected == candidate else { throw Failure.unexpectedMessage }
        _ = try BelugaUpdateInstalledArtifact.verify(context: context, expected: candidate)
        guard try store.read(expectedTarget: context.target)?.operation.operationID == operationID else {
            throw Failure.recoveryRequired
        }
        try channel.send(.menuReady(.init(operationID: operationID, target: context.target,
            candidate: candidate, menuInstanceID: menuInstanceID, challengeNonce: nonce, isReady: true)))
        guard try channel.receive(timeout: 30) == .released else { throw Failure.unexpectedMessage }
        try verifyReleased(context: context, expected: candidate)
        try? channel.send(.releaseObserved)
    }

    static func verifyReleased(context: BelugaUpdateRuntimeContext,
                               expected: BelugaUpdateOperation.ArtifactIdentity) throws {
        let lease = try WorldwideHostProcessLock.acquire()
        defer { lease.release() }
        try context.revalidate()
        guard try BelugaUpdateFenceStore(directoryURL: context.fenceDirectoryURL)
            .read(expectedTarget: context.target) == nil else { throw Failure.recoveryRequired }
        _ = try BelugaUpdateInstalledArtifact.verify(context: context, expected: expected)
    }
}
