import Cocoa
import ApplicationServices
import ServiceManagement
import SwiftUI

private final class LayoutPickerPanel: NSPanel {
    var dismiss: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { dismiss?() }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var library: LayoutLibrary
    /// Set when saved layouts could not be fully read; a backup of the original data was kept.
    let layoutsPartlyUnreadable: Bool
    @Published private(set) var trusted = false
    @Published private var loginItemStatus: SMAppService.Status = .notRegistered

    var startsAtLogin: Bool { loginItemStatus == .enabled || needsLoginItemApproval }
    var needsLoginItemApproval: Bool { loginItemStatus == .requiresApproval }

    @Published var dragToSnap = true {
        didSet {
            UserDefaults.standard.set(dragToSnap, forKey: "dragToSnap")
            refresh()
        }
    }
    @Published var gap = 8.0 {
        didSet {
            UserDefaults.standard.set(Int(gap), forKey: gapKey)
            controller.gap = CGFloat(gap)
        }
    }

    /// Custom layouts snap only while Option is held (F4); off keeps the original behaviour.
    @Published var layoutNeedsOption = false {
        didSet {
            UserDefaults.standard.set(layoutNeedsOption, forKey: layoutOptionKey)
            controller.layoutNeedsOption = layoutNeedsOption
        }
    }

    private let gapKey = "windowGapPoints"
    private let layoutOptionKey = "customLayoutNeedsOption"
    private let controller = SnapController()
    private var pickerPanel: LayoutPickerPanel?
    private var pickerMonitors: [Any] = []
    private var settingsWindow: NSWindow?
    /// One editor per layout id, so editing one layout never replaces or closes another's window.
    private var editors: [UUID: LayoutEditor] = [:]
    private var item: NSStatusItem!
    private var permissionTimer: Timer?
    private var lastExternalApp: NSRunningApplication?

    override init() {
        let loaded = LayoutLibrary.load()
        library = loaded.library
        layoutsPartlyUnreadable = loaded.lostData
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ManagedWindow.configureTimeouts()
        let event = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = event?.eventID == kAEOpenApplication &&
            event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        let workspace = NSWorkspace.shared
        rememberExternal(workspace.frontmostApplication)
        workspace.notificationCenter.addObserver(self, selector: #selector(appActivated(_:)),
                                                  name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged(_:)),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // Posted when any app's Accessibility permission changes; the new value lands shortly after.
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(accessibilityChanged(_:)),
                                                            name: NSNotification.Name("com.apple.accessibility.api"), object: nil)
        configurePreferences()
        configureStatusItem()
        refresh()
        if !launchedAtLogin { openSettings() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshLoginItem()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    private func configureStatusItem() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button else { return }
        if let url = Bundle.main.url(forResource: "MenuMark", withExtension: "svg"),
           let mark = NSImage(contentsOf: url) {
            mark.size = NSSize(width: 18, height: 18)
            mark.isTemplate = true
            mark.accessibilityDescription = "Glint"
            button.image = mark
        } else {
            button.image = NSImage(systemSymbolName: "rectangle.split.2x2", accessibilityDescription: "Glint")
        }
        button.setAccessibilityLabel("Glint window layouts")
        button.target = self
        button.action = #selector(togglePicker(_:))
    }

    private func configurePreferences() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: gapKey) == nil {
            for legacyDomain in ["local.panefold.mac", "local.edgesnap.mac"] {
                if let previous = defaults.persistentDomain(forName: legacyDomain)?[gapKey] as? Int {
                    defaults.set(min(32, max(0, previous)), forKey: gapKey)
                    break
                }
            }
        }
        defaults.register(defaults: [gapKey: 8, "dragToSnap": true])
        gap = Double(min(32, max(0, defaults.integer(forKey: gapKey))))
        dragToSnap = defaults.bool(forKey: "dragToSnap")
        layoutNeedsOption = defaults.bool(forKey: layoutOptionKey)
        controller.layout = library.active
    }

    @objc private func appActivated(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        rememberExternal(app)
        // The picker is bound to the window that was in front when it opened; never let it act on a stale target.
        if pickerPanel != nil, app?.processIdentifier != ProcessInfo.processInfo.processIdentifier { closePicker() }
    }

    @objc private func screensChanged(_ notification: Notification) {
        closePicker()
        controller.cancel()
    }

    @objc private func accessibilityChanged(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.refresh() }
    }

    private func rememberExternal(_ app: NSRunningApplication?) {
        if let app, app.activationPolicy == .regular, app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            lastExternalApp = app
        }
    }

    @objc private func togglePicker(_ sender: NSStatusBarButton) {
        if pickerPanel != nil {
            closePicker()
            return
        }
        guard let statusWindow = sender.window else { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? statusWindow.screen else { return }
        let anchor = statusWindow.convertToScreen(sender.convert(sender.bounds, to: nil))
        refresh()
        let frontmost = NSWorkspace.shared.frontmostApplication
        let app = frontmost?.activationPolicy == .regular ? frontmost : lastExternalApp
        let window = trusted ? app.flatMap(ManagedWindow.focused(in:)) : nil
        let view = LayoutPickerView(
            trusted: trusted,
            targetName: window == nil ? nil : app?.localizedName ?? "Active window",
            activeLayout: library.active,
            snap: { [weak self] region in
                guard let self, let app, let window else { return false }
                return self.snap(window, in: app, to: region)
            },
            settings: { [weak self] in self?.openSettings() },
            authorize: { [weak self] in self?.authorize() }
        )
        let hosting = NSHostingController(rootView: view)
        let size = hosting.view.fittingSize
        let panel = LayoutPickerPanel(contentRect: CGRect(origin: .zero, size: size),
                                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.level = .popUpMenu
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentViewController = hosting
        panel.dismiss = { [weak self] in self?.closePicker() }

        // The status item can live in a window whose frame changes during menu-bar tracking.
        // Clamp to the clicked screen's usable area so the header never sits behind the bar.
        let centerX = screen.frame.contains(CGPoint(x: anchor.midX, y: mouse.y)) ? anchor.midX : mouse.x
        let frame = layoutPickerFrame(size: size, centerX: centerX, in: screen.visibleFrame)
        panel.setFrame(frame, display: false)
        pickerPanel = panel
        panel.makeKeyAndOrderFront(nil)
        monitorPickerDismissal(statusWindow: statusWindow, anchor: anchor)
    }

    private func monitorPickerDismissal(statusWindow: NSWindow, anchor: CGRect) {
        let buttons: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: buttons, handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let point = NSEvent.mouseLocation
                if !anchor.contains(point), self.pickerPanel?.frame.contains(point) != true {
                    self.closePicker()
                }
            }
        }) {
            pickerMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: buttons, handler: { [weak self, weak statusWindow] event in
            MainActor.assumeIsolated {
                if let self, event.window !== self.pickerPanel, event.window !== statusWindow {
                    self.closePicker()
                }
            }
            return event
        }) {
            pickerMonitors.append(monitor)
        }
    }

    private func closePicker() {
        for monitor in pickerMonitors { NSEvent.removeMonitor(monitor) }
        pickerMonitors.removeAll()
        pickerPanel?.orderOut(nil)
        pickerPanel = nil
    }

    private func snap(_ window: ManagedWindow, in app: NSRunningApplication, to region: PickerRegion) -> Bool {
        guard AXIsProcessTrusted(), !app.isTerminated, let frame = window.frame,
              let primary = NSScreen.screens.first else { return false }
        let windowBounds = accessibilityFrame(frame, primaryTop: primary.frame.maxY)
        let screens = NSScreen.screens
        guard let screen = screens.max(by: {
            overlapArea($0.frame, windowBounds) < overlapArea($1.frame, windowBounds)
        }), overlapArea(screen.frame, windowBounds) > 0 else { return false }
        let usable = screen.visibleFrame
        let target = region.frame(in: usable, gap: CGFloat(gap))
        let top = primary.frame.maxY
        guard !target.isEmpty,
              window.place(in: accessibilityFrame(target, primaryTop: top),
                           within: accessibilityFrame(usable.insetForGap(CGFloat(gap)), primaryTop: top)).succeeded
        else { return false }
        closePicker()
        if NSApp.isActive { app.activate(options: []) }
        return true
    }

    private func overlapArea(_ display: CGRect, _ window: CGRect) -> CGFloat {
        let overlap = display.intersection(window)
        return overlap.isEmpty ? 0 : overlap.width * overlap.height
    }

    func openSettings() {
        closePicker()
        refreshLoginItem()
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: GlintSettingsView(model: self))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: hosting.view.fittingSize),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Glint Settings"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(name: nil) { appearance in
                let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return NSColor(glintSurface(for: dark ? .dark : .light))
            }
            window.isReleasedWhenClosed = false
            window.contentViewController = hosting
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func setStartsAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        refreshLoginItem()
        guard enabled != startsAtLogin else { return }
        defer { refreshLoginItem() }
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            if enabled && service.status == .requiresApproval { return }
            if let settingsWindow {
                NSAlert(error: error).beginSheetModal(for: settingsWindow)
            }
        }
    }

    func openLoginItemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func refreshLoginItem() {
        let status = SMAppService.mainApp.status
        if status != loginItemStatus { loginItemStatus = status }
    }

    func selectLayout(_ id: UUID?) {
        library.selected = id
        saveLayouts()
    }

    func newLayout() {
        openEditor(WindowLayout(name: "Untitled Layout", zones: []), isNew: true)
    }

    func editLayout() {
        if let active = library.active { openEditor(active, isNew: false) }
    }

    private func openEditor(_ layout: WindowLayout, isNew: Bool) {
        let editor = editors[layout.id] ?? LayoutEditor(layout: layout, isNew: isNew, onSave: { [weak self] result in
            guard let self else { return }
            if let index = self.library.layouts.firstIndex(where: { $0.id == result.id }) {
                self.library.layouts[index] = result
            } else {
                self.library.layouts.append(result)
            }
            self.selectLayout(result.id)
        }, onClose: { [weak self] id in
            self?.editors[id] = nil
        })
        editors[layout.id] = editor
        editor.showWindow(nil)
        editor.window?.makeKeyAndOrderFront(nil)
    }

    func deleteLayout() {
        guard let layout = library.active, let settingsWindow else { return }
        let alert = NSAlert()
        alert.messageText = "Delete “\(layout.name)”?"
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.beginSheetModal(for: settingsWindow) { [weak self] response in
            guard response == .alertSecondButtonReturn, let self else { return }
            self.editors[layout.id]?.close()   // only this layout's editor; other drafts stay open
            self.library.layouts.removeAll { $0.id == layout.id }
            if self.library.selected == layout.id { self.library.selected = nil }
            self.saveLayouts()
        }
    }

    private func saveLayouts() {
        library.save()
        controller.layout = library.active
    }

    func authorize() {
        closePicker()
        let option = "AXTrustedCheckOptionPrompt"   // value of kAXTrustedCheckOptionPrompt, a mutable global in Swift 6
        _ = AXIsProcessTrustedWithOptions([option: true] as CFDictionary)
    }

    private func refresh() {
        let allowed = AXIsProcessTrusted()
        if trusted != allowed { trusted = allowed }
        // Poll quickly only while waiting for a grant; once trusted, the accessibility
        // notification covers revocation and a slow timer is just a safety net.
        let interval: TimeInterval = allowed ? 30 : 2
        if permissionTimer?.timeInterval != interval {
            permissionTimer?.invalidate()
            permissionTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        item?.button?.toolTip = allowed ? "Glint window layouts" : "Glint needs Accessibility access"
        if allowed && dragToSnap { controller.start() } else { controller.stop() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        closePicker()
        permissionTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        controller.stop()
    }
}

// Top-level code runs on the main thread; say so, so the main-actor app delegate can be created here.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()   // NSApplication holds its delegate weakly
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { application.run() }
}
