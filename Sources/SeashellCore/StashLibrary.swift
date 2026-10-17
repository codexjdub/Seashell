import Foundation

public struct Shelf: Identifiable, Hashable, Sendable {
    public let url: URL
    public var id: URL { url }
    public var name: String { url.lastPathComponent }
    public var isDefault: Bool { name == SeashellFolders.defaultShelfName }
}

public struct StashItem: Identifiable, Hashable, Sendable {
    public let url: URL
    /// A real folder. Packages such as apps count as files.
    public let isFolder: Bool
    /// Folder it came from, if Put Back is possible.
    public let origin: String?
    public var id: URL { url }
    public var name: String { url.lastPathComponent }
}

public enum ShelfError: LocalizedError, Equatable {
    case invalidName(String)
    case nameTaken(String)
    case defaultShelf

    public var errorDescription: String? {
        switch self {
        case .invalidName(let name): "“\(name)” can’t be used as a shelf name."
        case .nameTaken(let name): "There’s already a shelf called “\(name)”."
        case .defaultShelf: "The \(SeashellFolders.defaultShelfName) shelf can’t be renamed or deleted."
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

    /// Main first, then the rest in Finder's name order.
    public func shelves() -> [Shelf] {
        contents(of: stash, keys: [.isDirectoryKey])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(Shelf.init)
            .sorted { a, b in
                if a.isDefault != b.isDefault { return a.isDefault }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
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
                             isFolder: values?.isDirectory == true && values?.isPackage != true,
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

    @discardableResult
    public func createShelf(named name: String) throws -> Shelf {
        let url = try freeShelfURL(for: name)
        try Coordinated.write(url) { try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: false) }
        Log.info("Created shelf \(url.lastPathComponent)")
        return Shelf(url: url)
    }

    @discardableResult
    public func renameShelf(_ shelf: Shelf, to name: String) throws -> Shelf {
        guard !shelf.isDefault else { throw ShelfError.defaultShelf }
        let url = try freeShelfURL(for: name)
        try Coordinated.move(shelf.url, to: url)
        Log.info("Renamed shelf \(shelf.name) → \(url.lastPathComponent)")
        return Shelf(url: url)
    }

    /// Sends a shelf and everything in it to the Trash.
    public func deleteShelf(_ shelf: Shelf) throws {
        guard !shelf.isDefault else { throw ShelfError.defaultShelf }
        try mover.delete(shelf.url)
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
