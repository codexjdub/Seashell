import Foundation

/// Petting the notes cat again and again: the third pet within a few seconds
/// gets her kneading instead of the usual purr.
public struct PetStreak: Sendable {
    public static let petsToKnead = 3
    public static let window: TimeInterval = 5

    private var times: [TimeInterval] = []

    public init() {}

    /// A pet at `time` (seconds, any clock that only goes forward); true if
    /// this one sets her kneading. The streak starts again after.
    public mutating func pet(at time: TimeInterval) -> Bool {
        times = times.filter { time - $0 < Self.window } + [time]
        guard times.count >= Self.petsToKnead else { return false }
        times = []
        return true
    }
}

/// A big batch arriving on the shelves (from an iPhone, another Mac or
/// Finder) puffs the cat up; a few things just wake her.
public enum ArrivalBurst {
    public static let bigBatch = 5

    /// `before` and `after` count what has arrived since the panel was last open.
    public static func isBig(from before: Int, to after: Int) -> Bool {
        after - before >= bigBatch
    }
}

/// What the cat wears, by the Mac's date.
public enum CatHat: Sendable, Equatable {
    case santa
    case pumpkin

    public static func on(_ date: Date, calendar: Calendar = .current) -> CatHat? {
        switch calendar.component(.month, from: date) {
        case 12: .santa
        case 10: .pumpkin
        default: nil
        }
    }
}

/// When nothing has happened for a while with the panel open, the cat grooms
/// or plays, once, at a random moment in a window that ends well before she
/// dozes off.
public enum CatIdle {
    public static let earliest: TimeInterval = 40
    public static let latest: TimeInterval = 120
    public static let dozeAfter: TimeInterval = 180

    /// Seconds into a quiet spell for the one idle move.
    public static func moment<G: RandomNumberGenerator>(using generator: inout G) -> TimeInterval {
        .random(in: earliest...latest, using: &generator)
    }

    public static func moment() -> TimeInterval {
        var generator = SystemRandomNumberGenerator()
        return moment(using: &generator)
    }
}

/// Watching a drag go by: she pounces the first time it comes within reach,
/// once a drag.
public struct CatPounce: Sendable {
    private var hasPounced = false

    public init() {}

    /// The drag is `distance` from her, and she reaches `reach`; true if she pounces now.
    public mutating func moved(distance: Double, reach: Double) -> Bool {
        guard !hasPounced, distance <= reach else { return false }
        hasPounced = true
        return true
    }

    /// The drag has gone: the next one gets a pounce too.
    public mutating func ended() {
        hasPounced = false
    }
}
