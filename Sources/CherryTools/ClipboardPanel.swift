import AppKit
import ImageIO
import SwiftUI

struct ClipboardPanel: View {
    @ObservedObject var store: ClipboardStore
    @State private var search = ""
    @State private var selectedID: UUID?
    @State private var failedID: UUID?

    private var visible: [Clip] {
        search.isEmpty ? store.clips : store.clips.filter {
            $0.preview.localizedCaseInsensitiveContains(search) ||
            ($0.kind == .text && $0.value.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        if store.isEnabled {
            history
        } else {
            ContentUnavailableView {
                Label("Clipboard History Is Off", systemImage: "doc.on.clipboard")
            } description: {
                Text("Turn it on to keep text and images you copy on this Mac for 30 days. Passwords marked as private are never saved.")
                    .foregroundStyle(Palette.secondaryText)
            } actions: {
                Button("Turn On Clipboard History") { store.setEnabled(true) }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var history: some View {
        VStack(spacing: 0) {
            NativeSearchField(placeholder: "Search clipboard history", text: $search,
                              onMove: moveSelection, onSubmit: chooseSelection)
            .frame(height: 29)
            .padding(.horizontal, 14).padding(.top, 11)

            HStack {
                Text("^[\(visible.count) item](inflect: true)")
                    .font(.subheadline.weight(.medium)).foregroundStyle(Palette.secondaryText)
                Spacer()
                Button(store.isPaused ? "Resume" : "Pause") { store.setPaused(!store.isPaused) }
                    .controlSize(.small)
                if !store.clips.isEmpty {
                    Button("Clear History…") { ClipboardAlerts.confirmClear(store) }
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 16).frame(height: 36)
            Divider()

            if store.isAccessDenied {
                notice("Clipboard access is off for CherryTools. Allow it in System Settings → Privacy & Security.",
                       systemImage: "exclamationmark.triangle")
            } else if store.isPaused {
                notice("Paused. New copies aren't saved.", systemImage: "pause.circle")
            }

            if visible.isEmpty {
                if search.isEmpty {
                    ContentUnavailableView("Nothing Copied Yet", systemImage: "doc.on.clipboard",
                                           description: Text("Text and images stay here for 30 days. Files are saved as links to their current location.")
                                               .foregroundStyle(Palette.secondaryText))
                } else {
                    NoSearchResults(search: search)
                }
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: search) { _, _ in selectedID = visible.first?.id }
        .onAppear { store.refreshAccess() }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visible) { clip in
                        ClipRow(store: store, clip: clip,
                                selected: clip.id == (selectedID ?? visible.first?.id),
                                failed: clip.id == failedID,
                                onChoose: { choose(clip) })
                        .id(clip.id)
                        Divider().padding(.leading, 48)
                    }
                }
            }
            .onChange(of: selectedID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    private func notice(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 0) {
            Label(text, systemImage: systemImage)
                .font(.subheadline).foregroundStyle(Palette.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 8)
            Divider()
        }
    }

    private func moveSelection(_ delta: Int) {
        let clips = visible
        guard !clips.isEmpty else { return }
        let current = clips.firstIndex { $0.id == selectedID } ?? 0
        selectedID = clips[min(max(current + delta, 0), clips.count - 1)].id
    }

    private func chooseSelection() {
        let clips = visible
        if let clip = clips.first(where: { $0.id == selectedID }) ?? clips.first { choose(clip) }
    }

    private func choose(_ clip: Clip) {
        if store.restore(clip) {
            failedID = nil
            AppController.shared?.closePopoverAndReturn()
        } else {
            failedID = clip.id
            NSSound.beep()
        }
    }
}

private struct ClipRow: View {
    @ObservedObject var store: ClipboardStore
    let clip: Clip
    let selected: Bool
    let failed: Bool
    let onChoose: () -> Void
    @State private var isHovering = false

    private var kindLabel: String {
        switch clip.kind {
        case .text: "Text"
        case .image: "Image"
        case .files: "Files"
        }
    }

    private var symbol: String {
        switch clip.kind {
        case .text: "text.alignleft"
        case .image: "photo"
        case .files: "doc.on.doc"
        }
    }

    private var isMissing: Bool { store.filesAreMissing(clip) }

    var body: some View {
        HStack(spacing: 11) {
            Button(action: onChoose) {
                HStack(spacing: 11) {
                    ClipThumbnail(url: store.imageURL(for: clip), symbol: symbol)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(clip.preview)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        if failed || isMissing {
                            Text(isMissing ? "File no longer available" : "Couldn't copy this item")
                                .font(.caption).foregroundStyle(Palette.secondaryText)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(kindLabel): \(clip.preview)")
            .accessibilityHint("Copies this item and closes the panel")
            .accessibilityAddTraits(selected ? .isSelected : [])

            Button { store.remove(clip) } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(Palette.secondaryText)
            }
            .buttonStyle(.borderless)
            .help("Remove from History")
            .accessibilityLabel("Remove \(clip.preview) from history")
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(selected ? Color.accentColor.opacity(0.16) : isHovering ? Color.primary.opacity(0.06) : .clear)
        .overlay(alignment: .leading) {
            // A tint alone is too faint to show selection, so a solid bar marks it.
            if selected { Rectangle().fill(.primary).frame(width: 3) }
        }
        .onHover { isHovering = $0 }
    }
}

private struct ClipThumbnail: View {
    let url: URL?
    let symbol: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable().scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(.rect(cornerRadius: 4))
            } else {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
        .task(id: url) {
            guard let url else { return }
            image = await Task.detached(priority: .utility) { () -> NSImage? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                               kCGImageSourceCreateThumbnailWithTransform: true,
                               kCGImageSourceThumbnailMaxPixelSize: 96] as CFDictionary
                guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
                return NSImage(cgImage: thumbnail, size: .zero)
            }.value
        }
    }
}

struct NoSearchResults: View {
    let search: String

    var body: some View {
        ContentUnavailableView("No Results", systemImage: "magnifyingglass",
                               description: Text("Nothing matches “\(search)”.").foregroundStyle(Palette.secondaryText))
    }
}

@MainActor
enum ClipboardAlerts {
    static func confirmClear(_ store: ClipboardStore) {
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "Saved items and images will be removed from this Mac."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { store.clear() }
    }
}
