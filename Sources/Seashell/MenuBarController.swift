import AppKit
import SeashellCore

/// The menu bar icon: a menu, and a drop target that stashes into Main.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate, NSWindowDelegate, NSDraggingDestination {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let store: StashStore
    private let dropper: StashDropper
    private let panel: PanelController
    private let settings: SettingsWindow
    private let menu = NSMenu()

    init(store: StashStore, dropper: StashDropper, panel: PanelController, settings: SettingsWindow) {
        self.store = store
        self.dropper = dropper
        self.panel = panel
        self.settings = settings
        super.init()
        statusItem.button?.image = MenuBarIcon.image
        menu.delegate = self
        statusItem.menu = menu

        // The icon's window forwards drag-and-drop calls to its delegate.
        if let window = statusItem.button?.window {
            window.registerForDraggedTypes(StashDropper.acceptedTypes)
            window.delegate = self
        } else {
            Log.error("Menu bar icon has no window; dropping onto it won’t work")
        }
    }

    /// Whether `point` (screen coordinates) is on the menu bar icon.
    func isOnIcon(_ point: NSPoint) -> Bool {
        guard let frame = statusItem.button?.window?.frame else { return false }
        return point.x >= frame.minX && point.x <= frame.maxX && point.y >= frame.minY && point.y <= frame.maxY
    }

    // MARK: Menu

    func menuWillOpen(_ menu: NSMenu) {
        Log.info("Menu opened (panel \(panel.stateDescription))")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for shelf in store.shelves {
            let count = store.items(in: shelf).count
            menu.addItem(NSMenuItem(title: "\(shelf.name): \(count) \(count == 1 ? "item" : "items")", action: nil, keyEquivalent: ""))
        }
        let show = NSMenuItem(title: "Show Stash in Finder", action: #selector(showStash), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        menu.addItem(.separator())
        let toggle = NSMenuItem(title: panel.isShowing ? "Close Seashell" : "Open Seashell", action: #selector(togglePanel), keyEquivalent: "")
        toggle.target = self
        // Shows the keyboard shortcut from Settings beside it.
        let shortcut = AppSettings.shared.panelShortcut
        if let letter = shortcut.letter {
            toggle.keyEquivalent = letter
            toggle.keyEquivalentModifierMask = shortcut == .controlOptionCommandS ? [.control, .option, .command] : [.control, .option]
        }
        menu.addItem(toggle)
        // For the app you're in (opening this menu leaves it in front).
        if let app = NSWorkspace.shared.frontmostApplication, app != .current, let id = app.bundleIdentifier {
            let item = NSMenuItem(title: "Ignore Shakes in \(app.localizedName ?? id)", action: #selector(toggleIgnoreShakes),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = id
            item.state = AppSettings.shared.shakeIgnoredApps.contains(id) ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem(title: "Quit Seashell", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func toggleIgnoreShakes(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        Log.info("Menu: \(sender.title) \(sender.state == .on ? "off" : "on")")
        AppSettings.shared.setShakesIgnored(sender.state != .on, in: id)
    }

    @objc private func openSettings() {
        settings.show()
    }

    @objc private func togglePanel() {
        panel.toggle(reason: "menu")
    }

    @objc private func showStash() {
        Log.info("Menu: Show Stash in Finder")
        NSWorkspace.shared.open(store.library.stash)
    }

    // MARK: Drop onto the icon

    func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        statusItem.button?.highlight(true)
        return StashDropper.operation(for: sender)
    }

    func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        StashDropper.operation(for: sender)
    }

    func draggingExited(_ sender: (any NSDraggingInfo)?) {
        statusItem.button?.highlight(false)
    }

    func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        statusItem.button?.highlight(false)
        guard let main = store.defaultShelf else {
            Log.error("No \(SeashellFolders.defaultShelfName) shelf to stash into")
            return false
        }
        return dropper.accept(sender, into: main.url)
    }
}
