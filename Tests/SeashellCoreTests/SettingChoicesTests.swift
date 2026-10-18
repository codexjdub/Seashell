import Foundation
import Testing
@testable import SeashellCore

struct SettingChoicesTests {
    @Test func defaults() {
        #expect(Theme.standard == .system)
        #expect(LargeFileLimit.standard == .gb1)
        #expect(ShakeSensitivity.standard == .normal)
    }

    @Test func largeFileLimits() {
        #expect(LargeFileLimit.allCases.map(\.bytes) == [500_000_000, 1_000_000_000, 5_000_000_000, nil])
    }

    @Test func normalShakeIsTheOriginal() {
        let normal = ShakeSensitivity.normal.detector
        let original = ShakeDetector()
        #expect(normal?.reversalsNeeded == original.reversalsNeeded)
        #expect(normal?.minimumSwing == original.minimumSwing)
        #expect(normal?.window == original.window)
    }

    @Test func offWatchesNoShakes() {
        #expect(ShakeSensitivity.off.detector == nil)
    }

    @Test func gentleShakesWithLess() {
        let small: [Double] = [0, 20, 0, 20]
        var gentle = ShakeSensitivity.gentle.detector!
        #expect(ShakeDetectorTests.shakes(&gentle, through: small, over: 0.3).count == 1)
        var normal = ShakeSensitivity.normal.detector!
        #expect(ShakeDetectorTests.shakes(&normal, through: small, over: 0.3).isEmpty)
    }

    @Test func firmNeedsMore() {
        var firm = ShakeSensitivity.firm.detector!
        #expect(ShakeDetectorTests.shakes(&firm, through: [0, 40, 0, 40, 0], over: 0.4).isEmpty)
        firm.reset()
        #expect(ShakeDetectorTests.shakes(&firm, through: [0, 40, 0, 40, 0, 40], over: 0.5, start: 10).count == 1)
    }
}
