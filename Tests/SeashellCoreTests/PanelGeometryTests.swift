import CoreGraphics
import Testing
@testable import SeashellCore

struct PanelGeometryTests {
    @Test func centeredBelowMenuBar() {
        // A 1512-wide laptop screen, 33 pt menu bar.
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 949)
        let frame = PanelGeometry.frame(in: visible)
        #expect(frame.width == 1000)
        #expect(frame.height == 320)
        #expect(frame.midX == visible.midX)
        #expect(frame.maxY == visible.maxY - 8)
    }

    @Test func narrowScreenKeepsMargins() {
        let frame = PanelGeometry.frame(in: CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(frame.minX == 16)
        #expect(frame.maxX == 784)
    }

    @Test func secondDisplayWithNegativeCoordinates() {
        // An external display to the left of and above the main one.
        let visible = CGRect(x: -3440, y: 900, width: 3440, height: 1415)
        let frame = PanelGeometry.frame(in: visible)
        #expect(frame.midX == visible.midX)
        #expect(frame.maxY == visible.maxY - 8)
        #expect(visible.contains(frame))
    }

    @Test func hiddenFrameSitsAboveIt() {
        let frame = CGRect(x: 100, y: 500, width: 1000, height: 320)
        #expect(PanelGeometry.hiddenFrame(for: frame) == CGRect(x: 100, y: 820, width: 1000, height: 320))
    }

    @Test func remembersDraggedSizeScaledByText() {
        let visible = CGRect(x: 47, y: 0, width: 3393, height: 1410)
        let frame = PanelGeometry.frame(in: visible, scale: 1.5, size: CGSize(width: 1200, height: 400))
        #expect(frame.size == CGSize(width: 1800, height: 600))
        #expect(frame.midX == visible.midX)
        #expect(frame.maxY == visible.maxY - 8)
    }

    @Test func draggedSizeNeverBelowMinimum() {
        let visible = CGRect(x: 0, y: 0, width: 3000, height: 1400)
        let frame = PanelGeometry.frame(in: visible, size: CGSize(width: 100, height: 50))
        #expect(frame.size == PanelGeometry.minimumSize)
    }

    @Test func resizingKeepsTopAndCenter() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 949)
        let start = PanelGeometry.frame(in: visible)
        let bigger = PanelGeometry.resized(start, by: CGSize(width: 100, height: 60), scale: 1, in: visible)
        #expect(bigger.width == start.width + 100)
        #expect(bigger.height == start.height + 60)
        #expect(bigger.maxY == start.maxY)
        #expect(bigger.midX == visible.midX)
    }

    @Test func resizingStopsAtMinimumAndScreen() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 949)
        let start = PanelGeometry.frame(in: visible)
        let tiny = PanelGeometry.resized(start, by: CGSize(width: -5000, height: -5000), scale: 1, in: visible)
        #expect(tiny.size == PanelGeometry.minimumSize)
        let huge = PanelGeometry.resized(start, by: CGSize(width: 5000, height: 5000), scale: 1, in: visible)
        #expect(huge.width == visible.width - 32)
        #expect(huge.minY == visible.minY + 16)
    }

    @Test func leavesRoomForThePillOnNarrowScreens() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 900)
        let frame = PanelGeometry.frame(in: visible, sideSpace: 40)
        #expect(frame.width == CGFloat(1000 - 2 * (16 + 40)))
        #expect(frame.midX == visible.midX)
        let wider = PanelGeometry.resized(frame, by: CGSize(width: 500, height: 0), scale: 1, in: visible, sideSpace: 40)
        #expect(wider.width == frame.width)
    }

    @Test func splitMovesAndStaysInRange() {
        #expect(PanelGeometry.split(0.55, movedBy: 100, across: 1000) == 0.65)
        #expect(PanelGeometry.split(0.55, movedBy: -1000, across: 1000) == PanelGeometry.splitRange.lowerBound)
        #expect(PanelGeometry.split(0.55, movedBy: 1000, across: 1000) == PanelGeometry.splitRange.upperBound)
    }

    @Test func previewSitsBelowPanel() {
        let visible = CGRect(x: 47, y: 0, width: 3393, height: 1410)
        let panel = PanelGeometry.frame(in: visible)
        let preview = PanelGeometry.previewFrame(below: panel, in: visible)
        #expect(preview.size == CGSize(width: 720, height: 480))
        #expect(preview.midX == panel.midX)
        #expect(preview.maxY == panel.minY - 16)
    }

    @Test func previewShrinksOnShortScreen() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 700)
        let panel = PanelGeometry.frame(in: visible)  // leaves 700 − 8 − 320 below
        let preview = PanelGeometry.previewFrame(below: panel, in: visible)
        #expect(preview.height == panel.minY - 32)
        #expect(preview.minY == 16)
    }

    @Test func previewOverlapsWhenNoRoom() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 420)
        let panel = PanelGeometry.frame(in: visible)
        let preview = PanelGeometry.previewFrame(below: panel, in: visible)
        #expect(preview.height == PanelGeometry.previewMinHeight)
        #expect(preview.minY == 16)
        #expect(visible.contains(preview))
    }

    @Test func topEdge() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        #expect(PanelGeometry.isAtTopEdge(CGPoint(x: 700, y: 982), screenFrame: screen))
        #expect(PanelGeometry.isAtTopEdge(CGPoint(x: 700, y: 979), screenFrame: screen))
        #expect(!PanelGeometry.isAtTopEdge(CGPoint(x: 700, y: 970), screenFrame: screen))
        #expect(!PanelGeometry.isAtTopEdge(CGPoint(x: 1600, y: 982), screenFrame: screen), "on another screen")
    }

    @Test func springLoadZoneAvoidsCorners() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        #expect(PanelGeometry.isInSpringLoadZone(CGPoint(x: 756, y: 982), screenFrame: screen))
        #expect(!PanelGeometry.isInSpringLoadZone(CGPoint(x: 50, y: 982), screenFrame: screen))
        #expect(!PanelGeometry.isInSpringLoadZone(CGPoint(x: 1480, y: 982), screenFrame: screen))
        #expect(!PanelGeometry.isInSpringLoadZone(CGPoint(x: 756, y: 900), screenFrame: screen))
    }
}
