import AppKit
import SwiftUI

struct PortsPanel: View {
    @ObservedObject var store: PortStore
    @AppStorage("ports.showAll") private var showAll = true
    @AppStorage("ports.showUDP") private var showUDP = false
    @State private var search = ""
    @State private var runtimeFilter: PortRuntime = .all
    @State private var expandedID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visible: [PortEntry] {
        PortEntry.filtered(store.entries, showAll: showAll, showUDP: showUDP).filter { entry in
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
                Text("^[\(visible.count) port](inflect: true)")
                    .font(.subheadline.weight(.medium)).foregroundStyle(Palette.secondaryText)
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
            .font(.caption)
            .toggleStyle(.switch)
            .controlSize(.mini)
            .padding(.horizontal, 16)
            .frame(height: 36)

            Divider()
            if let error = store.error {
                ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
            } else if !store.hasScanned {
                ProgressView("Scanning ports…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visible.isEmpty {
                if search.isEmpty {
                    ContentUnavailableView("No Ports Found", systemImage: "network",
                                           description: Text("Try Show all or All types.").foregroundStyle(Palette.secondaryText))
                } else {
                    NoSearchResults(search: search)
                }
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
            PortItem(entry: entry, expanded: expandedID == entry.id, reduceMotion: reduceMotion,
                     onToggle: {
                         withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                             expandedID = expandedID == entry.id ? nil : entry.id
                         }
                     }, onTerminate: { terminate(entry) })
            Divider().padding(.leading, 91)
        }
    }

    private func terminate(_ entry: PortEntry) {
        let alert = NSAlert()
        alert.messageText = "Terminate \(entry.displayName)?"
        alert.informativeText = "CherryTools will ask PID \(entry.pid) to quit. Unsaved work in the process may be lost."
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
    let reduceMotion: Bool
    let onToggle: () -> Void
    let onTerminate: () -> Void
    @State private var isHovering = false

    private var summary: String {
        "CPU \(entry.cpuLabel), memory \(entry.memoryLabel), running \(entry.uptimeLabel), \(entry.exposure.description)"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button(role: .destructive, action: onTerminate) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Palette.destructive)
                .help("Terminate \(entry.displayName)")
                .accessibilityHidden(true) // The row offers Terminate as a named action.
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
                .frame(width: 28, height: 56)

                Button(action: onToggle) {
                    HStack(alignment: .center, spacing: 0) {
                        Text(":\(entry.port, format: .number.grouping(.never))")
                            .font(.callout.monospaced().weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 63, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(entry.displayName)
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                tag(entry.exposure.label).help(entry.exposure.description)
                                if entry.isSystem { tag("SYSTEM") }
                            }
                            HStack(spacing: 8) {
                                Label(entry.sourceName ?? entry.runtime.rawValue,
                                      systemImage: entry.sourceName == nil ? "terminal" : "app")
                                Label(entry.uptimeLabel, systemImage: "clock")
                                Label(entry.cpuLabel, systemImage: "cpu")
                                Label(entry.memoryLabel, systemImage: "memorychip")
                                Label(entry.energyLabel, systemImage: "bolt")
                                    .help("Average power since the previous port scan")
                            }
                            .font(.caption)
                            .foregroundStyle(Palette.secondaryText)
                            .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.secondaryText)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .frame(width: 28, height: 56)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                    .frame(height: 56)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Port \(String(entry.port)), \(entry.displayName), \(entry.user)")
                .accessibilityValue("\(expanded ? "Expanded" : "Collapsed"), \(summary)")
                .accessibilityHint(expanded ? "Hides process details" : "Shows process details")
                .accessibilityAction(named: "Terminate", onTerminate)
            }
            .padding(.trailing, 10)
            .onHover { isHovering = $0 }
            .contextMenu {
                Button("Copy Address", action: copyAddress)
                if entry.directory != nil { Button("Show in Finder", action: showInFinder) }
                Divider()
                Button("Terminate…", role: .destructive, action: onTerminate)
            }

            if expanded {
                VStack(alignment: .leading, spacing: 7) {
                    detail("PID", "\(entry.pid)")
                    detail("Command", entry.command)
                    detail("User", entry.user)
                    if let directory = entry.directory { detail("Directory", directory) }
                    detail("Address", "\(entry.addressLabel) · \(entry.protocolName)")
                    detail("Access", entry.exposure.description)
                    Divider().padding(.vertical, 3)
                    HStack(alignment: .top, spacing: 5) {
                        metric("Port", ":\(entry.port)")
                        metric("Uptime", entry.uptimeLabel)
                        metric("CPU", entry.cpuLabel)
                        metric("Memory", entry.memoryLabel)
                        metric("Power", entry.energyLabel)
                    }
                    .padding(.bottom, 5)
                    HStack(spacing: 8) {
                        Button("Copy Address", action: copyAddress)
                        if entry.directory != nil {
                            Button("Show in Finder", action: showInFinder)
                        }
                        Spacer()
                        Button(role: .destructive, action: onTerminate) {
                            Label("Terminate", systemImage: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.destructiveFill)
                    }
                    .font(.subheadline)
                    .padding(.top, 4)
                }
                .padding(.leading, 92).padding(.trailing, 16).padding(.bottom, 14)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func copyAddress() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.copyableAddress, forType: .string)
    }

    private func showInFinder() {
        guard let directory = entry.directory else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: directory)])
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Palette.secondaryText)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).foregroundStyle(Palette.secondaryText).frame(width: 67, alignment: .leading)
            Text(value).foregroundStyle(.primary)
                .lineLimit(2).truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.caption)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).foregroundStyle(Palette.secondaryText)
                .font(.caption)
            Text(value).foregroundStyle(.primary)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
