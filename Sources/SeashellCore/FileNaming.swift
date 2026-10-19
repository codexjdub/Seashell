import Foundation

public enum FileNaming {
    /// A free spot for `name` in `folder`, Finder-style: `report.pdf`, then
    /// `report 2.pdf`, `report 3.pdf`… A numbered copy counts on from its number
    /// (`report 2.pdf` → `report 3.pdf`) when the original is there too; a name
    /// that merely ends in a number keeps it (`Budget 2024.xlsx` → `Budget 2024 2.xlsx`).
    public static func uniqueDestination(for name: String, in folder: URL, isDirectory: Bool) -> URL {
        let hint: URL.DirectoryHint = isDirectory ? .isDirectory : .notDirectory
        let first = folder.appending(path: name, directoryHint: hint)
        guard exists(first) else { return first }

        let ext = isDirectory ? "" : (name as NSString).pathExtension
        var base = ext.isEmpty ? name : (name as NSString).deletingPathExtension
        var number = 2
        if let range = base.range(of: #" [1-9]\d*$"#, options: .regularExpression),
           let existing = Int(base[range].dropFirst()) {
            let original = String(base[..<range.lowerBound])
            if exists(folder.appending(path: ext.isEmpty ? original : "\(original).\(ext)", directoryHint: hint)) {
                number = existing + 1
                base = original
            }
        }
        while true {
            let candidate = folder.appending(path: ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)",
                                             directoryHint: hint)
            if !exists(candidate) { return candidate }
            number += 1
        }
    }

    /// Whether `name` is a numbered copy of `original`, as `uniqueDestination`
    /// names them: `report 2.pdf` for `report.pdf`. Case doesn't matter.
    public static func isNumberedCopy(_ name: String, of original: String) -> Bool {
        let ext = (original as NSString).pathExtension
        let base = (ext.isEmpty ? original : (original as NSString).deletingPathExtension).lowercased()
        let suffix = ext.isEmpty ? "" : ".\(ext.lowercased())"
        let name = name.lowercased()
        guard name.hasPrefix(base + " "), name.hasSuffix(suffix), name.count > base.count + 1 + suffix.count else { return false }
        let number = name.dropFirst(base.count + 1).dropLast(suffix.count)
        return number.first != "0" && number.allSatisfy { $0.isASCII && $0.isNumber } && (Int(number) ?? 0) >= 2
    }

    /// File name for stashed text: its first few words (at most 6 words and 40
    /// characters), or `Snippet 2026-10-17 0942.txt` when it has none.
    public static func snippetName(for text: String, date: Date) -> String {
        var words = text.split(whereSeparator: \.isWhitespace).prefix(6).map(String.init)
        var name = sanitized(words.joined(separator: " "))
        while name.count > 40, words.count > 1 {
            words.removeLast()
            name = sanitized(words.joined(separator: " "))
        }
        if name.count > 40 { name = String(name.prefix(40)) }
        return (name.isEmpty ? "Snippet \(stamp(date))" : name) + ".txt"
    }

    /// File name for a stashed link: the page title, else the site, else "Link".
    public static func linkName(for url: URL, title: String?) -> String {
        let candidates = [title, url.host(percentEncoded: false)].compactMap { $0.map(sanitized) }
        let name = candidates.first { !$0.isEmpty } ?? "Link"
        return String(name.prefix(60)) + ".webloc"
    }

    public static func imageName(date: Date) -> String {
        "Image \(stamp(date)).png"
    }

    /// Makes text safe as a file name: no `/` or `:`, no leading dots, one line.
    public static func sanitized(_ name: String) -> String {
        var cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        return formatter.string(from: date)
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }
}
