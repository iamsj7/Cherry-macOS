import AppKit
import Foundation

enum ClipKind: String, Codable { case text, image, files }

struct Clip: Codable, Identifiable, Equatable {
    var id: UUID
    var createdAt: Date
    var kind: ClipKind
    var preview: String
    var value: String
}

final class ClipboardStore: ObservableObject {
    @Published private(set) var clips: [Clip] = []
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private let folder: URL
    private let indexURL: URL
    private let retention: TimeInterval = 30 * 24 * 60 * 60

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        folder = support.appendingPathComponent("CherryTools/Clipboard", isDirectory: true)
        indexURL = folder.appendingPathComponent("history.json")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        lastChangeCount = pasteboard.changeCount
        if let data = try? Data(contentsOf: indexURL),
           let saved = try? JSONDecoder().decode([Clip].self, from: data) {
            clips = saved
        }
        prune()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.captureIfChanged()
        }
        timer?.tolerance = 0.5
    }

    func captureIfChanged() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        let now = Date()
        var newClip: Clip?

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            let paths = urls.map(\.path)
            let title = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"
            newClip = Clip(id: UUID(), createdAt: now, kind: .files, preview: title, value: paths.joined(separator: "\n"))
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty {
            // Avoid persisting unexpectedly large copied documents.
            let limited = String(text.prefix(200_000))
            newClip = Clip(id: UUID(), createdAt: now, kind: .text,
                           preview: String(limited.replacingOccurrences(of: "\n", with: " ").prefix(120)), value: limited)
        } else if let image = NSImage(pasteboard: pasteboard),
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]),
                  png.count <= 10_000_000 {
            let id = UUID()
            let path = "\(id.uuidString).png"
            do {
                try png.write(to: folder.appendingPathComponent(path), options: .atomic)
                newClip = Clip(id: id, createdAt: now, kind: .image, preview: "Image", value: path)
            } catch { return }
        }

        guard let clip = newClip else { return }
        if let first = clips.first, first.kind == clip.kind, first.value == clip.value { return }
        clips.insert(clip, at: 0)
        prune()
        save()
    }

    func restore(_ clip: Clip) {
        pasteboard.clearContents()
        switch clip.kind {
        case .text:
            pasteboard.setString(clip.value, forType: .string)
        case .files:
            let urls = clip.value.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
            pasteboard.writeObjects(urls as [NSURL])
        case .image:
            let url = folder.appendingPathComponent(clip.value)
            if let image = NSImage(contentsOf: url) { pasteboard.writeObjects([image]) }
        }
        lastChangeCount = pasteboard.changeCount
    }

    func image(for clip: Clip) -> NSImage? {
        guard clip.kind == .image else { return nil }
        return NSImage(contentsOf: folder.appendingPathComponent(clip.value))
    }

    func remove(_ clip: Clip) {
        clips.removeAll { $0.id == clip.id }
        if clip.kind == .image { try? FileManager.default.removeItem(at: folder.appendingPathComponent(clip.value)) }
        save()
    }

    func clear() {
        for clip in clips where clip.kind == .image {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(clip.value))
        }
        clips.removeAll()
        save()
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-retention)
        let expired = clips.filter { $0.createdAt < cutoff }
        clips.removeAll { $0.createdAt < cutoff }
        for clip in expired where clip.kind == .image {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(clip.value))
        }
        if !expired.isEmpty { save() }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(clips) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }
}
