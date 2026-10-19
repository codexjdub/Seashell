import Foundation

/// A change to a note's text, as the editor makes it: replace `range` with
/// `replacement`, then select `selection` (nil: leave the selection be).
/// Ranges count UTF-16 units, as NSString and NSTextView do.
public struct NoteEdit: Equatable, Sendable {
    public let range: NSRange
    public let replacement: String
    public let selection: NSRange?
}

/// A note's lines, for the editing that works line by line (lists, to-dos).
enum NoteLines {
    struct Line {
        /// Without its line break.
        let contents: NSRange
        let terminator: NSRange
    }

    /// The line holding `location`, without its line break.
    static func contents(ofLineAt location: Int, in ns: NSString) -> NSRange {
        var start = 0
        var contentsEnd = 0
        ns.getLineStart(&start, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
        return NSRange(location: start, length: contentsEnd - start)
    }

    /// The lines `selection` touches. A selection ending right at a line's
    /// start doesn't take in that line.
    static func lines(in ns: NSString, covering selection: NSRange) -> [Line] {
        var lines: [Line] = []
        var location = selection.location
        let last = selection.length > 0 ? NSMaxRange(selection) - 1 : selection.location
        repeat {
            var start = 0
            var end = 0
            var contentsEnd = 0
            ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            lines.append(Line(contents: NSRange(location: start, length: contentsEnd - start),
                              terminator: NSRange(location: contentsEnd, length: end - contentsEnd)))
            location = end
        } while location <= last && location < ns.length
        return lines
    }

    /// Rewrites each line `selection` touches with `change` (nil leaves a line
    /// as it is), as one edit. Within one line the selection keeps its place in
    /// the words; across lines it grows to cover them all.
    static func rewrite(_ text: String, selection: NSRange,
                        _ change: (_ line: NSRange, _ contents: String) -> String?) -> NoteEdit {
        let ns = text as NSString
        let lines = self.lines(in: ns, covering: selection)
        var replacement = ""
        var kept: NSRange?
        for line in lines {
            let old = ns.substring(with: line.contents)
            let new = change(line.contents, old) ?? old
            if lines.count == 1 {
                let start = line.contents.location
                let length = (new as NSString).length
                func moved(_ location: Int) -> Int { max(start, start + length - (NSMaxRange(line.contents) - location)) }
                let from = moved(selection.location)
                kept = NSRange(location: from, length: moved(NSMaxRange(selection)) - from)
            }
            replacement += new + ns.substring(with: line.terminator)
        }
        let range = NSRange(location: lines[0].contents.location,
                            length: lines.reduce(0) { $0 + $1.contents.length + $1.terminator.length })
        return NoteEdit(range: range, replacement: replacement,
                        selection: kept ?? NSRange(location: range.location, length: (replacement as NSString).length))
    }
}

/// Bulleted (`- `, `* `, `+ `) and numbered (`1. `, `1) `) lists in notes:
/// Return starts the next item, and Tab and ⇧Tab move lines in and out a level
/// (a tab each, which nests under any kind of item in Markdown). To-dos are
/// list items too; Checklist handles their boxes.
public enum MarkdownList {
    struct Item {
        /// The whole line, without its line break.
        let line: NSRange
        let indent: String
        /// `-`, `*` or `+`; nil for a numbered item.
        let bullet: String?
        let number: Int?
        /// `.` or `)` after a number.
        let delimiter: String
        /// Where the item's words start, after the marker and its space.
        let textStart: Int
    }

    private static let pattern = try! NSRegularExpression(pattern: #"^([ \t]*)(?:([-*+])|([0-9]{1,9})([.)]))[ \t]"#)

    static func item(at location: Int, in ns: NSString) -> Item? {
        guard location >= 0, location <= ns.length else { return nil }
        let line = NoteLines.contents(ofLineAt: location, in: ns)
        guard let match = pattern.firstMatch(in: ns as String, range: line) else { return nil }
        func group(_ index: Int) -> String? {
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : ns.substring(with: range)
        }
        return Item(line: line, indent: group(1) ?? "", bullet: group(2), number: group(3).flatMap { Int($0) },
                    delimiter: group(4) ?? "", textStart: NSMaxRange(match.range))
    }

    /// Return on a list item starts the next one: the same bullet, the next
    /// number, or a new box for a to-do. On an empty item it moves the item out
    /// a level, or ends the list if it isn't indented. Nil when Return should
    /// simply break the line.
    public static func newline(in text: String, selection: NSRange) -> NoteEdit? {
        let ns = text as NSString
        guard selection.length == 0, let item = item(at: selection.location, in: ns) else { return nil }
        let todo = Checklist.item(at: selection.location, in: text)
        let textStart = todo?.textStart ?? item.textStart
        guard selection.location >= textStart else { return nil }

        let words = ns.substring(with: NSRange(location: textStart, length: NSMaxRange(item.line) - textStart))
        if words.trimmingCharacters(in: .whitespaces).isEmpty {
            if let out = outdented(item.indent) {
                let indent = NSRange(location: item.line.location, length: (item.indent as NSString).length)
                let shift = indent.length - (out as NSString).length
                return NoteEdit(range: indent, replacement: out, selection: NSRange(location: selection.location - shift, length: 0))
            }
            return NoteEdit(range: item.line, replacement: "", selection: NSRange(location: item.line.location, length: 0))
        }
        let marker = item.number.map { "\($0 + 1)\(item.delimiter)" } ?? item.bullet ?? "-"
        let next = "\n" + item.indent + marker + " " + (todo != nil ? "[ ] " : "")
        return NoteEdit(range: NSRange(location: selection.location, length: 0), replacement: next,
                        selection: NSRange(location: selection.location + (next as NSString).length, length: 0))
    }

    /// Tab: the cursor's line in a level if it's a list item, or every selected
    /// line when several are selected (blank ones stay as they are). Nil when
    /// Tab should just type a tab.
    public static func indent(in text: String, selection: NSRange) -> NoteEdit? {
        let ns = text as NSString
        let several = NoteLines.lines(in: ns, covering: selection).count > 1
        guard several || item(at: selection.location, in: ns) != nil else { return nil }
        return NoteLines.rewrite(text, selection: selection) { _, line in
            several && line.trimmingCharacters(in: .whitespaces).isEmpty ? nil : "\t" + line
        }
    }

    /// ⇧Tab: the cursor's line, or the selected lines, out a level: one tab, or
    /// up to four spaces. Nil if none of them is indented.
    public static func outdent(in text: String, selection: NSRange) -> NoteEdit? {
        let ns = text as NSString
        let lines = NoteLines.lines(in: ns, covering: selection)
        guard lines.contains(where: { outdented(ns.substring(with: $0.contents)) != nil }) else { return nil }
        return NoteLines.rewrite(text, selection: selection) { _, line in outdented(line) }
    }

    /// `text` less one level of indentation, or nil if it has none.
    private static func outdented(_ text: String) -> String? {
        if text.hasPrefix("\t") { return String(text.dropFirst()) }
        let spaces = text.prefix(4).prefix { $0 == " " }.count
        return spaces > 0 ? String(text.dropFirst(spaces)) : nil
    }
}
