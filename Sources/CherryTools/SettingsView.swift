import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var cut: FinderCut
    @ObservedObject var clipboard: ClipboardStore
    @ObservedObject var ports: PortStore
    @AppStorage("finder.cutEnabled") private var finderCutEnabled = true
    @AppStorage("finder.playCutSound") private var playCutSound = true
    @AppStorage("ports.showAll") private var showAllPorts = true
    @AppStorage("ports.showUDP") private var showUDP = false
    @AppStorage("general.showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("general.showPortCount") private var showPortCount = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

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
        .frame(width: 480, height: 300)
    }

    private var general: some View {
        Form {
            Toggle("Launch CherryTools at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, value in
                    do {
                        if value { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                    } catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                }
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
            Text("Use Control–Option–Command–M to show or hide the icon. Control–Option–V opens Clipboard even when it is hidden.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var shortcuts: some View {
        Form {
            Toggle("Use ⌘X to cut files in Finder", isOn: $finderCutEnabled)
                .onChange(of: finderCutEnabled) { _, value in
                    if value { cut.enable() }
                    else { cut.disable() }
                }
            Toggle("Play the macOS Tink sound when cutting", isOn: $playCutSound)
                .disabled(!finderCutEnabled)

            if finderCutEnabled {
                if cut.enabled {
                    Label("Finder shortcut is ready", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    HStack {
                        Button("Enable Accessibility access") { cut.requestAccess() }
                        Button("Open System Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
                Text("In Finder, ⌘X marks selected files for moving. ⌘V moves them to the destination.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    private var portSettings: some View {
        Form {
            Toggle("Show system and other users' ports by default", isOn: $showAllPorts)
                .onChange(of: showAllPorts) { _, _ in ports.refreshMenuCount() }
            Toggle("Include UDP sockets by default", isOn: $showUDP)
                .onChange(of: showUDP) { _, _ in ports.refreshMenuCount() }
            Text("Show all includes visible macOS services as well as your apps. Root-owned and protected processes may be unavailable without elevated access.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var clipboardSettings: some View {
        Form {
            LabeledContent("Retention", value: "30 days")
            LabeledContent("Saved items", value: "\(clipboard.clips.count)")
            Button("Clear clipboard history…", action: clearHistory)
            Text("Copied text, files, and images are stored locally on this Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var about: some View {
        Form {
            Section {
                Text("CherryTools")
                    .font(.title2.weight(.semibold))
                HStack(spacing: 5) {
                    Text("Made with")
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
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
        .padding(20)
    }

    private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "Saved items and images will be removed from this Mac."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { clipboard.clear() }
    }
}
