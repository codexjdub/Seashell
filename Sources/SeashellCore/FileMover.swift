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
        try once { try stash(source, into: shelf, rememberOrigin: rememberOrigin, measured: nil, edits: $0) }
    }

    /// Moves files in one after another, as `stash(_:into:rememberOrigin:)`
    /// does, writing the shelf's manifest once. `measured`: sizes already taken
    /// (see `transfer`). One result per file, in order.
    public func stash(_ sources: [URL], into shelf: URL, rememberOrigin: Bool = true,
                      measured: [URL: FileSize.Measurement] = [:]) -> [Result<URL, any Error>] {
        batch(sources) { try stash($0, into: shelf, rememberOrigin: rememberOrigin, measured: measured[$0], edits: $1) }
    }

    private func stash(_ source: URL, into shelf: URL, rememberOrigin: Bool, measured: FileSize.Measurement?,
                       edits: ManifestEdits) throws -> URL {
        guard exists(source) else { throw FileMoverError.missing(source.lastPathComponent) }
        // Dragged back in from Finder, say: it's already there.
        if source.deletingLastPathComponent().resolvingSymlinksInPath().pathComponents
            == shelf.resolvingSymlinksInPath().pathComponents {
            Log.info("\(source.lastPathComponent) is already in \(shelf.lastPathComponent)")
            return source
        }
        let destination = FileNaming.uniqueDestination(for: source.lastPathComponent, in: shelf, isDirectory: isDirectory(source))
        try transfer(source, to: destination, measured: measured)
        let origin = rememberOrigin ? source.deletingLastPathComponent().path(percentEncoded: false) : nil
        edits.change(shelf) { $0.add(destination.lastPathComponent, origin: origin) }
        Log.info("Stashed \(source.lastPathComponent) → \(shelf.lastPathComponent)/\(destination.lastPathComponent)")
        return destination
    }

    /// Copies a file or folder into `shelf`, leaving the original where it is:
    /// what pasting does. No Put Back, since the original never left.
    @discardableResult
    public func stashCopy(_ source: URL, into shelf: URL) throws -> URL {
        try once { try stashCopy(source, into: shelf, edits: $0) }
    }

    /// Copies several in, writing the shelf's manifest once. One result per file, in order.
    public func stashCopies(_ sources: [URL], into shelf: URL) -> [Result<URL, any Error>] {
        batch(sources) { try stashCopy($0, into: shelf, edits: $1) }
    }

    private func stashCopy(_ source: URL, into shelf: URL, edits: ManifestEdits) throws -> URL {
        guard exists(source) else { throw FileMoverError.missing(source.lastPathComponent) }
        let destination = FileNaming.uniqueDestination(for: source.lastPathComponent, in: shelf, isDirectory: isDirectory(source))
        try Coordinated.read(source) { try FileManager.default.copyItem(at: $0, to: destination) }
        edits.change(shelf) { $0.add(destination.lastPathComponent, origin: nil) }
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
        try once { try move(item, toShelf: shelf, named: name, edits: $0) }
    }

    /// Moves several to another shelf, writing each manifest once. One result per item, in order.
    public func move(_ items: [URL], toShelf shelf: URL) -> [Result<URL, any Error>] {
        batch(items) { try move($0, toShelf: shelf, named: nil, edits: $1) }
    }

    private func move(_ item: URL, toShelf shelf: URL, named name: String?, edits: ManifestEdits) throws -> URL {
        let from = item.deletingLastPathComponent()
        let origin = edits.origin(of: item)
        let destination = FileNaming.uniqueDestination(for: name ?? item.lastPathComponent, in: shelf, isDirectory: isDirectory(item))
        try transfer(item, to: destination)
        edits.change(from) { $0.remove(item.lastPathComponent) }
        edits.change(shelf) { $0.add(destination.lastPathComponent, origin: origin) }
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
        try once { try delete(item, edits: $0) }
    }

    /// Sends several to the Trash, writing each manifest once. One result per item, in order.
    public func delete(_ items: [URL]) -> [Result<Void, any Error>] {
        batch(items) { try delete($0, edits: $1) }
    }

    private func delete(_ item: URL, edits: ManifestEdits) throws {
        try Coordinated.write(item, options: .forDeleting) { try trash($0) }
        edits.change(item.deletingLastPathComponent()) { $0.remove(item.lastPathComponent) }
        Log.info("Moved \(item.lastPathComponent) to the Trash")
    }

    /// Returns a stashed item to the folder it came from.
    @discardableResult
    public func putBack(_ item: URL) throws -> URL {
        try once { try putBack(item, edits: $0) }
    }

    /// Returns several, writing each manifest once. One result per item, in order.
    public func putBack(_ items: [URL]) -> [Result<URL, any Error>] {
        batch(items) { try putBack($0, edits: $1) }
    }

    private func putBack(_ item: URL, edits: ManifestEdits) throws -> URL {
        guard let origin = edits.origin(of: item) else { throw FileMoverError.noOrigin(item.lastPathComponent) }
        let destination = try moveOut(item, to: URL(filePath: origin, directoryHint: .isDirectory), named: item.lastPathComponent,
                                      edits: edits)
        Log.info("Put back \(item.lastPathComponent) → \(origin)")
        return destination
    }

    // MARK: Undo

    /// Takes back one change made by a drop, paste or move between shelves (⌘Z).
    /// Returns where the item went, or nil if it went to the Trash.
    @discardableResult
    public func undo(_ change: StashChange) throws -> URL? {
        try once { try undo(change, edits: $0) }
    }

    /// Takes back several, writing each manifest once. One result per change, in order.
    public func undo(_ changes: [StashChange]) -> [Result<URL?, any Error>] {
        batch(changes) { try undo($0, edits: $1) }
    }

    private func undo(_ change: StashChange, edits: ManifestEdits) throws -> URL? {
        guard exists(change.item) else { throw FileMoverError.missing(change.item.lastPathComponent) }
        switch change {
        case .added(let item):
            try delete(item, edits: edits)
            return nil
        case .movedIn(let item, let from):
            let destination = try moveOut(item, to: from.deletingLastPathComponent(), named: from.lastPathComponent, edits: edits)
            Log.info("Undo: \(item.lastPathComponent) back to \(destination.path(percentEncoded: false))")
            return destination
        case .movedBetweenShelves(let item, let from):
            let shelf = from.deletingLastPathComponent()
            guard isDirectory(shelf) else { throw FileMoverError.originMissing(shelf.path(percentEncoded: false)) }
            return try move(item, toShelf: shelf, named: from.lastPathComponent, edits: edits)
        }
    }

    // MARK: Helpers

    /// One operation, its manifest changes written when it's done.
    private func once<T>(_ operation: (ManifestEdits) throws -> T) throws -> T {
        let edits = ManifestEdits()
        let result = try operation(edits)
        if let error = edits.write().values.first { throw error }
        return result
    }

    /// The same operation on each input, then each manifest written once. An
    /// input whose manifest change couldn't be written fails with that error,
    /// as it would on its own.
    private func batch<Input, T>(_ inputs: [Input], _ operation: (Input, ManifestEdits) throws -> T) -> [Result<T, any Error>] {
        let edits = ManifestEdits()
        let results = inputs.enumerated().map { index, input in
            edits.item = index
            return Result { try operation(input, edits) }
        }
        let failed = edits.write()
        return results.enumerated().map { index, result in
            if case .success = result, let error = failed[index] { return .failure(error) }
            return result
        }
    }

    /// Moves a stashed item out of Stash into `folder` as `name` (or a numbered
    /// name if that's taken), and forgets it in its shelf's manifest.
    private func moveOut(_ item: URL, to folder: URL, named name: String, edits: ManifestEdits) throws -> URL {
        guard isDirectory(folder) else { throw FileMoverError.originMissing(folder.path(percentEncoded: false)) }
        let destination = FileNaming.uniqueDestination(for: name, in: folder, isDirectory: isDirectory(item))
        try transfer(item, to: destination)
        edits.change(item.deletingLastPathComponent()) { $0.remove(item.lastPathComponent) }
        return destination
    }

    /// On the same volume this is an instant rename. Across volumes it copies,
    /// checks the copy matches, then deletes the original, like a Finder move.
    /// `measured`: the source's size if it was just taken (for asking about big
    /// files), so it isn't walked again; if it has changed since, the copy won't
    /// match and the original stays.
    func transfer(_ source: URL, to destination: URL, measured: FileSize.Measurement? = nil) throws {
        let folder = destination.deletingLastPathComponent()
        if !simulateOtherVolume, try sameVolume(source, folder) {
            try Coordinated.move(source, to: destination)
            return
        }

        let staging = folder.appending(path: ".seashell-incoming-\(UUID().uuidString)")
        do {
            try Coordinated.read(source) { try FileManager.default.copyItem(at: $0, to: staging) }
            let original = try measured ?? FileSize.measure(source)
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

/// The manifest changes of one operation or batch, written once per shelf at
/// the end, so trashing or moving many items doesn't rewrite (and re-upload to
/// iCloud) a shelf's manifest for each one.
private final class ManifestEdits {
    /// Which of the batch's inputs is being worked on.
    var item = 0
    private var edits: [(item: Int, shelf: URL, change: (inout ShelfManifest) -> Void)] = []
    /// Shelves' Put Back origins, read once each, as they were before the batch.
    private var origins: [URL: [String: String]] = [:]

    func change(_ shelf: URL, _ change: @escaping (inout ShelfManifest) -> Void) {
        edits.append((item, Self.key(shelf), change))
    }

    /// Where the stashed `item` came from, if its shelf's manifest knows.
    func origin(of item: URL) -> String? {
        let shelf = Self.key(item.deletingLastPathComponent())
        if origins[shelf] == nil { origins[shelf] = ShelfManifest.read(in: shelf).origins }
        return origins[shelf]?[item.lastPathComponent]
    }

    /// Writes each shelf's changes, in order, in one update. Returns the error
    /// for each input whose changes couldn't be written.
    func write() -> [Int: any Error] {
        var failed: [Int: any Error] = [:]
        var shelves: [URL] = []
        for edit in edits where !shelves.contains(edit.shelf) { shelves.append(edit.shelf) }
        for shelf in shelves {
            let mine = edits.filter { $0.shelf == shelf }
            do {
                try ShelfManifest.update(in: shelf) { manifest in mine.forEach { $0.change(&manifest) } }
            } catch {
                mine.forEach { failed[$0.item] = error }
            }
        }
        return failed
    }

    /// One spelling per folder, so a shelf reached two ways is still written once.
    private static func key(_ folder: URL) -> URL {
        URL(filePath: folder.path(percentEncoded: false), directoryHint: .isDirectory).standardizedFileURL
    }
}
