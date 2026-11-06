import AppKit
import SeashellCore

/// An invisible strip you drag to resize something: the panel's edges, the
/// gap between its cards, or a tear-off shelf's edges and corners. Shows a
/// resize pointer and reports how far you drag.
@MainActor
final class DragHandle: NSView {
    enum Direction {
        case horizontal
        case vertical
        /// A window's edge or corner, with the pointer macOS shows there.
        case frame(NSCursor.FrameResizePosition)
    }

    /// Movement since the last call, in points; y grows downward.
    var onDrag: ((_ dx: CGFloat, _ dy: CGFloat) -> Void)?
    var onEnd: (() -> Void)?

    private let direction: Direction

    init(_ direction: Direction) {
        self.direction = direction
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // .activeAlways: Seashell is never the active app while the panel is up.
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.cursorUpdate, .activeAlways, .inVisibleRect], owner: self))
    }

    override func cursorUpdate(with event: NSEvent) {
        switch direction {
        case .horizontal: NSCursor.columnResize.set()
        case .vertical: NSCursor.rowResize.set()
        case .frame(let position): NSCursor.frameResize(position: position, directions: .all).set()
        }
    }

    /// Floating shelves are rarely the key window: the first drag resizes.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// In a window that moves by its background, dragging here resizes instead.
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {}

    override func mouseDragged(with event: NSEvent) {
        onDrag?(event.deltaX, event.deltaY)
    }

    override func mouseUp(with event: NSEvent) {
        onEnd?()
    }
}

/// Where the panel's dragged sizes (per display, measured at Small text) and
/// the Stash / Notes split are remembered on this Mac.
@MainActor
enum PanelLayoutMemory {
    private static let sizesKey = "panelSizes"
    private static let splitKey = "panelSplit"

    static func size(on screen: NSScreen) -> CGSize? {
        guard let sizes = UserDefaults.standard.dictionary(forKey: sizesKey) as? [String: [Double]],
              let size = sizes[screen.localizedName], size.count == 2 else { return nil }
        return CGSize(width: size[0], height: size[1])
    }

    static func setSize(_ size: CGSize, on screen: NSScreen) {
        var sizes = UserDefaults.standard.dictionary(forKey: sizesKey) as? [String: [Double]] ?? [:]
        sizes[screen.localizedName] = [Double(size.width), Double(size.height)]
        UserDefaults.standard.set(sizes, forKey: sizesKey)
    }

    static var split: CGFloat {
        get {
            let stored = UserDefaults.standard.double(forKey: splitKey)
            return stored == 0 ? PanelGeometry.defaultSplit : CGFloat(stored)
        }
        set { UserDefaults.standard.set(Double(newValue), forKey: splitKey) }
    }
}
