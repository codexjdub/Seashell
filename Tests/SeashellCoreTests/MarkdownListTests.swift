import Foundation
import Testing
@testable import SeashellCore

struct MarkdownListTests {
    private func apply(_ edit: NoteEdit?, to text: String) -> (text: String, selection: NSRange?)? {
        edit.map { ((text as NSString).replacingCharacters(in: $0.range, with: $0.replacement), $0.selection) }
    }

    private func caret(_ location: Int) -> NSRange {
        NSRange(location: location, length: 0)
    }

    // MARK: Return

    @Test func bulletsContinue() {
        let result = apply(MarkdownList.newline(in: "- milk", selection: caret(6)), to: "- milk")
        #expect(result?.text == "- milk\n- ")
        #expect(result?.selection == caret(9))
        #expect(apply(MarkdownList.newline(in: "* eggs", selection: caret(6)), to: "* eggs")?.text == "* eggs\n* ")
        #expect(apply(MarkdownList.newline(in: "\t+ tea", selection: caret(6)), to: "\t+ tea")?.text == "\t+ tea\n\t+ ")
    }

    @Test func numbersCountOn() {
        let result = apply(MarkdownList.newline(in: "3. milk", selection: caret(7)), to: "3. milk")
        #expect(result?.text == "3. milk\n4. ")
        #expect(result?.selection == caret(11))
        #expect(apply(MarkdownList.newline(in: "9) a", selection: caret(4)), to: "9) a")?.text == "9) a\n10) ")
    }

    @Test func emptyIndentedItemMovesOutALevel() {
        let tabbed = "- a\n\t- "
        let result = apply(MarkdownList.newline(in: tabbed, selection: caret(7)), to: tabbed)
        #expect(result?.text == "- a\n- ")
        #expect(result?.selection == caret(6))
        let spaced = "- a\n    - "
        #expect(apply(MarkdownList.newline(in: spaced, selection: caret(10)), to: spaced)?.text == "- a\n- ")
    }

    @Test func emptyItemEndsTheList() {
        let text = "1. a\n2. "
        let result = apply(MarkdownList.newline(in: text, selection: caret(8)), to: text)
        #expect(result?.text == "1. a\n")
        #expect(result?.selection == caret(5))
    }

    @Test func otherLinesBreakAsUsual() {
        for text in ["plain", "-milk", "1.5 cups", "#1 thing"] {
            #expect(MarkdownList.newline(in: text, selection: caret((text as NSString).length)) == nil, "\(text)")
        }
        #expect(MarkdownList.newline(in: "- milk", selection: caret(1)) == nil, "in the marker")
        #expect(MarkdownList.newline(in: "- milk", selection: NSRange(location: 2, length: 4)) == nil, "with text selected")
    }

    // MARK: Tab and ⇧Tab

    @Test func tabMovesAListLineIn() {
        let result = apply(MarkdownList.indent(in: "- milk", selection: caret(3)), to: "- milk")
        #expect(result?.text == "\t- milk")
        #expect(result?.selection == caret(4))
        let selected = apply(MarkdownList.indent(in: "- milk", selection: NSRange(location: 2, length: 4)), to: "- milk")
        #expect(selected?.selection == NSRange(location: 3, length: 4))
    }

    @Test func tabElsewhereTypesATab() {
        #expect(MarkdownList.indent(in: "plain", selection: caret(2)) == nil)
    }

    @Test func tabMovesSelectedLinesInSkippingBlanks() {
        let text = "a\n\nb\nafter"
        let result = apply(MarkdownList.indent(in: text, selection: NSRange(location: 0, length: 4)), to: text)
        #expect(result?.text == "\ta\n\n\tb\nafter")
        #expect(result?.selection == NSRange(location: 0, length: 7))
    }

    @Test func shiftTabMovesOutATabOrUpToFourSpaces() {
        #expect(apply(MarkdownList.outdent(in: "\t- milk", selection: caret(4)), to: "\t- milk")?.text == "- milk")
        let spaced = apply(MarkdownList.outdent(in: "  - milk", selection: caret(5)), to: "  - milk")
        #expect(spaced?.text == "- milk")
        #expect(spaced?.selection == caret(3))
        #expect(apply(MarkdownList.outdent(in: "      x", selection: caret(7)), to: "      x")?.text == "  x")
        let lines = "\ta\n    b\nc"
        #expect(apply(MarkdownList.outdent(in: lines, selection: NSRange(location: 0, length: 9)), to: lines)?.text == "a\nb\nc")
    }

    @Test func shiftTabWithNothingIndentedDoesNothing() {
        #expect(MarkdownList.outdent(in: "- milk", selection: caret(3)) == nil)
    }
}
