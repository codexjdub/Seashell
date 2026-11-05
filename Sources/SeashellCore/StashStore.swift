import Foundation
import Observation

/// The live view of Stash for the UI: shelves and their items, refreshed
/// whenever the folder changes on disk. A change re-reads just the shelves it
/// touched, in the background: reading a shelf asks iCloud about each item,
/// which takes a moment per item.
@MainActor @Observable
public final class StashStore {
    public private(set) var shelves: [Shelf] = []
    /// Keyed by shelf name, which is unique within Stash and doesn't depend on how a path is spelled.
    private var itemsByShelf: [String: [StashItem]] = [:]
    /// Items that turned up since `markArrivalsSeen()`, by shelf name, that
    /// Seashell on this Mac didn't put there: saved from an iPhone or another
    /// Mac, or added in Finder. Counted from launch, on shelves already known
    /// (a shelf renamed here would otherwise arrive whole).
    public private(set) var arrivals: [String: Set<String>] = [:]

    @ObservationIgnored public let library: StashLibrary
    /// Called after each background re-read (a change on disk, or `reload(around:)`).
    @ObservationIgnored public var onChange: (() -> Void)?
    @ObservationIgnored private var watcher: FolderWatcher?

    /// Manifest entries ("Shelf/name") whose items have gone.
    @ObservationIgnored private let vanished: VanishedEntries
    /// Each shelf's manifest names whose items are gone, as last read.
    @ObservationIgnored private var vanishedByShelf: [String: Set<String>] = [:]

    /// What waits to be re-read in the background, and whether a re-read is under way.
    @ObservationIgnored private var queued = Rescan()
    @ObservationIgnored private var isRescanning = false
    /// Reloads done there and then so far: a background re-read that started before one is out of date.
    @ObservationIgnored private var fullReloads = 0
    /// The Stash folder's path, as written and with symlinks resolved (change events use the latter).
    @ObservationIgnored private let stashPaths: [[String]]

    /// `pruneGrace`: how long a manifest entry's item must stay gone before the
    /// entry is dropped (see VanishedEntries).
    public init(library: StashLibrary, pruneGrace: TimeInterval = 60) {
        self.library = library
        vanished = VanishedEntries(grace: pruneGrace)
        let written = library.stash.standardizedFileURL.pathComponents
        let resolved = library.stash.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        stashPaths = written == resolved ? [written] : [written, resolved]
        reload()
    }

    public var defaultShelf: Shelf? { shelves.first(where: \.isDefault) }

    public func items(in shelf: Shelf) -> [StashItem] {
        itemsByShelf[shelf.name] ?? []
    }

    /// The panel has been opened: nothing counts as new any more.
    public func markArrivalsSeen() {
        if !arrivals.isEmpty { arrivals = [:] }
    }

    /// The most recently added items across every shelf, newest first: what the
    /// grab shelf offers.
    public func recentItems(limit: Int) -> [StashItem] {
        Array(shelves.flatMap { items(in: $0) }
            .sorted { ($0.added ?? .distantPast) > ($1.added ?? .distantPast) }
            .prefix(limit))
    }

    /// Re-reads all of Stash now, for when the shelves themselves changed and
    /// what follows needs them. Only real differences are published, so views
    /// don't redraw (and lose their selection) each time Finder touches a hidden file.
    public func reload() {
        fullReloads += 1
        let newShelves = library.shelves()
        apply(newShelves, Dictionary(uniqueKeysWithValues: newShelves.map { ($0.name, library.contents(of: $0)) }))
    }

    /// Re-reads the list of shelves now, for when Seashell just added, renamed,
    /// removed or reordered one and what follows needs the new list. Only a
    /// shelf new to the list (made, or renamed) has its items read: reading
    /// every item asks iCloud about each, a moment apiece, too long to wait for.
    public func reloadShelves() {
        fullReloads += 1
        let newShelves = library.shelves()
        let fresh = newShelves.filter { itemsByShelf[$0.name] == nil }
        apply(newShelves, Dictionary(uniqueKeysWithValues: fresh.map { ($0.name, library.contents(of: $0)) }))
        // A re-read under way started before this, so it'll be dropped: read everything again after it.
        if isRescanning { reload(around: nil) }
    }

    /// Re-reads, in the background, the shelves holding `changed` (items in
    /// them, or the shelves themselves); nil re-reads all of Stash. The change
    /// shows a moment later, once it's read.
    public func reload(around changed: [URL]?) {
        queued.add(changed, under: stashPaths, known: Set(shelves.map(\.name)))
        rescanQueued()
    }

    public func startWatching() {
        watcher = FolderWatcher(folder: library.stash) { [weak self] changed in self?.reload(around: changed) }
    }

    /// One re-read at a time; changes that come in meanwhile wait for the next.
    private func rescanQueued() {
        guard !isRescanning, !queued.isEmpty else { return }
        let request = queued
        queued = Rescan()
        isRescanning = true
        let started = fullReloads
        let library = library
        let known = shelves
        Task { [weak self] in
            let (shelves, contents) = await Task.detached { request.read(library, known: known) }.value
            guard let self else { return }
            isRescanning = false
            if started == fullReloads {
                apply(shelves, contents)
                onChange?()
            }
            rescanQueued()
        }
    }

    /// Publishes `newShelves`, with the items in `contents` and, for shelves it
    /// doesn't cover, the ones already known.
    private func apply(_ newShelves: [Shelf], _ contents: [String: ShelfContents]) {
        var newItems: [String: [StashItem]] = [:]
        var newVanished: [String: Set<String>] = [:]
        var newArrivals: [String: Set<String>] = [:]
        for shelf in newShelves {
            let items = contents[shelf.name]?.items ?? itemsByShelf[shelf.name] ?? []
            newItems[shelf.name] = items
            newVanished[shelf.name] = contents[shelf.name]?.vanished ?? vanishedByShelf[shelf.name] ?? []
            let names = Set(items.map(\.name))
            var arrived = arrivals[shelf.name, default: []].intersection(names)  // less any since gone
            if contents[shelf.name] != nil, let before = itemsByShelf[shelf.name] {
                let known = Set(before.map(\.name))
                arrived.formUnion(items.filter { !known.contains($0.name) && !library.localWrites.claim($0.url) }.map(\.name))
            }
            if !arrived.isEmpty { newArrivals[shelf.name] = arrived }
        }
        if newShelves != shelves { shelves = newShelves }
        if newItems != itemsByShelf { itemsByShelf = newItems }
        if newArrivals != arrivals { arrivals = newArrivals }
        vanishedByShelf = newVanished
        pruneVanishedEntries()
    }

    /// Forgets manifest entries whose items have been gone for `pruneGrace`; the
    /// ones still within it get another look when it's up.
    private func pruneVanishedEntries() {
        var gone: [String: (shelf: Shelf, name: String)] = [:]
        for shelf in shelves {
            for name in vanishedByShelf[shelf.name] ?? [] { gone["\(shelf.name)/\(name)"] = (shelf, name) }
        }
        let expired = vanished.expired(among: Set(gone.keys)) { [weak self] in self?.reload(around: nil) }.compactMap { gone[$0] }
        for shelf in shelves {
            let names = Set(expired.filter { $0.shelf == shelf }.map(\.name))
            guard !names.isEmpty else { continue }
            do {
                try library.forget(names, in: shelf)
                vanishedByShelf[shelf.name]?.subtract(names)
                Log.info("Forgot \(names.count) item(s) no longer in \(shelf.name): \(names.sorted().joined(separator: ", "))")
            } catch {
                Log.error("Couldn’t update \(shelf.name)’s \(ShelfManifest.fileName): \(error.localizedDescription)")
            }
        }
    }
}

/// What a background re-read covers: the list of shelves (with their order in
/// the Stash folder's manifest), and which shelves' items.
private struct Rescan: Sendable {
    var shelfList = false
    var everything = false
    var shelves: Set<String> = []

    var isEmpty: Bool { !shelfList && !everything && shelves.isEmpty }

    /// Notes what `changed` (folders or items under Stash; nil for anything)
    /// needs re-read. `stash` is the Stash folder's path, spelled each way it may be.
    mutating func add(_ changed: [URL]?, under stash: [[String]], known: Set<String>) {
        guard let changed else {
            everything = true
            return
        }
        for url in changed {
            let components = url.standardizedFileURL.pathComponents
            guard let base = stash.first(where: { components.starts(with: $0) }) else {
                everything = true  // spelled some other way: read it all to be sure
                continue
            }
            // The Stash folder itself: shelves added, removed, renamed or reordered.
            guard let shelf = components.dropFirst(base.count).first else {
                shelfList = true
                continue
            }
            shelves.insert(shelf)
            if !known.contains(shelf) { shelfList = true }
        }
    }

    /// The shelves, and the contents of those asked for (and of any new ones).
    func read(_ library: StashLibrary, known: [Shelf]) -> ([Shelf], [String: ShelfContents]) {
        let gone = known.contains { self.shelves.contains($0.name) && !FileManager.default.fileExists(atPath: $0.url.path(percentEncoded: false)) }
        let shelves = shelfList || everything || gone ? library.shelves() : known
        let knownNames = Set(known.map(\.name))
        let wanted = shelves.filter { everything || self.shelves.contains($0.name) || !knownNames.contains($0.name) }
        return (shelves, Dictionary(uniqueKeysWithValues: wanted.map { ($0.name, library.contents(of: $0)) }))
    }
}
