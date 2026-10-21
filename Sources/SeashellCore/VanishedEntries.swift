import Foundation

/// Manifest entries whose item is gone, and since when. An entry is forgotten
/// only once its item has stayed gone for `grace`: another Mac's manifest can
/// arrive through iCloud slightly before the item itself, and that entry must
/// survive the wait. Used for shelf items (StashStore) and pins (NotesStore).
@MainActor
final class VanishedEntries {
    private let grace: TimeInterval
    /// Entry → when it was first seen gone.
    private var since: [String: Date] = [:]
    private var recheck: Task<Void, Never>?

    init(grace: TimeInterval) {
        self.grace = grace
    }

    /// Of `gone` (the entries whose items are gone now), the ones gone for
    /// `grace` or longer. Calls `lookAgain` when the next of the others is due.
    func expired(among gone: Set<String>, now: Date = .now, lookAgain: @escaping @MainActor () -> Void) -> Set<String> {
        var expired: Set<String> = []
        var waiting: [String: Date] = [:]
        var next: TimeInterval?
        for entry in gone {
            let first = since[entry] ?? now
            let waited = now.timeIntervalSince(first)
            if waited >= grace {
                expired.insert(entry)
            } else {
                waiting[entry] = first
                next = min(next ?? .infinity, grace - waited)
            }
        }
        since = waiting

        recheck?.cancel()
        if let next {
            recheck = Task {
                try? await Task.sleep(for: .seconds(next))
                guard !Task.isCancelled else { return }
                lookAgain()
            }
        }
        return expired
    }
}
