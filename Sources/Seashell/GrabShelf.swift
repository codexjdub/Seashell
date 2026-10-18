import AppKit
import SeashellCore

/// Watches for a shake of the pointer with ⌥ held and no mouse button down:
/// the gesture for the grab shelf. ⌥ keeps it from firing when you shake the
/// pointer just to find it (macOS enlarges the pointer on a plain shake).
@MainActor
final class OptionShakeWatcher {
    var onShake: ((NSPoint) -> Void)?

    /// Nil when shaking is off in Settings.
    private var detector = ShakeSensitivity.standard.detector
    private var monitors: [Any] = []

    func setShakeSensitivity(_ sensitivity: ShakeSensitivity) {
        detector = sensitivity.detector
    }

    func start() {
        // Global for the pointer over other apps; local for over Seashell's own windows.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }) {
            monitors.append(local)
        }
        Log.info(monitors.count == 2 ? "Watching for ⌥-shake" : "Couldn’t watch the pointer; ⌥-shake won’t open the grab shelf")
    }

    private func handle(_ event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .shift, .option, .control]) == .option else {
            detector?.reset()
            return
        }
        let point = NSEvent.mouseLocation
        if detector?.add(x: point.x, at: event.timestamp) == true {
            onShake?(point)
        }
    }
}

/// The grab shelf: pops up next to the pointer on ⌥-shake with the most recent
/// items from every shelf, to drag straight out (a copy lands; the item stays).
/// It goes away after a drag out, a click elsewhere, or when the pointer moves
/// well away; More… opens the full panel.
@MainActor
final class GrabShelf: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
    static let maxItems = 8
    private static let columns = 4
    private static let padding: CGFloat = 12
    private static let spacing: CGFloat = 6

    var onMore: ((NSPoint) -> Void)?
    /// After an item is dropped somewhere: where, so its app can come forward.
    var onDraggedOut: ((NSPoint) -> Void)?

    private let store: StashStore
    private let thumbnails = ThumbnailLoader()
    private var items: [StashItem] = []
    private let grid = StashGridView()
    private let layout = NSCollectionViewFlowLayout()
    private let title = NSTextField(labelWithString: "Recent in Stash")
    private let emptyLabel = NSTextField(labelWithString: "Nothing in Stash yet")
    private lazy var moreButton = NSButton(title: "More…", target: self, action: #selector(moreClicked))
    private lazy var panel = makePanel()
    private var monitors: [Any] = []
    private var isDragging = false
    private var gridTop: NSLayoutConstraint?
    /// Moving away doesn't count until then: the end of the shake itself can
    /// carry the pointer off before you reach for the shelf.
    private var shownAt = ContinuousClock.now
    private static let grace: Duration = .seconds(1)
    /// How far the pointer can wander from the shelf before it goes away.
    private static let reach: CGFloat = 220

    init(store: StashStore) {
        self.store = store
    }

    var isShowing: Bool { panel.isVisible }

    /// A second ⌥-shake while it's up puts it away.
    func toggle(at point: NSPoint) {
        isShowing ? hide(reason: "⌥-shake again") : show(at: point)
    }

    func show(at point: NSPoint) {
        items = store.library.recentItems(limit: Self.maxItems)
        title.font = UIScale.font(13, weight: .semibold)
        emptyLabel.font = UIScale.font(13)
        moreButton.font = UIScale.font(12)
        layout.itemSize = StashItemCell.tileSize
        gridTop?.constant = Self.padding + UIScale.pt(28)
        emptyLabel.isHidden = !items.isEmpty
        grid.reloadData()
        let size = Self.size(for: items.count)
        panel.setContentSize(size)
        panel.setFrameOrigin(Self.origin(near: point, size: size))
        panel.orderFrontRegardless()
        shownAt = .now
        watchForLeaving()
        Log.info("⌥-shake: grab shelf shown with \(items.count) item\(items.count == 1 ? "" : "s")")
    }

    func hide(reason: String) {
        guard isShowing else { return }
        stopWatching()
        panel.orderOut(nil)
        Log.info("Grab shelf hidden (\(reason))")
    }

    private static func size(for count: Int) -> NSSize {
        let tile = StashItemCell.tileSize
        let columns = max(1, min(count, Self.columns))
        let rows = max(1, Int(ceil(Double(count) / Double(Self.columns))))
        let header = UIScale.pt(28)
        let width = CGFloat(columns) * tile.width + CGFloat(columns - 1) * spacing + 2 * padding
        let gridHeight = count == 0 ? UIScale.pt(40) : CGFloat(rows) * tile.height + CGFloat(rows - 1) * spacing
        return NSSize(width: max(width, UIScale.pt(240)), height: header + gridHeight + 2 * padding)
    }

    /// Above the pointer, like the drop shelf; kept on screen.
    private static func origin(near point: NSPoint, size: NSSize) -> NSPoint {
        var origin = NSPoint(x: point.x - size.width / 2, y: point.y + 30)
        guard let screen = NSScreen.containing(point) else { return origin }
        let visible = screen.visibleFrame
        if origin.y + size.height > visible.maxY - 8 { origin.y = point.y - 30 - size.height }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        return origin
    }

    // MARK: Going away

    /// A click outside, or the pointer moving well away (not while dragging out).
    private func watchForLeaving() {
        stopWatching()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.hide(reason: "click elsewhere") }
        }) {
            monitors.append(global)
        }
        if let moves = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.hideIfFarAway() }
        }) {
            monitors.append(moves)
        }
    }

    private func hideIfFarAway() {
        guard !isDragging, ContinuousClock.now - shownAt > Self.grace,
              !panel.frame.insetBy(dx: -Self.reach, dy: -Self.reach).contains(NSEvent.mouseLocation) else { return }
        hide(reason: "pointer moved away")
    }

    private func stopWatching() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    @objc private func moreClicked() {
        let point = NSEvent.mouseLocation
        hide(reason: "More…")
        onMore?(point)
    }

    // MARK: Items

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(withIdentifier: StashItemCell.identifier, for: indexPath)
        (cell as? StashItemCell)?.configure(with: items[indexPath.item], thumbnails: thumbnails)
        return cell
    }

    func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
        true
    }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> (any NSPasteboardWriting)? {
        DragOut.writer(for: items[indexPath.item])
    }

    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
                        willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>) {
        isDragging = true
        let names = indexPaths.sorted().map { items[$0.item].name }.joined(separator: ", ")
        Log.info("Grab shelf: dragging out \(names)")
        for indexPath in indexPaths where CloudStatus.state(of: items[indexPath.item].url) == .cloudOnly {
            try? CloudStatus.startDownloading(items[indexPath.item].url)
        }
    }

    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
                        endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation) {
        isDragging = false
        Log.info(operation.isEmpty ? "Grab shelf: drag out ended, not taken" : "Grab shelf: drag out taken")
        guard !operation.isEmpty else { return }
        hide(reason: "dropped")
        onDraggedOut?(screenPoint)
    }

    // MARK: Building

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size(for: 1)),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

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
        grid.allowsMultipleSelection = false
        grid.backgroundColors = [.clear]
        grid.register(StashItemCell.self, forItemWithIdentifier: StashItemCell.identifier)
        grid.dataSource = self
        grid.delegate = self
        // Out to other apps as a copy; the item stays in Stash.
        grid.setDraggingSourceOperationMask(.copy, forLocal: false)
        grid.setDraggingSourceOperationMask([], forLocal: true)

        title.textColor = .secondaryLabelColor
        emptyLabel.textColor = .tertiaryLabelColor
        moreButton.bezelStyle = .accessoryBarAction
        moreButton.toolTip = "Open the panel"

        // A collection view lays out its items inside a scroll view; this one never scrolls.
        let scroll = NSScrollView()
        scroll.documentView = grid
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        for view in [title, moreButton, scroll, emptyLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }
        let p = Self.padding
        let gridTop = scroll.topAnchor.constraint(equalTo: background.topAnchor, constant: p + UIScale.pt(28))
        self.gridTop = gridTop
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: background.topAnchor, constant: p),
            title.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: p + 2),
            moreButton.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            moreButton.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -p),
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: p),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -p),
            scroll.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -p),
            gridTop,
            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
        ])
        panel.contentView = background
        return panel
    }
}
