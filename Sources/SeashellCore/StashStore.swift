import Foundation
import Observation

/// The live view of Stash for the UI: shelves and their items, refreshed
/// whenever the folder changes on disk.
@MainActor @Observable
public final class StashStore {
    public private(set) var shelves: [Shelf] = []
    /// Keyed by shelf name, which is unique within Stash and doesn't depend on how a path is spelled.
    private var itemsByShelf: [String: [StashItem]] = [:]

    @ObservationIgnored public let library: StashLibrary
    /// Called after each refresh caused by a change on disk.
    @ObservationIgnored public var onChange: (() -> Void)?
    @ObservationIgnored private var watcher: FolderWatcher?

    /// How long a manifest entry's item must stay gone before the entry is
    /// dropped. Another Mac's manifest can arrive through iCloud slightly before
    /// the item itself, and that entry must survive the wait.
    @ObservationIgnored private let pruneGrace: TimeInterval
    /// "Shelf/name" → when it was first seen missing.
    @ObservationIgnored private var missingSince: [String: Date] = [:]
    @ObservationIgnored private var pruneCheck: Task<Void, Never>?

    public init(library: StashLibrary, pruneGrace: TimeInterval = 60) {
        self.library = library
        self.pruneGrace = pruneGrace
        reload()
    }

    public var defaultShelf: Shelf? { shelves.first(where: \.isDefault) }

    public func items(in shelf: Shelf) -> [StashItem] {
        itemsByShelf[shelf.name] ?? []
    }

    public func reload() {
        shelves = library.shelves()
        itemsByShelf = Dictionary(uniqueKeysWithValues: shelves.map { ($0.name, library.items(in: $0)) })
        pruneVanishedEntries()
    }

    public func startWatching() {
        watcher = FolderWatcher(folder: library.stash) { [weak self] in
            self?.reload()
            self?.onChange?()
        }
    }

    /// Forgets manifest entries whose items have been gone for `pruneGrace`, and
    /// schedules another look for the ones still within it.
    private func pruneVanishedEntries(now: Date = .now) {
        var stillWaiting: [String: Date] = [:]
        var nextCheck: TimeInterval?
        for shelf in shelves {
            var expired: Set<String> = []
            for name in library.vanishedEntries(in: shelf) {
                let key = "\(shelf.name)/\(name)"
                let since = missingSince[key] ?? now
                let waited = now.timeIntervalSince(since)
                if waited >= pruneGrace {
                    expired.insert(name)
                } else {
                    stillWaiting[key] = since
                    nextCheck = min(nextCheck ?? .infinity, pruneGrace - waited)
                }
            }
            guard !expired.isEmpty else { continue }
            do {
                try library.forget(expired, in: shelf)
                Log.info("Forgot \(expired.count) item(s) no longer in \(shelf.name): \(expired.sorted().joined(separator: ", "))")
            } catch {
                Log.error("Couldn’t update \(shelf.name)’s \(ShelfManifest.fileName): \(error.localizedDescription)")
            }
        }
        missingSince = stillWaiting

        pruneCheck?.cancel()
        guard let nextCheck else { return }
        pruneCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(nextCheck))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }
}
