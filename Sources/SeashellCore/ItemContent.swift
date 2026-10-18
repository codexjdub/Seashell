import Foundation

/// What a text or link item holds, for dragging it out as content rather than
/// as a file.
public enum ItemContent {
    /// Larger text files drag out as files only.
    public static let maxTextBytes = 1_000_000

    /// The text of a text item. Nil if it's too big, not text, or only in iCloud
    /// (reading it would stall while it downloads).
    public static func text(of url: URL) -> String? {
        guard let size = try? FileSize.of(url), size <= maxTextBytes,
              CloudStatus.state(of: url) != .cloudOnly,
              let data = try? Coordinated.read(url, { try Data(contentsOf: $0) })
        else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16)
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
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > maxCharacters ? String(text.prefix(maxCharacters)) + "…" : text
    }

    /// The address in a `.webloc`.
    public static func link(of url: URL) -> URL? {
        guard CloudStatus.state(of: url) != .cloudOnly,
              let data = try? Coordinated.read(url, { try Data(contentsOf: $0) }),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let address = plist["URL"] as? String
        else { return nil }
        return URL(string: address)
    }
}
