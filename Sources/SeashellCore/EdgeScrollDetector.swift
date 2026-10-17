import Foundation

/// Recognises a pull down or push up made by scrolling with the pointer at the
/// top edge of the screen. Feed it scroll events; it answers on the event that
/// completes a gesture.
public struct EdgeScrollDetector: Sendable {
    public enum Gesture: Sendable, Equatable {
        case pullDown
        case pushUp
    }

    /// Trackpad: points of finger travel in one direction…
    public var trackpadDistance = 40.0
    /// …or mouse wheel: clicks in one direction…
    public var wheelClicks = 2
    /// …within this many seconds.
    public var window: TimeInterval = 0.5
    /// After a gesture, ignore scrolling for this long, so one swipe can't open and close.
    public var cooldown: TimeInterval = 0.6

    private struct Sample: Sendable {
        let time: TimeInterval
        let amount: Double
        let precise: Bool
    }

    private var samples: [Sample] = []
    private var direction = 0
    private var quietUntil: TimeInterval = -.infinity

    public init() {}

    public mutating func reset() {
        samples = []
        direction = 0
    }

    /// The physical direction of a scroll event: positive when fingers move down
    /// the trackpad or the wheel rolls toward you, whatever the natural-scrolling setting.
    public static func downward(deltaY: Double, invertedFromDevice: Bool) -> Double {
        invertedFromDevice ? deltaY : -deltaY
    }

    /// `downward` is from `downward(deltaY:invertedFromDevice:)`; `precise` is
    /// true for trackpads (and other devices with smooth, point-based deltas).
    public mutating func add(downward: Double, precise: Bool, at time: TimeInterval) -> Gesture? {
        guard downward != 0, time >= quietUntil else { return nil }
        let newDirection = downward > 0 ? 1 : -1
        if newDirection != direction {
            reset()
            direction = newDirection
        }
        samples.append(Sample(time: time, amount: abs(downward), precise: precise))
        samples.removeAll { time - $0.time > window }

        let reached = precise
            ? samples.filter(\.precise).reduce(0) { $0 + $1.amount } >= trackpadDistance
            : samples.filter { !$0.precise }.count >= wheelClicks
        guard reached else { return nil }

        let gesture: Gesture = direction > 0 ? .pullDown : .pushUp
        reset()
        quietUntil = time + cooldown
        return gesture
    }
}
