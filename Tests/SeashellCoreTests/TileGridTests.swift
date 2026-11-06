import CoreGraphics
import Testing
@testable import SeashellCore

struct TileGridTests {
    // Tiles 100 points across with 10 between them: 1 → 100, 2 → 210, 3 → 320.

    @Test func lengthCountsTheGapsBetweenTiles() {
        #expect(TileGrid.length(of: 1, tile: 100, spacing: 10) == 100)
        #expect(TileGrid.length(of: 3, tile: 100, spacing: 10) == 320)
        #expect(TileGrid.length(of: 0, tile: 100, spacing: 10) == 0)
    }

    @Test func nearestCountsATilePastHalfway() {
        #expect(TileGrid.count(nearest: 210, tile: 100, spacing: 10, maximum: 10) == 2)
        #expect(TileGrid.count(nearest: 264, tile: 100, spacing: 10, maximum: 10) == 2)
        #expect(TileGrid.count(nearest: 266, tile: 100, spacing: 10, maximum: 10) == 3)
        #expect(TileGrid.count(nearest: 154, tile: 100, spacing: 10, maximum: 10) == 1)
    }

    @Test func nearestStaysBetweenOneAndTheMaximum() {
        #expect(TileGrid.count(nearest: -500, tile: 100, spacing: 10, maximum: 10) == 1)
        #expect(TileGrid.count(nearest: 5000, tile: 100, spacing: 10, maximum: 4) == 4)
        #expect(TileGrid.count(nearest: 5000, tile: 100, spacing: 10, maximum: 0) == 1)
    }

    @Test func fittingNeverGoesOver() {
        #expect(TileGrid.count(fitting: 319, tile: 100, spacing: 10) == 2)
        #expect(TileGrid.count(fitting: 320, tile: 100, spacing: 10) == 3)
        #expect(TileGrid.count(fitting: 50, tile: 100, spacing: 10) == 1)
    }

    @Test func aCountsLengthComesBackToTheSameCount() {
        for count in 1...12 {
            let length = TileGrid.length(of: count, tile: 106, spacing: 6)
            #expect(TileGrid.count(nearest: length, tile: 106, spacing: 6, maximum: 99) == count)
            #expect(TileGrid.count(fitting: length, tile: 106, spacing: 6) == count)
        }
    }
}
