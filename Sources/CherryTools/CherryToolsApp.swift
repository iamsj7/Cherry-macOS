import AppKit
import Carbon
import Combine
import SwiftUI

enum Panel: String, CaseIterable { case ports = "Ports", clipboard = "Clipboard", toolbox = "Toolbox" }

@MainActor
final class AppModel: ObservableObject {
    @Published var panel: Panel = .ports
    @Published var unavailableShortcuts: [String] = []
    let clipboard: ClipboardStore
    let ports = PortStore()
    let finderCut = FinderCut()
    let toolbox = ToolboxStore()

    init(clipboard: ClipboardStore = ClipboardStore()) { self.clipboard = clipboard }
}

private func cherryHotKeyHandler(_: EventHandlerCallRef?, event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID(signature: 0, id: 0)
    let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID), nil,
                                   MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard result == noErr, hotKeyID.signature == 0x4D544F4C else { return OSStatus(eventNotHandledErr) }
    let id = hotKeyID.id
    return MainActor.assumeIsolated {
        switch id {
        case 1: AppController.shared?.toggle(select: .clipboard)
        case 2: AppController.shared?.toggleMenuBarIcon()
        default: return OSStatus(eventNotHandledErr)
        }
        return noErr
    }
}

/// Keeps SwiftUI's Settings action available to the status menu and app reopen.
private struct SettingsBridge: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear.onAppear {
            AppController.shared?.openSettingsAction = { openSettings() }
        }
    }
}

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    static var shared: AppController?
    let model = AppModel()
    var openSettingsAction: (() -> Void)?
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var bridgeWindow: NSWindow?
    private var clipboardHotKey: EventHotKeyRef?
    private var menuIconHotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var temporarilyVisible = false
    private var settingsWereRequested = false
    private var previousApp: NSRunningApplication?
    private var canHideMenuBarIcon = false
    private var menuCountObservation: AnyCancellable?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Windows open only when asked for, never because they were open at the last quit.
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        closeRestoredWindows()
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.menuBarImage()
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
            button.toolTip = "CherryTools"
            button.setAccessibilityLabel("CherryTools")
        }
        menuCountObservation = model.ports.$menuPortCount.sink { [weak self] count in
            self?.statusItem.button?.title = count.map(String.init) ?? ""
            self?.statusItem.button?.setAccessibilityValue(count.map { "\($0) ports" })
        }
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentSize = NSSize(width: 466, height: 568)
        popover.contentViewController = NSHostingController(rootView: ContentView(model: model))
        installSettingsBridge()
        registerShortcuts()
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        let shouldShowIcon = UserDefaults.standard.object(forKey: "general.showMenuBarIcon") as? Bool ?? true
        if !shouldShowIcon && !canHideMenuBarIcon {
            UserDefaults.standard.set(true, forKey: "general.showMenuBarIcon")
        }
        statusItem.isVisible = shouldShowIcon || !canHideMenuBarIcon
        updateMenuPortCount()
    }

    private static func fileURLs(on pasteboard: NSPasteboard) -> [URL] {
        pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    /// Finder service: Cut with CherryTools.
    @objc func cutFiles(_ pasteboard: NSPasteboard, userData: String,
                        error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = Self.fileURLs(on: pasteboard)
        if !urls.isEmpty { model.finderCut.cut(files: urls) }
    }

    /// Finder service: Move Cut Files Here.
    @objc func moveCutFiles(_ pasteboard: NSPasteboard, userData: String,
                            error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let folder = Self.fileURLs(on: pasteboard).first else { return }
        Task {
            guard let result = await model.finderCut.moveCutFiles(to: folder) else {
                showMoveAlert("No files are waiting to move",
                              "Right-click files in Finder and choose Cut with CherryTools first.")
                return
            }
            if !result.skipped.isEmpty {
                showMoveAlert("Some items weren't moved",
                              "\(result.skipped.formatted(.list(type: .and))) already exist in this folder or can't be moved there.")
            }
        }
    }

    private func showMoveAlert(_ title: String, _ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Done")
        alert.runModal()
    }

    /// Opening the app again is the way back when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !popover.isShown { toggle(select: nil) }
        return false
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showStatusMenu()
        } else {
            toggle(select: nil)
        }
    }

    private func showStatusMenu() {
        guard let button = statusItem.button else { return }
        popover.performClose(nil)
        let menu = NSMenu()
        menu.addItem(item("Ports", #selector(showPorts)))
        menu.addItem(item("Clipboard", #selector(showClipboard)))
        menu.addItem(item("Toolbox", #selector(showToolbox)))
        if model.clipboard.isEnabled {
            let title = model.clipboard.isPaused ? "Resume Clipboard History" : "Pause Clipboard History"
            menu.addItem(item(title, #selector(toggleClipboardPause)))
        }
        menu.addItem(.separator())
        menu.addItem(item("About CherryTools", #selector(showAbout)))
        menu.addItem(item("Settings…", #selector(openSettingsFromMenu), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Quit CherryTools", #selector(quit), key: "q"))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func showPorts() { show(.ports) }
    @objc private func showClipboard() { show(.clipboard) }
    @objc private func showToolbox() { show(.toolbox) }
    @objc private func toggleClipboardPause() { model.clipboard.setPaused(!model.clipboard.isPaused) }
    @objc private func openSettingsFromMenu() { showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    private func show(_ panel: Panel) {
        if popover.isShown {
            model.panel = panel
        } else {
            toggle(select: panel)
        }
    }

    func closePopover() { popover.performClose(nil) }

    /// Puts people back where they were so ⌘V pastes the chosen item there.
    func closePopoverAndReturn() {
        popover.performClose(nil)
        if let previousApp, !previousApp.isTerminated {
            NSApp.yieldActivation(to: previousApp)
            previousApp.activate()
        }
        previousApp = nil
    }

    func showSettings() {
        settingsWereRequested = true
        popover.performClose(nil)
        DispatchQueue.main.async { [self] in
            NSApp.activate()
            openSettingsAction?()
        }
    }

    func toggle(select panel: Panel?) {
        if popover.isShown, panel == nil || panel == model.panel {
            popover.performClose(nil)
            return
        }
        if let panel { model.panel = panel }
        if !statusItem.isVisible {
            statusItem.isVisible = true
            temporarilyVisible = true
        }
        guard let button = statusItem.button else { return }
        if !popover.isShown {
            let frontmost = NSWorkspace.shared.frontmostApplication
            previousApp = frontmost?.processIdentifier == getpid() ? nil : frontmost
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
        if model.panel == .ports { model.ports.start() }
        else { model.ports.stop() }
    }

    func popoverDidClose(_ notification: Notification) {
        model.ports.stop()
        if temporarilyVisible {
            temporarilyVisible = false
            statusItem.isVisible = UserDefaults.standard.object(forKey: "general.showMenuBarIcon") as? Bool ?? true
            updateMenuPortCount()
        }
    }

    func popoverDidShow(_ notification: Notification) {
        guard let window = popover.contentViewController?.view.window else { return }
        window.makeKey()
        if let field = Self.searchField(in: window.contentView) { window.makeFirstResponder(field) }
    }

    private static func searchField(in view: NSView?) -> NSSearchField? {
        guard let view else { return nil }
        if let field = view as? NSSearchField { return field }
        return view.subviews.lazy.compactMap(searchField).first
    }

    @discardableResult
    func setMenuBarIconVisible(_ visible: Bool) -> Bool {
        guard visible || canHideMenuBarIcon else { return false }
        temporarilyVisible = false
        statusItem.isVisible = visible
        updateMenuPortCount()
        return true
    }

    func updateMenuPortCount() {
        let enabled = UserDefaults.standard.bool(forKey: "general.showPortCount") && statusItem.isVisible
        model.ports.setMenuCountEnabled(enabled)
    }

    func toggleMenuBarIcon() {
        let visible = UserDefaults.standard.object(forKey: "general.showMenuBarIcon") as? Bool ?? true
        guard setMenuBarIconVisible(!visible) else { return }
        UserDefaults.standard.set(!visible, forKey: "general.showMenuBarIcon")
    }

    private func closeRestoredWindows() {
        // Restored windows can appear just after launch finishes.
        for delay in [0.0, 0.3, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
                guard !settingsWereRequested else { return }
                NSApp.windows.filter { $0.styleMask.contains(.titled) && $0.isVisible }.forEach { $0.close() }
            }
        }
    }

    private func installSettingsBridge() {
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 1, height: 1),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.transient, .ignoresCycle]
        window.contentView = NSHostingView(rootView: SettingsBridge())
        window.orderBack(nil)
        bridgeWindow = window
    }

    private func registerShortcuts() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        guard InstallEventHandler(GetApplicationEventTarget(), cherryHotKeyHandler, 1, &type,
                                  nil, &hotKeyHandler) == noErr else {
            model.unavailableShortcuts = ["Control–Option–V", "Control–Option–Command–M"]
            return
        }
        let clipboardID = EventHotKeyID(signature: 0x4D544F4C, id: 1)
        let clipboardKey = KeyLayout.keyCode(for: "v", fallback: CGKeyCode(kVK_ANSI_V))
        if RegisterEventHotKey(UInt32(clipboardKey), UInt32(controlKey | optionKey), clipboardID,
                               GetApplicationEventTarget(), 0, &clipboardHotKey) != noErr {
            model.unavailableShortcuts.append("Control–Option–V")
        }
        let menuID = EventHotKeyID(signature: 0x4D544F4C, id: 2)
        let menuKey = KeyLayout.keyCode(for: "m", fallback: CGKeyCode(kVK_ANSI_M))
        canHideMenuBarIcon = RegisterEventHotKey(UInt32(menuKey), UInt32(controlKey | optionKey | cmdKey), menuID,
                                                 GetApplicationEventTarget(), 0, &menuIconHotKey) == noErr
        if !canHideMenuBarIcon { model.unavailableShortcuts.append("Control–Option–Command–M") }
    }

    /// A simple cherry silhouette, drawn so the system can tint it for any menu bar.
    private static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()
            NSBezierPath(ovalIn: NSRect(x: 1, y: 9, width: 8, height: 8)).fill()
            NSBezierPath(ovalIn: NSRect(x: 9.5, y: 9.5, width: 7.5, height: 7.5)).fill()
            let stems = NSBezierPath()
            stems.lineWidth = 1.3
            stems.lineCapStyle = .round
            stems.move(to: NSPoint(x: 5, y: 10))
            stems.curve(to: NSPoint(x: 10, y: 2), controlPoint1: NSPoint(x: 5.5, y: 6.5), controlPoint2: NSPoint(x: 8, y: 3.5))
            stems.move(to: NSPoint(x: 13.2, y: 10))
            stems.curve(to: NSPoint(x: 10, y: 2), controlPoint1: NSPoint(x: 13, y: 7), controlPoint2: NSPoint(x: 11.5, y: 4))
            stems.stroke()
            let leaf = NSBezierPath()
            leaf.move(to: NSPoint(x: 10, y: 2))
            leaf.curve(to: NSPoint(x: 16.5, y: 3.5), controlPoint1: NSPoint(x: 12, y: 0), controlPoint2: NSPoint(x: 15, y: 0.5))
            leaf.curve(to: NSPoint(x: 10, y: 2), controlPoint1: NSPoint(x: 15, y: 5.5), controlPoint2: NSPoint(x: 12, y: 5))
            leaf.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "CherryTools"
        return image
    }
}

@main
struct CherryToolsApp: App {
    @NSApplicationDelegateAdaptor(AppController.self) var controller
    var body: some Scene {
        Settings {
            SettingsView(model: controller.model, cut: controller.model.finderCut,
                         clipboard: controller.model.clipboard, ports: controller.model.ports)
        }
    }
}
