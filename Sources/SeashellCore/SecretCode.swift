import Foundation

/// A short code typed on the keyboard, such as 1 1 1 and Return in About
/// Seashell (the easter egg). Each key has to follow the last within `gap`
/// seconds; extra keys before the code don't matter ("1111⏎" counts too).
public struct SecretCode: Sendable {
    public let code: [Character]
    public let gap: TimeInterval
    private var typed: [Character] = []
    private var lastKey: Date?

    public init(_ code: String, gap: TimeInterval = 2) {
        self.code = Array(code)
        self.gap = gap
    }

    /// Whether `character` appears in the code, so the window can take it
    /// quietly instead of beeping.
    public func isPart(_ character: Character) -> Bool {
        code.contains(character)
    }

    /// Notes a typed character. True when it completes the code.
    public mutating func type(_ character: Character, at time: Date = .now) -> Bool {
        if let lastKey, time.timeIntervalSince(lastKey) > gap { typed = [] }
        lastKey = time
        typed.append(character)
        if typed.count > code.count { typed.removeFirst(typed.count - code.count) }
        guard typed == code else { return false }
        typed = []
        return true
    }
}
