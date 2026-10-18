import Foundation

/// A shelf's `.seashell.json`: item order and where each item came from. The
/// Stash folder has one too, for the order of the shelves. It syncs with the
/// folder, so every Mac sees the same order.
public struct ShelfManifest: Codable, Equatable, Sendable {
    public static let fileName = ".seashell.json"

    public var version = 1
    /// Item names, newest first. Items missing from it (added in Finder) show before these.
    public var order: [String] = []
    /// Item name → path of the folder it came from, for Put Back.
    public var origins: [String: String] = [:]

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        order = try container.decodeIfPresent([String].self, forKey: .order) ?? []
        origins = try container.decodeIfPresent([String: String].self, forKey: .origins) ?? [:]
    }

    static func url(in shelf: URL) -> URL {
        shelf.appending(path: fileName, directoryHint: .notDirectory)
    }

    /// The shelf's manifest. A missing or unreadable one counts as empty.
    public static func read(in shelf: URL) -> ShelfManifest {
        let url = url(in: shelf)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return ShelfManifest() }
        do {
            return try Coordinated.read(url) { try JSONDecoder().decode(ShelfManifest.self, from: Data(contentsOf: $0)) }
        } catch {
            Log.error("Unreadable \(fileName) in \(shelf.lastPathComponent): \(error.localizedDescription)")
            return ShelfManifest()
        }
    }

    /// Read, change and write back under one coordinated write.
    static func update(in shelf: URL, _ change: (inout ShelfManifest) -> Void) throws {
        try Coordinated.write(url(in: shelf), options: .forReplacing) { url in
            var manifest = (try? JSONDecoder().decode(ShelfManifest.self, from: Data(contentsOf: url))) ?? ShelfManifest()
            change(&manifest)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(to: url, options: .atomic)
        }
    }

    /// Puts `name` first and records its origin, replacing any earlier entry.
    mutating func add(_ name: String, origin: String?) {
        remove(name)
        order.insert(name, at: 0)
        origins[name] = origin
    }

    mutating func remove(_ name: String) {
        order.removeAll { $0 == name }
        origins[name] = nil
    }
}
