import AppKit
import SeashellCore

/// The small shelf that pops up next to the pointer when you shake during a drag.
/// For now it has one zone, Stash (Copy and Cut join it in Milestone 6). It hides
/// about a second after the mouse is released, whether or not you dropped on it.
@MainActor
final class FloatingShelf {
    private static let size = NSSize(width: 170, height: 110)

    private let store: StashStore
    private let dropper: StashDropper
    private lazy var stashZone = DropZoneView(title: "Stash", symbol: "tray.and.arrow.down") { [weak self] info in
        self?.stash(info) ?? false
    }
    private lazy var panel = makePanel()
    private var hideTask: Task<Void, Never>?

    init(store: StashStore, dropper: StashDropper) {
        self.store = store
        self.dropper = dropper
    }

    func show(at point: NSPoint) {
        stashZone.reset()
        panel.setFrameOrigin(origin(near: point))
        panel.orderFrontRegardless()
        Log.info("Shake: floating shelf shown")
        hideAfterRelease()
    }

    private func stash(_ info: any NSDraggingInfo) -> Bool {
        guard let main = store.defaultShelf else {
            Log.error("No \(SeashellFolders.defaultShelfName) shelf to stash into")
            return false
        }
        return dropper.accept(info, into: main.url)
    }

    /// Above the pointer, so it doesn't sit under what's being dragged; kept on screen.
    private func origin(near point: NSPoint) -> NSPoint {
        let size = Self.size
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
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
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

        stashZone.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stashZone)
        NSLayoutConstraint.activate([
            stashZone.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 10),
            stashZone.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -10),
            stashZone.topAnchor.constraint(equalTo: background.topAnchor, constant: 10),
            stashZone.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -10),
        ])
        panel.contentView = background
        return panel
    }
}

/// A labelled drop target that highlights while something hovers over it and
/// shows a check mark once it has taken a drop.
@MainActor
final class DropZoneView: NSView {
    private let title: String
    private let onDrop: (any NSDraggingInfo) -> Bool
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let symbol: String

    init(title: String, symbol: String, onDrop: @escaping (any NSDraggingInfo) -> Bool) {
        self.title = title
        self.symbol = symbol
        self.onDrop = onDrop
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1.5
        layer?.borderColor = NSColor.tertiaryLabelColor.cgColor

        icon.symbolConfiguration = .init(pointSize: 24, weight: .regular)
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        let stack = NSStackView(views: [icon, label])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        registerForDraggedTypes(StashDropper.acceptedTypes)
        reset()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func reset() {
        show(symbol: symbol, text: title)
        setHighlighted(false)
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
        return StashDropper.operation(for: sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        StashDropper.operation(for: sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        setHighlighted(false)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        setHighlighted(false)
        let accepted = onDrop(sender)
        if accepted { show(symbol: "checkmark.circle.fill", text: "Stashed") }
        return accepted
    }
}
