import CoreGraphics

/// Whole tiles along one side of a grid, with a gap between each two: how a
/// tear-off shelf's width and height follow a drag, a column or row at a time.
public enum TileGrid {
    /// The points `count` tiles take, gaps included.
    public static func length(of count: Int, tile: CGFloat, spacing: CGFloat) -> CGFloat {
        CGFloat(count) * tile + CGFloat(max(count - 1, 0)) * spacing
    }

    /// How many tiles come nearest to filling `length`: past halfway to the
    /// next tile counts it. From 1 up to `maximum`.
    public static func count(nearest length: CGFloat, tile: CGFloat, spacing: CGFloat, maximum: Int) -> Int {
        let count = Int(((length + spacing) / (tile + spacing)).rounded())
        return min(max(count, 1), max(maximum, 1))
    }

    /// The most whole tiles that fit in `length`; at least 1, even if it doesn't fit.
    public static func count(fitting length: CGFloat, tile: CGFloat, spacing: CGFloat) -> Int {
        max(Int(((length + spacing) / (tile + spacing)).rounded(.down)), 1)
    }
}
