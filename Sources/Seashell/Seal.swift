import AppKit
import SeashellCore

/// The app icon's shell pressed onto the right edge of Seashell's panels like a
/// seal: the pull-down panel, the grab shelf, the drop shelf and tear-off
/// shelves. It's the icon without its tile (Seal.png, made by make-icon.sh),
/// which would glare on a dark panel. About a third of it sticks out past the
/// edge. Sizes are at Small text, scaled.
@MainActor
enum Seal {
    static let size: CGFloat = 42
    /// The icon's frame past the panel's right edge; the artwork leaves a margin
    /// inside its frame, so about a third of what you see is outside.
    static let overhang: CGFloat = 15
    /// Room the window keeps past the panel's right edge for it.
    static let sideRoom: CGFloat = PanelGeometry.sideColumn
    /// It sits a fifth of the way down the right edge, on the panel and the shelves alike.
    static let shelfPosition: CGFloat = 0.2

    /// The shell and strands, or the app icon if the picture is missing.
    static var picture: NSImage {
        NSImage(named: "Seal") ?? NSApp.applicationIconImage
    }

    /// Clickable, for the panel and the grab shelf.
    static func button(target: AnyObject, action: Selector, toolTip: String) -> NSButton {
        let button = IconButton(image: picture, target: target, action: action)
        button.isBordered = false
        button.imageScaling = .scaleProportionallyUpOrDown
        button.toolTip = toolTip
        button.setAccessibilityLabel(toolTip)
        return button
    }

    /// Just the picture, for the drop shelf (it can't be clicked mid-drag).
    static func image() -> NSImageView {
        let view = NSImageView(image: picture)
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
    }

    /// Where its center sits below a shelf's top: a fifth of the way down, but
    /// never so high that it would stick out above a short shelf.
    static func centerOffset(inHeight height: CGFloat) -> CGFloat {
        max(height * shelfPosition, UIScale.pt(size) / 2 + 2)
    }
}
