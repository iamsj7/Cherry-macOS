import Foundation

struct CommandResult: Sendable {
    let succeeded: Bool
    let message: String
}

/// One-click Mac maintenance actions. Add new tools here and in ToolboxPanel.
@MainActor
final class ToolboxStore: ObservableObject {
    enum Status: Equatable {
        case idle, running, succeeded(Date), failed(String)
    }

    typealias Runner = @Sendable (String) async -> CommandResult

    /// A fixed command with no outside input. macOS asks for an administrator password first.
    static let flushDNSScript = """
    do shell script "/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder" \
    with prompt "CherryTools needs your password to flush the DNS cache." with administrator privileges
    """

    @Published private(set) var dnsStatus = Status.idle
    private let runner: Runner

    init(runner: @escaping Runner = ToolboxStore.runAppleScript) { self.runner = runner }

    func flushDNS() async {
        guard dnsStatus != .running else { return }
        dnsStatus = .running
        let result = await runner(Self.flushDNSScript)
        if result.succeeded {
            dnsStatus = .succeeded(Date())
        } else if result.message.contains("-128") { // The password prompt was cancelled.
            dnsStatus = .idle
        } else {
            dnsStatus = .failed(result.message.isEmpty ? "The DNS cache could not be flushed." : result.message)
        }
    }

    nonisolated static func runAppleScript(_ script: String) async -> CommandResult {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            let errors = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = errors
            do {
                try process.run()
            } catch {
                return CommandResult(succeeded: false, message: error.localizedDescription)
            }
            let data = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return CommandResult(succeeded: process.terminationStatus == 0, message: message)
        }.value
    }
}
