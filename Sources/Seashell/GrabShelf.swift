import AppKit
import SeashellCore

/// Watches for a shake of the pointer with ⌥ held and no mouse button down:
/// the gesture for the grab shelf. ⌥ keeps it from firing when you shake the
/// pointer just to find it (macOS enlarges the pointer on a plain shake).
///
/// It listens for ⌥ and follows the pointer only while ⌥ is held: watching
/// every mouse move would wake Seashell over 100 times a second whenever the
/// pointer moves. (Hearing modifier keys needs no Accessibility permission.)
@MainActor
final class OptionShakeWatcher {
    var onShake: ((NSPoint) -> Void)?

    /// Nil when shaking is off in Settings.
    private var detector: ShakeDetector?
    private var keyMonitors: [Any] = []
    private var pointerMonitors: [Any] = []

    /// Starts watching, or stops altogether when shaking is off.
    func setShakeSensitivity(_ sensitivity: ShakeSensitivity) {
        detector = sensitivity.detector
        detector == nil ? stop() : start()
    }

    private func start() {
        guard keyMonitors.isEmpty else { return }
        keyMonitors = Self.monitor(.flagsChanged) { [weak self] in self?.modifiersChanged($0) }
        Log.info(keyMonitors.count == 2 ? "Watching for ⌥-shake" : "Couldn’t watch for ⌥; ⌥-shake won’t open the grab shelf")
    }

    private func stop() {
        guard !keyMonitors.isEmpty else { return }
        stopFollowingPointer()
        keyMonitors.forEach(NSEvent.removeMonitor)
        keyMonitors = []
        Log.info("Stopped watching for ⌥-shake (shaking is off)")
    }

    private func modifiersChanged(_ event: NSEvent) {
        Self.isOptionAlone(event) ? followPointer() : stopFollowingPointer()
    }

    private func followPointer() {
        guard pointerMonitors.isEmpty else { return }
        detector?.reset()
        pointerMonitors = Self.monitor(.mouseMoved) { [weak self] in self?.pointerMoved($0) }
    }

    private func stopFollowingPointer() {
        pointerMonitors.forEach(NSEvent.removeMonitor)
        pointerMonitors = []
    }

    private func pointerMoved(_ event: NSEvent) {
        // ⌥ can be let go unheard, e.g. while a password field has the keyboard.
        guard Self.isOptionAlone(event) else { return stopFollowingPointer() }
        let point = NSEvent.mouseLocation
        if detector?.add(x: point.x, at: event.timestamp) == true {
            onShake?(point)
        }
    }

    private static func isOptionAlone(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection([.command, .shift, .option, .control]) == .option
    }

    /// Global for events in other apps; local for Seashell's own windows.
    private static func monitor(_ events: NSEvent.EventTypeMask, _ handle: @escaping @MainActor (NSEvent) -> Void) -> [Any] {
        let global = NSEvent.addGlobalMonitorForEvents(matching: events) { event in
            MainActor.assumeIsolated { handle(event) }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: events) { event in
            MainActor.assumeIsolated { handle(event) }
            return event
        }
        return [global, local].compactMap { $0 }
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
    /// The seal on its edge opens Settings, like the panel's.
    var onSettings: (() -> Void)?
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
    private lazy var seal = Seal.button(target: self, action: #selector(sealClicked), toolTip: "Seashell Settings")
    /// Sizes around the seal, written at Small and scaled with the text.
    private var sealConstraints: [(constraint: NSLayoutConstraint, base: CGFloat)] = []
    private var sealCenter: NSLayoutConstraint?
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
        _ = panel  // built first, so its seal constraints exist to size
        let shelf = Self.size(for: items.count)
        for (constraint, base) in sealConstraints { constraint.constant = UIScale.pt(base) }
        sealCenter?.constant = Seal.centerOffset(inHeight: shelf.height)
        // The window is a little wider than the shelf, for the seal on its edge.
        let size = NSSize(width: shelf.width + UIScale.pt(Seal.sideRoom), height: shelf.height)
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
        // All of them at once, never scrolling; a couple of points spare so rounding
        // at any text size can't push a column or row out.
        let width = CGFloat(columns) * tile.width + CGFloat(columns - 1) * spacing + 2 * padding + 2
        let gridHeight = count == 0 ? UIScale.pt(40) : CGFloat(rows) * tile.height + CGFloat(rows - 1) * spacing + 2
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

    @objc private func sealClicked() {
        hide(reason: "seal clicked")
        onSettings?()
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
        // Over the pull-down panel. Floating first: setting it resets the level.
        panel.isFloatingPanel = true
        panel.level = PanelController.shelfLevel
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

        // A collection view lays out its items inside a scroll view; this one is
        // sized to show them all and never scrolls or bounces.
        let scroll = FixedScrollView()
        scroll.documentView = grid
        scroll.drawsBackground = false
        scroll.verticalScrollElasticity = .none
        scroll.horizontalScrollElasticity = .none
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
        let sealCenter = seal.centerYAnchor.constraint(equalTo: background.topAnchor, constant: 60)
        self.sealCenter = sealCenter
        NSLayoutConstraint.activate(sealConstraints.map(\.constraint) + [
            background.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            background.topAnchor.constraint(equalTo: container.topAnchor),
            background.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            sealCenter,
        ])
        panel.contentView = container
        return panel
    }
}

/// A scroll view that never shows scroll bars or scrolls. The collection view
/// turns its scroll bar back on as it lays out, and with a mouse connected
/// that bar takes room from the grid, squeezing it to three columns.
final class FixedScrollView: NSScrollView {
    override var hasVerticalScroller: Bool {
        get { false }
        set {}
    }

    override var hasHorizontalScroller: Bool {
        get { false }
        set {}
    }

    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}
