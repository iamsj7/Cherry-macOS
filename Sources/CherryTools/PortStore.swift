import AppKit
import CProcessMetrics
import Darwin
import Foundation

enum PortRuntime: String, CaseIterable, Identifiable, Sendable {
    case all = "All types", node = "Node", vite = "Vite", next = "Next.js"
    case python = "Python", rails = "Rails", go = "Go", bun = "Bun"
    case deno = "Deno", ruby = "Ruby", java = "Java", other = "Other"

    var id: String { rawValue }

    static func detect(command: String, commandLine: String) -> PortRuntime {
        let executable = command.lowercased()
        let line = commandLine.lowercased()
        if line.contains("/vite/") || line.contains("/vite ") || line.contains("vite.js") || executable == "vite" { return .vite }
        if line.contains("/next/") || line.contains("next-server") || line.contains("next dev") || executable == "next" { return .next }
        if line.contains("/rails") || line.contains(" rails ") || executable == "puma" || executable == "rails" { return .rails }
        if executable == "bun" || line.contains("/bun ") { return .bun }
        if executable == "deno" || line.contains("/deno ") { return .deno }
        if executable.hasPrefix("python") || line.contains("/python") { return .python }
        if executable == "go" || line.contains("/go-build/") { return .go }
        if executable == "node" || line.contains("/node ") { return .node }
        if executable == "ruby" || line.contains("/ruby ") { return .ruby }
        if executable == "java" || line.contains("/java ") { return .java }
        return .other
    }
}

enum PortExposure: Sendable {
    case local, network

    var label: String { self == .local ? "LOCAL" : "NETWORK" }
    var description: String { self == .local ? "Only this Mac can connect" : "Other devices may be able to connect" }

    static func of(hosts: [String]) -> PortExposure {
        hosts.allSatisfy { $0 == "::1" || $0.hasPrefix("127.") } ? .local : .network
    }
}

struct PortEntry: Identifiable, Hashable, Sendable {
    let pid: Int32
    let displayName: String
    let command: String
    let sourceName: String?
    let executablePath: String?
    let runtime: PortRuntime
    let user: String
    let ownerUID: uid_t?
    let port: Int
    let hosts: [String]
    let protocolName: String
    let memoryBytes: UInt64?
    let elapsedSeconds: TimeInterval?
    let cpuPercent: Double?
    let powerMilliwatts: Double?
    let directory: String?
    let startToken: UInt64?

    var id: String { "\(pid)-\(protocolName)-\(port)" }
    var isSystem: Bool { Self.isSystemProcess(ownerUID: ownerUID, executablePath: executablePath) }
    var exposure: PortExposure { .of(hosts: hosts) }
    var addressLabel: String { hosts.map { Self.address(host: $0, port: port) }.joined(separator: ", ") }

    /// A value people can paste into a browser or client.
    var copyableAddress: String {
        let host = hosts.first { $0 != "*" } ?? "localhost"
        return Self.address(host: host, port: port)
    }

    static func address(host: String, port: Int) -> String {
        host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
    }

    static func isSystemProcess(ownerUID: uid_t?, executablePath: String?) -> Bool {
        if let ownerUID, ownerUID != getuid() { return true }
        guard let executablePath else { return false }
        return executablePath.hasPrefix("/System/") ||
            executablePath.hasPrefix("/usr/libexec/") ||
            executablePath.hasPrefix("/usr/sbin/") ||
            executablePath.hasPrefix("/sbin/") ||
            executablePath.contains("/Cryptexes/OS/System/")
    }

    var memoryLabel: String {
        guard let memoryBytes, memoryBytes > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(memoryBytes), countStyle: .memory)
    }
    var cpuLabel: String {
        guard let cpuPercent else { return "—" }
        return (cpuPercent / 100).formatted(.percent.precision(.fractionLength(1)))
    }
    var energyLabel: String {
        guard let powerMilliwatts else { return "—" }
        return Measurement(value: powerMilliwatts, unit: UnitPower.milliwatts)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                    numberFormatStyle: .number.precision(.fractionLength(1))))
    }
    var uptimeLabel: String { Self.uptimeLabel(seconds: elapsedSeconds) }

    static func uptimeLabel(seconds: TimeInterval?) -> String {
        guard let seconds, seconds >= 0 else { return "—" }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = seconds >= 86_400 ? 1 : 2
        formatter.allowedUnits = seconds < 60 ? [.second] : [.day, .hour, .minute]
        return formatter.string(from: seconds) ?? "—"
    }

    static func filtered(_ entries: [PortEntry], showAll: Bool, showUDP: Bool) -> [PortEntry] {
        entries.filter { (showAll || !$0.isSystem) && (showUDP || $0.protocolName == "TCP") }
    }
}

/// Reads sockets and process details directly from the kernel; nothing is spawned.
enum PortScanner {
    struct Sample: Sendable {
        let nanojoules: UInt64
        let cpuNanoseconds: UInt64
        let timestamp: TimeInterval
    }

    struct Memory: Sendable {
        var samples: [Int32: Sample] = [:]
        var projectNames: [String: String] = [:] // An empty name means no manifest was found.
    }

    struct Socket: Sendable {
        let pid: Int32
        let port: Int
        let host: String
        let protocolName: String
    }

    struct Result: Sendable {
        let entries: [PortEntry]
        let error: String?
        let memory: Memory
    }

    static func sockets(includeUDP: Bool) -> [Socket]? {
        var count = 0
        guard let raw = ct_copy_sockets(includeUDP, &count) else { return nil }
        defer { free(raw) }
        return UnsafeBufferPointer(start: raw, count: count).map { socket in
            let host = withUnsafeBytes(of: socket.address) { bytes in
                String(cString: bytes.bindMemory(to: CChar.self).baseAddress!)
            }
            return Socket(pid: socket.pid, port: Int(socket.port), host: host,
                          protocolName: socket.is_udp ? "UDP" : "TCP")
        }
    }

    static func scan(memory previous: Memory, readProtectedFolders: Bool) -> Result {
        guard let sockets = sockets(includeUDP: true) else {
            return Result(entries: [], error: "Could not read the process list.", memory: previous)
        }
        var grouped: [String: (first: Socket, hosts: [String])] = [:]
        for socket in sockets {
            let key = "\(socket.pid)-\(socket.protocolName)-\(socket.port)"
            var group = grouped[key] ?? (socket, [])
            if !group.hosts.contains(socket.host) { group.hosts.append(socket.host) }
            grouped[key] = group
        }

        let now = ProcessInfo.processInfo.systemUptime
        var memory = Memory(samples: [:], projectNames: previous.projectNames)
        var details: [Int32: ProcessDetails] = [:]
        for pid in Set(grouped.values.map(\.first.pid)) {
            let (detail, sample) = processDetails(pid: pid, now: now, previous: previous.samples[pid])
            details[pid] = detail
            memory.samples[pid] = sample
        }

        let entries = grouped.values.map { group -> PortEntry in
            let socket = group.first
            let detail = details[socket.pid] ?? ProcessDetails()
            let runtime = PortRuntime.detect(command: detail.command, commandLine: detail.commandLine)
            let name = displayName(detail: detail, runtime: runtime, memory: &memory,
                                   readProtectedFolders: readProtectedFolders)
            return PortEntry(pid: socket.pid, displayName: name, command: detail.command,
                             sourceName: detail.sourceName, executablePath: detail.path, runtime: runtime,
                             user: detail.user, ownerUID: detail.uid, port: socket.port,
                             hosts: group.hosts.sorted(), protocolName: socket.protocolName,
                             memoryBytes: detail.memoryBytes, elapsedSeconds: detail.elapsedSeconds,
                             cpuPercent: detail.cpuPercent, powerMilliwatts: detail.powerMilliwatts,
                             directory: detail.directory, startToken: detail.startToken)
        }
        return Result(entries: entries.sorted { $0.port == $1.port ? $0.pid < $1.pid : $0.port < $1.port },
                      error: nil, memory: memory)
    }

    static func count(showAll: Bool, showUDP: Bool) -> Int? {
        guard let sockets = sockets(includeUDP: showUDP) else { return nil }
        let unique = Dictionary(sockets.map { ("\($0.pid)-\($0.protocolName)-\($0.port)", $0.pid) },
                                uniquingKeysWith: { first, _ in first })
        if showAll { return unique.count }
        return unique.values.filter { pid in
            var info = ct_process_info()
            let uid = ct_get_process_info(pid, &info) ? info.uid : nil
            return !PortEntry.isSystemProcess(ownerUID: uid, executablePath: path(for: pid))
        }.count
    }

    /// The token identifies one process lifetime, so a reused PID never matches.
    static func startToken(for pid: Int32) -> UInt64? {
        var usage = ct_process_usage()
        return ct_get_process_usage(pid, &usage) ? usage.start_abstime : nil
    }

    private struct ProcessDetails {
        var command = ""
        var commandLine = ""
        var path: String?
        var directory: String?
        var sourceName: String?
        var user = "Unknown"
        var uid: uid_t?
        var memoryBytes: UInt64?
        var elapsedSeconds: TimeInterval?
        var cpuPercent: Double?
        var powerMilliwatts: Double?
        var startToken: UInt64?
    }

    private static func processDetails(pid: Int32, now: TimeInterval, previous: Sample?) -> (ProcessDetails, Sample?) {
        var detail = ProcessDetails()
        var info = ct_process_info()
        if ct_get_process_info(pid, &info) {
            detail.command = string(from: info.name)
            detail.uid = info.uid
            detail.user = userName(for: info.uid) ?? "Unknown"
            if info.start_seconds > 0 {
                detail.elapsedSeconds = Date().timeIntervalSince1970 - TimeInterval(info.start_seconds)
            }
        }
        detail.path = path(for: pid)
        detail.directory = read(pid, 4096, ct_process_directory)
        detail.commandLine = read(pid, 262_144, ct_process_arguments) ?? ""
        detail.sourceName = sourceName(for: pid)

        var usage = ct_process_usage()
        guard ct_get_process_usage(pid, &usage) else { return (detail, nil) }
        detail.memoryBytes = usage.footprint_bytes
        detail.startToken = usage.start_abstime
        let sample = Sample(nanojoules: usage.energy_nj, cpuNanoseconds: usage.cpu_ns, timestamp: now)
        if let previous, now > previous.timestamp {
            let interval = now - previous.timestamp
            if sample.cpuNanoseconds >= previous.cpuNanoseconds {
                detail.cpuPercent = Double(sample.cpuNanoseconds - previous.cpuNanoseconds) / (interval * 10_000_000)
            }
            if sample.nanojoules > 0, sample.nanojoules >= previous.nanojoules {
                detail.powerMilliwatts = Double(sample.nanojoules - previous.nanojoules) / (interval * 1_000_000)
            }
        }
        return (detail, sample)
    }

    private static func path(for pid: Int32) -> String? { read(pid, 4096, ct_process_path) }

    private static func read(_ pid: Int32, _ size: Int,
                             _ reader: (pid_t, UnsafeMutablePointer<CChar>?, Int) -> Int) -> String? {
        var buffer = [CChar](repeating: 0, count: size)
        let length = buffer.withUnsafeMutableBufferPointer { reader(pid, $0.baseAddress, $0.count) }
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func string<T>(from tuple: T) -> String {
        withUnsafeBytes(of: tuple) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
    }

    private static func userName(for uid: uid_t) -> String? {
        var record = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 4096)
        guard getpwuid_r(uid, &record, &buffer, buffer.count, &result) == 0, result != nil else { return nil }
        return String(cString: record.pw_name)
    }

    private static func sourceName(for pid: Int32) -> String? {
        var ancestor = pid
        for _ in 0..<8 {
            guard ancestor > 1 else { break }
            if let name = path(for: ancestor).flatMap(appName(in:)) { return name }
            var info = ct_process_info()
            guard ct_get_process_info(ancestor, &info) else { break }
            ancestor = info.parent_pid
        }
        return nil
    }

    private static func appName(in path: String) -> String? {
        path.split(separator: "/").first { $0.hasSuffix(".app") }.map { String($0.dropLast(4)) }
    }

    static func isProtectedFolder(_ directory: String, home: String = NSHomeDirectory()) -> Bool {
        ["Desktop", "Documents", "Downloads"].contains { folder in
            let root = "\(home)/\(folder)"
            return directory == root || directory.hasPrefix(root + "/")
        }
    }

    private static func displayName(detail: ProcessDetails, runtime: PortRuntime, memory: inout Memory,
                                     readProtectedFolders: Bool) -> String {
        if let directory = detail.directory, directory.contains("/.gradle/daemon/") {
            return "Gradle Daemon \(URL(fileURLWithPath: directory).lastPathComponent)"
        }
        if detail.commandLine.contains("org.gradle.launcher.daemon.bootstrap.GradleDaemon") {
            return "Gradle Daemon"
        }

        if let directory = detail.directory, directory.hasPrefix(NSHomeDirectory()) {
            if readProtectedFolders || !isProtectedFolder(directory),
               let name = projectName(in: directory, memory: &memory) {
                return name
            }
            let folder = URL(fileURLWithPath: directory).lastPathComponent
            let genericFolders: Set<String> = ["bin", "daemon", "Contents", "MacOS", "tmp", "var"]
            let looksLikeVersion = !folder.isEmpty && folder.allSatisfy { $0.isNumber || $0 == "." || $0 == "-" }
            if !genericFolders.contains(folder) && !looksLikeVersion && runtime != .other && runtime != .all {
                return folder
            }
        }

        if runtime == .java, let jarIndex = detail.commandLine.range(of: " -jar "),
           let jar = detail.commandLine[jarIndex.upperBound...].split(separator: " ").first {
            return "\(URL(fileURLWithPath: String(jar)).lastPathComponent) (Java)"
        }
        return detail.path.flatMap(appName(in:)) ?? detail.command
    }

    private static func projectName(in directory: String, memory: inout Memory) -> String? {
        if let cached = memory.projectNames[directory] { return cached.isEmpty ? nil : cached }
        var name = ""
        let manifest = URL(fileURLWithPath: directory).appendingPathComponent("package.json")
        if let data = try? Data(contentsOf: manifest), data.count < 100_000,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let value = json["name"] as? String {
            name = value
        }
        memory.projectNames[directory] = name
        return name.isEmpty ? nil : name
    }
}

@MainActor
final class PortStore: ObservableObject {
    @Published private(set) var entries: [PortEntry] = []
    @Published private(set) var isScanning = false
    @Published private(set) var hasScanned = false
    @Published private(set) var menuPortCount: Int?
    @Published var error: String?
    private var timer: Timer?
    private var menuCountTimer: Timer?
    private var isCounting = false
    private var needsMenuCountRefresh = false
    private var memory = PortScanner.Memory()

    private var showAll: Bool { UserDefaults.standard.object(forKey: "ports.showAll") as? Bool ?? true }
    private var showUDP: Bool { UserDefaults.standard.bool(forKey: "ports.showUDP") }

    func start() {
        // Samples from before the panel closed would average over the closed period.
        memory.samples = [:]
        refresh()
        timer?.invalidate()
        timer = Self.repeating(every: 8, tolerance: 2) { [weak self] in self?.refresh() }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            if self?.timer != nil { self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func setMenuCountEnabled(_ enabled: Bool) {
        menuCountTimer?.invalidate()
        menuCountTimer = nil
        guard enabled else {
            menuPortCount = nil
            needsMenuCountRefresh = false
            return
        }
        menuCountTimer = Self.repeating(every: 30, tolerance: 5) { [weak self] in self?.refreshMenuCount() }
        refreshMenuCount()
    }

    func refreshMenuCount() {
        guard menuCountTimer != nil else { return }
        let showAll = showAll, showUDP = showUDP
        if timer != nil {
            menuPortCount = PortEntry.filtered(entries, showAll: showAll, showUDP: showUDP).count
            return
        }
        guard !isCounting else {
            needsMenuCountRefresh = true
            return
        }
        isCounting = true
        Task {
            let count = await Task.detached(priority: .utility) {
                PortScanner.count(showAll: showAll, showUDP: showUDP)
            }.value
            if menuCountTimer != nil && timer == nil { menuPortCount = count }
            isCounting = false
            if needsMenuCountRefresh {
                needsMenuCountRefresh = false
                refreshMenuCount()
            }
        }
    }

    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        let memory = memory
        let readProtected = UserDefaults.standard.bool(forKey: "ports.readProjectNames")
        Task {
            let result = await Task.detached(priority: .utility) {
                PortScanner.scan(memory: memory, readProtectedFolders: readProtected)
            }.value
            entries = result.entries
            error = result.error
            self.memory = result.memory
            if menuCountTimer != nil {
                menuPortCount = PortEntry.filtered(result.entries, showAll: showAll, showUDP: showUDP).count
            }
            hasScanned = true
            isScanning = false
        }
    }

    /// Clears remembered project names after the folder-access setting changes.
    func resetProjectNames() {
        memory.projectNames = [:]
        if timer != nil { refresh() }
    }

    func terminate(_ entry: PortEntry) -> String? {
        guard entry.pid != getpid() else { return "CherryTools cannot terminate itself from this list." }
        guard PortScanner.startToken(for: entry.pid) == entry.startToken else {
            refresh()
            return "\(entry.displayName) has already quit."
        }
        // A normal quit lets apps save their work; everything else gets SIGTERM.
        let asked = NSRunningApplication(processIdentifier: entry.pid)?.terminate() ?? false
        if !asked, kill(entry.pid, SIGTERM) != 0 {
            return String(cString: strerror(errno))
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.5))
            self?.refresh()
        }
        return nil
    }

    private static func repeating(every interval: TimeInterval, tolerance: TimeInterval,
                                  _ action: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { action() }
        }
        timer.tolerance = tolerance
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
