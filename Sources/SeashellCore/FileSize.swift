import Foundation

public enum FileSize {
    /// Stashing anything bigger asks first: everything in Stash uploads to iCloud.
    public static let confirmationThreshold: Int64 = 1_000_000_000

    /// Logical size of a file, or of everything inside a folder or package.
    public static func of(_ url: URL) throws -> Int64 {
        try measure(url).bytes
    }

    /// Total bytes and number of items (the item itself included), used to check a copy.
    static func measure(_ url: URL) throws -> (bytes: Int64, items: Int) {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey]
        let values = try url.resourceValues(forKeys: keys)
        guard values.isDirectory == true else { return (Int64(values.fileSize ?? 0), 1) }

        var bytes: Int64 = 0
        var items = 1
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        while let file = enumerator?.nextObject() as? URL {
            items += 1
            let values = try file.resourceValues(forKeys: keys)
            if values.isRegularFile == true { bytes += Int64(values.fileSize ?? 0) }
        }
        return (bytes, items)
    }
}
