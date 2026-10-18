import AppKit
import SeashellCore

/// The small shelf that pops up next to the pointer when you shake during a drag:
/// one zone per shelf, in the panel's tab order (Main first), `maxShelves` at a
/// time. With more shelves, holding the drag over More… shows the next ones,
/// and on the last page it goes back to the start. It hides about a second
/// after the mouse is released, whether or not you dropped on it.
@MainActor
final class FloatingShelf {
    static let maxShelves = 5
    /// Sizes at Small, scaled with the text (except the padding).
    private static let width: CGFloat = 180
    private static let zoneHeight: CGFloat = 40
    private static let spacing: CGFloat = 6
    private static let padding: CGFloat = 10
    /// Holding a drag over More… this long shows the next shelves.
    private static let moreDelay: Duration = .milliseconds(400)

    private let store: StashStore
    private let dropper: StashDropper
    private let zones = NSStackView()
    /// Stays put while the pages change, so it keeps the drag that's over it
    /// and doesn't flip again until you move off it and back.
    private lazy var moreZone = DropZoneView(title: "More…", symbol: "ellipsis.circle", holdDelay: Self.moreDelay,
                                             onHold: { [weak self] in self?.nextPage() },
                                             onDrop: { _ in false })
    private lazy var panel = makePanel()
    private var hideTask: Task<Void, Never>?
    /// The shelves when the shelf appeared, and which `maxShelves` of them show.
    private var shelves: [Shelf] = []
    private var page = 0

    init(store: StashStore, dropper: StashDropper) {
        self.store = store
        self.dropper = dropper
    }

    func show(at point: NSPoint) {
        shelves = store.shelves
        page = 0
        zones.spacing = UIScale.pt(Self.spacing)
        moreZone.reset()
        showPage()
        let size = Self.size(zones: isPaged ? Self.maxShelves + 1 : shelves.count)
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(near: point, size: size))
        panel.orderFrontRegardless()
        Log.info("Shake: floating shelf shown with \(shelves.count) shelves\(isPaged ? " on \(pageCount) pages" : "")")
        hideAfterRelease()
    }

    private var pageCount: Int { max(1, (shelves.count + Self.maxShelves - 1) / Self.maxShelves) }
    private var isPaged: Bool { pageCount > 1 }

    /// Every page keeps the first page's size (a short last page gets empty
    /// slots), so More… stays under the pointer.
    private func showPage() {
        let onPage = Array(shelves.dropFirst(page * Self.maxShelves).prefix(Self.maxShelves))
        var views: [NSView] = onPage.map { shelf in
            DropZoneView(title: shelf.name, symbol: "tray.and.arrow.down") { [weak self] info in
                self?.stash(info, into: shelf) ?? false
            }
        }
        if isPaged {
            views += (onPage.count..<Self.maxShelves).map { _ in NSView() }
        }
        for view in zones.arrangedSubviews where view !== moreZone { view.removeFromSuperview() }
        for (index, view) in views.enumerated() { zones.insertArrangedSubview(view, at: index) }
        if isPaged {
            let isLast = page == pageCount - 1
            moreZone.setTitle(isLast ? "Back to \(SeashellFolders.defaultShelfName)…" : "More…",
                              symbol: isLast ? "arrow.uturn.backward.circle" : "ellipsis.circle")
            if moreZone.superview == nil { zones.addArrangedSubview(moreZone) }
        } else {
            moreZone.removeFromSuperview()
        }
    }

    private func nextPage() {
        page = (page + 1) % pageCount
        showPage()
        Log.info("Floating shelf: More… shows page \(page + 1) of \(pageCount)")
    }

    /// The zones share the height equally.
    private static func size(zones: Int) -> NSSize {
        let stack = CGFloat(zones) * zoneHeight + CGFloat(max(zones - 1, 0)) * spacing
        return NSSize(width: UIScale.pt(width), height: 2 * padding + UIScale.pt(stack))
    }

    private func stash(_ info: any NSDraggingInfo, into shelf: Shelf) -> Bool {
        Log.info("Floating shelf: dropped into \(shelf.name)")
        return dropper.accept(info, into: shelf.url)
    }

    /// Above the pointer, so it doesn't sit under what's being dragged; kept on screen.
    private func origin(near point: NSPoint, size: NSSize) -> NSPoint {
        var origin = NSPoint(x: point.x - size.width / 2, y: point.y + 40)
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) else { return origin }
        let visible = screen.visibleFrame
        if origin.y + size.height > visible.maxY - 8 { origin.y = point.y - 40 - size.height }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        return origin
    }

    /// The drag may end anywhere, even outside every app, so check the button
    /// while the shelf is up rather than wait for an event. Then hide a second later.
    private func hideAfterRelease() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            while NSEvent.pressedMouseButtons & 1 != 0 {
                try? await Task.sleep(for: .milliseconds(150))
                if Task.isCancelled { return }
            }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.panel.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size(zones: 1)),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true

        zones.orientation = .vertical
        zones.distribution = .fillEqually
        zones.alignment = .width
        zones.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(zones)
        NSLayoutConstraint.activate([
            zones.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: Self.padding),
            zones.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -Self.padding),
            zones.topAnchor.constraint(equalTo: background.topAnchor, constant: Self.padding),
            zones.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -Self.padding),
        ])
        panel.contentView = background
        return panel
    }
}

/// A labelled drop target, a row with an icon and a name, that highlights while
/// something hovers over it and shows a check mark once it has taken a drop.
/// With `onHold`, holding a drag over it for `holdDelay` calls that instead.
@MainActor
final class DropZoneView: NSView {
    private var title: String
    private let onDrop: (any NSDraggingInfo) -> Bool
    private let onHold: (() -> Void)?
    private let holdDelay: Duration
    private var holdTask: Task<Void, Never>?
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var symbol: String

    init(title: String, symbol: String, holdDelay: Duration = .zero, onHold: (() -> Void)? = nil,
         onDrop: @escaping (any NSDraggingInfo) -> Bool) {
        self.title = title
        self.symbol = symbol
        self.holdDelay = holdDelay
        self.onHold = onHold
        self.onDrop = onDrop
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1.5
        layer?.borderColor = NSColor.tertiaryLabelColor.cgColor

        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        registerForDraggedTypes(StashDropper.acceptedTypes)
        reset()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func reset() {
        icon.symbolConfiguration = .init(pointSize: UIScale.pt(16), weight: .regular)
        label.font = UIScale.font(14, weight: .semibold)
        show(symbol: symbol, text: title)
        setHighlighted(false)
    }

    func setTitle(_ title: String, symbol: String) {
        self.title = title
        self.symbol = symbol
        show(symbol: symbol, text: title)
    }

    private func show(symbol: String, text: String) {
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: text)
        label.stringValue = text
    }

    private func setHighlighted(_ on: Bool) {
        layer?.backgroundColor = on ? NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor : nil
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        setHighlighted(true)
        if let onHold {
            holdTask = Task { [weak self, holdDelay] in
                try? await Task.sleep(for: holdDelay)
                guard !Task.isCancelled else { return }
                self?.setHighlighted(false)
                onHold()
            }
        }
        return StashDropper.operation(for: sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        StashDropper.operation(for: sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        holdTask?.cancel()
        setHighlighted(false)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        holdTask?.cancel()
        setHighlighted(false)
        let accepted = onDrop(sender)
        if accepted { show(symbol: "checkmark.circle.fill", text: "Stashed") }
        return accepted
    }
}
