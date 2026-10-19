import AppKit
import SeashellCore

/// Tear-off shelves: one shelf of Stash in its own small floating window, made
/// by dragging the shelf's tab out of the panel. A window onto the shelf, not a
/// copy: the same files, in iCloud and in the panel. They stay until closed and
/// come back after a restart where they were.
@MainActor
final class TearOffShelves {
    private static let key = "tearOffShelves"

    /// After an item is dropped somewhere: where, so its app can come forward.
    var onDraggedOut: ((NSPoint) -> Void)?
    /// The seal on a tear-off's edge opens Settings, like everywhere else.
    var onSettings: (() -> Void)?

    private let store: StashStore
    private let mover: FileMover
    private let dropper: StashDropper
    private var shelves: [String: TearOffShelf] = [:]

    init(store: StashStore, mover: FileMover, dropper: StashDropper) {
        self.store = store
        self.mover = mover
        self.dropper = dropper
        // A shelf deleted (or renamed) elsewhere takes its window with it.
        observeChanges { [weak self] in self?.closeVanished() }
    }

    /// Opens `shelf` in its own window with its top centered on `point`; if it's
    /// already open, moves that window there.
    func open(_ shelf: Shelf, at point: NSPoint) {
        let window = shelves[shelf.name] ?? make(shelf.name)
        window.show(topCenter: point)
        save()
        Log.info("Tear-off shelf: \(shelf.name) opened")
    }

    /// A shelf renamed in the panel: its window stays open under the new name.
    /// (Renamed in Finder or on another Mac, it can't be told from a deletion,
    /// so the window closes.)
    func rename(from old: String, to new: String) {
        guard let shelf = shelves.removeValue(forKey: old) else { return }
        shelf.rename(to: new)
        shelves[new] = shelf
        save()
        Log.info("Tear-off shelf: \(old) is now \(new)")
    }

    /// The ones open when Seashell quit, where they were.
    func restore() {
        guard let saved = UserDefaults.standard.array(forKey: Self.key) as? [[String: Any]] else { return }
        for entry in saved {
            guard let name = entry["name"] as? String, let x = entry["x"] as? Double, let y = entry["y"] as? Double,
                  store.shelves.contains(where: { $0.name == name }) else { continue }
            make(name).show(topLeft: NSPoint(x: x, y: y))
            Log.info("Tear-off shelf: \(name) restored")
        }
    }

    private func make(_ name: String) -> TearOffShelf {
        let shelf = TearOffShelf(shelfName: name, store: store, mover: mover, dropper: dropper)
        shelf.onMove = { [weak self] in self?.save() }
        shelf.onClose = { [weak self, weak shelf] in
            guard let self, let shelf else { return }
            self.shelves[shelf.shelfName] = nil
            self.save()
            Log.info("Tear-off shelf: \(shelf.shelfName) closed")
        }
        shelf.onDraggedOut = { [weak self] point in self?.onDraggedOut?(point) }
        shelf.onSettings = { [weak self] in self?.onSettings?() }
        shelves[name] = shelf
        return shelf
    }

    private func closeVanished() {
        let names = Set(store.shelves.map(\.name))
        for (name, shelf) in shelves where !names.contains(name) { shelf.close() }
    }

    /// Names and top left corners, in screen coordinates.
    private func save() {
        let entries: [[String: Any]] = shelves.values.map { shelf in
            ["name": shelf.shelfName, "x": Double(shelf.frame.minX), "y": Double(shelf.frame.maxY)]
        }
        UserDefaults.standard.set(entries, forKey: Self.key)
    }
}

/// One tear-off shelf: a small floating window with the shelf's name, a close
/// button and its items. It does what a shelf in the panel does: drop to stash,
/// drag out for a copy, double-click or ⌘O to open, Space to preview, ⌘⌫ and
/// the right-click menu.
@MainActor
final class TearOffShelf: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate, NSWindowDelegate {
    private static let columns = 4
    private static let rows = 2
    private static let padding: CGFloat = 10
    private static let spacing: CGFloat = 6

    private(set) var shelfName: String
    var onMove: (() -> Void)?
    var onClose: (() -> Void)?
    var onDraggedOut: ((NSPoint) -> Void)?
    var onSettings: (() -> Void)?

    private let store: StashStore
    private let mover: FileMover
    private let dropper: StashDropper
    private var items: [StashItem] = []
    private lazy var seal = Seal.button(target: self, action: #selector(sealClicked), toolTip: "Seashell Settings")
    private var sealConstraints: [(constraint: NSLayoutConstraint, base: CGFloat)] = []
    private var sealCenter: NSLayoutConstraint?
    private let grid = StashGridView()
    private let layout = NSCollectionViewFlowLayout()
    private let title = NSTextField(labelWithString: "")
    private lazy var closeButton = PillButton(target: self, action: #selector(closeClicked))
    private let thumbnails = ThumbnailLoader()
    private let preview = PreviewWindow()
    private var headerHeight: NSLayoutConstraint?
    private var closeSize: [NSLayoutConstraint] = []
    private lazy var window = makeWindow()
    private var isClosing = false

    var frame: NSRect { window.frame }

    init(shelfName: String, store: StashStore, mover: FileMover, dropper: StashDropper) {
        self.shelfName = shelfName
        self.store = store
        self.mover = mover
        self.dropper = dropper
        super.init()
        title.stringValue = shelfName
        observeChanges { [weak self] in self?.refresh() }
        observeChanges { [weak self] in self?.applyTextSize() }
    }

    func show(topCenter point: NSPoint) {
        show(topLeft: NSPoint(x: point.x - window.frame.width / 2, y: point.y + Self.padding))
    }

    func show(topLeft point: NSPoint) {
        var frame = NSRect(origin: NSPoint(x: point.x, y: point.y - window.frame.height), size: window.frame.size)
        // Back on a screen if its spot is gone (a display unplugged).
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(frame) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
    }

    func rename(to name: String) {
        shelfName = name
        title.stringValue = name
        refresh()
    }

    func close() {
        guard !isClosing else { return }
        isClosing = true
        preview.hide()
        window.orderOut(nil)
        onClose?()
    }

    // MARK: Content

    private var shelf: Shelf? { store.shelves.first { $0.name == shelfName } }

    private func refresh() {
        let newItems = shelf.map { store.items(in: $0) } ?? []
        guard newItems != items else { return }
        items = newItems
        grid.reloadData()
    }

    private func applyTextSize() {
        _ = TextSizeSetting.shared.size
        title.font = UIScale.font(13, weight: .semibold)
        headerHeight?.constant = UIScale.pt(26)
        closeSize.forEach { $0.constant = UIScale.pt(20) }
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: UIScale.pt(10), weight: .semibold))
        layout.itemSize = StashItemCell.tileSize
        layout.invalidateLayout()
        grid.reloadData()
        let shelf = Self.size()
        for (constraint, base) in sealConstraints { constraint.constant = UIScale.pt(base) }
        sealCenter?.constant = Seal.centerOffset(inHeight: shelf.height)
        // Wider than the shelf, for the seal on its edge; the top left corner stays put.
        let old = window.frame
        let size = NSSize(width: shelf.width + UIScale.pt(Seal.sideRoom), height: shelf.height)
        window.setFrame(NSRect(x: old.minX, y: old.maxY - size.height, width: size.width, height: size.height), display: true)
    }

    /// Four tiles across and two rows high; more scroll. Room for a scroll bar,
    /// which takes width when a mouse is connected.
    private static func size() -> NSSize {
        let tile = StashItemCell.tileSize
        let scroller = NSScroller.scrollerWidth(for: .regular, scrollerStyle: NSScroller.preferredScrollerStyle)
        let width = CGFloat(columns) * tile.width + CGFloat(columns - 1) * spacing + 2 * padding + scroller + 2
        let height = UIScale.pt(26) + CGFloat(rows) * tile.height + CGFloat(rows - 1) * spacing + 2 * padding + 2
        return NSSize(width: width, height: height)
    }

    @objc private func closeClicked() {
        close()
    }

    @objc private func sealClicked() {
        onSettings?()
    }

    func windowDidMove(_ notification: Notification) {
        onMove?()
    }

    // MARK: Items

    private var selectedItems: [StashItem] {
        grid.selectionIndexPaths.sorted().compactMap { items.indices.contains($0.item) ? items[$0.item] : nil }
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(withIdentifier: StashItemCell.identifier, for: indexPath)
        (cell as? StashItemCell)?.configure(with: items[indexPath.item], thumbnails: thumbnails)
        return cell
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        if preview.isShowing, let item = selectedItems.first { preview.update(item.url) }
    }

    func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
        true
    }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> (any NSPasteboardWriting)? {
        DragOut.writer(for: items[indexPath.item])
    }

    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
                        willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>) {
        for indexPath in indexPaths where CloudStatus.state(of: items[indexPath.item].url) == .cloudOnly {
            try? CloudStatus.startDownloading(items[indexPath.item].url)
        }
    }

    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
                        endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation) {
        guard !operation.isEmpty, !window.frame.contains(screenPoint) else { return }
        note("item dragged out")
        onDraggedOut?(screenPoint)
    }

    func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: any NSDraggingInfo,
                        proposedIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                        dropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        dropOperation.pointee = .before
        return StashDropper.operation(for: draggingInfo)
    }

    func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: any NSDraggingInfo,
                        indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        guard let shelf else { return false }
        note("drop into “\(shelf.name)”")
        return dropper.accept(draggingInfo, into: shelf.url)
    }

    // MARK: Actions

    private func openSelection() {
        selectedItems.forEach { NSWorkspace.shared.open($0.url) }
    }

    private func togglePreview() {
        if preview.isShowing {
            preview.hide()
        } else if let item = selectedItems.first, let screen = window.screen {
            preview.show(item.url, below: window.frame, in: screen.visibleFrame, level: window.level)
        }
    }

    private func itemMenu() -> NSMenu {
        let selection = selectedItems
        let menu = NSMenu()
        menu.autoenablesItems = false
        func add(_ title: String, enabled: Bool = true, _ action: @escaping @MainActor () -> Void) {
            let item = menu.addItem(withTitle: title, action: #selector(MenuAction.run), keyEquivalent: "")
            let handler = MenuAction(action)
            item.target = handler
            item.representedObject = handler  // keeps it alive while the menu is up
            item.isEnabled = enabled
        }
        add("Open") { [weak self] in self?.openSelection() }
        add("Quick Look") { [weak self] in self?.togglePreview() }
        add("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(selection.map(\.url)) }
        menu.addItem(.separator())
        add("Copy") { ItemActions.copy(selection) }
        add("Paste", enabled: ItemActions.canPaste) { [weak self] in self?.paste() }
        add("Rename…", enabled: selection.count == 1) { [weak self] in
            guard let self, let item = selection.first else { return }
            ItemActions.rename(item, with: self.mover)
            self.store.reload()
        }
        menu.addItem(.separator())
        add("Put Back", enabled: !selection.isEmpty && selection.allSatisfy { $0.origin != nil }) { [weak self] in
            self?.perform("put back", selection.filter { $0.origin != nil }.map(\.url)) { _ = try $0.putBack($1) }
        }
        add("Move to Trash") { [weak self] in self?.deleteSelection() }
        return menu
    }

    private func paste() {
        guard let shelf else { return }
        note("paste")
        if !dropper.paste(into: shelf.url) { NSSound.beep() }
    }

    /// ⌘Z: the latest drop, paste or move between shelves goes back.
    private func undo() {
        note("undo")
        Task {
            if await dropper.undoLast() {
                store.reload()
            } else {
                NSSound.beep()
            }
        }
    }

    private func deleteSelection() {
        perform("move to the Trash", selectedItems.map(\.url)) { try $0.delete($1) }
    }

    /// Runs a file operation on each item off the main thread, reporting failures.
    private func perform(_ verb: String, _ urls: [URL], _ operation: @escaping @Sendable (FileMover, URL) throws -> Void) {
        guard !urls.isEmpty else { return }
        note("\(verb): \(urls.count) item\(urls.count == 1 ? "" : "s")")
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

    private func note(_ message: String) {
        Log.info("Tear-off shelf \(shelfName): \(message)")
    }

    // MARK: Building

    private func makeWindow() -> NSPanel {
        let window = TearOffWindow(contentRect: NSRect(origin: .zero, size: Self.size()),
                                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.level = .floating
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.delegate = self
        window.onEscape = { [weak self] in
            guard let self, self.preview.isShowing else { return }
            self.preview.hide()
        }

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true

        layout.minimumInteritemSpacing = Self.spacing
        layout.minimumLineSpacing = Self.spacing
        grid.collectionViewLayout = layout
        grid.isSelectable = true
        grid.allowsMultipleSelection = true
        grid.backgroundColors = [.clear]
        grid.register(StashItemCell.self, forItemWithIdentifier: StashItemCell.identifier)
        grid.dataSource = self
        grid.delegate = self
        grid.registerForDraggedTypes(StashDropper.acceptedTypes)
        // Out to other apps as a copy; the item stays on the shelf.
        grid.setDraggingSourceOperationMask(.copy, forLocal: false)
        grid.setDraggingSourceOperationMask([], forLocal: true)
        grid.onOpen = { [weak self] in self?.openSelection() }
        grid.onDelete = { [weak self] in self?.deleteSelection() }
        grid.onTogglePreview = { [weak self] in self?.togglePreview() }
        grid.onCopy = { [weak self] in self.map { ItemActions.copy($0.selectedItems) } }
        grid.onPaste = { [weak self] in self?.paste() }
        grid.onUndo = { [weak self] in self?.undo() }
        grid.contextMenu = { [weak self] in self?.itemMenu() }

        let scroll = NSScrollView()
        scroll.documentView = grid
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        title.textColor = .secondaryLabelColor
        title.lineBreakMode = .byTruncatingTail
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.toolTip = "Close (the shelf stays in Stash)"

        for view in [title, closeButton, scroll] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }
        let p = Self.padding
        let header = title.heightAnchor.constraint(equalToConstant: UIScale.pt(26))
        headerHeight = header
        closeSize = [closeButton.widthAnchor.constraint(equalToConstant: UIScale.pt(20)),
                     closeButton.heightAnchor.constraint(equalToConstant: UIScale.pt(20))]
        NSLayoutConstraint.activate(closeSize + [
            title.topAnchor.constraint(equalTo: background.topAnchor, constant: p),
            title.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: p + 4),
            title.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -8),
            header,
            closeButton.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -p),
            scroll.topAnchor.constraint(equalTo: title.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: p),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -p),
            scroll.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -p),
        ])
        // The shelf, with the seal a fifth of the way down its right edge.
        let container = NSView()
        for view in [background, seal] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        let scaled: [(NSLayoutConstraint, CGFloat)] = [
            (container.trailingAnchor.constraint(equalTo: background.trailingAnchor), Seal.sideRoom),
            (seal.trailingAnchor.constraint(equalTo: background.trailingAnchor), Seal.overhang),
            (seal.widthAnchor.constraint(equalToConstant: 0), Seal.size),
            (seal.heightAnchor.constraint(equalToConstant: 0), Seal.size),
        ]
        sealConstraints = scaled.map { (constraint: $0.0, base: $0.1) }
        for (constraint, base) in sealConstraints { constraint.constant = UIScale.pt(base) }
        let sealCenter = seal.centerYAnchor.constraint(equalTo: background.topAnchor,
                                                       constant: Seal.centerOffset(inHeight: Self.size().height))
        self.sealCenter = sealCenter
        NSLayoutConstraint.activate(sealConstraints.map(\.constraint) + [
            background.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            background.topAnchor.constraint(equalTo: container.topAnchor),
            background.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            sealCenter,
        ])
        window.contentView = container
        return window
    }
}

/// A borderless panel that can take keys (Space, ⌘⌫, ⌘O, Esc) without making
/// Seashell the active app.
final class TearOffWindow: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    /// No menu bar of its own: ⌘C, ⌘V and ⌘Z go to the grid by hand.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let action: Selector? = switch (modifiers, event.charactersIgnoringModifiers?.lowercased()) {
        case (.command, "c"): #selector(NSText.copy(_:))
        case (.command, "v"): #selector(NSText.paste(_:))
        case (.command, "a"): #selector(NSText.selectAll(_:))
        case (.command, "z"): Selector(("undo:"))
        default: nil
        }
        if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// A menu item's action as a closure.
@MainActor
final class MenuAction: NSObject {
    private let action: @MainActor () -> Void

    init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    @objc func run() {
        action()
    }
}
