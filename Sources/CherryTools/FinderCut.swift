import AppKit
import ApplicationServices

final class FinderCut: ObservableObject {
    @Published private(set) var enabled = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var cutPasteboardCount: Int?
    private let cutSound = NSSound(named: NSSound.Name("Tink"))
    private let syntheticTag: Int64 = 0x4D_54_4F_4C

    init() {
        if UserDefaults.standard.object(forKey: "finder.cutEnabled") as? Bool ?? true,
           AXIsProcessTrusted() { enable() }
    }

    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) { enable() }
    }

    func enable() {
        guard tap == nil, AXIsProcessTrusted() else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                options: .defaultTap, eventsOfInterest: mask,
                                callback: { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<FinderCut>.fromOpaque(userInfo).takeUnretainedValue()
            return manager.handle(type: type, event: event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
        enabled = true
    }

    func disable() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
        cutPasteboardCount = nil
        enabled = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown,
              event.getIntegerValueField(.eventSourceUserData) != syntheticTag,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder",
              event.flags.contains(.maskCommand),
              !event.flags.contains(.maskAlternate),
              !event.flags.contains(.maskControl) else { return Unmanaged.passUnretained(event) }

        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if key == 7 { // Command-X copies the Finder selection and arms a move.
            cutPasteboardCount = NSPasteboard.general.changeCount + 1
            postKey(8, flags: .maskCommand) // Command-C
            if UserDefaults.standard.object(forKey: "finder.playCutSound") as? Bool ?? true {
                cutSound?.play()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                if self.cutPasteboardCount != nil {
                    self.cutPasteboardCount = NSPasteboard.general.changeCount
                }
            }
            return nil
        }
        if key == 9, let count = cutPasteboardCount { // Command-V becomes Finder's Move Item Here.
            cutPasteboardCount = nil
            if NSPasteboard.general.changeCount == count {
                postKey(9, flags: [.maskCommand, .maskAlternate])
                return nil
            }
        }
        if key == 8 { cutPasteboardCount = nil }
        return Unmanaged.passUnretained(event)
    }

    private func postKey(_ key: CGKeyCode, flags: CGEventFlags) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: syntheticTag)
            event.post(tap: .cgSessionEventTap)
        }
    }
}
