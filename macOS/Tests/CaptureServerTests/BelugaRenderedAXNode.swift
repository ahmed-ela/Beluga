import AppKit
import BelugaRenderedAXTestSupport

@MainActor
struct HandoffRenderedAXNode {
    let object: NSObject
    var identity: ObjectIdentifier { ObjectIdentifier(object) }

    init(_ raw: Any) throws {
        guard let object = raw as? NSObject else { throw HandoffRenderedAXFailure.unsupportedNode }
        self.object = object
    }

    private func read(_ property: BelugaRenderedAXProperty) throws -> AnyObject? {
        var value: AnyObject?
        let status = BelugaRenderedAXReadObject(object, property, &value)
        if property == .title && status == .missingSelector { return nil }
        guard status == .ok else {
            reportRefusal(status, operation: "object-\(property.rawValue)")
            throw HandoffRenderedAXFailure.bridge(status)
        }
        return value
    }

    private func string(_ property: BelugaRenderedAXProperty) throws -> String? {
        guard let value = try read(property) else { return nil }
        guard let text = value as? String else { throw HandoffRenderedAXFailure.malformedValue }
        return text
    }

    func identifier() throws -> String? { try string(.identifier) }
    func label() throws -> String? { try string(.label) }
    func title() throws -> String? { try string(.title) }
    func textValue() throws -> String? { try string(.value) }
    func role() throws -> NSAccessibility.Role {
        guard let role = try string(.role) else { throw HandoffRenderedAXFailure.malformedValue }
        return NSAccessibility.Role(rawValue: role)
    }

    func enabled() throws -> Bool {
        var enabled = ObjCBool(false)
        let status = BelugaRenderedAXReadEnabled(object, &enabled)
        guard status == .ok else {
            reportRefusal(status, operation: "enabled")
            throw HandoffRenderedAXFailure.bridge(status)
        }
        return enabled.boolValue
    }

    func children() throws -> [Any] {
        guard let raw = try read(.children) else { return [] }
        guard let children = raw as? [Any], children.count <= 128 else {
            throw HandoffRenderedAXFailure.malformedValue
        }
        return children
    }

    func hasExactText(_ expected: String, includeValue: Bool) throws -> Bool {
        // AppKit's role-specific contracts require value for static text and label
        // for buttons. There is no alternate-field fallback or denied-read coercion.
        // The caller must first establish the exact role, identifier and cardinality.
        let text = includeValue ? try textValue() : try label()
        return text == expected
    }

    func press() throws -> Bool {
        var accepted = ObjCBool(false)
        let status = BelugaRenderedAXPress(object, &accepted)
        guard status == .ok else {
            reportRefusal(status, operation: "press")
            throw HandoffRenderedAXFailure.bridge(status)
        }
        // Genuine public BOOL acknowledgment, not evidence of command effect.
        // Existing model admission/entry/exact target/count checks stay mandatory.
        return accepted.boolValue
    }

    private func reportRefusal(_ status: BelugaRenderedAXStatus, operation: String) {
        print("RENDERED_MENU_AX_REFUSAL operation=\(operation) status=\(status.rawValue) class=\(NSStringFromClass(type(of: object)))")
    }
}

@MainActor
func renderedAXNodes(_ root: NSView) throws -> [HandoffRenderedAXNode] {
    var pending: [Any] = [root]
    var seen = Set<ObjectIdentifier>()
    var result: [HandoffRenderedAXNode] = []
    while let raw = pending.popLast() {
        let node = try HandoffRenderedAXNode(raw)
        guard seen.insert(node.identity).inserted else { continue }
        guard seen.count <= 128 else { throw HandoffRenderedAXFailure.excessNodes }
        result.append(node)
        let children = try node.children()
        guard children.count <= 128, pending.count <= 128 - children.count else {
            throw HandoffRenderedAXFailure.excessNodes
        }
        pending.append(contentsOf: children)
    }
    return result
}

// Existing bounded polling uses these SAME real nodes. Nonmatching valid state
// retries; unsupported/denied/malformed/signature/bounds refusal does NOT retry.
@MainActor
func exactRenderedButton(_ nodes: [HandoffRenderedAXNode],
                                 present: Bool, enabled: Bool) throws -> HandoffRenderedAXNode? {
    let matches = try nodes.filter { try $0.identifier() == "beluga.move-media-to-phone" }
    if !present {
        guard matches.isEmpty else { throw HandoffRenderedAXFailure.unexpectedState }
        return nil
    }
    guard matches.count == 1, let button = matches.first,
          try button.role() == .button,
          try button.hasExactText("Move media to phone", includeValue: false),
          try button.enabled() == enabled else { throw HandoffRenderedAXFailure.unexpectedState }
    return button
}

@MainActor
func hasExactRenderedText(_ nodes: [HandoffRenderedAXNode],
                                  identifier: String, expected: String?) throws -> Bool {
    let matches = try nodes.filter { try $0.identifier() == identifier }
    guard let expected else { return matches.isEmpty }
    guard matches.count == 1, let text = matches.first, try text.role() == .staticText else { return false }
    return try text.hasExactText(expected, includeValue: true)
}

enum HandoffRenderedAXFailure: Error {
    case unsupportedNode, malformedValue, excessNodes, unexpectedState
    case bridge(BelugaRenderedAXStatus)
}
