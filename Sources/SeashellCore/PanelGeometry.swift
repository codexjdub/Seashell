import CoreGraphics

/// Where the pull-down panel goes, and where the top edge counts as "the top edge".
public enum PanelGeometry {
    public static let maxWidth: CGFloat = 1000
    public static let height: CGFloat = 320
    /// Gap between the menu bar and the panel, and the panel and the screen's sides.
    public static let margin: CGFloat = 16
    /// The pointer counts as at the top edge within this many points of it.
    public static let topEdgeTolerance: CGFloat = 4
    /// Holding a drag at the top edge opens the panel, but not this close to a
    /// corner, where hot corners live.
    public static let cornerMargin: CGFloat = 100

    /// The smallest you can drag the panel to, at Small text (scaled like the rest).
    public static let minimumSize = CGSize(width: 640, height: 220)
    /// Stash's share of the width; the rest is Notes.
    public static let defaultSplit: CGFloat = 0.55
    public static let splitRange: ClosedRange<CGFloat> = 0.3...0.75
    /// How far the app icon and the pin-and-close pill stick out past the
    /// panel's right edge, at Small text. The window keeps this much room on
    /// both sides, so the panel stays centered.
    public static let sideColumn: CGFloat = 16

    /// The panel itself (not the window around it, which has `sideSpace` more
    /// on each side): centered horizontally, just below the menu bar.
    /// `visibleFrame` is the screen's area without the menu bar and Dock.
    /// `size` is the size you dragged it to on this display, if any, measured
    /// at Small text; `scale` follows the text size. Never bigger than the
    /// screen allows.
    public static func frame(in visibleFrame: CGRect, scale: CGFloat = 1, size: CGSize? = nil, sideSpace: CGFloat = 0) -> CGRect {
        let base = size ?? CGSize(width: maxWidth, height: height)
        let width = min(max(base.width, minimumSize.width) * scale, visibleFrame.width - 2 * (margin + sideSpace))
        let height = min(max(base.height, minimumSize.height) * scale, visibleFrame.height - 2 * margin)
        return CGRect(x: visibleFrame.midX - width / 2,
                      y: visibleFrame.maxY - margin / 2 - height,
                      width: width, height: height)
    }

    /// The panel after dragging an edge. Width changes on both sides, so it stays
    /// centered; the top stays under the menu bar. Kept between the minimum
    /// size and the screen.
    public static func resized(_ frame: CGRect, by delta: CGSize, scale: CGFloat, in visibleFrame: CGRect,
                               sideSpace: CGFloat = 0) -> CGRect {
        let width = min(max(frame.width + delta.width, minimumSize.width * scale), visibleFrame.width - 2 * (margin + sideSpace))
        let height = min(max(frame.height + delta.height, minimumSize.height * scale), frame.maxY - visibleFrame.minY - margin)
        return CGRect(x: visibleFrame.midX - width / 2, y: frame.maxY - height, width: width, height: height)
    }

    /// Stash's share after dragging the gap between the cards by `dx` points.
    public static func split(_ fraction: CGFloat, movedBy dx: CGFloat, across width: CGFloat) -> CGFloat {
        guard width > 0 else { return fraction }
        return min(max(fraction + dx / width, splitRange.lowerBound), splitRange.upperBound)
    }

    /// Where the panel slides from: the same frame, raised by its height, so it
    /// comes out from under the menu bar.
    public static func hiddenFrame(for frame: CGRect) -> CGRect {
        frame.offsetBy(dx: 0, dy: frame.height)
    }

    public static let previewMaxSize = CGSize(width: 720, height: 480)
    public static let previewMinHeight: CGFloat = 200

    /// The preview window: centered below the panel, as big as fits up to
    /// `previewMaxSize`. If there's too little room below, it sits at the bottom
    /// of the screen and overlaps the panel.
    public static func previewFrame(below panel: CGRect, in visibleFrame: CGRect) -> CGRect {
        let width = min(previewMaxSize.width, panel.width, visibleFrame.width - 2 * margin)
        let room = panel.minY - visibleFrame.minY - 2 * margin
        let height = min(previewMaxSize.height, max(room, previewMinHeight), visibleFrame.height - 2 * margin)
        let x = min(max(panel.midX - width / 2, visibleFrame.minX + margin), visibleFrame.maxX - margin - width)
        let y = max(panel.minY - margin - height, visibleFrame.minY + margin)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Whether `point` is on the screen's top edge. `screenFrame` is the whole screen.
    public static func isAtTopEdge(_ point: CGPoint, screenFrame: CGRect) -> Bool {
        point.x >= screenFrame.minX && point.x < screenFrame.maxX
            && point.y <= screenFrame.maxY && screenFrame.maxY - point.y <= topEdgeTolerance
    }

    /// Top edge, but not near either corner.
    public static func isInSpringLoadZone(_ point: CGPoint, screenFrame: CGRect) -> Bool {
        isAtTopEdge(point, screenFrame: screenFrame)
            && point.x - screenFrame.minX >= cornerMargin
            && screenFrame.maxX - point.x >= cornerMargin
    }
}
