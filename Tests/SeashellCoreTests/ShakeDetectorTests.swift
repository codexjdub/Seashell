import Foundation
import Testing
@testable import SeashellCore

struct ShakeDetectorTests {
    /// Moves the pointer through `waypoints` in 5-point steps over `duration`
    /// seconds, starting at `start`. Returns the times at which a shake fired.
    static func shakes(_ detector: inout ShakeDetector, through waypoints: [Double],
                       over duration: TimeInterval, start: TimeInterval = 0) -> [TimeInterval] {
        var samples: [Double] = [waypoints[0]]
        for (from, to) in zip(waypoints, waypoints.dropFirst()) {
            let step = to > from ? 5.0 : -5.0
            samples += stride(from: from + step, through: to, by: step).map { $0 }
        }
        let interval = duration / Double(samples.count - 1)
        return samples.enumerated().compactMap { index, x in
            let time = start + Double(index) * interval
            return detector.add(x: x, at: time) ? time : nil
        }
    }

    @Test func quickSwingsShake() {
        var detector = ShakeDetector()
        #expect(Self.shakes(&detector, through: [0, 40, 0, 40, 0], over: 0.4).count == 1)
    }

    @Test func slowSwingsDoNot() {
        var detector = ShakeDetector()
        #expect(Self.shakes(&detector, through: [0, 40, 0, 40, 0], over: 3).isEmpty)
    }

    @Test func smallWigglesDoNot() {
        var detector = ShakeDetector()
        #expect(Self.shakes(&detector, through: [0, 10, 0, 10, 0, 10, 0], over: 0.4).isEmpty)
    }

    @Test func straightDragDoesNot() {
        var detector = ShakeDetector()
        #expect(Self.shakes(&detector, through: [0, 600], over: 0.4).isEmpty)
    }

    @Test func secondShakeRightAfterIsIgnored() {
        var detector = ShakeDetector()
        let fired = Self.shakes(&detector, through: [0, 40, 0, 40, 0, 40, 0, 40, 0, 40, 0], over: 0.8)
        #expect(fired.count == 1)
    }

    @Test func shakeWorksAgainAfterCooldown() {
        var detector = ShakeDetector()
        #expect(Self.shakes(&detector, through: [0, 40, 0, 40, 0], over: 0.4).count == 1)
        detector.reset()
        #expect(Self.shakes(&detector, through: [0, 40, 0, 40, 0], over: 0.4, start: 2).count == 1)
    }

    @Test func resetForgetsHalfAShake() {
        var detector = ShakeDetector()
        #expect(Self.shakes(&detector, through: [0, 40, 0, 40], over: 0.3).isEmpty)
        detector.reset()
        #expect(Self.shakes(&detector, through: [40, 0], over: 0.1, start: 0.3).isEmpty)
    }
}
