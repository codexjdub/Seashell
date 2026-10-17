import Foundation

public enum FileMoverError: LocalizedError, Equatable {
    case missing(String)
    case copyMismatch(String)
    case noOrigin(String)
    case originMissing(String)
    case unreadableImage

    public var errorDescription: String? {
        switch self {
        case .missing(let name): "“\(name)” no longer exists."
        case .copyMismatch(let name): "The copy of “\(name)” didn’t match the original, so the original was kept."
        case .noOrigin(let name): "Seashell doesn’t know where “\(name)” came from."
        case .originMissing(let path): "The folder it came from no longer exists: \(path)"
        case .unreadableImage: "The image couldn’t be read."
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
        let destination = FileNaming.uniqueDestination(for: source.lastPathComponent, in: shelf, isDirectory: isDirectory(source))
        try transfer(source, to: destination)
        let origin = rememberOrigin ? source.deletingLastPathComponent().path(percentEncoded: false) : nil
        try ShelfManifest.update(in: shelf) { $0.add(destination.lastPathComponent, origin: origin) }
        Log.info("Stashed \(source.lastPathComponent) → \(shelf.lastPathComponent)/\(destination.lastPathComponent)")
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

    /// Moves a stashed item to another shelf. It keeps its Put Back origin.
    @discardableResult
    public func move(_ item: URL, toShelf shelf: URL) throws -> URL {
        let from = item.deletingLastPathComponent()
        let origin = ShelfManifest.read(in: from).origins[item.lastPathComponent]
        let destination = FileNaming.uniqueDestination(for: item.lastPathComponent, in: shelf, isDirectory: isDirectory(item))
        try transfer(item, to: destination)
        try ShelfManifest.update(in: from) { $0.remove(item.lastPathComponent) }
        try ShelfManifest.update(in: shelf) { $0.add(destination.lastPathComponent, origin: origin) }
        Log.info("Moved \(item.lastPathComponent) → \(shelf.lastPathComponent)")
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
        let folder = URL(filePath: origin, directoryHint: .isDirectory)
        guard isDirectory(folder) else { throw FileMoverError.originMissing(origin) }
        let destination = FileNaming.uniqueDestination(for: item.lastPathComponent, in: folder, isDirectory: isDirectory(item))
        try transfer(item, to: destination)
        try ShelfManifest.update(in: shelf) { $0.remove(item.lastPathComponent) }
        Log.info("Put back \(item.lastPathComponent) → \(origin)")
        return destination
    }

    // MARK: Helpers

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
