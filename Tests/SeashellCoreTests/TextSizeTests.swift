import CoreGraphics
import Testing
@testable import SeashellCore

struct TextSizeTests {
    @Test func mediumIsTheDefault() {
        #expect(TextSize.standard == .medium)
    }

    @Test func stepsGoUpAndDownAndStopAtTheEnds() {
        #expect(TextSize.small.larger == .medium)
        #expect(TextSize.large.larger == .extraLarge)
        #expect(TextSize.extraLarge.larger == .extraLarge)
        #expect(TextSize.medium.smaller == .small)
        #expect(TextSize.small.smaller == .small)
    }

    @Test func scalesGrow() {
        #expect(TextSize.allCases.map(\.scale) == [1.0, 1.15, 1.3, 1.5])
    }

    @Test func panelGrowsWithTextUpToTheScreen() {
        let big = CGRect(x: 47, y: 0, width: 3393, height: 1410)
        let frame = PanelGeometry.frame(in: big, scale: 1.5)
        #expect(frame.size == CGSize(width: 1500, height: 480))
        #expect(frame.midX == big.midX)

        let small = CGRect(x: 0, y: 0, width: 1200, height: 500)
        let clamped = PanelGeometry.frame(in: small, scale: 1.5)
        #expect(clamped.width == CGFloat(1200 - 32))
        #expect(clamped.height == CGFloat(500 - 32))
        #expect(small.contains(clamped))
    }
}
