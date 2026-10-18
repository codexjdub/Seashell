import AppKit
import SeashellCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: StashStore?
    private var menuBar: MenuBarController?
    private var floatingShelf: FloatingShelf?
    private var panel: PanelController?
    private var notesStore: NotesStore?
    private let dragWatcher = DragWatcher()
    private let edgeScrollWatcher = EdgeScrollWatcher()
    private var isSecondCopy = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if anotherCopyIsRunning() {
            isSecondCopy = true
            NSApp.terminate(nil)
            return
        }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        Log.info("Seashell \(version) launched from \(Bundle.main.bundlePath)")

        let folders = SeashellFolders.standard
        prepare(folders)
        let mover = FileMover()
        let store = StashStore(library: StashLibrary(stash: folders.stash, mover: mover))
        // Finder and iCloud touch hidden files often; log only real changes in what's stashed.
        var lastSummary = Self.summary(of: store)
        store.onChange = { [weak store] in
            guard let store else { return }
            let summary = Self.summary(of: store)
            guard summary != lastSummary else { return }
            lastSummary = summary
            Log.info("Stash changed: \(summary)")
        }
        store.startWatching()
        self.store = store

        let dropper = StashDropper(mover: mover)
        let notesStore = NotesStore(library: NotesLibrary(folder: folders.notes))
        notesStore.startWatching()
        self.notesStore = notesStore
        let panel = PanelController(store: store, notesStore: notesStore, mover: mover, dropper: dropper)
        self.panel = panel
        menuBar = MenuBarController(store: store, dropper: dropper, panel: panel)
        panel.ignoresClick = { [weak self] point in self?.menuBar?.isOnIcon(point) ?? false }
        let floatingShelf = FloatingShelf(store: store, dropper: dropper)
        self.floatingShelf = floatingShelf

        dragWatcher.onShake = { floatingShelf.show(at: $0) }
        dragWatcher.onHoldAtTopEdge = { panel.open(on: NSScreen.containing($0), reason: "drag held at top edge") }
        dragWatcher.start()
        edgeScrollWatcher.onGesture = { gesture, screen in
            switch gesture {
            case .pullDown: panel.open(on: screen, reason: "pull down at top edge")
            case .pushUp: panel.close(reason: "push up at top edge")
            }
        }
        edgeScrollWatcher.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !isSecondCopy else { return }
        panel?.saveNotes()
        Log.info("Seashell quit")
    }

    private static func summary(of store: StashStore) -> String {
        store.shelves.map { "\($0.name) \(store.items(in: $0).count)" }.joined(separator: ", ")
    }

    /// Two copies would both react to every shake and edge scroll, so a second launch bows out.
    private func anotherCopyIsRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != NSRunningApplication.current }
        guard let running = others.first else { return false }
        Log.info("Seashell is already running (pid \(running.processIdentifier)); this copy quits")
        return true
    }

    private func prepare(_ folders: SeashellFolders) {
        do {
            for folder in try folders.createMissing() {
                Log.info("Created \(folder.path(percentEncoded: false))")
            }
        } catch {
            Log.error("Could not create Seashell folders: \(error.localizedDescription)")
        }
    }
}
