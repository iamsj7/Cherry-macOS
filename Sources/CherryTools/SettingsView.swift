import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var cut: FinderCut
    @ObservedObject var clipboard: ClipboardStore
    @ObservedObject var ports: PortStore
    @AppStorage("finder.cutEnabled") private var finderCutEnabled = true
    @AppStorage("finder.playCutSound") private var playCutSound = true
    @AppStorage("ports.showAll") private var showAllPorts = true
    @AppStorage("ports.showUDP") private var showUDP = false
    @AppStorage("ports.readProjectNames") private var readProjectNames = false
    @AppStorage("general.showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("general.showPortCount") private var showPortCount = false
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "gearshape") }
            shortcuts
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            portSettings
                .tabItem { Label("Ports", systemImage: "network") }
            clipboardSettings
                .tabItem { Label("Clipboard", systemImage: "doc.on.clipboard") }
            about
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 500, height: 430)
        .onAppear(perform: refreshSystemState)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshSystemState()
        }
    }

    private var launchAtLogin: Binding<Bool> {
        Binding {
            loginStatus == .enabled || loginStatus == .requiresApproval
        } set: { enabled in
            do {
                if enabled { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
                loginError = nil
            } catch {
                loginError = error.localizedDescription
            }
            loginStatus = SMAppService.mainApp.status
        }
    }

    private var general: some View {
        Form {
            Section {
                Toggle("Launch CherryTools at login", isOn: launchAtLogin)
                if loginStatus == .requiresApproval {
                    LabeledContent("Allow CherryTools in Login Items to finish turning this on.") {
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    }
                    .font(.caption)
                }
                if let loginError {
                    Label(loginError, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(Palette.secondaryText)
                }
            }
            Section {
                Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
                    .onChange(of: showMenuBarIcon) { _, visible in
                        if AppController.shared?.setMenuBarIconVisible(visible) == false {
                            showMenuBarIcon = true
                        }
                    }
                Toggle("Show port count beside menu bar icon", isOn: $showPortCount)
                    .disabled(!showMenuBarIcon)
                    .onChange(of: showPortCount) { _, _ in
                        AppController.shared?.updateMenuPortCount()
                    }
            } footer: {
                Text("Control–Option–Command–M shows or hides the icon. Control–Option–V opens Clipboard, and opening CherryTools again shows the panel, even when the icon is hidden.")
                    .font(.caption).foregroundStyle(Palette.secondaryText)
            }
            if !model.unavailableShortcuts.isEmpty {
                Section {
                    Label("Another app is using \(model.unavailableShortcuts.formatted(.list(type: .and))).",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(Palette.secondaryText)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var shortcuts: some View {
        Form {
            Section {
                Toggle("Use ⌘X to cut files in Finder", isOn: $finderCutEnabled)
                    .onChange(of: finderCutEnabled) { _, _ in cut.synchronize() }
                Toggle("Play the macOS Tink sound when cutting", isOn: $playCutSound)
                    .disabled(!finderCutEnabled)

                if finderCutEnabled {
                    if cut.enabled {
                        Label("Finder shortcut is ready", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Palette.success)
                    } else {
                        HStack {
                            Button("Enable Accessibility Access") { cut.requestAccess() }
                            Button("Open System Settings") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                            }
                        }
                    }
                }
            } footer: {
                Text("In Finder, ⌘X marks selected files for moving and ⌘V moves them. Text fields such as rename and search keep normal Cut and Paste. You can also right-click in Finder and choose Cut with CherryTools, then right-click a folder and choose Move Cut Files Here.")
                    .font(.caption).foregroundStyle(Palette.secondaryText)
            }
        }
        .formStyle(.grouped)
    }

    private var portSettings: some View {
        Form {
            Section {
                Toggle("Show system and other users' ports", isOn: $showAllPorts)
                    .onChange(of: showAllPorts) { _, _ in ports.refreshMenuCount() }
                Toggle("Include UDP sockets", isOn: $showUDP)
                    .onChange(of: showUDP) { _, _ in ports.refreshMenuCount() }
            } footer: {
                Text("Processes owned by other users and protected processes may not be visible.")
                    .font(.caption).foregroundStyle(Palette.secondaryText)
            }
            Section {
                Toggle("Read project names in Desktop, Documents, and Downloads", isOn: $readProjectNames)
                    .onChange(of: readProjectNames) { _, _ in ports.resetProjectNames() }
            } footer: {
                Text("When this is off, those projects show their folder name. Turning it on can make macOS ask for folder access.")
                    .font(.caption).foregroundStyle(Palette.secondaryText)
            }
        }
        .formStyle(.grouped)
    }

    private var clipboardSettings: some View {
        Form {
            Section {
                Toggle("Save clipboard history", isOn: Binding(get: { clipboard.isEnabled }, set: { clipboard.setEnabled($0) }))
                Toggle("Pause saving", isOn: Binding(get: { clipboard.isPaused }, set: { clipboard.setPaused($0) }))
                    .disabled(!clipboard.isEnabled)
                LabeledContent("Retention", value: "30 days")
                LabeledContent("Saved items", value: clipboard.clips.count.formatted())
                Button("Clear History…") { ClipboardAlerts.confirmClear(clipboard) }
                    .disabled(clipboard.clips.isEmpty)
            } footer: {
                Text("History stays on this Mac and isn't included in Time Machine backups. Items that apps mark as private, such as passwords, are never saved.")
                    .font(.caption).foregroundStyle(Palette.secondaryText)
            }
            Section("Never Save From") {
                ForEach(clipboard.excludedApps, id: \.self) { bundleID in
                    LabeledContent(appName(for: bundleID)) {
                        Button("Remove") { clipboard.include(app: bundleID) }
                            .controlSize(.small)
                    }
                }
                Button("Add App…", action: addExcludedApp)
            }
        }
        .formStyle(.grouped)
    }

    private var about: some View {
        Form {
            Section {
                Text("CherryTools")
                    .font(.title2.weight(.semibold))
                HStack(spacing: 5) {
                    Text("Made with")
                    Image(systemName: "heart.fill")
                        .foregroundStyle(Palette.destructive)
                        .accessibilityLabel("love")
                    Text("in Muscat")
                }
                LabeledContent("Developer credits", value: "Shaik Jaleel")
            }
            Section("Version") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")
            }
        }
        .formStyle(.grouped)
    }

    private func refreshSystemState() {
        loginStatus = SMAppService.mainApp.status
        clipboard.refreshAccess()
        cut.synchronize()
    }

    private func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return ClipboardPolicy.knownAppNames[bundleID] ?? bundleID
        }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        clipboard.exclude(app: bundleID)
    }
}
