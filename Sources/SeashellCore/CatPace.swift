import Foundation

/// How often the notes cat bats a paw at what you type: once a few keys have
/// gone by, and never sooner than a couple of seconds after the last time, so
/// it keeps you company without getting in the way.
public struct CatPace: Sendable {
    public static let keysPerBat = 8
    public static let minimumGap: TimeInterval = 2.5

    private var keys = 0
    private var lastBat: TimeInterval?

    public init() {}

    /// A key typed at `time` (seconds, any clock that only goes forward);
    /// true if the cat bats at it.
    public mutating func key(at time: TimeInterval) -> Bool {
        keys += 1
        guard keys >= Self.keysPerBat else { return false }
        if let lastBat, time - lastBat < Self.minimumGap { return false }
        keys = 0
        lastBat = time
        return true
    }
}
