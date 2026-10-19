import Foundation

/// The Notes folder's `.seashell.json`: which notes are pinned to the top of
/// the list. It syncs with the folder, so every Mac sees the same pins.
public struct NotesManifest: Codable, Equatable, Sendable {
    public static let fileName = ShelfManifest.fileName

    public var version = 1
    /// File names of pinned notes.
    public var pinned: [String] = []

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        pinned = try container.decodeIfPresent([String].self, forKey: .pinned) ?? []
    }

    static func url(in folder: URL) -> URL {
        folder.appending(path: fileName, directoryHint: .notDirectory)
    }

    /// The folder's manifest. A missing or unreadable one counts as empty.
    public static func read(in folder: URL) -> NotesManifest {
        let url = url(in: folder)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return NotesManifest() }
        do {
            return try Coordinated.read(url) { try JSONDecoder().decode(NotesManifest.self, from: Data(contentsOf: $0)) }
        } catch {
            Log.error("Unreadable \(fileName) in Notes: \(error.localizedDescription)")
            return NotesManifest()
        }
    }

    /// Read, change and write back under one coordinated write, as
    /// ShelfManifest.update does: one that exists but can't be read is left alone.
    static func update(in folder: URL, _ change: (inout NotesManifest) -> Void) throws {
        try Coordinated.write(url(in: folder), options: .forMerging) { url in
            var manifest = NotesManifest()
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                do {
                    manifest = try JSONDecoder().decode(NotesManifest.self, from: Data(contentsOf: url))
                } catch {
                    throw ShelfManifestError.unreadable(folder.lastPathComponent)
                }
            }
            change(&manifest)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(to: url, options: .atomic)
        }
    }
}
