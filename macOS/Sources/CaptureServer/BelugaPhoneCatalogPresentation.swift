import Foundation

/// The menu receives labels/IDs and a stale-safe action ticket, never trust records or keys.
struct BelugaPairedPhonePresentation: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let needsPairingRecovery: Bool

    init(id: UUID, name: String?, needsPairingRecovery: Bool) {
        self.id = id
        self.name = Self.safeName(name ?? "")
        self.needsPairingRecovery = needsPairingRecovery
    }

    var label: String { "\(name) · \(id.uuidString.suffix(6))" }

    static func safeName(_ input: String) -> String {
        var scalars = String.UnicodeScalarView()
        var byteCount = 0
        for scalar in input.unicodeScalars {
            let normalized: Unicode.Scalar
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator: normalized = " "
            default: normalized = scalar
            }
            let size = normalized.utf8.count
            guard byteCount + size <= 256 else { break }
            byteCount += size
            scalars.append(normalized)
        }
        let flattened = String(scalars)
        let bounded = String(flattened.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(64))
        return bounded.isEmpty ? "Phone" : bounded
    }
}

struct BelugaPhoneCatalogPresentation: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let items: [BelugaPairedPhonePresentation]
    let selectedPhoneID: UUID?
    let action: WorldwidePhoneCatalogAction?
    let canAddPhone: Bool

    static let unavailable = Self(items: [], selectedPhoneID: nil, action: nil, canAddPhone: false)
    var description: String { "Beluga phone catalog: \(items.count) saved phones" }
    var debugDescription: String { description }
}

enum BelugaPhoneCatalogCommand: Sendable, Equatable {
    case pairAnother
    case select(UUID?)
    case forget(UUID)
}

struct BelugaPhoneCatalogCommands: Sendable {
    let perform: @Sendable (BelugaPhoneCatalogCommand, WorldwidePhoneCatalogAction) async throws -> Void

    static func owned(by coordinator: WorldwideHostCoordinator) -> Self {
        Self { [weak coordinator] command, ticket in
            guard let coordinator else { throw WorldwidePhoneCatalogRuntimeError.ownerNotAuthorized }
            switch command {
            case .pairAnother: _ = try await coordinator.pairAnotherPhone(action: ticket)
            case .select(let id): try await coordinator.selectPhone(id, action: ticket)
            case .forget(let id): try await coordinator.forgetPhone(id, action: ticket)
            }
        }
    }
}
