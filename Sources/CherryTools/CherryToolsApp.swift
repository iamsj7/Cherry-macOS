import AppKit
import Carbon
import Combine
import SwiftUI

enum Panel: String, CaseIterable { case ports = "Ports", clipboard = "Clipboard" }

final class AppModel: ObservableObject {
    @Published var panel: Panel = .ports
    let clipboard = ClipboardStore()
    let ports = PortStore()
    let finderCut = FinderCut()
}

private func cherryHotKeyHandler(_: EventHandlerCallRef?, event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID(signature: 0, id: 0)
    let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID), nil,
                                   MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard result == noErr, hotKeyID.signature == 0x4D544F4C else { return OSStatus(eventNotHandledErr) }
    switch hotKeyID.id {
    case 1: AppController.shared?.toggle(select: .clipboard)
    case 2: AppController.shared?.toggleMenuBarIcon()
    default: return OSStatus(eventNotHandledErr)
    }
    return noErr
}

final class AppController: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    static var shared: AppController?
    let model = AppModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var clipboardHotKey: EventHotKeyRef?
    private var menuIconHotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var temporarilyVisible = false
    private var canHideMenuBarIcon = false
    private var menuCountObservation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let url = Bundle.main.url(forResource: "CherryToolsIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            icon.isTemplate = true
            icon.size = NSSize(width: 19, height: 19)
            statusItem.button?.image = icon
        } else {
            statusItem.button?.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: "CherryTools")
        }
        statusItem.button?.action = #selector(toggleFromStatusItem)
        statusItem.button?.target = self
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.font = .systemFont(ofSize: 11, weight: .semibold)
        menuCountObservation = model.ports.$menuPortCount.sink { [weak self] count in
            self?.statusItem.button?.title = count.map(String.init) ?? ""
        }
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentSize = NSSize(width: 466, height: 568)
        popover.contentViewController = NSHostingController(rootView: ContentView(model: model))
        registerShortcuts()
        let shouldShowIcon = UserDefaults.standard.object(forKey: "general.showMenuBarIcon") as? Bool ?? true
        if !shouldShowIcon && !canHideMenuBarIcon {
            UserDefaults.standard.set(true, forKey: "general.showMenuBarIcon")
        }
        statusItem.isVisible = shouldShowIcon || !canHideMenuBarIcon
        updateMenuPortCount()
    }

    @objc private func toggleFromStatusItem() { toggle(select: nil) }

    func closePopover() { popover.performClose(nil) }

    func toggle(select panel: Panel?) {
        if popover.isShown, panel == nil { popover.performClose(nil); return }
        if let panel { model.panel = panel }
        if !statusItem.isVisible {
            statusItem.isVisible = true
            temporarilyVisible = true
        }
        guard let button = statusItem.button else { return }
        if !popover.isShown {
            NSApp.activate(ignoringOtherApps: true)
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
        popover.contentViewController?.view.window?.makeKey()
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

    private func registerShortcuts() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        guard InstallEventHandler(GetApplicationEventTarget(), cherryHotKeyHandler, 1, &type,
                                  nil, &hotKeyHandler) == noErr else { return }
        let clipboardID = EventHotKeyID(signature: 0x4D544F4C, id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(controlKey | optionKey), clipboardID,
                            GetApplicationEventTarget(), 0, &clipboardHotKey)
        let menuID = EventHotKeyID(signature: 0x4D544F4C, id: 2)
        canHideMenuBarIcon = RegisterEventHotKey(UInt32(kVK_ANSI_M),
                                                 UInt32(controlKey | optionKey | cmdKey), menuID,
                                                 GetApplicationEventTarget(), 0, &menuIconHotKey) == noErr
    }
}

@main
struct CherryToolsApp: App {
    @NSApplicationDelegateAdaptor(AppController.self) var controller
    var body: some Scene {
        Settings {
            SettingsView(cut: controller.model.finderCut, clipboard: controller.model.clipboard,
                         ports: controller.model.ports)
        }
    }
}
