import Foundation

/// Choosing where Seashell's folder lives (Settings ▸ Folder): what choosing a
/// folder would do, and moving Seashell's folder into it.
public enum FolderMove {
    public enum Plan: Equatable, Sendable {
        /// It's there already.
        case nothing
        /// The chosen folder already has a Seashell folder with files in it
        /// (synced from another Mac, say): use that as it is, and leave the
        /// current one where it is.
        case useExisting(URL)
        /// Move the current folder to `to`.
        case move(from: URL, to: URL)
        /// The current folder isn't there, so nothing moves: start afresh at the URL.
        case startNew(URL)
    }

    public enum Problem: LocalizedError, Equatable {
        /// The chosen folder is Seashell's own folder, or inside it.
        case insideCurrent
        /// A file, not a folder, is already called Seashell there.
        case fileInTheWay(String)
        /// Files turned up in the Seashell folder there before the move.
        case destinationInUse
        /// The copy on the other disk didn't come out the same size.
        case copyMismatch

        public var errorDescription: String? {
            switch self {
            case .insideCurrent: "That folder is inside Seashell’s own folder. Choose one outside it."
            case .fileInTheWay(let parent): "There’s already a file called “\(SeashellFolders.folderName)” in \(parent)."
            case .destinationInUse: "A Seashell folder with things in it turned up there first."
            case .copyMismatch: "The copy didn’t match the original, so nothing moved."
            }
        }
    }

    /// What choosing `parent` would do with Seashell's folder, now at `current`.
    public static func plan(from current: URL, toParent parent: URL) throws -> Plan {
        let destination = SeashellFolders.root(in: parent)
        let currentPath = canonicalPath(current)
        let destinationPath = canonicalPath(destination)
        if destinationPath == currentPath { return .nothing }
        if destinationPath.hasPrefix(currentPath + "/") { throw Problem.insideCurrent }
        var isDirectory: ObjCBool = false
        // Without the folder's trailing slash, which a file at that path wouldn't match.
        if FileManager.default.fileExists(atPath: parent.appending(path: SeashellFolders.folderName).path(percentEncoded: false),
                                          isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw Problem.fileInTheWay(parent.path(percentEncoded: false)) }
            if !holdsNothing(destination) { return .useExisting(destination) }
        }
        guard FileManager.default.fileExists(atPath: current.path(percentEncoded: false)) else { return .startNew(destination) }
        return .move(from: current, to: destination)
    }

    /// Moves Seashell's folder from `source` to `destination`. A Seashell
    /// folder there with no files in it (empty shelves another Mac made, say)
    /// goes to the Trash first. On the same disk it's renamed. Across disks it's
    /// copied beside the destination, checked to come out the same size and
    /// renamed into place, so a copy that fails leaves both places as they
    /// were; then the original is removed, like a Finder move. Returns the
    /// error if everything moved but the original couldn't all be removed.
    @discardableResult
    public static func move(from source: URL, to destination: URL, trash: FileMover.Trash = FileMover.systemTrash) throws -> (any Error)? {
        try move(from: source, to: destination, copying: !onSameVolume(source, destination.deletingLastPathComponent()), trash: trash)
    }

    static func move(from source: URL, to destination: URL, copying: Bool, trash: FileMover.Trash) throws -> (any Error)? {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            guard holdsNothing(destination) else { throw Problem.destinationInUse }
            try trash(destination)
        }
        guard copying else {
            try Coordinated.move(source, to: destination)
            return nil
        }
        let temporary = destination.deletingLastPathComponent()
            .appending(path: ".\(SeashellFolders.folderName)-moving-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try Coordinated.read(source) { try fileManager.copyItem(at: $0, to: temporary) }
            guard try FileSize.measure(source) == FileSize.measure(temporary) else { throw Problem.copyMismatch }
            try fileManager.moveItem(at: temporary, to: destination)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
        do {
            try Coordinated.write(source, options: .forDeleting) { try fileManager.removeItem(at: $0) }
            return nil
        } catch {
            return error
        }
    }

    /// Whether two URLs name the same folder.
    public static func isSame(_ first: URL, _ second: URL) -> Bool {
        canonicalPath(first) == canonicalPath(second)
    }

    /// A folder with no files anywhere in it: only folders (empty shelves),
    /// Seashell's lists of them and Finder's own files.
    static func holdsNothing(_ folder: URL) -> Bool {
        let ignored: Set<String> = [".DS_Store", ShelfManifest.fileName, "Icon\r"]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey]) else { return false }
        for case let url as URL in enumerator {
            let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            if !isFolder, !ignored.contains(url.lastPathComponent) { return false }
        }
        return true
    }

    static func onSameVolume(_ first: URL, _ second: URL) -> Bool {
        func volume(_ url: URL) -> NSObject? {
            (try? url.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject
        }
        guard let a = volume(first), let b = volume(second) else { return false }
        return a.isEqual(b)
    }

    /// The path with symbolic links resolved as far as it exists, so two names
    /// for one folder (`/var` and `/private/var`, say) compare equal.
    static func canonicalPath(_ url: URL) -> String {
        var existing = url.standardizedFileURL
        var missing: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path(percentEncoded: false)), existing.pathComponents.count > 1 {
            missing.insert(existing.lastPathComponent, at: 0)
            existing = existing.deletingLastPathComponent()
        }
        var path = existing.withUnsafeFileSystemRepresentation { representation -> String? in
            guard let representation, let resolved = realpath(representation, nil) else { return nil }
            defer { free(resolved) }
            return String(cString: resolved)
        } ?? existing.path(percentEncoded: false)
        for component in missing { path = (path as NSString).appendingPathComponent(component) }
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
