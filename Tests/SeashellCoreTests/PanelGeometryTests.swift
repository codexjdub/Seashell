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
