import AppKit
import ApplicationServices
import Carbon

enum KeyLayout {
    /// Finds the key that types a character on the current layout, for Command shortcuts.
    static func keyCode(for character: Character, fallback: CGKeyCode) -> CGKeyCode {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return fallback }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        let target = String(character)
        return data.withUnsafeBytes { bytes -> CGKeyCode in
            guard let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return fallback }
            for code in UInt16(0)..<128 {
                var state: UInt32 = 0
                var length = 0
                var output = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                            OptionBits(kUCKeyTranslateNoDeadKeysBit), &state, 4, &length, &output)
                if status == noErr, String(utf16CodeUnits: output, count: length).lowercased() == target {
                    return code
                }
            }
            return fallback
        }
    }
}

enum FinderKey: Sendable {
    case cut, copy, paste

    /// Uses the typed character so other layouts work; non-Latin layouts fall back to the physical key.
    static func resolve(characters: String?, keyCode: Int64) -> FinderKey? {
        if let characters, let character = characters.lowercased().first, character.isASCII {
            switch character {
            case "x": return .cut
            case "c": return .copy
            case "v": return .paste
            default: return nil
            }
        }
        switch keyCode {
        case 7: return .cut
        case 8: return .copy
        case 9: return .paste
        default: return nil
        }
    }
}

/// Tracks whether the next paste should move files.
struct CutState: Equatable, Sendable {
    private enum Phase: Equatable, Sendable {
        case idle, waiting(from: Int), armed(at: Int)
    }

    private var phase = Phase.idle

    var isWaiting: Bool {
        if case .waiting = phase { return true }
        return false
    }

    func isArmed(changeCount: Int) -> Bool { phase == .armed(at: changeCount) }

    mutating func begin(changeCount: Int) { phase = .waiting(from: changeCount) }
    mutating func arm(changeCount: Int) { phase = .armed(at: changeCount) }
    mutating func reset() { phase = .idle }

    /// Returns true when Finder has put files on the pasteboard and the cut is ready.
    mutating func confirm(changeCount: Int, hasFiles: Bool) -> Bool {
        guard case .waiting(let start) = phase, changeCount != start else { return false }
        phase = hasFiles ? .armed(at: changeCount) : .idle
        return hasFiles
    }

    /// Returns true when this paste should become a move. A paste always ends the cut.
    mutating func paste(changeCount: Int, hasFiles: Bool) -> Bool {
        _ = confirm(changeCount: changeCount, hasFiles: hasFiles)
        defer { phase = .idle }
        return phase == .armed(at: changeCount)
    }
}

/// Moves files without ever replacing something already at the destination.
enum FileMover {
    struct Result: Sendable {
        var moved: [URL] = []
        var skipped: [String] = []
    }

    static func move(_ urls: [URL], to folder: URL) -> Result {
        var result = Result()
        let manager = FileManager.default
        let target = folder.standardizedFileURL.path
        for url in urls {
            let source = url.standardizedFileURL
            let destination = folder.appendingPathComponent(source.lastPathComponent)
            let isInsideItself = target == source.path || target.hasPrefix(source.path + "/")
            if isInsideItself || manager.fileExists(atPath: destination.path) {
                result.skipped.append(source.lastPathComponent)
            } else if (try? manager.moveItem(at: source, to: destination)) != nil {
                result.moved.append(destination)
            } else {
                result.skipped.append(source.lastPathComponent)
            }
        }
        return result
    }
}

@MainActor
final class FinderCut: ObservableObject {
    private nonisolated static let finderID = "com.apple.finder"
    private nonisolated static let syntheticTag: Int64 = 0x4D_54_4F_4C
    private static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    @Published private(set) var enabled = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var state = CutState()
    private var finder: pid_t?
    private let cutSound = NSSound(named: NSSound.Name("Tink"))
    private var wantsTap: Bool { UserDefaults.standard.object(forKey: "finder.cutEnabled") as? Bool ?? true }

    init() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == Self.finderID else { return }
                MainActor.assumeIsolated {
                    self?.disable()
                    self?.synchronize()
                }
            }
        }
        // Permission can change in System Settings while CherryTools keeps running.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.synchronize() }
        }
        synchronize()
    }

    func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) { synchronize() }
    }

    func synchronize() {
        if wantsTap && AXIsProcessTrusted() { enable() } else { disable() }
    }

    func enable() {
        guard tap == nil, AXIsProcessTrusted(),
              let pid = NSRunningApplication.runningApplications(withBundleIdentifier: Self.finderID).first?.processIdentifier
        else { return }
        // Only Finder's key events reach this tap, not typing in other apps.
        tap = CGEvent.tapCreateForPid(pid: pid, place: .headInsertEventTap, options: .defaultTap,
                                      eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
                                      callback: finderCutCallback,
                                      userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return }
        finder = pid
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
        enabled = true
    }

    func disable() {
        guard tap != nil else { return } // Service cuts stay valid without the tap.
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
        finder = nil
        state.reset()
        enabled = false
    }

    fileprivate func reenableTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Returns true when the key press is replaced and must not reach Finder.
    fileprivate func handle(_ key: FinderKey, isRepeat: Bool) -> Bool {
        if isEditingText() { return false }
        let pasteboard = NSPasteboard.general
        switch key {
        case .cut:
            if !isRepeat { beginCut() }
            return true
        case .copy:
            state.reset()
            return false
        case .paste:
            guard !isRepeat else { return false }
            let shouldMove = state.paste(changeCount: pasteboard.changeCount, hasFiles: hasFiles)
            if shouldMove {
                post(KeyLayout.keyCode(for: "v", fallback: 9), flags: [.maskCommand, .maskAlternate])
            }
            return shouldMove
        }
    }

    /// Finder's Cut with CherryTools service. It works without Accessibility permission.
    func cut(files urls: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
        state.arm(changeCount: pasteboard.changeCount)
        playCutSound()
    }

    /// Finder's Move Cut Files Here service. Returns nil when nothing is waiting to move.
    func moveCutFiles(to folder: URL) async -> FileMover.Result? {
        let pasteboard = NSPasteboard.general
        guard state.isArmed(changeCount: pasteboard.changeCount),
              let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else { return nil }
        state.reset()
        return await Task.detached(priority: .userInitiated) { FileMover.move(urls, to: folder) }.value
    }

    private var hasFiles: Bool { NSPasteboard.general.types?.contains(.fileURL) ?? false }

    private func beginCut() {
        state.begin(changeCount: NSPasteboard.general.changeCount)
        post(KeyLayout.keyCode(for: "c", fallback: 8), flags: .maskCommand)
        Task { [weak self] in
            // Slow or network volumes can take a moment to fill the pasteboard.
            for _ in 0..<40 {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, self.state.isWaiting else { return }
                if self.state.confirm(changeCount: NSPasteboard.general.changeCount, hasFiles: self.hasFiles) {
                    self.playCutSound()
                    return
                }
            }
            self?.state.reset()
        }
    }

    private func playCutSound() {
        guard UserDefaults.standard.object(forKey: "finder.playCutSound") as? Bool ?? true else { return }
        cutSound?.play()
    }

    /// Rename fields, search and other text keep the normal Cut and Paste commands.
    private func isEditingText() -> Bool {
        guard let finder else { return false }
        let app = AXUIElementCreateApplication(finder)
        AXUIElementSetMessagingTimeout(app, 0.1)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXRoleAttribute as CFString, &role)
        return (role as? String).map(Self.textRoles.contains) ?? false
    }

    private func post(_ key: CGKeyCode, flags: CGEventFlags) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticTag)
            event.post(tap: .cgSessionEventTap)
        }
    }

    fileprivate nonisolated static func isCandidate(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) != syntheticTag &&
            event.flags.contains(.maskCommand) &&
            event.flags.isDisjoint(with: [.maskAlternate, .maskControl, .maskShift])
    }
}

private func finderCutCallback(_: CGEventTapProxy, type: CGEventType, event: CGEvent,
                               userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    let unchanged = Unmanaged.passUnretained(event)
    guard let userInfo else { return unchanged }
    let pointer = UInt(bitPattern: userInfo)
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated {
            Unmanaged<FinderCut>.fromOpaque(UnsafeRawPointer(bitPattern: pointer)!).takeUnretainedValue().reenableTap()
        }
        return unchanged
    }
    guard type == .keyDown, FinderCut.isCandidate(event),
          let key = FinderKey.resolve(characters: NSEvent(cgEvent: event)?.charactersIgnoringModifiers,
                                      keyCode: event.getIntegerValueField(.keyboardEventKeycode)) else { return unchanged }
    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    let replaced = MainActor.assumeIsolated {
        Unmanaged<FinderCut>.fromOpaque(UnsafeRawPointer(bitPattern: pointer)!).takeUnretainedValue()
            .handle(key, isRepeat: isRepeat)
    }
    return replaced ? nil : unchanged
}
