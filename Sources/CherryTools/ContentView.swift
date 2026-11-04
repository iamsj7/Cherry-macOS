import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Group {
                switch model.panel {
                case .ports: PortsPanel(store: model.ports)
                case .clipboard: ClipboardPanel(store: model.clipboard)
                case .toolbox: ToolboxPanel(store: model.toolbox)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer
        }
        .frame(width: 466, height: 568)
        .background(Palette.panelBackground)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 27, height: 27)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(model.panel.rawValue)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption).foregroundStyle(Palette.secondaryText)
            }
            Spacer()
            if model.panel == .ports {
                if model.ports.isScanning {
                    ProgressView().controlSize(.small).frame(width: 25, height: 25)
                        .accessibilityLabel("Scanning ports")
                } else {
                    Button { model.ports.refresh() } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                            .frame(width: 25, height: 25)
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh Ports")
                    .accessibilityLabel("Refresh ports")
                }
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 53)
    }

    private var symbol: String {
        switch model.panel {
        case .ports: "network"
        case .clipboard: "doc.on.clipboard"
        case .toolbox: "wrench.and.screwdriver"
        }
    }

    private var subtitle: String {
        switch model.panel {
        case .ports: "Processes listening on this Mac"
        case .clipboard: "Recent copies, kept for 30 days"
        case .toolbox: "Quick fixes for this Mac"
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Picker("Panel", selection: $model.panel) {
                Label("Ports", systemImage: "network").tag(Panel.ports)
                Label("Clipboard", systemImage: "doc.on.clipboard").tag(Panel.clipboard)
                Label("Toolbox", systemImage: "wrench.and.screwdriver").tag(Panel.toolbox)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .fixedSize()
            .onChange(of: model.panel) { _, panel in
                if panel == .ports { model.ports.start() }
                else { model.ports.stop() }
            }
            Spacer()
            Button { AppController.shared?.showSettings() } label: {
                Label("Settings…", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.horizontal, 9)
        .frame(height: 48)
    }
}
