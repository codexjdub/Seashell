import Foundation

public struct Shelf: Identifiable, Hashable, Sendable {
    public let url: URL
    public var id: URL { url }
    public var name: String { url.lastPathComponent }
    public var isDefault: Bool { name == SeashellFolders.defaultShelfName }
}

public struct StashItem: Identifiable, Hashable, Sendable {
    public enum Kind: Sendable {
        case file
        /// A real folder. Packages such as apps count as files.
        case folder
        /// A `.txt`: dragged out as its text, so it can go into text fields.
        case text
        /// A `.webloc`: dragged out as its address.
        case link
    }

    public let url: URL
    public let kind: Kind
    /// Folder it came from, if Put Back is possible.
    public let origin: String?
    public var id: URL { url }
    public var name: String { url.lastPathComponent }
    public var isFolder: Bool { kind == .folder }

    static func kind(of url: URL, isDirectory: Bool, isPackage: Bool) -> Kind {
        if isDirectory, !isPackage { return .folder }
        switch url.pathExtension.lowercased() {
        case "txt": return .text
        case "webloc": return .link
        default: return .file
        }
    }
}

public enum ShelfError: LocalizedError, Equatable {
    case invalidName(String)
    case nameTaken(String)
    case defaultShelf

    public var errorDescription: String? {
        switch self {
        case .invalidName(let name): "“\(name)” can’t be used as a shelf name."
        case .nameTaken(let name): "There’s already a shelf called “\(name)”."
        case .defaultShelf: "The \(SeashellFolders.defaultShelfName) shelf can’t be renamed, moved or deleted."
        }
    }
}

/// Reads and manages shelves on disk. The folders are the source of truth.
public struct StashLibrary: Sendable {
    public let stash: URL
    private let mover: FileMover

    public init(stash: URL, mover: FileMover = FileMover()) {
        self.stash = stash
        self.mover = mover
    }

    /// Main first, then the order you dragged the tabs into (the Stash folder's
    /// `.seashell.json`, so it syncs), then any shelves it doesn't list yet
    /// (made in Finder or on another Mac) in Finder's name order.
    public func shelves() -> [Shelf] {
        let order = ShelfManifest.read(in: stash).order
        let position = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return contents(of: stash, keys: [.isDirectoryKey])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(Shelf.init)
            .sorted { a, b in
                if a.isDefault != b.isDefault { return a.isDefault }
                switch (position[a.name], position[b.name]) {
                case let (x?, y?): return x < y
                case (.some, nil): return true
                case (nil, .some): return false
                case (nil, nil): return a.name.localizedStandardCompare(b.name) == .orderedAscending
                }
            }
    }

    /// Moves `shelf` to `index` among the shelves after Main, and saves the order.
    public func moveShelf(_ shelf: Shelf, to index: Int) throws {
        guard !shelf.isDefault else { throw ShelfError.defaultShelf }
        var names = shelfOrder().filter { $0 != shelf.name }
        names.insert(shelf.name, at: min(max(index, 0), names.count))
        try saveShelfOrder(names)
        Log.info("Moved shelf \(shelf.name) to position \(index + 2)")
    }

    /// The shelves after Main, as they're shown now.
    private func shelfOrder() -> [String] {
        shelves().filter { !$0.isDefault }.map(\.name)
    }

    private func saveShelfOrder(_ names: [String]) throws {
        try ShelfManifest.update(in: stash) { $0.order = names }
    }

    /// Items added outside Seashell (in Finder, or not yet in the manifest) come
    /// first, newest first; then the manifest's order.
    public func items(in shelf: Shelf) -> [StashItem] {
        let manifest = ShelfManifest.read(in: shelf.url)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .addedToDirectoryDateKey]
        let urls = contents(of: shelf.url, keys: keys)
        let byName = Dictionary(urls.map { ($0.lastPathComponent, $0) }, uniquingKeysWith: { first, _ in first })
        let listed = manifest.order.compactMap { byName[$0] }
        let listedNames = Set(manifest.order)
        let unlisted = urls
            .filter { !listedNames.contains($0.lastPathComponent) }
            .sorted { dateAdded($0) > dateAdded($1) }
        return (unlisted + listed).map { url in
            let values = try? url.resourceValues(forKeys: keys)
            return StashItem(url: url,
                             kind: StashItem.kind(of: url, isDirectory: values?.isDirectory == true, isPackage: values?.isPackage == true),
                             origin: manifest.origins[url.lastPathComponent])
        }
    }

    /// Names the shelf's manifest still lists although the item is gone, e.g.
    /// moved out or deleted in Finder.
    public func vanishedEntries(in shelf: Shelf) -> Set<String> {
        let manifest = ShelfManifest.read(in: shelf.url)
        return Set(manifest.order).union(manifest.origins.keys).filter { name in
            !FileManager.default.fileExists(atPath: shelf.url.appending(path: name).path(percentEncoded: false))
        }
    }

    /// Drops manifest entries, so a different item later given the same name
    /// doesn't inherit an old position or Put Back origin.
    public func forget(_ names: Set<String>, in shelf: Shelf) throws {
        guard !names.isEmpty else { return }
        try ShelfManifest.update(in: shelf.url) { manifest in
            names.forEach { manifest.remove($0) }
        }
    }

    /// A new shelf goes at the end.
    @discardableResult
    public func createShelf(named name: String) throws -> Shelf {
        let url = try freeShelfURL(for: name)
        let existing = shelfOrder()
        try Coordinated.write(url) { try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: false) }
        Log.info("Created shelf \(url.lastPathComponent)")
        try? saveShelfOrder(existing + [url.lastPathComponent])
        return Shelf(url: url)
    }

    /// Keeps its place in the order.
    @discardableResult
    public func renameShelf(_ shelf: Shelf, to name: String) throws -> Shelf {
        guard !shelf.isDefault else { throw ShelfError.defaultShelf }
        let url = try freeShelfURL(for: name)
        let order = shelfOrder().map { $0 == shelf.name ? url.lastPathComponent : $0 }
        try Coordinated.move(shelf.url, to: url)
        Log.info("Renamed shelf \(shelf.name) → \(url.lastPathComponent)")
        try? saveShelfOrder(order)
        return Shelf(url: url)
    }

    /// Sends a shelf and everything in it to the Trash.
    public func deleteShelf(_ shelf: Shelf) throws {
        guard !shelf.isDefault else { throw ShelfError.defaultShelf }
        let order = shelfOrder().filter { $0 != shelf.name }
        try mover.delete(shelf.url)
        try? saveShelfOrder(order)
    }

    private func freeShelfURL(for name: String) throws -> URL {
        let cleaned = FileNaming.sanitized(name)
        guard !cleaned.isEmpty, cleaned == name.trimmingCharacters(in: .whitespaces) else { throw ShelfError.invalidName(name) }
        let url = stash.appending(path: cleaned, directoryHint: .isDirectory)
        guard !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { throw ShelfError.nameTaken(cleaned) }
        return url
    }

    private func contents(of folder: URL, keys: Set<URLResourceKey>) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])) ?? []
    }

    private func dateAdded(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate) ?? .distantPast
    }
}
