import AppKit
import SeashellCore

/// The menu bar icon: a menu, and a drop target that stashes into Main.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate, NSWindowDelegate, NSDraggingDestination {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let store: StashStore
    private let notesStore: NotesStore
    private let dropper: StashDropper
    private let panel: PanelController
    private let settings: SettingsWindow
    private let tips: TipsWindow
    private let about = AboutWindow()
    private let menu = NSMenu()

    init(store: StashStore, notesStore: NotesStore, dropper: StashDropper, panel: PanelController,
         settings: SettingsWindow, tips: TipsWindow) {
        self.store = store
        self.notesStore = notesStore
        self.dropper = dropper
        self.panel = panel
        self.settings = settings
        self.tips = tips
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

    /// The panel first; then the shelves and the notes, with counts, each opening
    /// the panel there; then settings; then Tips and About; then Quit.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let toggle = item(panel.isShowing ? "Close Seashell" : "Open Seashell", #selector(togglePanel))
        // Shows the keyboard shortcut from Settings beside it.
        let shortcut = AppSettings.shared.panelShortcut
        if let letter = shortcut.letter {
            toggle.keyEquivalent = letter
            toggle.keyEquivalentModifierMask = shortcut == .controlOptionCommandS ? [.control, .option, .command] : [.control, .option]
        }
        menu.addItem(toggle)
        menu.addItem(.separator())

        // Grey headings, with their rows indented under them.
        menu.addItem(.sectionHeader(title: "Stash"))
        for shelf in store.shelves {
            let shelfItem = item(shelf.name, #selector(openShelf), represents: shelf.name)
            shelfItem.badge = NSMenuItemBadge(count: store.items(in: shelf).count)
            shelfItem.indentationLevel = 1
            menu.addItem(shelfItem)
        }
        menu.addItem(.sectionHeader(title: "Notes"))
        let notes = item("All Notes", #selector(openNotes))
        notes.badge = NSMenuItemBadge(count: notesStore.notes.count)
        notes.indentationLevel = 1
        menu.addItem(notes)
        menu.addItem(.separator())

        menu.addItem(item("Show in Finder", #selector(showFolder)))

        // For the app you're in (opening this menu leaves it in front).
        if let app = NSWorkspace.shared.frontmostApplication, app != .current, let id = app.bundleIdentifier {
            let ignore = item("Ignore Shakes in \(app.localizedName ?? id)", #selector(toggleIgnoreShakes), represents: id)
            ignore.state = AppSettings.shared.shakeIgnoredApps.contains(id) ? .on : .off
            menu.addItem(ignore)
        }
        let settingsItem = item("Settings…", #selector(openSettings))
        settingsItem.keyEquivalent = ","
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        menu.addItem(item("Tips…", #selector(openTips)))
        menu.addItem(item("About Seashell", #selector(openAbout)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Seashell", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector, represents value: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = value
        return item
    }

    @objc private func openShelf(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        panel.open(shelfNamed: name, reason: "menu: shelf \(name)")
    }

    @objc private func openNotes() {
        panel.openNotes(reason: "menu: Notes")
    }

    @objc private func toggleIgnoreShakes(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        Log.info("Menu: \(sender.title) \(sender.state == .on ? "off" : "on")")
        AppSettings.shared.setShakesIgnored(sender.state != .on, in: id)
    }

    @objc private func openTips() {
        tips.show()
    }

    @objc private func openAbout() {
        about.show()
    }

    @objc private func openSettings() {
        settings.show()
    }

    @objc private func togglePanel() {
        panel.toggle(reason: "menu")
    }

    /// `~/Documents/Seashell`, which holds both Stash and Notes.
    @objc private func showFolder() {
        Log.info("Menu: Show in Finder")
        NSWorkspace.shared.open(store.library.stash.deletingLastPathComponent())
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
