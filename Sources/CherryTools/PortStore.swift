import Darwin
import Foundation
import CProcessMetrics

enum PortRuntime: String, CaseIterable, Identifiable {
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

struct PortEntry: Identifiable, Hashable {
    let pid: Int32
    let displayName: String
    let command: String
    let launchCommand: String
    let sourceName: String?
    let executablePath: String?
    let runtime: PortRuntime
    let user: String
    let ownerUID: uid_t?
    let port: Int
    let address: String
    let protocolName: String
    let memoryKB: Int
    let elapsed: String
    let cpuPercent: Double
    let powerMilliwatts: Double?
    let directory: String?

    var id: String { "\(pid)-\(protocolName)-\(port)" }
    var isSystem: Bool { Self.isSystemProcess(ownerUID: ownerUID, executablePath: executablePath) }
    static func isSystemProcess(ownerUID: uid_t?, executablePath: String?) -> Bool {
        if let ownerUID, ownerUID != getuid() { return true }
        guard let executablePath else { return false }
        return executablePath.hasPrefix("/System/") ||
            executablePath.hasPrefix("/usr/libexec/") ||
            executablePath.hasPrefix("/usr/sbin/") ||
            executablePath.hasPrefix("/sbin/") ||
            executablePath.contains("/Cryptexes/OS/System/")
    }
    var memoryLabel: String { memoryKB > 0 ? "\(memoryKB / 1024) MB" : "—" }
    var cpuLabel: String { String(format: "%.1f%%", cpuPercent) }
    var energyLabel: String {
        guard let powerMilliwatts else { return "—" }
        return String(format: "%.1f mW", powerMilliwatts)
    }
    var uptimeLabel: String {
        guard !elapsed.isEmpty else { return "—" }
        let dayParts = elapsed.split(separator: "-")
        if dayParts.count == 2, let days = Int(dayParts[0]) { return "\(days)d" }
        let parts = elapsed.split(separator: ":").compactMap { Int($0) }
        if parts.count == 3 { return parts[0] > 0 ? "\(parts[0])h \(parts[1])m" : "\(parts[1])m" }
        if parts.count == 2 { return parts[0] > 0 ? "\(parts[0])m" : "\(parts[1])s" }
        return elapsed
    }
}

final class PortStore: ObservableObject {
    private struct EnergySample {
        let nanojoules: UInt64
        let timestamp: TimeInterval
    }

    @Published private(set) var entries: [PortEntry] = []
    @Published private(set) var isScanning = false
    @Published private(set) var menuPortCount: Int?
    @Published var error: String?
    private var timer: Timer?
    private var menuCountTimer: Timer?
    private var isCounting = false
    private var needsMenuCountRefresh = false
    private var energySamples: [Int32: EnergySample] = [:]

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = 2
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
        menuCountTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refreshMenuCount()
        }
        menuCountTimer?.tolerance = 5
        refreshMenuCount()
    }

    func refreshMenuCount() {
        guard menuCountTimer != nil else { return }
        let showAll = UserDefaults.standard.object(forKey: "ports.showAll") as? Bool ?? true
        let showUDP = UserDefaults.standard.bool(forKey: "ports.showUDP")
        if timer != nil {
            menuPortCount = Self.filteredCount(entries, showAll: showAll, showUDP: showUDP)
            return
        }
        guard !isCounting else {
            needsMenuCountRefresh = true
            return
        }
        isCounting = true
        DispatchQueue.global(qos: .utility).async {
            let count = Self.scanMenuCount(showAll: showAll, showUDP: showUDP)
            DispatchQueue.main.async {
                if self.menuCountTimer != nil && self.timer == nil {
                    self.menuPortCount = count
                }
                self.isCounting = false
                if self.needsMenuCountRefresh {
                    self.needsMenuCountRefresh = false
                    self.refreshMenuCount()
                }
            }
        }
    }

    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        let previousSamples = energySamples
        DispatchQueue.global(qos: .utility).async {
            let result = Self.scan(previousSamples: previousSamples)
            DispatchQueue.main.async {
                self.entries = result.entries
                self.error = result.error
                self.energySamples = result.energySamples
                if self.menuCountTimer != nil {
                    let showAll = UserDefaults.standard.object(forKey: "ports.showAll") as? Bool ?? true
                    let showUDP = UserDefaults.standard.bool(forKey: "ports.showUDP")
                    self.menuPortCount = Self.filteredCount(result.entries, showAll: showAll, showUDP: showUDP)
                }
                self.isScanning = false
            }
        }
    }

    func terminate(_ entry: PortEntry) -> String? {
        guard entry.pid != getpid() else { return "CherryTools cannot terminate itself from this list." }
        guard kill(entry.pid, SIGTERM) == 0 else {
            return String(cString: strerror(errno))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.refresh() }
        return nil
    }

    private static func run(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8)
        } catch { return nil }
    }

    private static func scan(previousSamples: [Int32: EnergySample]) ->
        (entries: [PortEntry], error: String?, energySamples: [Int32: EnergySample]) {
        guard let tcp = run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-FpcunPT"]),
              let udp = run("/usr/sbin/lsof", ["-nP", "-iUDP", "-FpcunPT"]) else {
            return ([], "Could not run lsof.", [:])
        }
        let details = processDetails()
        var sockets: [String: (pid: Int32, command: String, uid: uid_t?, port: Int, address: String, proto: String)] = [:]
        for (output, proto) in [(tcp, "TCP"), (udp, "UDP")] {
            var pid: Int32 = 0
            var command = ""
            var ownerUID: uid_t?
            for line in output.split(separator: "\n") {
                guard let type = line.first else { continue }
                let value = String(line.dropFirst())
                switch type {
                case "p":
                    pid = Int32(value) ?? 0
                    ownerUID = nil
                case "c": command = value
                case "u": ownerUID = uid_t(value)
                case "n":
                    guard pid > 0, let port = portNumber(from: value) else { continue }
                    sockets["\(pid)-\(proto)-\(port)"] = (pid, command, ownerUID, port, value, proto)
                default: break
                }
            }
        }
        let directories = workingDirectories(for: Set(sockets.values.map(\.pid)))
        let executablePaths = Dictionary(uniqueKeysWithValues: Set(sockets.values.map(\.pid)).compactMap { pid in
            processPath(for: pid).map { (pid, $0) }
        })
        let sourceNames = Dictionary(uniqueKeysWithValues: Set(sockets.values.map(\.pid)).compactMap { pid in
            sourceName(for: pid, details: details, executablePaths: executablePaths).map { (pid, $0) }
        })
        let now = ProcessInfo.processInfo.systemUptime
        var samples: [Int32: EnergySample] = [:]
        var power: [Int32: Double] = [:]
        for pid in Set(sockets.values.map(\.pid)) {
            guard let nanojoules = energyUsed(by: pid) else { continue }
            samples[pid] = EnergySample(nanojoules: nanojoules, timestamp: now)
            if let old = previousSamples[pid], now > old.timestamp, nanojoules >= old.nanojoules {
                power[pid] = Double(nanojoules - old.nanojoules) / ((now - old.timestamp) * 1_000_000)
            }
        }
        let entries = sockets.values.map { socket -> PortEntry in
            let info = details[socket.pid]
            let directory = directories[socket.pid]
            let runtime = PortRuntime.detect(command: socket.command, commandLine: info?.commandLine ?? "")
            return PortEntry(pid: socket.pid,
                             displayName: displayName(command: socket.command,
                                                      commandLine: info?.commandLine ?? "",
                                                      executablePath: executablePaths[socket.pid],
                                                      directory: directory, runtime: runtime),
                             command: socket.command,
                             launchCommand: info?.commandLine ?? "",
                             sourceName: sourceNames[socket.pid],
                             executablePath: executablePaths[socket.pid],
                             runtime: runtime,
                             user: socket.uid.flatMap { getpwuid($0).map { String(cString: $0.pointee.pw_name) } }
                                 ?? info?.user ?? "Unknown",
                             ownerUID: socket.uid,
                             port: socket.port, address: socket.address, protocolName: socket.proto,
                             memoryKB: info?.memoryKB ?? 0, elapsed: info?.elapsed ?? "",
                             cpuPercent: info?.cpuPercent ?? 0,
                             powerMilliwatts: power[socket.pid], directory: directory)
        }
        return (entries.sorted { $0.port == $1.port ? $0.pid < $1.pid : $0.port < $1.port }, nil, samples)
    }

    private static func filteredCount(_ entries: [PortEntry], showAll: Bool, showUDP: Bool) -> Int {
        entries.filter { (showAll || !$0.isSystem) && (showUDP || $0.protocolName == "TCP") }.count
    }

    private static func scanMenuCount(showAll: Bool, showUDP: Bool) -> Int? {
        guard let tcp = run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpun"]) else {
            return nil
        }
        let udp = showUDP ? run("/usr/sbin/lsof", ["-nP", "-iUDP", "-Fpun"]) : nil
        var sockets: [String: (pid: Int32, uid: uid_t?)] = [:]
        for (output, proto) in [(tcp, "TCP"), (udp ?? "", "UDP")] {
            var pid: Int32 = 0
            var ownerUID: uid_t?
            for line in output.split(separator: "\n") {
                guard let type = line.first else { continue }
                let value = String(line.dropFirst())
                switch type {
                case "p":
                    pid = Int32(value) ?? 0
                    ownerUID = nil
                case "u": ownerUID = uid_t(value)
                case "n":
                    if pid > 0, let port = portNumber(from: value) {
                        sockets["\(pid)-\(proto)-\(port)"] = (pid, ownerUID)
                    }
                default: break
                }
            }
        }
        if showAll { return sockets.count }
        let paths = Dictionary(uniqueKeysWithValues: Set(sockets.values.map(\.pid)).compactMap { pid in
            processPath(for: pid).map { (pid, $0) }
        })
        return sockets.values.filter {
            !PortEntry.isSystemProcess(ownerUID: $0.uid, executablePath: paths[$0.pid])
        }.count
    }

    private static func energyUsed(by pid: Int32) -> UInt64? {
        var nanojoules: UInt64 = 0
        return ct_process_energy_nj(pid, &nanojoules) ? nanojoules : nil
    }

    private static func processPath(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = buffer.withUnsafeMutableBufferPointer { pointer in
            ct_process_path(pid, pointer.baseAddress, pointer.count)
        }
        return length > 0 ? String(cString: buffer) : nil
    }

    private static func portNumber(from address: String) -> Int? {
        let local = address.components(separatedBy: "->")[0]
        guard let last = local.split(separator: ":").last else { return nil }
        return Int(last)
    }

    private static func processDetails() -> [Int32: (ppid: Int32, user: String, memoryKB: Int, cpuPercent: Double, elapsed: String, commandLine: String)] {
        guard let output = run("/bin/ps", ["-ww", "-axo", "pid=,ppid=,user=,rss=,%cpu=,etime=,command="]) else { return [:] }
        var details: [Int32: (ppid: Int32, user: String, memoryKB: Int, cpuPercent: Double, elapsed: String, commandLine: String)] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(whereSeparator: \.isWhitespace)
            if parts.count >= 6, let pid = Int32(parts[0]) {
                details[pid] = (Int32(parts[1]) ?? 0, String(parts[2]), Int(parts[3]) ?? 0,
                                Double(parts[4]) ?? 0, String(parts[5]),
                                parts.dropFirst(6).joined(separator: " "))
            }
        }
        return details
    }

    private static func sourceName(for pid: Int32,
                                   details: [Int32: (ppid: Int32, user: String, memoryKB: Int, cpuPercent: Double, elapsed: String, commandLine: String)],
                                   executablePaths: [Int32: String]) -> String? {
        var ancestor = pid
        for _ in 0..<8 {
            guard ancestor > 1 else { break }
            if let path = executablePaths[ancestor] ?? processPath(for: ancestor),
               let app = path.split(separator: "/").first(where: { $0.hasSuffix(".app") }) {
                return String(app.dropLast(4))
            }
            ancestor = details[ancestor]?.ppid ?? 0
        }
        return nil
    }

    private static func workingDirectories(for pids: Set<Int32>) -> [Int32: String] {
        guard !pids.isEmpty else { return [:] }
        let list = pids.sorted().map(String.init).joined(separator: ",")
        guard let output = run("/usr/sbin/lsof", ["-nP", "-a", "-d", "cwd", "-p", list, "-Fpn"]) else { return [:] }
        var directories: [Int32: String] = [:]
        var pid: Int32 = 0
        for line in output.split(separator: "\n") {
            if line.first == "p" { pid = Int32(line.dropFirst()) ?? 0 }
            if line.first == "n", pid > 0 { directories[pid] = String(line.dropFirst()) }
        }
        return directories
    }

    private static func displayName(command: String, commandLine: String,
                                    executablePath: String?, directory: String?,
                                    runtime: PortRuntime) -> String {
        if let directory, directory.contains("/.gradle/daemon/") {
            let version = URL(fileURLWithPath: directory).lastPathComponent
            return "Gradle Daemon \(version)"
        }
        if commandLine.contains("org.gradle.launcher.daemon.bootstrap.GradleDaemon") {
            return "Gradle Daemon"
        }

        if let directory, directory.hasPrefix(NSHomeDirectory()) {
            let packageURL = URL(fileURLWithPath: directory).appendingPathComponent("package.json")
            if let data = try? Data(contentsOf: packageURL), data.count < 100_000,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let name = json["name"] as? String, !name.isEmpty {
                return name
            }

            let folder = URL(fileURLWithPath: directory).lastPathComponent
            let genericFolders: Set<String> = ["bin", "daemon", "Contents", "MacOS", "tmp", "var"]
            let looksLikeVersion = !folder.isEmpty && folder.allSatisfy { $0.isNumber || $0 == "." || $0 == "-" }
            if !genericFolders.contains(folder) && !looksLikeVersion &&
                [.node, .vite, .next, .python, .rails, .go, .bun, .deno, .ruby, .java].contains(runtime) {
                return folder
            }
        }

        if runtime == .java, let jarIndex = commandLine.range(of: " -jar ") {
            let jar = commandLine[jarIndex.upperBound...].split(separator: " ").first.map(String.init)
            if let jar { return "\(URL(fileURLWithPath: jar).lastPathComponent) (Java)" }
        }
        if let executablePath, let appComponent = executablePath.split(separator: "/")
            .first(where: { $0.hasSuffix(".app") }) {
            return String(appComponent.dropLast(4))
        }
        return command
    }
}
