import AppKit
import SeashellCore

/// The app icon pressed onto the right edge of Seashell's panels like a seal:
/// the pull-down panel, the grab shelf and the drop shelf. About a third of the
/// visible icon sticks out past the edge. Sizes are at Small text, scaled.
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

    /// Clickable, for the panel and the grab shelf.
    static func button(target: AnyObject, action: Selector, toolTip: String) -> NSButton {
        let button = IconButton(image: NSApp.applicationIconImage, target: target, action: action)
        button.isBordered = false
        button.imageScaling = .scaleProportionallyUpOrDown
        button.toolTip = toolTip
        button.setAccessibilityLabel(toolTip)
        return button
    }

    /// Just the picture, for the drop shelf (it can't be clicked mid-drag).
    static func image() -> NSImageView {
        let view = NSImageView(image: NSApp.applicationIconImage)
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
    }

    /// Where its center sits below a shelf's top: a fifth of the way down, but
    /// never so high that it would stick out above a short shelf.
    static func centerOffset(inHeight height: CGFloat) -> CGFloat {
        max(height * shelfPosition, UIScale.pt(size) / 2 + 2)
    }
}
