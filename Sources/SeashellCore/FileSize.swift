import Foundation

public enum FileSize {
    /// Logical size of a file, or of everything inside a folder or package.
    public static func of(_ url: URL) throws -> Int64 {
        try measure(url).bytes
    }

    /// Total bytes and number of items (the item itself included), used to check a copy.
    public struct Measurement: Equatable, Sendable {
        public let bytes: Int64
        public let items: Int
    }

    public static func measure(_ url: URL) throws -> Measurement {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey]
        let values = try url.resourceValues(forKeys: keys)
        guard values.isDirectory == true else { return Measurement(bytes: Int64(values.fileSize ?? 0), items: 1) }

        var bytes: Int64 = 0
        var items = 1
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        while let file = enumerator?.nextObject() as? URL {
            items += 1
            let values = try file.resourceValues(forKeys: keys)
            if values.isRegularFile == true { bytes += Int64(values.fileSize ?? 0) }
        }
        return Measurement(bytes: bytes, items: items)
    }
}
