import Foundation

/// To-dos in notes, written as Markdown task lines: `- [ ] milk` to do,
/// `- [x] eggs` done (`*` or `+` work too, indented or not). The note stays
/// plain text; this finds them and works out the edits for ticking and ⇧⌘L.
/// (Return on a to-do is MarkdownList's, as for any list item.) Ranges count
/// UTF-16 units, as NSString and NSTextView do.
public enum Checklist {
    public struct Item: Equatable, Sendable {
        /// The whole line, without its line break.
        public let line: NSRange
        /// From the bullet to the box: `- [ ]`. Clicking here ticks it.
        public let marker: NSRange
        /// `[ ]` or `[x]`.
        public let box: NSRange
        public let isDone: Bool
        /// Where the to-do's own words start, after `] `.
        public let textStart: Int

        /// The to-do's own words.
        public var words: NSRange { NSRange(location: textStart, length: NSMaxRange(line) - textStart) }
    }

    // Indentation, bullet, space, box; then a space or the end of the line.
    private static let task = try! NSRegularExpression(
        pattern: #"^[ \t]*([-*+]) \[([ xX])\](?=[ \t]|$)"#, options: [.anchorsMatchLines])
    private static let bullet = try! NSRegularExpression(pattern: #"^[ \t]*[-*+] "#)

    /// Every to-do in `text`, top to bottom.
    public static func items(in text: String) -> [Item] {
        let ns = text as NSString
        return task.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { item(from: $0, in: ns) }
    }

    /// The to-do on the line holding `location`, if that line is one.
    public static func item(at location: Int, in text: String) -> Item? {
        let ns = text as NSString
        guard location >= 0, location <= ns.length else { return nil }
        let line = NoteLines.contents(ofLineAt: location, in: ns)
        return task.firstMatch(in: text, range: line).map { item(from: $0, in: ns) }
    }

    /// Ticks `item`, or unticks it if it's done.
    public static func toggle(_ item: Item) -> NoteEdit {
        NoteEdit(range: NSRange(location: item.box.location + 1, length: 1), replacement: item.isDone ? " " : "x", selection: nil)
    }

    /// ⇧⌘L: the line holding the cursor, or every selected line, becomes a
    /// to-do; if they all are already, they go back to plain lines. A plain
    /// bulleted line keeps its bullet.
    public static func toggleLines(in text: String, selection: NSRange) -> NoteEdit {
        let ns = text as NSString
        let lines = NoteLines.lines(in: ns, covering: selection)
        let filled = lines.filter { $0.contents.length > 0 }
        let removing = !filled.isEmpty && filled.allSatisfy { item(at: $0.contents.location, in: text) != nil }
        return NoteLines.rewrite(text, selection: selection) { line, old in
            if removing, let item = item(at: line.location, in: text) {
                // Keep the indentation, drop "- [ ] ".
                let indent = ns.substring(with: NSRange(location: line.location, length: item.marker.location - line.location))
                return indent + ns.substring(with: item.words)
            }
            guard !removing, item(at: line.location, in: text) == nil, !(old.isEmpty && lines.count > 1) else { return nil }
            return withBox(old)
        }
    }

    /// A note's first line as a title: without its to-do marker.
    public static func withoutMarker(_ line: String) -> String {
        let ns = line as NSString
        guard let match = task.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return line }
        return ns.substring(from: NSMaxRange(match.range)).trimmingCharacters(in: .whitespaces)
    }

    // MARK: Helpers

    private static func item(from match: NSTextCheckingResult, in ns: NSString) -> Item {
        let bullet = match.range(at: 1)
        let box = NSRange(location: bullet.location + 2, length: 3)
        let line = NoteLines.contents(ofLineAt: match.range.location, in: ns)
        var textStart = NSMaxRange(box)
        if textStart < NSMaxRange(line), [" ", "\t"].contains(ns.substring(with: NSRange(location: textStart, length: 1))) {
            textStart += 1
        }
        return Item(line: line, marker: NSRange(location: bullet.location, length: NSMaxRange(box) - bullet.location),
                    box: box, isDone: ns.substring(with: match.range(at: 2)) != " ", textStart: textStart)
    }

    /// "- milk" → "- [ ] milk"; "milk" → "- [ ] milk"; indentation stays.
    private static func withBox(_ line: String) -> String {
        let ns = line as NSString
        if let match = bullet.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
            return ns.substring(to: NSMaxRange(match.range)) + "[ ] " + ns.substring(from: NSMaxRange(match.range))
        }
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        return indent + "- [ ] " + line.dropFirst(indent.count)
    }
}
