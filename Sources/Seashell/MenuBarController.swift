import AppKit
import SeashellCore

/// The menu bar icon: a menu, and a drop target that stashes into Main.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate, NSWindowDelegate, NSDraggingDestination {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let store: StashStore
    private let dropper: StashDropper
    private let menu = NSMenu()

    init(store: StashStore, dropper: StashDropper) {
        self.store = store
        self.dropper = dropper
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "tray.full", accessibilityDescription: "Seashell")
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

    // MARK: Menu

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
        // No action yet, so the menu shows it disabled. The panel arrives in Milestone 3.
        menu.addItem(NSMenuItem(title: "Open Seashell", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Seashell", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func showStash() {
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
