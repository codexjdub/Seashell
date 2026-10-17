import Foundation

/// Where Seashell keeps things. Stash and Notes live in Documents so iCloud syncs
/// them; anything that only makes sense on this Mac lives in Application Support.
public struct SeashellFolders: Sendable {
    public static let defaultShelfName = "Main"

    /// `~/Documents/Seashell`
    public let root: URL
    /// `~/Library/Application Support/Seashell`
    public let support: URL

    public var stash: URL { root.appending(path: "Stash", directoryHint: .isDirectory) }
    public var defaultShelf: URL { stash.appending(path: Self.defaultShelfName, directoryHint: .isDirectory) }
    public var notes: URL { root.appending(path: "Notes", directoryHint: .isDirectory) }

    public init(root: URL, support: URL) {
        self.root = root
        self.support = support
    }

    public static var standard: SeashellFolders {
        SeashellFolders(
            root: URL.documentsDirectory.appending(path: "Seashell", directoryHint: .isDirectory),
            support: URL.applicationSupportDirectory.appending(path: "Seashell", directoryHint: .isDirectory)
        )
    }

    /// Creates whichever of Stash/Main, Notes and Application Support are missing,
    /// and returns the ones it created. Existing folders and their contents are left alone.
    @discardableResult
    public func createMissing() throws -> [URL] {
        let fileManager = FileManager.default
        var created: [URL] = []
        for folder in [defaultShelf, notes, support] where !fileManager.fileExists(atPath: folder.path(percentEncoded: false)) {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            created.append(folder)
        }
        return created
    }
}
