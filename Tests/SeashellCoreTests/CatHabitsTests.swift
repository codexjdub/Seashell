import Foundation
import Testing
@testable import SeashellCore

struct PetStreakTests {
    @Test func thirdQuickPetKneads() {
        var streak = PetStreak()
        let first = streak.pet(at: 0), second = streak.pet(at: 1), third = streak.pet(at: 2)
        #expect(!first && !second && third)
    }

    @Test func slowPetsNeverKnead() {
        var streak = PetStreak()
        let kneads = (0..<10).map { streak.pet(at: Double($0) * PetStreak.window) }
        #expect(!kneads.contains(true))
    }

    @Test func streakStartsAgainAfterKneading() {
        var streak = PetStreak()
        _ = streak.pet(at: 0); _ = streak.pet(at: 0.5); _ = streak.pet(at: 1)
        let fourth = streak.pet(at: 1.5), fifth = streak.pet(at: 2), sixth = streak.pet(at: 2.5)
        #expect(!fourth && !fifth && sixth)
    }

    @Test func oldPetsDropOut() {
        var streak = PetStreak()
        _ = streak.pet(at: 0); _ = streak.pet(at: 1)
        let late = streak.pet(at: 1 + PetStreak.window)
        #expect(!late)
    }
}

struct ArrivalBurstTests {
    @Test func aFewIsNotBig() {
        #expect(!ArrivalBurst.isBig(from: 0, to: ArrivalBurst.bigBatch - 1))
        #expect(!ArrivalBurst.isBig(from: 10, to: 10 + ArrivalBurst.bigBatch - 1))
    }

    @Test func enoughAtOnceIsBig() {
        #expect(ArrivalBurst.isBig(from: 0, to: ArrivalBurst.bigBatch))
        #expect(ArrivalBurst.isBig(from: 3, to: 3 + ArrivalBurst.bigBatch + 2))
    }

    @Test func fewerIsNotBig() {
        #expect(!ArrivalBurst.isBig(from: 20, to: 0))
    }
}

struct CatHatTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
    }

    @Test func santaThroughDecember() {
        #expect(CatHat.on(date(12, 1), calendar: calendar) == .santa)
        #expect(CatHat.on(date(12, 31), calendar: calendar) == .santa)
    }

    @Test func pumpkinThroughOctober() {
        #expect(CatHat.on(date(10, 1), calendar: calendar) == .pumpkin)
        #expect(CatHat.on(date(10, 31), calendar: calendar) == .pumpkin)
    }

    @Test func nothingTheRestOfTheYear() {
        for month in [1, 2, 3, 4, 5, 6, 7, 8, 9, 11] {
            #expect(CatHat.on(date(month, 15), calendar: calendar) == nil)
        }
    }
}

struct CatIdleTests {
    @Test func momentFallsInTheWindowBeforeDozing() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let moment = CatIdle.moment(using: &generator)
            #expect(moment >= CatIdle.earliest && moment <= CatIdle.latest)
        }
        #expect(CatIdle.latest < CatIdle.dozeAfter)
    }
}

struct CatPounceTests {
    @Test func pouncesOnceWithinReach() {
        var pounce = CatPounce()
        let far = pounce.moved(distance: 200, reach: 60)
        let near = pounce.moved(distance: 50, reach: 60)
        let again = pounce.moved(distance: 10, reach: 60)
        #expect(!far && near && !again)
    }

    @Test func nextDragPouncesAgain() {
        var pounce = CatPounce()
        _ = pounce.moved(distance: 10, reach: 60)
        pounce.ended()
        let next = pounce.moved(distance: 10, reach: 60)
        #expect(next)
    }
}
