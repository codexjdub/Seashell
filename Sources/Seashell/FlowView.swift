import AppKit

/// Lays `views` out left to right in rows of `rowHeight`, wrapping onto another
/// row when the next one doesn't fit, like words in a paragraph. Its height
/// follows the number of rows.
final class FlowView: NSView {
    var views: [NSView] = [] {
        didSet {
            for old in oldValue where !views.contains(where: { $0 === old }) { old.removeFromSuperview() }
            for view in views where view.superview !== self {
                view.translatesAutoresizingMaskIntoConstraints = true
                addSubview(view)
            }
            needsLayout = true
        }
    }
    var spacing: CGFloat = 6 {
        didSet { needsLayout = true }
    }
    var rowSpacing: CGFloat = 6 {
        didSet { invalidateIntrinsicContentSize() }
    }
    var rowHeight: CGFloat = 28 {
        didSet { invalidateIntrinsicContentSize() }
    }
    private var rows = 1

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: CGFloat(rows) * rowHeight + CGFloat(rows - 1) * rowSpacing)
    }

    override func layout() {
        super.layout()
        var x: CGFloat = 0
        var row = 0
        for view in views {
            let size = view.fittingSize
            if x > 0, x + size.width > bounds.width {
                x = 0
                row += 1
            }
            // Centered in its row.
            let y = CGFloat(row) * (rowHeight + rowSpacing) + ((rowHeight - size.height) / 2).rounded()
            view.frame = NSRect(x: x, y: y, width: min(size.width, bounds.width), height: size.height)
            x += size.width + spacing
        }
        if row + 1 != rows {
            rows = row + 1
            invalidateIntrinsicContentSize()
        }
    }
}
