import Foundation
import Testing
@testable import SeashellCore

struct EdgeScrollDetectorTests {
    /// Feeds equal scroll steps, `interval` seconds apart. Returns every gesture recognised.
    static func scroll(_ detector: inout EdgeScrollDetector, steps: [Double], precise: Bool,
                       interval: TimeInterval = 0.02, start: TimeInterval = 0) -> [EdgeScrollDetector.Gesture] {
        steps.enumerated().compactMap { index, amount in
            detector.add(downward: amount, precise: precise, at: start + Double(index) * interval)
        }
    }

    @Test func trackpadPullDown() {
        var detector = EdgeScrollDetector()
        #expect(Self.scroll(&detector, steps: [10, 10, 10, 10], precise: true) == [.pullDown])
    }

    @Test func shortTrackpadSwipeDoesNothing() {
        var detector = EdgeScrollDetector()
        #expect(Self.scroll(&detector, steps: [10, 10, 10], precise: true).isEmpty)
    }

    @Test func slowTrackpadScrollDoesNothing() {
        var detector = EdgeScrollDetector()
        #expect(Self.scroll(&detector, steps: [10, 10, 10, 10, 10], precise: true, interval: 0.3).isEmpty)
    }

    @Test func trackpadPushUp() {
        var detector = EdgeScrollDetector()
        #expect(Self.scroll(&detector, steps: [-20, -25], precise: true) == [.pushUp])
    }

    @Test func wheelNeedsTwoClicks() {
        var detector = EdgeScrollDetector()
        #expect(Self.scroll(&detector, steps: [0.1], precise: false).isEmpty)
        detector = EdgeScrollDetector()
        #expect(Self.scroll(&detector, steps: [0.1, 0.1], precise: false) == [.pullDown])
    }

    @Test func changingDirectionStartsOver() {
        var detector = EdgeScrollDetector()
        #expect(Self.scroll(&detector, steps: [30, -30, 30], precise: true).isEmpty)
    }

    @Test func oneLongSwipeFiresOnce() {
        var detector = EdgeScrollDetector()
        #expect(Self.scroll(&detector, steps: Array(repeating: 10, count: 20), precise: true) == [.pullDown])
    }

    @Test func worksAgainAfterCooldown() {
        var detector = EdgeScrollDetector()
        #expect(Self.scroll(&detector, steps: [20, 20], precise: true) == [.pullDown])
        #expect(Self.scroll(&detector, steps: [-20, -20], precise: true, start: 1) == [.pushUp])
    }

    @Test func physicalDirectionIgnoresNaturalScrolling() {
        // Fingers moving down: natural scrolling reports +deltaY, classic scrolling −deltaY.
        #expect(EdgeScrollDetector.downward(deltaY: 12, invertedFromDevice: true) == 12)
        #expect(EdgeScrollDetector.downward(deltaY: -12, invertedFromDevice: false) == 12)
    }
}
