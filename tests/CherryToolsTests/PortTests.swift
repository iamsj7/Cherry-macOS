import Darwin
import XCTest
@testable import CherryTools

final class PortTests: XCTestCase {
    private func entry(pid: Int32 = 1, uid: uid_t? = getuid(), path: String? = "/opt/app", proto: String = "TCP",
                       hosts: [String] = ["127.0.0.1"], port: Int = 3000) -> PortEntry {
        PortEntry(pid: pid, displayName: "app", command: "app", sourceName: nil, executablePath: path, runtime: .node,
                  user: "me", ownerUID: uid, port: port, hosts: hosts, protocolName: proto, memoryBytes: nil,
                  elapsedSeconds: nil, cpuPercent: nil, powerMilliwatts: nil, directory: nil, startToken: nil)
    }

    func testRuntimeDetection() {
        XCTAssertEqual(PortRuntime.detect(command: "node", commandLine: "node /x/node_modules/vite/bin/vite.js"), .vite)
        XCTAssertEqual(PortRuntime.detect(command: "node", commandLine: "next-server (v15)"), .next)
        XCTAssertEqual(PortRuntime.detect(command: "Python", commandLine: "python -m http.server"), .python)
        XCTAssertEqual(PortRuntime.detect(command: "node", commandLine: "node server.js"), .node)
        XCTAssertEqual(PortRuntime.detect(command: "nginx", commandLine: "nginx"), .other)
    }

    func testExposure() {
        XCTAssertEqual(PortExposure.of(hosts: ["127.0.0.1", "::1"]), .local)
        XCTAssertEqual(PortExposure.of(hosts: ["*"]), .network)
        XCTAssertEqual(PortExposure.of(hosts: ["127.0.0.1", "192.168.1.4"]), .network)
    }

    func testAddresses() {
        XCTAssertEqual(entry(hosts: ["*"]).copyableAddress, "localhost:3000")
        XCTAssertEqual(entry(hosts: ["*", "::1"]).copyableAddress, "[::1]:3000")
        XCTAssertEqual(entry(hosts: ["127.0.0.1", "::1"]).addressLabel, "127.0.0.1:3000, [::1]:3000")
    }

    func testUptimeLabels() {
        XCTAssertEqual(PortEntry.uptimeLabel(seconds: nil), "—")
        XCTAssertEqual(PortEntry.uptimeLabel(seconds: 30), "30s")
        XCTAssertEqual(PortEntry.uptimeLabel(seconds: 3_900), "1h 5m")
        XCTAssertEqual(PortEntry.uptimeLabel(seconds: 200_000), "2d")
    }

    func testFiltering() {
        let entries = [entry(), entry(pid: 2, proto: "UDP"), entry(pid: 3, uid: 0), entry(pid: 4, path: "/usr/sbin/x")]
        XCTAssertEqual(PortEntry.filtered(entries, showAll: false, showUDP: false).map(\.pid), [1])
        XCTAssertEqual(PortEntry.filtered(entries, showAll: false, showUDP: true).map(\.pid), [1, 2])
        XCTAssertEqual(PortEntry.filtered(entries, showAll: true, showUDP: false).map(\.pid), [1, 3, 4])
    }

    func testProtectedFolders() {
        XCTAssertTrue(PortScanner.isProtectedFolder("/Users/a/Documents/app", home: "/Users/a"))
        XCTAssertTrue(PortScanner.isProtectedFolder("/Users/a/Desktop", home: "/Users/a"))
        XCTAssertFalse(PortScanner.isProtectedFolder("/Users/a/Documentation", home: "/Users/a"))
        XCTAssertFalse(PortScanner.isProtectedFolder("/Users/a/code/app", home: "/Users/a"))
    }

    func testScanFindsARealListener() throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(descriptor, $0, size) }
        }
        XCTAssertEqual(bound, 0)
        XCTAssertEqual(Darwin.listen(descriptor, 1), 0)
        var actual = sockaddr_in()
        var actualSize = size
        _ = withUnsafeMutablePointer(to: &actual) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &actualSize) }
        }
        let port = Int(UInt16(bigEndian: actual.sin_port))

        let first = PortScanner.scan(memory: .init(), readProtectedFolders: false)
        let found = try XCTUnwrap(first.entries.first { $0.pid == getpid() && $0.port == port })
        XCTAssertEqual(found.hosts, ["127.0.0.1"])
        XCTAssertEqual(found.exposure, .local)
        XCTAssertEqual(found.protocolName, "TCP")
        XCTAssertEqual(found.ownerUID, getuid())
        XCTAssertNotNil(found.memoryBytes)
        XCTAssertNotNil(found.elapsedSeconds)
        XCTAssertFalse(found.command.isEmpty)
        XCTAssertEqual(found.startToken, PortScanner.startToken(for: getpid()))
        XCTAssertNil(found.cpuPercent, "CPU needs two samples")

        Thread.sleep(forTimeInterval: 0.05)
        let second = PortScanner.scan(memory: first.memory, readProtectedFolders: false)
        XCTAssertNotNil(second.entries.first { $0.pid == getpid() && $0.port == port }?.cpuPercent)
    }
}
