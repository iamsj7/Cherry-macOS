import AppKit
import XCTest
@testable import CherryTools

@MainActor
final class ClipboardStoreTests: XCTestCase {
    private var folder: URL!
    private var defaults: UserDefaults!
    private var pasteboard: NSPasteboard!
    private var source: String?

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defaults = UserDefaults(suiteName: UUID().uuidString)
        pasteboard = NSPasteboard.withUniqueName()
        source = nil
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeStore(enabled: Bool = true) -> ClipboardStore {
        defaults.set(enabled, forKey: ClipboardStore.enabledKey)
        return ClipboardStore(folder: folder, pasteboard: pasteboard, defaults: defaults, sourceApp: { [unowned self] in source })
    }

    private func copy(_ text: String, extraType: String? = nil) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        if let extraType { pasteboard.setData(Data(), forType: .init(extraType)) }
    }

    private func png(color: NSColor) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for x in 0..<8 { for y in 0..<8 { rep.setColor(color, atX: x, y: y) } }
        return rep.representation(using: .png, properties: [:])!
    }

    func testIsOffUntilTurnedOn() {
        let store = makeStore(enabled: false)
        copy("secret")
        store.captureIfChanged()
        XCTAssertTrue(store.clips.isEmpty)
    }

    func testTurningOnDoesNotSaveWhatWasAlreadyCopied() {
        copy("before")
        let store = makeStore(enabled: false)
        store.setEnabled(true)
        store.captureIfChanged()
        XCTAssertTrue(store.clips.isEmpty)
    }

    func testSkipsConcealedAndTransientItems() {
        let store = makeStore()
        for type in ClipboardPolicy.ignoredTypes {
            copy("hunter2", extraType: type)
            store.captureIfChanged()
        }
        XCTAssertTrue(store.clips.isEmpty)
    }

    func testSkipsExcludedApps() {
        let store = makeStore()
        store.exclude(app: "com.example.vault")
        source = "com.example.vault"
        copy("from vault")
        store.captureIfChanged()
        XCTAssertTrue(store.clips.isEmpty)
        source = "com.example.notes"
        copy("from notes")
        store.captureIfChanged()
        XCTAssertEqual(store.clips.map(\.value), ["from notes"])
    }

    func testPauseSkipsCopiesMadeWhilePaused() {
        let store = makeStore()
        store.setPaused(true)
        copy("while paused")
        store.captureIfChanged()
        store.setPaused(false)
        store.captureIfChanged()
        XCTAssertTrue(store.clips.isEmpty)
    }

    func testRepeatedTextMovesToTop() {
        let store = makeStore()
        for text in ["one", "two", "one"] {
            copy(text)
            store.captureIfChanged()
        }
        XCTAssertEqual(store.clips.map(\.value), ["one", "two"])
    }

    func testHistoryIsPrivateAndExcludedFromBackups() async throws {
        let store = makeStore()
        copy("saved")
        store.captureIfChanged()
        await store.flush()
        let manager = FileManager.default
        let index = folder.appendingPathComponent("history.json")
        XCTAssertEqual(try manager.attributesOfItem(atPath: folder.path)[.posixPermissions] as? Int, 0o700)
        XCTAssertEqual(try manager.attributesOfItem(atPath: index.path)[.posixPermissions] as? Int, 0o600)
        XCTAssertEqual(try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    func testHistoryPersists() async {
        let store = makeStore()
        copy("kept")
        store.captureIfChanged()
        await store.flush()
        XCTAssertEqual(makeStore().clips.map(\.value), ["kept"])
    }

    func testExpiredItemsAreRemoved() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let old = Clip(id: UUID(), createdAt: Date().addingTimeInterval(-31 * 86_400), kind: .text, preview: "old", value: "old")
        try JSONEncoder().encode([old]).write(to: folder.appendingPathComponent("history.json"))
        XCTAssertTrue(makeStore().clips.isEmpty)
    }

    func testOldHistoryFormatStillLoads() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let json = #"[{"id":"\#(UUID().uuidString)","createdAt":\#(Date().timeIntervalSinceReferenceDate),"kind":"text","preview":"p","value":"v"}]"#
        try Data(json.utf8).write(to: folder.appendingPathComponent("history.json"))
        XCTAssertEqual(makeStore().clips.map(\.value), ["v"])
    }

    func testRichTextRoundTrip() async throws {
        let store = makeStore()
        let rich = NSAttributedString(string: "bold", attributes: [.font: NSFont.boldSystemFont(ofSize: 20)])
        let rtf = try rich.data(from: NSRange(location: 0, length: rich.length),
                                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        pasteboard.clearContents()
        pasteboard.setString("bold", forType: .string)
        pasteboard.setData(rtf, forType: .rtf)
        store.captureIfChanged()
        await store.flush()
        pasteboard.clearContents()
        XCTAssertTrue(store.restore(try XCTUnwrap(store.clips.first)))
        XCTAssertEqual(pasteboard.string(forType: .string), "bold")
        XCTAssertEqual(pasteboard.data(forType: .rtf), rtf)
    }

    func testDuplicateImagesAreStoredOnce() async throws {
        let store = makeStore()
        let data = png(color: .red)
        for _ in 0..<2 {
            pasteboard.clearContents()
            pasteboard.setData(data, forType: .png)
            store.captureIfChanged()
            await store.flush()
        }
        XCTAssertEqual(store.clips.count, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".png") }.count, 1)
        XCTAssertNotNil(NSImage(contentsOf: try XCTUnwrap(store.imageURL(for: store.clips[0]))))
    }

    func testClearRemovesFiles() async throws {
        let store = makeStore()
        pasteboard.clearContents()
        pasteboard.setData(png(color: .blue), forType: .png)
        store.captureIfChanged()
        await store.flush()
        store.clear()
        await store.flush()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["history.json"])
    }

    func testMissingFilesCannotBeRestored() {
        let store = makeStore()
        pasteboard.clearContents()
        let url = folder.appendingPathComponent("gone.txt")
        FileManager.default.createFile(atPath: url.path, contents: Data())
        pasteboard.writeObjects([url as NSURL])
        store.captureIfChanged()
        let clip = store.clips[0]
        XCTAssertEqual(clip.kind, .files)
        XCTAssertFalse(store.filesAreMissing(clip))
        try? FileManager.default.removeItem(at: url)
        XCTAssertTrue(store.filesAreMissing(clip))
        XCTAssertFalse(store.restore(clip))
    }
}
