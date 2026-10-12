import Darwin
import Foundation
import XCTest
@testable import BelugaUpdateCore

final class BelugaUpdateBrokerLaunchTests: XCTestCase {
    func testExactArgumentsRoundTripWithoutShellInterpolation() throws {
        let target = try BelugaUpdateOperation.Target(canonicalPath: "/Applications/A space; $(not a command).app",
                                                     effectiveUID: Darwin.geteuid())
        let launch = try BelugaUpdateBrokerLaunch(operationID: UUID(), target: target)
        XCTAssertEqual(try BelugaUpdateBrokerLaunch(arguments: ["BelugaUpdater"] + launch.arguments), launch)
        XCTAssertEqual(launch.arguments.count, 4)
    }

    func testMissingExtraAliasedAndInvalidArgumentsFailClosed() throws {
        let id = UUID().uuidString
        for arguments in [[], ["broker", "--operation", id],
                          ["broker", "--operation", id, "--target", "/Applications/A.app", "--install"],
                          ["broker", "--operation", id.lowercased(), "--target", "/Applications/A.app"],
                          ["broker", "--operation", id, "--target", "/Applications/../A.app"],
                          ["broker", "--operation", id, "--target", "/Applications/A.app/"],
                          ["broker", "--operation", "00000000-0000-0000-0000-000000000000", "--target", "/A.app"]] {
            XCTAssertThrowsError(try BelugaUpdateBrokerLaunch(arguments: arguments))
        }
    }
}
