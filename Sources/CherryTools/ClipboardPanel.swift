import AppKit
import SwiftUI

struct ClipboardPanel: View {
    @ObservedObject var store: ClipboardStore
    @State private var search = ""

    private var visible: [Clip] {
        search.isEmpty ? store.clips : store.clips.filter {
            $0.preview.localizedCaseInsensitiveContains(search) ||
            ($0.kind == .text && $0.value.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            NativeSearchField(placeholder: "Search clipboard history", text: $search)
            .frame(height: 29)
            .padding(.horizontal, 14).padding(.top, 11)

            HStack {
                Text("\(visible.count) \(visible.count == 1 ? "item" : "items")")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if !store.clips.isEmpty {
                    Button("Clear history", action: clearHistory)
                        .buttonStyle(.plain).font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16).frame(height: 36)
            Divider()

            if visible.isEmpty {
                ContentUnavailableView("Nothing copied yet", systemImage: "doc.on.clipboard",
                                       description: Text("Text, files, and images stay here for 30 days."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visible) { clip in
                            HStack(spacing: 11) {
                                Image(systemName: symbol(for: clip))
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22)
                                Text(clip.preview)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(2)
                                Spacer()
                                Button { store.restore(clip) } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                .help("Copy again")
                                .accessibilityLabel("Copy again")
                                Button { store.remove(clip) } label: {
                                    Image(systemName: "xmark")
                                }
                                .help("Remove from history")
                                .accessibilityLabel("Remove from history")
                            }
                            .buttonStyle(.borderless)
                            .padding(.horizontal, 16).padding(.vertical, 11)
                            Divider().padding(.leading, 48)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func symbol(for clip: Clip) -> String {
        switch clip.kind {
        case .text: "text.alignleft"
        case .image: "photo"
        case .files: "doc.on.doc"
        }
    }

    private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "Saved items and images will be removed from this Mac."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { store.clear() }
    }
}
