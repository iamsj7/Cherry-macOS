import SwiftUI

struct ToolboxPanel: View {
    @ObservedObject var store: ToolboxStore

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ToolRow(title: "Flush DNS Cache",
                        detail: "Clears saved website addresses, which can fix sites that won't load or still show an old address. macOS asks for your password.",
                        systemImage: "arrow.triangle.2.circlepath",
                        actionTitle: "Flush",
                        status: store.dnsStatus,
                        successText: "DNS cache flushed") {
                    Task { await store.flushDNS() }
                }
                Divider().padding(.leading, 54)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct ToolRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let actionTitle: String
    let status: ToolboxStore.Status
    let successText: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Palette.secondaryText)
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold))
                Text(detail)
                    .font(.subheadline).foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                statusLabel
            }
            Spacer(minLength: 8)
            if status == .running {
                ProgressView().controlSize(.small).frame(width: 52)
                    .accessibilityLabel("\(title) in progress")
            } else {
                Button(actionTitle, action: action)
                    .accessibilityLabel(title)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    @ViewBuilder private var statusLabel: some View {
        switch status {
        case .succeeded(let date):
            Label("\(successText) at \(date.formatted(date: .omitted, time: .shortened))",
                  systemImage: "checkmark.circle.fill")
                .font(.subheadline).foregroundStyle(Palette.success)
                .padding(.top, 3)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.subheadline).foregroundStyle(Palette.secondaryText)
                .padding(.top, 3)
        case .idle, .running:
            EmptyView()
        }
    }
}
