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

    /// Centered horizontally, just below the menu bar. `visibleFrame` is the
    /// screen's area without the menu bar and Dock.
    public static func frame(in visibleFrame: CGRect) -> CGRect {
        let width = min(maxWidth, visibleFrame.width - 2 * margin)
        let height = min(height, visibleFrame.height - 2 * margin)
        return CGRect(x: visibleFrame.midX - width / 2,
                      y: visibleFrame.maxY - margin / 2 - height,
                      width: width, height: height)
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
