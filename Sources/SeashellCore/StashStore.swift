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

    /// Manifest entries ("Shelf/name") whose items have gone.
    @ObservationIgnored private let vanished: VanishedEntries

    /// `pruneGrace`: how long a manifest entry's item must stay gone before the
    /// entry is dropped (see VanishedEntries).
    public init(library: StashLibrary, pruneGrace: TimeInterval = 60) {
        self.library = library
        vanished = VanishedEntries(grace: pruneGrace)
        reload()
    }

    public var defaultShelf: Shelf? { shelves.first(where: \.isDefault) }

    public func items(in shelf: Shelf) -> [StashItem] {
        itemsByShelf[shelf.name] ?? []
    }

    /// The most recently added items across every shelf, newest first: what the
    /// grab shelf offers.
    public func recentItems(limit: Int) -> [StashItem] {
        Array(shelves.flatMap { items(in: $0) }
            .sorted { ($0.added ?? .distantPast) > ($1.added ?? .distantPast) }
            .prefix(limit))
    }

    /// Re-reads the disk. Only real differences are published, so views don't
    /// redraw (and lose their selection) each time Finder touches a hidden file.
    public func reload() {
        let newShelves = library.shelves()
        let newItems = Dictionary(uniqueKeysWithValues: newShelves.map { ($0.name, library.items(in: $0)) })
        if newShelves != shelves { shelves = newShelves }
        if newItems != itemsByShelf { itemsByShelf = newItems }
        pruneVanishedEntries()
    }

    public func startWatching() {
        watcher = FolderWatcher(folder: library.stash) { [weak self] in
            self?.reload()
            self?.onChange?()
        }
    }

    /// Forgets manifest entries whose items have been gone for `pruneGrace`; the
    /// ones still within it get another look when it's up.
    private func pruneVanishedEntries() {
        var gone: [String: (shelf: Shelf, name: String)] = [:]
        for shelf in shelves {
            for name in library.vanishedEntries(in: shelf) { gone["\(shelf.name)/\(name)"] = (shelf, name) }
        }
        let expired = vanished.expired(among: Set(gone.keys)) { [weak self] in self?.reload() }.compactMap { gone[$0] }
        for shelf in shelves {
            let names = Set(expired.filter { $0.shelf == shelf }.map(\.name))
            guard !names.isEmpty else { continue }
            do {
                try library.forget(names, in: shelf)
                Log.info("Forgot \(names.count) item(s) no longer in \(shelf.name): \(names.sorted().joined(separator: ", "))")
            } catch {
                Log.error("Couldn’t update \(shelf.name)’s \(ShelfManifest.fileName): \(error.localizedDescription)")
            }
        }
    }
}
