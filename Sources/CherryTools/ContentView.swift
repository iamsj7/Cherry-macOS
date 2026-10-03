import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Group {
                switch model.panel {
                case .ports: PortsPanel(store: model.ports)
                case .clipboard: ClipboardPanel(store: model.clipboard)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer
        }
        .frame(width: 466, height: 568)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: model.panel == .ports ? "network" : "doc.on.clipboard")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 27, height: 27)

            VStack(alignment: .leading, spacing: 1) {
                Text(model.panel.rawValue)
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            if model.panel == .ports {
                Button { model.ports.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 25, height: 25)
                }
                .buttonStyle(.borderless)
                .help("Refresh ports")
                .accessibilityLabel("Refresh ports")
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 53)
    }

    private var subtitle: String {
        switch model.panel {
        case .ports: "Processes listening on this Mac"
        case .clipboard: "Recent copies, kept for 30 days"
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Picker("Panel", selection: $model.panel) {
                Label("Ports", systemImage: "network").tag(Panel.ports)
                Label("Clipboard", systemImage: "doc.on.clipboard").tag(Panel.clipboard)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .onChange(of: model.panel) { _, panel in
                if panel == .ports { model.ports.start() }
                else { model.ports.stop() }
            }
            Spacer()
            Button {
                AppController.shared?.closePopover()
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            Button("Quit") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 9)
        .frame(height: 48)
    }
}
