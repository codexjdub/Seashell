import Foundation
import Synchronization

/// Items Seashell on this Mac has just put on a shelf (stashed, copied, moved
/// or renamed), so StashStore can tell them from arrivals: things saved from
/// an iPhone or another Mac, or added in Finder. Each is remembered for ten
/// minutes, or until the store has seen it.
public final class LocalWrites: Sendable {
    public static let shared = LocalWrites()
    private static let memory: TimeInterval = 600

    /// Path → when it was written.
    private let written = Mutex<[String: Date]>([:])

    public init() {}

    func note(_ url: URL, now: Date = .now) {
        written.withLock { written in
            written = written.filter { now.timeIntervalSince($0.value) < Self.memory }
            written[Self.key(url)] = now
        }
    }

    /// The write noted for `url` didn't happen after all.
    func forget(_ url: URL) {
        written.withLock { _ = $0.removeValue(forKey: Self.key(url)) }
    }

    /// Whether Seashell just wrote `url`. It's forgotten either way: the store
    /// asks once, when the item first shows up.
    func claim(_ url: URL, now: Date = .now) -> Bool {
        written.withLock { written in
            guard let at = written.removeValue(forKey: Self.key(url)) else { return false }
            return now.timeIntervalSince(at) < Self.memory
        }
    }

    /// One spelling per item, folder or not.
    private static func key(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
