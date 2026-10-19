import Foundation
import Testing
@testable import SeashellCore

struct ChecklistTests {
    /// Applies an edit the way the editor does, returning the text and where the cursor ends up.
    private func apply(_ edit: NoteEdit, to text: String) -> (text: String, selection: NSRange?) {
        ((text as NSString).replacingCharacters(in: edit.range, with: edit.replacement), edit.selection)
    }

    // MARK: Finding to-dos

    @Test func findsToDosAndDoneOnes() {
        let text = "Groceries\n- [ ] milk\n- [x] eggs\n  * [X] nested\n+ [ ]\nplain - [ ] not one\n-[ ] no space\n- [ ]tight"
        let items = Checklist.items(in: text)
        let ns = text as NSString
        #expect(items.map { ns.substring(with: $0.words) } == ["milk", "eggs", "nested", ""])
        #expect(items.map(\.isDone) == [false, true, true, false])
        #expect(ns.substring(with: items[2].marker) == "* [X]")
        #expect(ns.substring(with: items[2].line) == "  * [X] nested")
    }

    @Test func itemAtLocationLooksAtThatLine() {
        let text = "Title\n- [ ] milk\nmore"
        #expect(Checklist.item(at: 0, in: text) == nil)
        #expect(Checklist.item(at: 8, in: text)?.isDone == false)
        #expect(Checklist.item(at: 16, in: text) != nil)  // its line break still counts as its line
        #expect(Checklist.item(at: 17, in: text) == nil)
        #expect(Checklist.item(at: (text as NSString).length, in: text) == nil)
    }

    // MARK: Ticking

    @Test func tickingFlipsTheBox() throws {
        let text = "- [ ] milk\n- [x] eggs"
        let items = Checklist.items(in: text)
        let ticked = apply(Checklist.toggle(items[0]), to: text)
        #expect(ticked.text == "- [x] milk\n- [x] eggs")
        #expect(ticked.selection == nil)
        #expect(apply(Checklist.toggle(items[1]), to: text).text == "- [ ] milk\n- [ ] eggs")
    }

    // MARK: Return (MarkdownList, as for any list item)

    @Test func returnStartsTheNextToDo() {
        let text = "  - [x] milk"
        let edit = MarkdownList.newline(in: text, selection: NSRange(location: 12, length: 0))
        let result = edit.map { apply($0, to: text) }
        #expect(result?.text == "  - [x] milk\n  - [ ] ")
        #expect(result?.selection == NSRange(location: 21, length: 0))
    }

    @Test func returnInTheMiddleSplitsTheWords() {
        let text = "- [ ] milk eggs"
        let result = MarkdownList.newline(in: text, selection: NSRange(location: 10, length: 0)).map { apply($0, to: text) }
        #expect(result?.text == "- [ ] milk\n- [ ]  eggs")
    }

    @Test func returnOnAnEmptyToDoEndsTheList() {
        let text = "- [ ] milk\n- [ ] "
        let result = MarkdownList.newline(in: text, selection: NSRange(location: 17, length: 0)).map { apply($0, to: text) }
        #expect(result?.text == "- [ ] milk\n")
        #expect(result?.selection == NSRange(location: 11, length: 0))
    }

    @Test func returnElsewhereIsAPlainLineBreak() {
        #expect(MarkdownList.newline(in: "milk", selection: NSRange(location: 4, length: 0)) == nil)
        // In the marker, or with text selected.
        #expect(MarkdownList.newline(in: "- [ ] milk", selection: NSRange(location: 2, length: 0)) == nil)
        #expect(MarkdownList.newline(in: "- [ ] milk", selection: NSRange(location: 6, length: 4)) == nil)
    }

    // MARK: ⇧⌘L

    @Test func makesTheCursorsLineAToDo() {
        let text = "Groceries\nmilk"
        let result = apply(Checklist.toggleLines(in: text, selection: NSRange(location: 12, length: 0)), to: text)
        #expect(result.text == "Groceries\n- [ ] milk")
        #expect(result.selection == NSRange(location: 18, length: 0))  // still between "mi" and "lk"
    }

    @Test func emptyLineBecomesAnEmptyToDo() {
        let text = "Groceries\n"
        let result = apply(Checklist.toggleLines(in: text, selection: NSRange(location: 10, length: 0)), to: text)
        #expect(result.text == "Groceries\n- [ ] ")
        #expect(result.selection == NSRange(location: 16, length: 0))
    }

    @Test func selectedLinesBecomeToDosKeepingBulletsAndSkippingBlanks() {
        let text = "milk\n\n- eggs\n  bread\n- [x] tea\nafter"
        let selection = NSRange(location: 0, length: (text as NSString).range(of: "after").location)
        let result = apply(Checklist.toggleLines(in: text, selection: selection), to: text)
        #expect(result.text == "- [ ] milk\n\n- [ ] eggs\n  - [ ] bread\n- [x] tea\nafter")
    }

    @Test func allToDosGoBackToPlainLines() {
        let text = "- [ ] milk\n  - [x] eggs"
        let result = apply(Checklist.toggleLines(in: text, selection: NSRange(location: 0, length: 23)), to: text)
        #expect(result.text == "milk\n  eggs")
        #expect(result.selection == NSRange(location: 0, length: 11))
    }

    // MARK: Titles

    @Test func titleDropsTheToDoMarker() {
        #expect(Checklist.withoutMarker("- [ ] Buy milk") == "Buy milk")
        #expect(Checklist.withoutMarker("- [x] Done") == "Done")
        #expect(Checklist.withoutMarker("- milk") == "- milk")
        #expect(NoteNaming.title(for: "\n- [ ] Call the bank\n- [ ] Pay rent") == "Call the bank")
        #expect(NoteNaming.title(for: "- [ ]") == "Untitled")
    }
}
