import AppKit
import BelugaRenderedAXTestSupport
import ObjectiveC
import XCTest

@MainActor
final class BelugaRenderedAXBridgeTests: XCTestCase {
    private func fixture(_ kind: BelugaRenderedAXFixture) throws -> NSObject {
        XCTAssertTrue(Thread.isMainThread)
        return try XCTUnwrap(BelugaRenderedAXMakeFixture(kind))
    }

    private func assertBridgeError<T>(_ body: @autoclosure () throws -> T,
                                     _ expected: BelugaRenderedAXStatus,
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            guard let failure = error as? HandoffRenderedAXFailure,
                  case .bridge(let actual) = failure else {
                XCTFail("Expected exact bridge refusal, got \(error)", file: file, line: line)
                return
            }
            XCTAssertEqual(actual, expected, file: file, line: line)
        }
    }

    func testWrongReturnSignaturesRefuseBeforeInvocation() throws {
        let object = try fixture(.wrongObjectSignature)
        var value: AnyObject? = "sentinel" as NSString
        XCTAssertEqual(BelugaRenderedAXReadObject(object, .label, &value), .malformedSignature)
        XCTAssertNil(value)
        assertBridgeError(try HandoffRenderedAXNode(object).label(), .malformedSignature)
        XCTAssertEqual(BelugaRenderedAXFixtureTargetCalls(object), 0)

        let wrongValue = try fixture(.wrongStringValue)
        value = "sentinel" as NSString
        XCTAssertEqual(BelugaRenderedAXReadObject(wrongValue, .label, &value), .malformedValue)
        XCTAssertNil(value)
        assertBridgeError(try HandoffRenderedAXNode(wrongValue).label(), .malformedValue)
        XCTAssertEqual(BelugaRenderedAXFixtureTargetCalls(wrongValue), 2)

        for kind in [BelugaRenderedAXFixture.wrongEnabledSignature, .wrongPressSignature] {
            let object = try fixture(kind)
            var output = ObjCBool(true)
            let status = kind == .wrongEnabledSignature
                ? BelugaRenderedAXReadEnabled(object, &output) : BelugaRenderedAXPress(object, &output)
            XCTAssertEqual(status, .malformedSignature)
            XCTAssertFalse(output.boolValue)
            let node = try HandoffRenderedAXNode(object)
            if kind == .wrongEnabledSignature { assertBridgeError(try node.enabled(), .malformedSignature) }
            else { assertBridgeError(try node.press(), .malformedSignature) }
            XCTAssertEqual(BelugaRenderedAXFixtureTargetCalls(object), 0)
        }
    }

    func testDeniedAndMalformedPermissionsRefuseBeforeTargetInvocation() throws {
        for kind in [BelugaRenderedAXFixture.deniedLabel, .deniedTitle,
                     .wrongPermissionReturn, .wrongPermissionArgument] {
            let object = try fixture(kind)
            let property: BelugaRenderedAXProperty = kind == .deniedTitle ? .title : .label
            let expected: BelugaRenderedAXStatus =
                (kind == .deniedLabel || kind == .deniedTitle) ? .deniedSelector : .malformedSignature
            var value: AnyObject? = "sentinel" as NSString
            XCTAssertEqual(BelugaRenderedAXReadObject(object, property, &value), expected)
            XCTAssertNil(value)
            let node = try HandoffRenderedAXNode(object)
            if property == .title { assertBridgeError(try node.title(), expected) }
            else { assertBridgeError(try node.label(), expected) }
            XCTAssertEqual(BelugaRenderedAXFixtureTargetCalls(object), 0)
            XCTAssertEqual(BelugaRenderedAXFixturePermissionCalls(object),
                expected == .deniedSelector ? 2 : 0)
        }
        for kind in [BelugaRenderedAXFixture.deniedEnabled, .deniedPress] {
            let object = try fixture(kind), node = try HandoffRenderedAXNode(object)
            var output = ObjCBool(true)
            let status = kind == .deniedEnabled
                ? BelugaRenderedAXReadEnabled(object, &output) : BelugaRenderedAXPress(object, &output)
            XCTAssertEqual(status, .deniedSelector)
            XCTAssertFalse(output.boolValue)
            if kind == .deniedEnabled { assertBridgeError(try node.enabled(), .deniedSelector) }
            else { assertBridgeError(try node.press(), .deniedSelector) }
            XCTAssertEqual(BelugaRenderedAXFixtureTargetCalls(object), 0)
            XCTAssertEqual(BelugaRenderedAXFixturePermissionCalls(object), 2)
        }
    }

    func testMissingTitleOnlyIsOptionalAndDeclaredNilTitleIsSeparate() throws {
        let object = try fixture(.genuineNo)
        let selector = NSSelectorFromString("accessibilityTitle")
        XCTAssertFalse(object.responds(to: selector))
        XCTAssertNil(class_getInstanceMethod(object_getClass(object), selector))
        var value: AnyObject? = "sentinel" as NSString
        XCTAssertEqual(BelugaRenderedAXReadObject(object, .title, &value), .missingSelector)
        XCTAssertNil(value)
        XCTAssertNil(try HandoffRenderedAXNode(object).title())

        let nilTitle = try fixture(.nilTitle)
        XCTAssertTrue(nilTitle.responds(to: selector))
        XCTAssertNotNil(class_getInstanceMethod(object_getClass(nilTitle), selector))
        value = "sentinel" as NSString
        XCTAssertEqual(BelugaRenderedAXReadObject(nilTitle, .title, &value), .ok)
        XCTAssertNil(value)
        XCTAssertNil(try HandoffRenderedAXNode(nilTitle).title())

        let missing = try fixture(.noMethods), node = try HandoffRenderedAXNode(missing)
        assertBridgeError(try node.enabled(), .missingSelector)
        assertBridgeError(try node.press(), .missingSelector)
        assertBridgeError(try node.role(), .missingSelector)
        assertBridgeError(try node.identifier(), .missingSelector)
        assertBridgeError(try node.label(), .missingSelector)
        assertBridgeError(try node.textValue(), .missingSelector)
        assertBridgeError(try node.children(), .missingSelector)
        XCTAssertEqual(BelugaRenderedAXFixtureTargetCalls(missing), 0)
    }

    func testTextBoundCoversAllPropertiesBeforeOutputAndCountsUTF16() throws {
        let properties: [BelugaRenderedAXProperty] = [.role, .identifier, .label, .title, .value]
        for property in properties {
            for (kind, count, expected) in [
                (BelugaRenderedAXFixture.text4096, 4096, BelugaRenderedAXStatus.ok),
                (.text4097, 4097, .excessText),
                (.emoji4096, 4096, .ok),
                (.emoji4098, 4098, .excessText)
            ] {
                let object = try fixture(kind)
                var value: AnyObject? = "sentinel" as NSString
                XCTAssertEqual(BelugaRenderedAXReadObject(object, property, &value), expected)
                if expected == .ok {
                    XCTAssertEqual((try XCTUnwrap(value as? NSString)).length, count)
                } else {
                    XCTAssertNil(value, "Oversized string must not cross to Swift")
                }
                XCTAssertEqual(BelugaRenderedAXFixtureTargetCalls(object), 1)
            }
        }
        let node = try HandoffRenderedAXNode(fixture(.text4097))
        assertBridgeError(try node.label(), .excessText)
        assertBridgeError(try node.title(), .excessText)
    }

    func testChildrenBoundAndWrongObjectTypeRefuseBeforeOutput() throws {
        for (kind, expected) in [
            (BelugaRenderedAXFixture.children128, BelugaRenderedAXStatus.ok),
            (.children129, .excessChildren),
            (.wrongChildrenValue, .malformedValue)
        ] {
            let object = try fixture(kind), node = try HandoffRenderedAXNode(object)
            var value: AnyObject? = "sentinel" as NSString
            XCTAssertEqual(BelugaRenderedAXReadObject(object, .children, &value), expected)
            if expected == .ok {
                XCTAssertEqual((try XCTUnwrap(value as? NSArray)).count, 128)
                XCTAssertEqual(try node.children().count, 128)
            } else {
                XCTAssertNil(value)
                assertBridgeError(try node.children(), expected)
            }
            XCTAssertEqual(BelugaRenderedAXFixtureTargetCalls(object), 2)
        }
    }

    func testProviderExceptionsAreExplicitForAllThreeEntryPoints() throws {
        let object = try fixture(.throwingLabel), node = try HandoffRenderedAXNode(object)
        var value: AnyObject? = "sentinel" as NSString
        XCTAssertEqual(BelugaRenderedAXReadObject(object, .label, &value), .raisedException)
        XCTAssertNil(value)
        assertBridgeError(try node.label(), .raisedException)
        XCTAssertEqual(BelugaRenderedAXFixtureTargetCalls(object), 2)
        for kind in [BelugaRenderedAXFixture.throwingEnabled, .throwingPress] {
            let object = try fixture(kind), node = try HandoffRenderedAXNode(object)
            var output = ObjCBool(true)
            let status = kind == .throwingEnabled
                ? BelugaRenderedAXReadEnabled(object, &output) : BelugaRenderedAXPress(object, &output)
            XCTAssertEqual(status, .raisedException)
            XCTAssertFalse(output.boolValue)
            if kind == .throwingEnabled { assertBridgeError(try node.enabled(), .raisedException) }
            else { assertBridgeError(try node.press(), .raisedException) }
            XCTAssertEqual(BelugaRenderedAXFixtureTargetCalls(object), 2)
        }
    }

    func testGenuineNoIsSuccessfulNotMissingOrFailed() throws {
        let object = try fixture(.genuineNo), node = try HandoffRenderedAXNode(object)
        var enabled = ObjCBool(true), accepted = ObjCBool(true)
        XCTAssertEqual(BelugaRenderedAXReadEnabled(object, &enabled), .ok)
        XCTAssertFalse(enabled.boolValue)
        XCTAssertEqual(BelugaRenderedAXPress(object, &accepted), .ok)
        XCTAssertFalse(accepted.boolValue)
        XCTAssertFalse(try node.enabled())
        XCTAssertFalse(try node.press())
        XCTAssertEqual(BelugaRenderedAXFixtureTargetCalls(object), 4)
    }

    func testRoleSpecificRequiredTextHonorsDenialAndExactRoleCardinality() throws {
        let identifier = "beluga.render-test-sentinel", expected = "Rendered menu test host"
        let object = try fixture(.staticTextExactValue), node = try HandoffRenderedAXNode(object)
        let title = NSSelectorFromString("accessibilityTitle")
        XCTAssertFalse(object.responds(to: title))
        XCTAssertNil(class_getInstanceMethod(object_getClass(object), title))
        XCTAssertNil(try node.title())
        assertBridgeError(try node.label(), .deniedSelector)
        XCTAssertEqual(BelugaRenderedAXFixtureTargetCalls(object), 0)
        XCTAssertEqual(BelugaRenderedAXFixturePermissionCalls(object), 1)
        XCTAssertTrue(try hasExactRenderedText([node], identifier: identifier, expected: expected))
        XCTAssertEqual(BelugaRenderedAXFixtureTargetCalls(object), 3)
        XCTAssertEqual(BelugaRenderedAXFixturePermissionCalls(object), 4)
        let duplicate = try HandoffRenderedAXNode(fixture(.staticTextExactValue))
        XCTAssertNotEqual(node.identity, duplicate.identity)
        XCTAssertFalse(try hasExactRenderedText([node, duplicate], identifier: identifier, expected: expected))
        XCTAssertFalse(try hasExactRenderedText([], identifier: identifier, expected: expected))
        XCTAssertFalse(try hasExactRenderedText([node], identifier: identifier, expected: nil))

        let deniedObject = try fixture(.staticTextDeniedValue)
        let denied = try HandoffRenderedAXNode(deniedObject)
        assertBridgeError(try hasExactRenderedText([denied], identifier: identifier, expected: expected),
            .deniedSelector)
        // Identifier+role entered; denied required value never enters its getter.
        XCTAssertEqual(BelugaRenderedAXFixtureTargetCalls(deniedObject), 2)
        XCTAssertEqual(BelugaRenderedAXFixturePermissionCalls(deniedObject), 3)

        for kind in [BelugaRenderedAXFixture.staticTextWrongValue, .staticTextWrongRole] {
            let object = try fixture(kind), node = try HandoffRenderedAXNode(object)
            XCTAssertFalse(try hasExactRenderedText([node], identifier: identifier, expected: expected))
            // Wrong role refuses before value; wrong mandatory text is read, never
            // replaced by a permitted alternate field or model-derived value.
            XCTAssertEqual(BelugaRenderedAXFixtureTargetCalls(object), kind == .staticTextWrongRole ? 2 : 3)
            XCTAssertEqual(BelugaRenderedAXFixturePermissionCalls(object), kind == .staticTextWrongRole ? 2 : 3)
        }

        let buttonObject = try fixture(.deniedLabel), button = try HandoffRenderedAXNode(buttonObject)
        assertBridgeError(try exactRenderedButton([button], present: true, enabled: false), .deniedSelector)
        XCTAssertEqual(BelugaRenderedAXFixtureTargetCalls(buttonObject), 2)
        XCTAssertEqual(BelugaRenderedAXFixturePermissionCalls(buttonObject), 3)
    }
}
