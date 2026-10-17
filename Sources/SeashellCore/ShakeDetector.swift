import Foundation

/// Recognises a shake: quick left-right swings of the pointer. Feed it pointer
/// positions as they arrive; it answers true on the sample that completes a shake.
public struct ShakeDetector: Sendable {
    /// Direction changes needed, each after a swing of at least `minimumSwing` points…
    public var reversalsNeeded = 3
    public var minimumSwing = 20.0
    /// …all within this many seconds.
    public var window: TimeInterval = 0.6
    /// After a shake, ignore further shakes for this long.
    public var cooldown: TimeInterval = 1

    private var lastX: Double?
    private var direction = 0
    private var swing = 0.0
    private var reversals: [TimeInterval] = []
    private var quietUntil: TimeInterval = -.infinity

    public init() {}

    /// Forgets the current gesture (not the cooldown).
    public mutating func reset() {
        lastX = nil
        direction = 0
        swing = 0
        reversals = []
    }

    public mutating func add(x: Double, at time: TimeInterval) -> Bool {
        defer { lastX = x }
        guard let lastX else { return false }
        let dx = x - lastX
        guard abs(dx) >= 1 else { return false }
        let newDirection = dx > 0 ? 1 : -1

        if direction == 0 || newDirection == direction {
            direction = newDirection
            swing += abs(dx)
            return false
        }

        // Direction changed: count it if the swing that just ended was big enough.
        if swing >= minimumSwing { reversals.append(time) }
        direction = newDirection
        swing = abs(dx)
        reversals.removeAll { time - $0 > window }

        guard reversals.count >= reversalsNeeded, time >= quietUntil else { return false }
        quietUntil = time + cooldown
        reversals = []
        return true
    }
}
