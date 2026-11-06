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

    /// The ones open when Seashell quit, where they were and at their size.
    func restore() {
        guard let saved = UserDefaults.standard.array(forKey: Self.key) as? [[String: Any]] else { return }
        for entry in saved {
            guard let name = entry["name"] as? String, let x = entry["x"] as? Double, let y = entry["y"] as? Double,
                  store.shelves.contains(where: { $0.name == name }) else { continue }
            let columns = entry["columns"] as? Int ?? TearOffShelf.defaultColumns
            let rows = entry["rows"] as? Int ?? TearOffShelf.defaultRows
            make(name, columns: max(columns, 1), rows: max(rows, 1)).show(topLeft: NSPoint(x: x, y: y))
            Log.info("Tear-off shelf: \(name) restored")
        }
    }

    private func make(_ name: String, columns: Int = TearOffShelf.defaultColumns, rows: Int = TearOffShelf.defaultRows) -> TearOffShelf {
        let shelf = TearOffShelf(shelfName: name, columns: columns, rows: rows, store: store, mover: mover, dropper: dropper)
        shelf.onFrameChange = { [weak self] in self?.save() }
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

    /// Names, top left corners (in screen coordinates) and sizes in tiles.
    private func save() {
        let entries: [[String: Any]] = shelves.values.map { shelf in
            ["name": shelf.shelfName, "x": Double(shelf.frame.minX), "y": Double(shelf.frame.maxY),
             "columns": shelf.columns, "rows": shelf.rows]
        }
        UserDefaults.standard.set(entries, forKey: Self.key)
    }
}

/// One tear-off shelf: a small floating window with the shelf's name, a close
/// button and its items. It does what a shelf in the panel does: drop to stash,
/// drag out for a copy, double-click or ⌘O to open, Space to preview, ⌘⌫ and
/// the right-click menu. Its edges and corners resize it a column or row of
/// tiles at a time.
@MainActor
final class TearOffShelf: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate, NSWindowDelegate {
    static let defaultColumns = 4
    static let defaultRows = 2
    private static let padding: CGFloat = 10
    private static let spacing: CGFloat = 6
    /// The shelf's name and its close button, along the top.
    private static var titleBarHeight: CGFloat { UIScale.pt(26) }

    private(set) var shelfName: String
    /// Tiles across and rows down; more items scroll.
    private(set) var columns: Int
    private(set) var rows: Int
    /// Moved or resized.
    var onFrameChange: (() -> Void)?
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
    private let preview = PreviewWindow()
    private var headerHeight: NSLayoutConstraint?
    private var closeSize: [NSLayoutConstraint] = []
    private lazy var window = makeWindow()
    private var isClosing = false

    var frame: NSRect { window.frame }

    init(shelfName: String, columns: Int, rows: Int, store: StashStore, mover: FileMover, dropper: StashDropper) {
        self.shelfName = shelfName
        self.columns = columns
        self.rows = rows
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
        // Back on a screen if its spot is gone (a display unplugged), and no
        // bigger than that screen (one smaller than where it was made bigger).
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(frame) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let fitting = gridFitting(visible.size)
            frame.size = setGrid(columns: fitting.columns, rows: fitting.rows)
            frame.origin.y = point.y - frame.height
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
        let old = items
        items = newItems
        grid.reload(showing: items, after: old)
        previewFollowsSelection()
    }

    private func applyTextSize() {
        _ = TextSizeSetting.shared.size
        title.font = UIScale.font(13, weight: .semibold)
        headerHeight?.constant = Self.titleBarHeight
        closeSize.forEach { $0.constant = UIScale.pt(20) }
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: UIScale.pt(10), weight: .semibold))
        layout.itemSize = StashItemCell.tileSize
        layout.invalidateLayout()
        grid.reloadData()
        for (constraint, base) in sealConstraints { constraint.constant = UIScale.pt(base) }
        // The same tiles across and down, bigger or smaller; the top left corner stays put.
        let size = setGrid(columns: columns, rows: rows)
        let old = window.frame
        window.setFrame(NSRect(x: old.minX, y: old.maxY - size.height, width: size.width, height: size.height), display: true)
    }

    /// Takes on `columns` × `rows` and returns the window's size for them,
    /// leaving the window itself to the caller.
    private func setGrid(columns: Int, rows: Int) -> NSSize {
        self.columns = columns
        self.rows = rows
        let size = windowSize(columns: columns, rows: rows)
        sealCenter?.constant = Self.sealOffset(inHeight: size.height)
        return size
    }

    /// Below the title bar, so on a shelf a row tall it doesn't cover the close button.
    private static func sealOffset(inHeight height: CGFloat) -> CGFloat {
        Seal.centerOffset(inHeight: height, clearing: padding + titleBarHeight)
    }

    /// The shelf for `columns` × `rows` tiles, and room for the seal on its right edge.
    private func windowSize(columns: Int, rows: Int) -> NSSize {
        let tile = StashItemCell.tileSize
        return NSSize(width: TileGrid.length(of: columns, tile: tile.width, spacing: Self.spacing) + Self.extraWidth + UIScale.pt(Seal.sideRoom),
                      height: TileGrid.length(of: rows, tile: tile.height, spacing: Self.spacing) + Self.extraHeight)
    }

    /// Up to the current columns and rows, as many as fit in `space`.
    private func gridFitting(_ space: NSSize) -> (columns: Int, rows: Int) {
        let tile = StashItemCell.tileSize
        let across = TileGrid.count(fitting: space.width - Self.extraWidth - UIScale.pt(Seal.sideRoom), tile: tile.width, spacing: Self.spacing)
        let down = TileGrid.count(fitting: space.height - Self.extraHeight, tile: tile.height, spacing: Self.spacing)
        return (min(columns, across), min(rows, down))
    }

    /// Around the tiles across: padding, a scroll bar (which takes width when a
    /// mouse is connected) and a point each side.
    private static var extraWidth: CGFloat {
        2 * padding + NSScroller.scrollerWidth(for: .regular, scrollerStyle: NSScroller.preferredScrollerStyle) + 2
    }

    /// Around the tiles down: the header, padding and a point each side.
    private static var extraHeight: CGFloat { titleBarHeight + 2 * padding + 2 }

    @objc private func closeClicked() {
        close()
    }

    @objc private func sealClicked() {
        onSettings?()
    }

    func windowDidMove(_ notification: Notification) {
        onFrameChange?()
    }

    // MARK: Resizing

    /// The edges a handle moves.
    private struct Edges: OptionSet {
        let rawValue: Int
        static let left = Edges(rawValue: 1 << 0)
        static let right = Edges(rawValue: 1 << 1)
        static let top = Edges(rawValue: 1 << 2)
        static let bottom = Edges(rawValue: 1 << 3)
    }

    /// While an edge or corner is dragged: the frame it started from, and how
    /// far the pointer has gone since (y grows downward).
    private var resizeStart: NSRect?
    private var resizeDrag = CGSize.zero

    /// Invisible strips along the edges and squares at the corners, under
    /// everything else, so the title, close button and tiles keep their clicks.
    private func addResizeHandles(to background: NSView) {
        let edge: CGFloat = 6
        let corner: CGFloat = 14
        let handles: [(NSCursor.FrameResizePosition, Edges)] = [
            (.left, .left), (.right, .right), (.top, .top), (.bottom, .bottom),
            (.topLeft, [.top, .left]), (.topRight, [.top, .right]), (.bottomLeft, [.bottom, .left]), (.bottomRight, [.bottom, .right]),
        ]
        var constraints: [NSLayoutConstraint] = []
        for (position, edges) in handles {
            let handle = DragHandle(.frame(position))
            background.addSubview(handle, positioned: .below, relativeTo: nil)
            handle.onDrag = { [weak self] dx, dy in self?.resize(edges, by: CGSize(width: dx, height: dy)) }
            handle.onEnd = { [weak self] in self?.endResize() }
            if edges.contains(.left) { constraints.append(handle.leadingAnchor.constraint(equalTo: background.leadingAnchor)) }
            if edges.contains(.right) { constraints.append(handle.trailingAnchor.constraint(equalTo: background.trailingAnchor)) }
            if edges.contains(.top) { constraints.append(handle.topAnchor.constraint(equalTo: background.topAnchor)) }
            if edges.contains(.bottom) { constraints.append(handle.bottomAnchor.constraint(equalTo: background.bottomAnchor)) }
            switch edges {
            case .left, .right:  // the side between the corners
                constraints += [handle.widthAnchor.constraint(equalToConstant: edge),
                                handle.topAnchor.constraint(equalTo: background.topAnchor, constant: corner),
                                handle.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -corner)]
            case .top, .bottom:
                constraints += [handle.heightAnchor.constraint(equalToConstant: edge),
                                handle.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: corner),
                                handle.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -corner)]
            default:
                constraints += [handle.widthAnchor.constraint(equalToConstant: corner),
                                handle.heightAnchor.constraint(equalToConstant: corner)]
            }
        }
        NSLayoutConstraint.activate(constraints)
    }

    /// Follows the drag a whole column or row at a time, the tile counts
    /// nearest to where the pointer is, as far as the screen allows on that
    /// side. The opposite edges stay put.
    private func resize(_ edges: Edges, by delta: CGSize) {
        if resizeStart == nil {
            resizeStart = window.frame
            resizeDrag = .zero
            preview.hide()
        }
        guard let start = resizeStart, let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        resizeDrag.width += delta.width
        resizeDrag.height += delta.height
        let tile = StashItemCell.tileSize
        let side = UIScale.pt(Seal.sideRoom)
        var newColumns = columns
        var newRows = rows
        if !edges.isDisjoint(with: [.left, .right]) {
            // Dragging right widens from the right edge and narrows from the left.
            let width = start.width + (edges.contains(.left) ? -resizeDrag.width : resizeDrag.width)
            let room = edges.contains(.left) ? start.maxX - visible.minX : visible.maxX - start.minX
            let most = TileGrid.count(fitting: room - Self.extraWidth - side, tile: tile.width, spacing: Self.spacing)
            newColumns = TileGrid.count(nearest: width - Self.extraWidth - side, tile: tile.width, spacing: Self.spacing, maximum: most)
        }
        if !edges.isDisjoint(with: [.top, .bottom]) {
            // Dragging down lowers the bottom edge, or the top edge.
            let height = start.height + (edges.contains(.top) ? -resizeDrag.height : resizeDrag.height)
            let room = edges.contains(.top) ? visible.maxY - start.minY : start.maxY - visible.minY
            let most = TileGrid.count(fitting: room - Self.extraHeight, tile: tile.height, spacing: Self.spacing)
            newRows = TileGrid.count(nearest: height - Self.extraHeight, tile: tile.height, spacing: Self.spacing, maximum: most)
        }
        guard newColumns != columns || newRows != rows else { return }
        let size = setGrid(columns: newColumns, rows: newRows)
        let x = edges.contains(.left) ? start.maxX - size.width : start.minX
        let y = edges.contains(.top) ? start.minY : start.maxY - size.height
        window.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    private func endResize() {
        guard resizeStart != nil else { return }
        resizeStart = nil
        onFrameChange?()
        note("resized to \(columns) × \(rows) tiles")
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
        (cell as? StashItemCell)?.configure(with: items[indexPath.item], thumbnails: .shared,
                                                scale: collectionView.window?.backingScaleFactor ?? 2)
        return cell
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        previewFollowsSelection()
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        previewFollowsSelection()
    }

    /// An open preview follows the selection, and closes when nothing is selected.
    private func previewFollowsSelection() {
        guard preview.isShowing else { return }
        if let item = selectedItems.first {
            preview.update(item.url)
        } else {
            preview.hide()
        }
    }

    func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
        true
    }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> (any NSPasteboardWriting)? {
        DragOut.writer(for: items[indexPath.item])
    }

    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
                        willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>) {
        ItemActions.startDownloading(indexPaths.map { items[$0.item] })
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
        ItemActions.menu(for: selectedItems, note: { [weak self] in self?.note($0) }, ItemActions.MenuHandlers(
            open: { [weak self] in self?.openSelection() },
            quickLook: { [weak self] in self?.togglePreview() },
            paste: { [weak self] in self?.paste() },
            rename: { [weak self] item in
                guard let self else { return }
                note("Rename… \(item.name)")
                ItemActions.rename(item, with: mover)
                store.reload(around: [item.url])
            },
            putBack: { [weak self] items in self?.perform("put back", items) { $0.putBack($1) } },
            moveToTrash: { [weak self] items in self?.perform("move to the Trash", items) { $0.delete($1) } }))
    }

    private func paste() {
        guard let shelf else { return }
        note("paste")
        if dropper.paste(into: shelf.url) {
            SealView.react(.catchDrop, in: window)
        } else {
            NSSound.beep()
        }
    }

    /// ⌘Z: the latest drop, paste or move between shelves goes back.
    private func undo() {
        note("undo")
        Task {
            if await dropper.undoLast() {
                store.reload(around: nil)
            } else {
                NSSound.beep()
                SealView.react(.shake, in: window)
            }
        }
    }

    private func deleteSelection() {
        perform("move to the Trash", selectedItems) { $0.delete($1) }
    }

    /// Notes it in the log, then runs a file operation on `items` (see ItemActions.perform).
    private func perform<T: Sendable>(_ verb: String, _ items: [StashItem],
                                      _ operation: @escaping @Sendable (FileMover, [URL]) -> [Result<T, any Error>]) {
        guard !items.isEmpty else { return }
        note("\(verb): \(items.count) item\(items.count == 1 ? "" : "s")")
        ItemActions.perform(verb, items.map(\.url), with: mover, store: store, operation)
    }

    private func note(_ message: String) {
        Log.info("Tear-off shelf \(shelfName): \(message)")
    }

    // MARK: Building

    private func makeWindow() -> NSPanel {
        let window = TearOffWindow(contentRect: NSRect(origin: .zero, size: windowSize(columns: columns, rows: rows)),
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
        addResizeHandles(to: background)
        let p = Self.padding
        let header = title.heightAnchor.constraint(equalToConstant: Self.titleBarHeight)
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
                                                       constant: Self.sealOffset(inHeight: windowSize(columns: columns, rows: rows).height))
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

    /// No menu bar of its own: ⌘C, ⌘V, ⌘A and ⌘Z go to the grid by hand, and
    /// ⌘+ / ⌘− / ⌘0 set the text size, as in the panel (EditShortcuts).
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        EditShortcuts.perform(event, from: self) || super.performKeyEquivalent(with: event)
    }
}
