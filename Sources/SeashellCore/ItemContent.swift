import Foundation

/// What a text or link item holds, for dragging it out as content rather than
/// as a file.
public enum ItemContent {
    /// Larger text files drag out as files only.
    public static let maxTextBytes = 1_000_000

    /// The text of a text item. Nil if it's too big, not text, or only in iCloud
    /// (reading it would stall while it downloads).
    public static func text(of url: URL) -> String? {
        text(of: url, cloudOnly: { CloudStatus.state(of: url) == .cloudOnly })
    }

    /// The same, going by what `item` already knows about iCloud rather than asking again.
    public static func text(of item: StashItem) -> String? {
        text(of: item.url, cloudOnly: { item.cloud == .cloudOnly })
    }

    private static func text(of url: URL, cloudOnly: () -> Bool) -> String? {
        guard let size = try? FileSize.of(url), size <= maxTextBytes, !cloudOnly(),
              let data = try? Coordinated.read(url, { try Data(contentsOf: $0) })
        else { return nil }
        return isUTF16(data) ? String(data: data, encoding: .utf16) : String(data: data, encoding: .utf8)
    }

    /// UTF-16 is told by the byte order mark it starts with. Without one it
    /// would "decode" almost any bytes (a Latin-1 file comes out as Chinese),
    /// so such a file counts as not text and drags out as the file.
    private static func isUTF16(_ data: Data) -> Bool {
        data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
    }

    /// The text at the start of a file, read the same way; `data` may end
    /// partway through a character.
    private static func partialText(_ data: Data) -> String {
        guard isUTF16(data) else { return String(decoding: data, as: UTF8.self) }
        let littleEndian = data.first == 0xFF
        let bytes = Array(data.dropFirst(2))
        let units = stride(from: 0, to: bytes.count - 1, by: 2).map { index in
            littleEndian ? UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8 : UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])
        }
        return String(decoding: units, as: UTF16.self)
    }

    /// The start of a text item, for showing on its card: reads only the first
    /// few kilobytes. Nil if it's only in iCloud.
    public static func preview(of url: URL, maxCharacters: Int = 300) -> String? {
        guard CloudStatus.state(of: url) != .cloudOnly,
              let data = try? Coordinated.read(url, { url in
                  let handle = try FileHandle(forReadingFrom: url)
                  defer { try? handle.close() }
                  return try handle.read(upToCount: maxCharacters * 4) ?? Data()
              })
        else { return nil }
        let text = partialText(data).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > maxCharacters ? String(text.prefix(maxCharacters)) + "…" : text
    }

    /// The address in a `.webloc`.
    public static func link(of url: URL) -> URL? {
        link(of: url, cloudOnly: CloudStatus.state(of: url) == .cloudOnly)
    }

    /// The same, going by what `item` already knows about iCloud rather than asking again.
    public static func link(of item: StashItem) -> URL? {
        link(of: item.url, cloudOnly: item.cloud == .cloudOnly)
    }

    private static func link(of url: URL, cloudOnly: Bool) -> URL? {
        guard !cloudOnly,
              let data = try? Coordinated.read(url, { try Data(contentsOf: $0) }),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let address = plist["URL"] as? String
        else { return nil }
        return URL(string: address)
    }
}
