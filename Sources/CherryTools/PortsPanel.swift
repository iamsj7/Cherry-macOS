import AppKit
import SwiftUI

struct PortsPanel: View {
    @ObservedObject var store: PortStore
    @AppStorage("ports.showAll") private var showAll = true
    @AppStorage("ports.showUDP") private var showUDP = false
    @State private var search = ""
    @State private var runtimeFilter: PortRuntime = .all
    @State private var expandedID: String?

    private var visible: [PortEntry] {
        store.entries.filter { entry in
            (showAll || !entry.isSystem) && (showUDP || entry.protocolName == "TCP") &&
            (runtimeFilter == .all || entry.runtime == runtimeFilter) &&
            (search.isEmpty || "\(entry.port) \(entry.displayName) \(entry.command) \(entry.runtime.rawValue) \(entry.user) \(entry.pid) \(entry.directory ?? "")"
                .localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            NativeSearchField(placeholder: "Search ports or processes", text: $search)
            .frame(height: 29)
            .padding(.horizontal, 14).padding(.top, 11)

            HStack(spacing: 13) {
                Text("\(visible.count) \(visible.count == 1 ? "port" : "ports")")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Picker("Type", selection: $runtimeFilter) {
                    ForEach(PortRuntime.allCases) { runtime in
                        Text(runtime.rawValue).tag(runtime)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 105)
                Toggle("UDP", isOn: $showUDP)
                    .onChange(of: showUDP) { _, _ in store.refreshMenuCount() }
                Toggle("Show all", isOn: $showAll)
                    .onChange(of: showAll) { _, _ in store.refreshMenuCount() }
            }
            .font(.system(size: 10))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .padding(.horizontal, 16)
            .frame(height: 36)

            Divider()
            if let error = store.error {
                ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
            } else if visible.isEmpty {
                ContentUnavailableView("No ports found", systemImage: "network",
                                       description: Text("Try Show all or change your search."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visible) { entry in portRow(entry) }
                    }
                }
                .scrollIndicators(.visible)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func portRow(_ entry: PortEntry) -> some View {
        VStack(spacing: 0) {
            PortItem(entry: entry, expanded: expandedID == entry.id,
                     onToggle: {
                         withAnimation(.easeInOut(duration: 0.16)) {
                             expandedID = expandedID == entry.id ? nil : entry.id
                         }
                     }, onTerminate: { terminate(entry) })
            Divider().padding(.leading, 91)
        }
    }

    private func terminate(_ entry: PortEntry) {
        let alert = NSAlert()
        alert.messageText = "Terminate \(entry.displayName)?"
        alert.informativeText = "This sends SIGTERM to PID \(entry.pid). Unsaved work in the process may be lost."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Terminate")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if let error = store.terminate(entry) {
            let failure = NSAlert()
            failure.messageText = "Could not terminate process"
            failure.informativeText = error
            failure.runModal()
        }
    }
}

private struct PortItem: View {
    let entry: PortEntry
    let expanded: Bool
    let onToggle: () -> Void
    let onTerminate: () -> Void
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button(role: .destructive, action: onTerminate) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help("Terminate \(entry.displayName)")
                .accessibilityLabel("Terminate \(entry.displayName)")
                .accessibilityHidden(!isHovering)
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
                .frame(width: 28, height: 56)

                Button(action: onToggle) {
                    HStack(alignment: .center, spacing: 0) {
                    Text(":\(entry.port)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 63, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(entry.displayName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if entry.isSystem {
                                Text("SYSTEM")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: 8) {
                            Label(entry.sourceName ?? entry.runtime.rawValue,
                                  systemImage: entry.sourceName == nil ? "terminal" : "app")
                            Label(entry.uptimeLabel, systemImage: "clock")
                            Label(entry.cpuLabel, systemImage: "cpu")
                            Label(entry.memoryLabel, systemImage: "memorychip")
                            Label(entry.energyLabel, systemImage: "bolt")
                                .help("Measured power during the last port scan interval")
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    }
                    .contentShape(Rectangle())
                    .padding(.trailing, 4)
                    .frame(height: 56)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Port \(entry.port), \(entry.displayName), \(entry.user)")
                .accessibilityHint(expanded ? "Collapse process details" : "Expand process details")

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 28, height: 56)
            }
            .padding(.trailing, 10)
            .onHover { isHovering = $0 }

            if expanded {
                VStack(alignment: .leading, spacing: 7) {
                    detail("PID", "\(entry.pid)")
                    detail("Command", entry.command)
                    detail("User", entry.user)
                    if let directory = entry.directory { detail("Directory", directory) }
                    detail("Address", "\(entry.address) · \(entry.protocolName)")
                    Divider().padding(.vertical, 3)
                    HStack(alignment: .top, spacing: 5) {
                        metric("Port", ":\(entry.port)")
                        metric("Uptime", entry.uptimeLabel)
                        metric("CPU", entry.cpuLabel)
                        metric("Memory", entry.memoryLabel)
                        metric("Energy", entry.energyLabel)
                    }
                    .padding(.bottom, 5)
                    HStack(spacing: 8) {
                        Button("Copy address") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.address, forType: .string)
                        }
                        .buttonStyle(.borderless)
                        if let directory = entry.directory {
                            Button("Show in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: directory)) }
                                .buttonStyle(.borderless)
                        }
                        Spacer()
                        Button(role: .destructive, action: onTerminate) {
                            Label("Terminate", systemImage: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                    .font(.system(size: 11))
                    .padding(.top, 4)
                }
                .padding(.leading, 92).padding(.trailing, 16).padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).foregroundStyle(.tertiary).frame(width: 67, alignment: .leading)
            Text(value).foregroundStyle(.secondary)
                .lineLimit(2).truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.system(size: 10))
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).foregroundStyle(.tertiary)
                .font(.system(size: 9))
            Text(value).foregroundStyle(.secondary)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
