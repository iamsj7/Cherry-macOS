import XCTest
@testable import CherryTools

@MainActor
final class ToolboxTests: XCTestCase {
    func testSuccessRunsTheFixedAdminCommand() async {
        let store = ToolboxStore { script in
            XCTAssertTrue(script.contains("/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder"))
            XCTAssertTrue(script.contains("with administrator privileges"))
            return CommandResult(succeeded: true, message: "")
        }
        await store.flushDNS()
        guard case .succeeded = store.dnsStatus else { return XCTFail("Expected success") }
    }

    func testCancellingThePasswordPromptIsNotAnError() async {
        let store = ToolboxStore { _ in CommandResult(succeeded: false, message: "User canceled. (-128)") }
        await store.flushDNS()
        XCTAssertEqual(store.dnsStatus, .idle)
    }

    func testFailureIsShown() async {
        let store = ToolboxStore { _ in CommandResult(succeeded: false, message: "Something failed") }
        await store.flushDNS()
        XCTAssertEqual(store.dnsStatus, .failed("Something failed"))
    }

    func testScriptIsValidAppleScript() throws {
        let process = Process()
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).scpt")
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
        process.arguments = ["-e", ToolboxStore.flushDNSScript, "-o", output.path]
        try process.run()
        process.waitUntilExit()
        try? FileManager.default.removeItem(at: output)
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
