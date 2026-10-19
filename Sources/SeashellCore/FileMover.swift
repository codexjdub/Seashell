import Foundation

public enum FileMoverError: LocalizedError, Equatable {
    case missing(String)
    case copyMismatch(String)
    case noOrigin(String)
    case originMissing(String)
    case unreadableImage
    case invalidName(String)
    case nameTaken(String)

    public var errorDescription: String? {
        switch self {
        case .missing(let name): "“\(name)” no longer exists."
        case .copyMismatch(let name): "The copy of “\(name)” didn’t match the original, so the original was kept."
        case .noOrigin(let name): "Seashell doesn’t know where “\(name)” came from."
        case .originMissing(let path): "The folder it came from no longer exists: \(path)"
        case .unreadableImage: "The image couldn’t be read."
        case .invalidName(let name): "“\(name)” can’t be used as a name."
        case .nameTaken(let name): "There’s already an item called “\(name)” on this shelf."
        }
    }
}

/// Every file operation on Stash: moving things in, between shelves, back out
/// to where they came from, and to the Trash. Keeps each shelf's manifest in step.
public struct FileMover: Sendable {
    public typealias Trash = @Sendable (URL) throws -> Void

    public static let systemTrash: Trash = { url in
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    private let trash: Trash
    /// Tests set this to exercise the copy-verify-delete path on a single disk.
    private let simulateOtherVolume: Bool

    public init(trash: @escaping Trash = FileMover.systemTrash) {
        self.init(trash: trash, simulateOtherVolume: false)
    }

    init(trash: @escaping Trash, simulateOtherVolume: Bool) {
        self.trash = trash
        self.simulateOtherVolume = simulateOtherVolume
    }

    // MARK: Into Stash

    /// Moves a file or folder into `shelf`. Remembers the folder it came from for
    /// Put Back, unless it came from somewhere temporary (a promised file).
    @discardableResult
    public func stash(_ source: URL, into shelf: URL, rememberOrigin: Bool = true) throws -> URL {
        guard exists(source) else { throw FileMoverError.missing(source.lastPathComponent) }
        // Dragged back in from Finder, say: it's already there.
        if source.deletingLastPathComponent().resolvingSymlinksInPath().pathComponents
            == shelf.resolvingSymlinksInPath().pathComponents {
            Log.info("\(source.lastPathComponent) is already in \(shelf.lastPathComponent)")
            return source
        }
        let destination = FileNaming.uniqueDestination(for: source.lastPathComponent, in: shelf, isDirectory: isDirectory(source))
        try transfer(source, to: destination)
        let origin = rememberOrigin ? source.deletingLastPathComponent().path(percentEncoded: false) : nil
        try ShelfManifest.update(in: shelf) { $0.add(destination.lastPathComponent, origin: origin) }
        Log.info("Stashed \(source.lastPathComponent) → \(shelf.lastPathComponent)/\(destination.lastPathComponent)")
        return destination
    }

    /// Copies a file or folder into `shelf`, leaving the original where it is:
    /// what pasting does. No Put Back, since the original never left.
    @discardableResult
    public func stashCopy(_ source: URL, into shelf: URL) throws -> URL {
        guard exists(source) else { throw FileMoverError.missing(source.lastPathComponent) }
        let destination = FileNaming.uniqueDestination(for: source.lastPathComponent, in: shelf, isDirectory: isDirectory(source))
        try Coordinated.read(source) { try FileManager.default.copyItem(at: $0, to: destination) }
        try ShelfManifest.update(in: shelf) { $0.add(destination.lastPathComponent, origin: nil) }
        Log.info("Copied \(source.lastPathComponent) → \(shelf.lastPathComponent)/\(destination.lastPathComponent)")
        return destination
    }

    @discardableResult
    public func stash(text: String, into shelf: URL, date: Date = .now) throws -> URL {
        try write(Data(text.utf8), named: FileNaming.snippetName(for: text, date: date), into: shelf)
    }

    @discardableResult
    public func stash(link: URL, title: String?, into shelf: URL) throws -> URL {
        let plist = try PropertyListSerialization.data(fromPropertyList: ["URL": link.absoluteString], format: .xml, options: 0)
        return try write(plist, named: FileNaming.linkName(for: link, title: title), into: shelf)
    }

    @discardableResult
    public func stash(imageData: Data, into shelf: URL, date: Date = .now) throws -> URL {
        try write(ImageConversion.png(from: imageData), named: FileNaming.imageName(date: date), into: shelf)
    }

    // MARK: Within and out of Stash

    /// Moves a stashed item to another shelf, as `name` if given. It keeps its
    /// Put Back origin.
    @discardableResult
    public func move(_ item: URL, toShelf shelf: URL, named name: String? = nil) throws -> URL {
        let from = item.deletingLastPathComponent()
        let origin = ShelfManifest.read(in: from).origins[item.lastPathComponent]
        let destination = FileNaming.uniqueDestination(for: name ?? item.lastPathComponent, in: shelf, isDirectory: isDirectory(item))
        try transfer(item, to: destination)
        try ShelfManifest.update(in: from) { $0.remove(item.lastPathComponent) }
        try ShelfManifest.update(in: shelf) { $0.add(destination.lastPathComponent, origin: origin) }
        Log.info("Moved \(item.lastPathComponent) → \(shelf.lastPathComponent)")
        return destination
    }

    /// Renames a stashed item where it is; it keeps its place and Put Back origin.
    @discardableResult
    public func rename(_ item: URL, to name: String) throws -> URL {
        let cleaned = FileNaming.sanitized(name)
        guard !cleaned.isEmpty, cleaned == name.trimmingCharacters(in: .whitespaces) else { throw FileMoverError.invalidName(name) }
        let current = item.lastPathComponent
        guard cleaned != current else { return item }
        let shelf = item.deletingLastPathComponent()
        let destination = shelf.appending(path: cleaned, directoryHint: isDirectory(item) ? .isDirectory : .notDirectory)
        // Another item already has that name (a change of case alone is fine).
        if exists(destination), cleaned.lowercased() != current.lowercased() { throw FileMoverError.nameTaken(cleaned) }
        try Coordinated.move(item, to: destination)
        try ShelfManifest.update(in: shelf) { $0.rename(current, to: cleaned) }
        Log.info("Renamed \(current) → \(cleaned)")
        return destination
    }

    /// Sends a stashed item to the Trash.
    public func delete(_ item: URL) throws {
        try Coordinated.write(item, options: .forDeleting) { try trash($0) }
        try ShelfManifest.update(in: item.deletingLastPathComponent()) { $0.remove(item.lastPathComponent) }
        Log.info("Moved \(item.lastPathComponent) to the Trash")
    }

    /// Returns a stashed item to the folder it came from.
    @discardableResult
    public func putBack(_ item: URL) throws -> URL {
        let shelf = item.deletingLastPathComponent()
        guard let origin = ShelfManifest.read(in: shelf).origins[item.lastPathComponent] else {
            throw FileMoverError.noOrigin(item.lastPathComponent)
        }
        let destination = try moveOut(item, to: URL(filePath: origin, directoryHint: .isDirectory), named: item.lastPathComponent)
        Log.info("Put back \(item.lastPathComponent) → \(origin)")
        return destination
    }

    // MARK: Undo

    /// Takes back one change made by a drop, paste or move between shelves (⌘Z).
    /// Returns where the item went, or nil if it went to the Trash.
    @discardableResult
    public func undo(_ change: StashChange) throws -> URL? {
        guard exists(change.item) else { throw FileMoverError.missing(change.item.lastPathComponent) }
        switch change {
        case .added(let item):
            try delete(item)
            return nil
        case .movedIn(let item, let from):
            let destination = try moveOut(item, to: from.deletingLastPathComponent(), named: from.lastPathComponent)
            Log.info("Undo: \(item.lastPathComponent) back to \(destination.path(percentEncoded: false))")
            return destination
        case .movedBetweenShelves(let item, let from):
            let shelf = from.deletingLastPathComponent()
            guard isDirectory(shelf) else { throw FileMoverError.originMissing(shelf.path(percentEncoded: false)) }
            return try move(item, toShelf: shelf, named: from.lastPathComponent)
        }
    }

    // MARK: Helpers

    /// Moves a stashed item out of Stash into `folder` as `name` (or a numbered
    /// name if that's taken), and forgets it in its shelf's manifest.
    private func moveOut(_ item: URL, to folder: URL, named name: String) throws -> URL {
        guard isDirectory(folder) else { throw FileMoverError.originMissing(folder.path(percentEncoded: false)) }
        let destination = FileNaming.uniqueDestination(for: name, in: folder, isDirectory: isDirectory(item))
        try transfer(item, to: destination)
        try ShelfManifest.update(in: item.deletingLastPathComponent()) { $0.remove(item.lastPathComponent) }
        return destination
    }

    /// On the same volume this is an instant rename. Across volumes it copies,
    /// checks the copy matches, then deletes the original, like a Finder move.
    func transfer(_ source: URL, to destination: URL) throws {
        let folder = destination.deletingLastPathComponent()
        if !simulateOtherVolume, try sameVolume(source, folder) {
            try Coordinated.move(source, to: destination)
            return
        }

        let staging = folder.appending(path: ".seashell-incoming-\(UUID().uuidString)")
        do {
            try Coordinated.read(source) { try FileManager.default.copyItem(at: $0, to: staging) }
            let original = try FileSize.measure(source)
            let copy = try FileSize.measure(staging)
            guard original == copy else { throw FileMoverError.copyMismatch(source.lastPathComponent) }
            try Coordinated.move(staging, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }

        do {
            try Coordinated.write(source, options: .forDeleting) { try FileManager.default.removeItem(at: $0) }
        } catch {
            // e.g. a read-only drive: the copy is safe in Stash, the original stays where it was.
            Log.error("Copied \(source.lastPathComponent) but couldn’t remove the original: \(error.localizedDescription)")
        }
    }

    private func write(_ data: Data, named name: String, into shelf: URL) throws -> URL {
        let destination = FileNaming.uniqueDestination(for: name, in: shelf, isDirectory: false)
        try Coordinated.write(destination) { try data.write(to: $0, options: .withoutOverwriting) }
        try ShelfManifest.update(in: shelf) { $0.add(destination.lastPathComponent, origin: nil) }
        Log.info("Stashed \(destination.lastPathComponent) → \(shelf.lastPathComponent)")
        return destination
    }

    private func sameVolume(_ a: URL, _ b: URL) throws -> Bool {
        let first = try a.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        let second = try b.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        guard let first, let second else { return false }
        return first.isEqual(second)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
