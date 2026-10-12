import Foundation

// Independent test-only derivative, frozen before Rust authoring.
// Original owner: MacSystemNowPlayingController.swift lines 265–337 at SHA-256
// 0d09851a9ec69e6417ef89c3c84aa674e37b6e9742457254258307c08f69bddd.
// Exact original excerpt SHA-256:
// 1dbc9faacf1905eee0aba149f9a1669db8565254f436220d39e4db56e850ca5a.
// Only the class name/visibility, test-only seed initializer and read-only
// snapshots are added. All original transition/membership methods are verbatim.
// This model imports no CaptureServer, BelugaCore, C export or production facade.
final class FrozenMediaCommandGateReference: @unchecked Sendable {
    struct Lifecycle: Sendable, Equatable {
        fileprivate let value: UInt64
    }

    struct Authorization: Sendable, Equatable {
        fileprivate let lifecycle: UInt64
        fileprivate let commandEpoch: UInt64
        fileprivate let contextID: String
    }

    struct Snapshot: Sendable, Equatable {
        let lifecycle: UInt64
        let commandEpoch: UInt64
        let isOpen: Bool
        let contextIDs: Set<String>
    }

    struct AuthorizationSnapshot: Sendable, Equatable {
        let lifecycle: UInt64
        let commandEpoch: UInt64
        let contextID: String
    }

    private let lock = NSLock()
    private var lifecycle: UInt64 = 0
    private var commandEpoch: UInt64 = 0
    private var isOpen = false
    private var contextIDs: Set<String> = []

    // A synthetic preimage state allows exact full-UInt64 arithmetic boundaries
    // without billions of transitions. It is not a production-state backdoor.
    init(lifecycle: UInt64 = 0, commandEpoch: UInt64 = 0,
         isOpen: Bool = false, contextIDs: Set<String> = []) {
        self.lifecycle = lifecycle
        self.commandEpoch = commandEpoch
        self.isOpen = isOpen
        self.contextIDs = contextIDs
    }

    var snapshot: Snapshot {
        lock.withLock {
            Snapshot(lifecycle: lifecycle, commandEpoch: commandEpoch,
                     isOpen: isOpen, contextIDs: contextIDs)
        }
    }

    // A readonly value snapshot, including a legal zero-after-wrap token.
    // Obtaining a token does not make lifecycleIsCurrent return true while closed.
    var currentLifecycleToken: Lifecycle {
        lock.withLock { Lifecycle(value: lifecycle) }
    }

    static func lifecycleValue(_ token: Lifecycle) -> UInt64 { token.value }

    static func authorizationSnapshot(_ value: Authorization) -> AuthorizationSnapshot {
        AuthorizationSnapshot(lifecycle: value.lifecycle, commandEpoch: value.commandEpoch,
                              contextID: value.contextID)
    }

    func open() -> Lifecycle {
        lock.withLock {
            lifecycle &+= 1
            commandEpoch &+= 1
            isOpen = true
            contextIDs = []
            return Lifecycle(value: lifecycle)
        }
    }

    func close() {
        lock.withLock {
            lifecycle &+= 1
            commandEpoch &+= 1
            isOpen = false
            contextIDs = []
        }
    }

    func invalidateCommands() {
        lock.withLock { commandEpoch &+= 1 }
    }

    func setContext(_ newContextID: String?) {
        setContexts(newContextID.map { [$0] } ?? [])
    }

    func setContexts(_ values: Set<String>) {
        lock.withLock { contextIDs = values }
    }

    func lifecycleIsCurrent(_ candidate: Lifecycle) -> Bool {
        lock.withLock { isOpen && lifecycle == candidate.value }
    }

    func capture(contextID candidate: String) -> Authorization? {
        lock.withLock {
            guard isOpen, contextIDs.contains(candidate) else { return nil }
            return Authorization(
                lifecycle: lifecycle,
                commandEpoch: commandEpoch,
                contextID: candidate
            )
        }
    }

    func admits(_ authorization: Authorization) -> Bool {
        lock.withLock {
            isOpen
                && lifecycle == authorization.lifecycle
                && commandEpoch == authorization.commandEpoch
                && contextIDs.contains(authorization.contextID)
        }
    }
}
