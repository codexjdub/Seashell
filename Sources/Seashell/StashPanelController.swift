import AppKit
import Observation
import SeashellCore

/// Stash inside the pull-down panel: shelf tabs across the top, the shelf's
/// items in a grid below. Follows the store, so changes from Finder or another
/// Mac show up live.
@MainActor
final class StashPanelController: NSViewController {
    let grid = StashGridView()
    /// Called when items dragged out of the grid were taken by a drop, with
    /// where it happened (screen coordinates).
    var onDraggedOut: ((NSPoint) -> Void)?
    /// A tab dragged out of the panel: that shelf, and where it was let go.
    var onTearOff: ((Shelf, NSPoint) -> Void)?
    /// A shelf renamed here: its old and new names.
    var onRenamed: ((String, String) -> Void)?

    private let store: StashStore
    private let mover: FileMover
    private let dropper: StashDropper
    private let thumbnails = ThumbnailLoader()
    private let preview = PreviewWindow()
    /// Shelf tabs and the + button, wrapping onto more rows when they don't fit.
    private let tabs = FlowView()
    private let layout = NSCollectionViewFlowLayout()
    private let emptyLabel = PassThroughLabel(labelWithString: "Drop files here, or shake while dragging.")
    private var currentShelfName = SeashellFolders.defaultShelfName
    private var items: [StashItem] = []
    /// The items in the current drag out of the grid. Text and links go on the
    /// pasteboard as content, not file URLs, so moving to a tab needs these.
    private var draggedURLs: [URL] = []

    init(store: StashStore, mover: FileMover, dropper: StashDropper) {
        self.store = store
        self.mover = mover
        self.dropper = dropper
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private var currentShelf: Shelf? {
        store.shelves.first { $0.name == currentShelfName }
    }

    // MARK: Layout

    override func loadView() {
        let root = NSView()

        tabs.spacing = 6
        let add = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: "New shelf")!,
                           target: self, action: #selector(addShelf))
        add.bezelStyle = .accessoryBarAction
        add.toolTip = "New shelf"
        tabs.views = [add]
        let header = tabs

        layout.itemSize = StashItemCell.tileSize
        layout.minimumInteritemSpacing = 6
        layout.minimumLineSpacing = 6
        layout.sectionInset = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        grid.collectionViewLayout = layout
        grid.isSelectable = true
        grid.allowsMultipleSelection = true
        grid.backgroundColors = [.clear]
        grid.register(StashItemCell.self, forItemWithIdentifier: StashItemCell.identifier)
        grid.dataSource = self
        grid.delegate = self
        grid.registerForDraggedTypes(StashDropper.acceptedTypes)
        // Out to other apps: a copy, the item stays. Within Seashell: onto a tab, to move it.
        grid.setDraggingSourceOperationMask(.copy, forLocal: false)
        grid.setDraggingSourceOperationMask(.move, forLocal: true)
        grid.onOpen = { [weak self] in self?.openSelection() }
        grid.onDelete = { [weak self] in self?.deleteSelection() }
        grid.contextMenu = { [weak self] in self?.itemMenu() }
        grid.onTogglePreview = { [weak self] in self?.togglePreview() }

        let scroll = NSScrollView()
        scroll.documentView = grid
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        emptyLabel.textColor = .secondaryLabelColor

        for subview in [header, scroll, emptyLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(subview)
        }
        // Rows as tall as Notes' header, so the first row and Notes' header
        // sit on one center line.
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
        ])
        view = root
        observeChanges { [weak self] in self?.refresh() }
        observeChanges { [weak self] in self?.applyTextSize() }
    }

    /// Re-sizes text, tiles and tabs. Reads the text size, so it runs again when that changes.
    private func applyTextSize() {
        _ = TextSizeSetting.shared.size
        emptyLabel.font = UIScale.font(14)
        tabs.rowHeight = UIScale.pt(28)
        tabButtons.forEach { $0.font = UIScale.font(13) }
        tabs.needsLayout = true
        layout.itemSize = StashItemCell.tileSize
        layout.invalidateLayout()
        grid.reloadData()
    }

    func willHide() {
        closePreview()
    }

    // MARK: Preview

    private func togglePreview() {
        if preview.isShowing {
            closePreview()
            return
        }
        guard let item = selectedItems.first, let window = grid.window, let screen = window.screen else { return }
        note("preview of \(item.name)")
        preview.show(item.url, below: window.frame, in: screen.visibleFrame, level: window.level)
    }

    /// Closes the preview if it's open; true if it was.
    @discardableResult
    func closePreview() -> Bool {
        guard preview.isShowing else { return false }
        note("preview closed")
        preview.hide()
        return true
    }

    /// An open preview follows the selection, e.g. with the arrow keys.
    private func previewFollowsSelection() {
        guard preview.isShowing else { return }
        if let item = selectedItems.first {
            preview.update(item.url)
        } else {
            closePreview()
        }
    }

    // MARK: Following the store

    /// Re-reads shelves and items from the store. Reading them inside
    /// `observeChanges` is what makes this run again when they change.
    private func refresh() {
        let shelves = store.shelves
        if !shelves.contains(where: { $0.name == currentShelfName }) {
            currentShelfName = SeashellFolders.defaultShelfName
        }
        updateTabs(for: shelves)

        let newItems = currentShelf.map { store.items(in: $0) } ?? []
        emptyLabel.isHidden = !newItems.isEmpty
        guard newItems != items else { return }
        let selected = Set(selectedItems.map(\.url))
        items = newItems
        grid.reloadData()
        let reselect = items.indices.filter { selected.contains(items[$0].url) }.map { IndexPath(item: $0, section: 0) }
        grid.selectItems(at: Set(reselect), scrollPosition: [])
    }

    private func show(shelfNamed name: String) {
        currentShelfName = name
        items = []
        grid.reloadData()
        refresh()
    }

    // MARK: Tabs

    private var tabButtons: [ShelfTabButton] {
        tabs.views.compactMap { $0 as? ShelfTabButton }
    }

    /// Rebuilds the tabs only when the shelves changed, so a drag hovering over
    /// a tab isn't interrupted by unrelated refreshes.
    private func updateTabs(for shelves: [Shelf]) {
        if tabButtons.map(\.shelf) != shelves {
            var buttons: [ShelfTabButton] = []
            for shelf in shelves {
                let button = ShelfTabButton(shelf: shelf, target: self, action: #selector(tabClicked))
                button.font = UIScale.font(13)
                button.operation = { [weak self] info in self?.dropOperation(info, onto: shelf) ?? [] }
                button.onDrop = { [weak self] info in self?.drop(info, onto: shelf) ?? false }
                button.onReorder = { [weak self] name, after in self?.moveShelf(named: name, nextTo: shelf, after: after) }
                button.onTearOff = { [weak self] point in
                    self?.note("tab “\(shelf.name)” torn off")
                    self?.onTearOff?(shelf, point)
                }
                button.menu = shelf.isDefault ? nil : tabMenu(for: shelf)
                buttons.append(button)
            }
            // The + button stays last.
            tabs.views = buttons + tabs.views.filter { !($0 is ShelfTabButton) }
        }
        for button in tabButtons {
            button.state = button.shelf.name == currentShelfName ? .on : .off
        }
    }

    /// A tab dragged onto another goes just before or after it. Main stays first.
    private func moveShelf(named name: String, nextTo target: Shelf, after: Bool) {
        guard name != target.name, let dragged = store.shelves.first(where: { $0.name == name }) else { return }
        let others = store.shelves.filter { !$0.isDefault && $0.name != name }.map(\.name)
        let index = target.isDefault ? 0 : (others.firstIndex(of: target.name).map { after ? $0 + 1 : $0 } ?? others.count)
        note("tab “\(name)” moved \(after ? "after" : "before") “\(target.name)”")
        do {
            try store.library.moveShelf(dragged, to: index)
            store.reload()
        } catch {
            Alerts.showError("Couldn’t move “\(name)”", error)
        }
    }

    @objc private func tabClicked(_ sender: ShelfTabButton) {
        note("tab “\(sender.shelf.name)” clicked")
        show(shelfNamed: sender.shelf.name)
    }

    private func tabMenu(for shelf: Shelf) -> NSMenu {
        let menu = NSMenu()
        let rename = menu.addItem(withTitle: "Rename…", action: #selector(renameShelf), keyEquivalent: "")
        let delete = menu.addItem(withTitle: "Delete…", action: #selector(deleteShelf), keyEquivalent: "")
        for item in [rename, delete] {
            item.target = self
            item.representedObject = shelf.name
        }
        return menu
    }

    @objc private func addShelf() {
        note("+ clicked")
        guard let name = Alerts.askForName("New shelf", confirm: "Create") else { return note("new shelf cancelled") }
        do {
            let shelf = try store.library.createShelf(named: name)
            store.reload()
            show(shelfNamed: shelf.name)
        } catch {
            Alerts.showError("Couldn’t create the shelf", error)
        }
    }

    @objc private func renameShelf(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let shelf = store.shelves.first(where: { $0.name == name }) else { return }
        note("Rename… chosen for “\(name)”")
        guard let newName = Alerts.askForName("Rename “\(name)”", initial: name, confirm: "Rename"), newName != name else {
            return note("rename cancelled")
        }
        do {
            let renamed = try store.library.renameShelf(shelf, to: newName)
            if currentShelfName == name { currentShelfName = renamed.name }
            onRenamed?(name, renamed.name)
            store.reload()
        } catch {
            Alerts.showError("Couldn’t rename “\(name)”", error)
        }
    }

    @objc private func deleteShelf(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let shelf = store.shelves.first(where: { $0.name == name }) else { return }
        note("Delete… chosen for “\(name)”")
        let count = store.items(in: shelf).count
        if count > 0, !Alerts.confirm("Move “\(name)” to the Trash?",
                                      detail: "Its \(count) \(count == 1 ? "item goes" : "items go") with it.",
                                      confirm: "Move to Trash") {
            return note("delete cancelled")
        }
        do {
            try store.library.deleteShelf(shelf)
            store.reload()
        } catch {
            Alerts.showError("Couldn’t delete “\(name)”", error)
        }
    }

    // MARK: Dropping onto a tab

    private func dropOperation(_ info: any NSDraggingInfo, onto shelf: Shelf) -> NSDragOperation {
        if info.draggingSource is StashGridView {
            return shelf.name == currentShelfName ? [] : .move
        }
        return StashDropper.operation(for: info)
    }

    private func drop(_ info: any NSDraggingInfo, onto shelf: Shelf) -> Bool {
        guard info.draggingSource is StashGridView else {
            note("drop from another app onto tab “\(shelf.name)”")
            return dropper.accept(info, into: shelf.url)
        }
        let urls = draggedURLs
        note("\(count(urls.count)) dragged from the grid onto tab “\(shelf.name)”")
        let destination = shelf.url
        perform("move", urls) { try $0.move($1, toShelf: destination) }
        return !urls.isEmpty
    }

    // MARK: Item actions

    private var selectedItems: [StashItem] {
        grid.selectionIndexPaths.sorted().compactMap { items.indices.contains($0.item) ? items[$0.item] : nil }
    }

    private func itemMenu() -> NSMenu {
        let selection = selectedItems
        note("right-click menu for \(count(selection.count))")
        let menu = NSMenu()
        menu.autoenablesItems = false
        func add(_ title: String, _ action: Selector, enabled: Bool = true) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = enabled
        }
        add("Open", #selector(openSelection))
        add("Quick Look", #selector(quickLookSelection))
        add("Show in Finder", #selector(showSelectionInFinder))
        menu.addItem(.separator())
        add("Put Back", #selector(putBackSelection), enabled: !selection.isEmpty && selection.allSatisfy { $0.origin != nil })
        add("Move to Trash", #selector(deleteSelection))
        return menu
    }

    @objc private func openSelection() {
        note("Open \(count(selectedItems.count))")
        selectedItems.forEach { NSWorkspace.shared.open($0.url) }
    }

    @objc private func quickLookSelection() {
        togglePreview()
    }

    @objc private func showSelectionInFinder() {
        note("Show in Finder \(count(selectedItems.count))")
        NSWorkspace.shared.activateFileViewerSelecting(selectedItems.map(\.url))
    }

    @objc private func putBackSelection() {
        note("Put Back \(count(selectedItems.count))")
        perform("put back", selectedItems.filter { $0.origin != nil }.map(\.url)) { _ = try $0.putBack($1) }
    }

    @objc private func deleteSelection() {
        note("Move to Trash \(count(selectedItems.count))")
        perform("move to the Trash", selectedItems.map(\.url)) { try $0.delete($1) }
    }

    private func note(_ message: String) {
        Log.info("Panel: \(message)")
    }

    private func count(_ n: Int) -> String {
        "\(n) \(n == 1 ? "item" : "items")"
    }

    /// Runs a file operation on each item off the main thread, reporting failures.
    private func perform(_ verb: String, _ urls: [URL], _ operation: @escaping @Sendable (FileMover, URL) throws -> Void) {
        guard !urls.isEmpty else { return }
        let mover = self.mover
        Task {
            for url in urls {
                do {
                    try await Task.detached { try operation(mover, url) }.value
                } catch {
                    Alerts.showError("Couldn’t \(verb) “\(url.lastPathComponent)”", error)
                }
            }
            store.reload()
        }
    }
}

// MARK: Grid data and drops

extension StashPanelController: NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(withIdentifier: StashItemCell.identifier, for: indexPath)
        (cell as? StashItemCell)?.configure(with: items[indexPath.item], thumbnails: thumbnails)
        return cell
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        previewFollowsSelection()
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        previewFollowsSelection()
    }

    // Dragging out

    func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
        true
    }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> (any NSPasteboardWriting)? {
        DragOut.writer(for: items[indexPath.item])
    }

    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
                        willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>) {
        draggedURLs = indexPaths.sorted().map { items[$0.item].url }
        let kinds = indexPaths.sorted().map { "\(items[$0.item].kind)" }.joined(separator: ", ")
        note("dragging out \(count(indexPaths.count)) (\(kinds))")
        // Files only in iCloud start downloading now, so the copy lands sooner.
        for indexPath in indexPaths where CloudStatus.state(of: items[indexPath.item].url) == .cloudOnly {
            try? CloudStatus.startDownloading(items[indexPath.item].url)
        }
    }

    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
                        endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation) {
        draggedURLs = []
        let how = [(NSDragOperation.copy, "copy"), (.move, "move"), (.link, "link"), (.generic, "generic")]
            .filter { operation.contains($0.0) }.map(\.1).joined(separator: "+")
        note(operation.isEmpty ? "drag out ended: not taken (cancelled or refused)" : "drag out ended: taken as \(how)")
        if !operation.isEmpty { onDraggedOut?(screenPoint) }
    }

    // Dropping in from elsewhere

    func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: any NSDraggingInfo,
                        proposedIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                        dropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        dropOperation.pointee = .before
        return StashDropper.operation(for: draggingInfo)
    }

    func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: any NSDraggingInfo,
                        indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        guard let shelf = currentShelf else { return false }
        note("drop from another app into “\(shelf.name)”")
        return dropper.accept(draggingInfo, into: shelf.url)
    }
}

/// A shelf tab: click to show it; drop files or text on it to stash there, or
/// items from the grid to move them there. Dragging the tab onto another tab
/// reorders the shelves (all but Main, which stays first); dragging it out of
/// the panel tears the shelf off into its own window.
@MainActor
final class ShelfTabButton: NSButton, NSDraggingSource {
    /// What a dragged tab carries: its shelf's name. Only Seashell reads it.
    static let shelfType = NSPasteboard.PasteboardType("io.github.codexjdub.seashell.shelf")

    let shelf: Shelf
    var operation: ((any NSDraggingInfo) -> NSDragOperation)?
    var onDrop: ((any NSDraggingInfo) -> Bool)?
    /// A tab dropped here: its shelf's name, and whether it goes after this tab.
    var onReorder: ((_ name: String, _ after: Bool) -> Void)?
    /// This tab dropped outside the panel: where, on screen.
    var onTearOff: ((NSPoint) -> Void)?
    /// Where a dragged tab would land: true after this one, false before it.
    private var insertAfter: Bool? {
        didSet { needsDisplay = true }
    }

    init(shelf: Shelf, target: AnyObject, action: Selector) {
        self.shelf = shelf
        super.init(frame: .zero)
        title = shelf.name
        self.target = target
        self.action = action
        setButtonType(.pushOnPushOff)
        bezelStyle = .accessoryBar
        registerForDraggedTypes(StashDropper.acceptedTypes + [Self.shelfType])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Dragging the tab

    /// A click selects the tab; moving a few points first drags it instead.
    override func mouseDown(with event: NSEvent) {
        // Control-click still opens the tab's menu.
        guard !event.modifierFlags.contains(.control), let window else { return super.mouseDown(with: event) }
        let start = event.locationInWindow
        while let next = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            if next.type == .leftMouseUp {
                sendAction(action, to: target)
                return
            }
            if hypot(next.locationInWindow.x - start.x, next.locationInWindow.y - start.y) > 4 {
                beginDraggingTab(with: event)
                return
            }
        }
    }

    private func beginDraggingTab(with event: NSEvent) {
        let item = NSPasteboardItem()
        item.setString(shelf.name, forType: Self.shelfType)
        let dragged = NSDraggingItem(pasteboardWriter: item)
        let snapshot = NSImage(size: bounds.size)
        if let rep = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: rep)
            snapshot.addRepresentation(rep)
        }
        dragged.setDraggingFrame(bounds, contents: snapshot)
        beginDraggingSession(with: [dragged], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        // Let go outside the panel, it becomes a window there: no sliding back.
        session.animatesToStartingPositionsOnCancelOrFail = false
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        guard operation.isEmpty, let window, !window.frame.contains(screenPoint) else { return }
        onTearOff?(screenPoint)
    }

    // MARK: Drops

    private static func draggedShelf(_ info: any NSDraggingInfo) -> String? {
        info.draggingPasteboard.string(forType: shelfType)
    }

    /// Nothing goes before Main.
    /// Main can be dragged out to tear it off, but not reordered.
    private func reorder(_ info: any NSDraggingInfo, name: String) -> NSDragOperation {
        guard name != shelf.name, name != SeashellFolders.defaultShelfName else {
            insertAfter = nil
            return []
        }
        insertAfter = shelf.isDefault || convert(info.draggingLocation, from: nil).x > bounds.midX
        return .move
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if let name = Self.draggedShelf(sender) { return reorder(sender, name: name) }
        let result = operation?(sender) ?? []
        isHighlighted = !result.isEmpty
        return result
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if let name = Self.draggedShelf(sender) { return reorder(sender, name: name) }
        return operation?(sender) ?? []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        isHighlighted = false
        insertAfter = nil
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        isHighlighted = false
        if let name = Self.draggedShelf(sender) {
            defer { insertAfter = nil }
            guard let after = insertAfter else { return false }
            onReorder?(name, after)
            return true
        }
        return onDrop?(sender) ?? false
    }

    /// A line on the side where a dragged tab would land.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let insertAfter else { return }
        NSColor.controlAccentColor.setFill()
        NSRect(x: insertAfter ? bounds.maxX - 2 : 0, y: 2, width: 2, height: bounds.height - 4).fill()
    }
}

/// A label that lets clicks and drags through to whatever is underneath.
final class PassThroughLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Runs `apply` now, and again whenever an @Observable value it read changes.
@MainActor
func observeChanges(_ apply: @escaping @MainActor @Sendable () -> Void) {
    withObservationTracking(apply) {
        Task { @MainActor in observeChanges(apply) }
    }
}
