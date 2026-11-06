import Foundation
import Testing
@testable import SeashellCore

struct CatPaceTests {
    /// Types `count` keys, `gap` seconds apart from `start`; the times it batted.
    private func type(_ count: Int, every gap: TimeInterval, from start: TimeInterval = 0, pace: inout CatPace) -> [TimeInterval] {
        (0..<count).compactMap { index in
            let time = start + Double(index) * gap
            return pace.key(at: time) ? time : nil
        }
    }

    @Test func batsOnceEnoughKeysHaveGoneBy() {
        var pace = CatPace()
        let bats = type(CatPace.keysPerBat, every: 0.5, pace: &pace)
        #expect(bats == [Double(CatPace.keysPerBat - 1) * 0.5])
    }

    @Test func fewerKeysNeverBat() {
        var pace = CatPace()
        #expect(type(CatPace.keysPerBat - 1, every: 1, pace: &pace).isEmpty)
    }

    @Test func fastTypingIsHeldBackToTheGap() {
        var pace = CatPace()
        // 10 keys a second for 10 seconds.
        let bats = type(100, every: 0.1, pace: &pace)
        #expect(!bats.isEmpty)
        for (earlier, later) in zip(bats, bats.dropFirst()) {
            #expect(later - earlier >= CatPace.minimumGap - 1e-9)
        }
        #expect(bats.count <= Int(10 / CatPace.minimumGap) + 1)
    }

    @Test func afterTheGapItStillWaitsForKeys() {
        var pace = CatPace()
        _ = type(CatPace.keysPerBat, every: 0.1, pace: &pace)
        // Long after, a single key isn't enough.
        let batted = pace.key(at: 100)
        #expect(!batted)
        let more = type(CatPace.keysPerBat - 1, every: 0.1, from: 100.1, pace: &pace)
        #expect(more.count == 1)
    }
}
