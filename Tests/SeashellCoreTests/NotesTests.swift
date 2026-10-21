import Foundation
import Testing
@testable import SeashellCore

struct NoteNamingTests {
    @Test func firstLineIsTheTitle() {
        #expect(NoteNaming.title(for: "Groceries\nmilk\neggs") == "Groceries")
        #expect(NoteNaming.title(for: "\n\n   Trip plan  \nday 1") == "Trip plan")
    }

    @Test func headingMarksAreDropped() {
        #expect(NoteNaming.title(for: "## Meeting notes") == "Meeting notes")
    }

    @Test func unsafeCharactersAndLength() {
        #expect(NoteNaming.title(for: "a/b: c") == "a-b- c")
        #expect(NoteNaming.title(for: String(repeating: "x", count: 100)).count == NoteNaming.maxTitleLength)
    }

    @Test func emojiTitlesFitAFileName() {
        let family = "👨‍👩‍👧‍👦"  // one character, 11 UTF-16 units
        let title = NoteNaming.title(for: String(repeating: family, count: 30))
        #expect(title.utf16.count <= FileNaming.maxNameLength)
        #expect(!title.isEmpty && title.allSatisfy { $0 == Character(family) }, "cut between emoji, not inside one")
    }

    @Test func onlyTheFirstFilledLineCounts() {
        #expect(NoteNaming.title(for: "\r\n  \r\nTrip\r\nday 1") == "Trip")
        #expect(NoteNaming.title(for: "Trip") == "Trip", "a single line with no break")
    }

    @Test func emptyIsUntitled() {
        #expect(NoteNaming.title(for: " \n\t") == "Untitled")
        #expect(NoteNaming.title(for: "###") == "Untitled")
    }
}

struct NotesLibraryTests {
    let folder = TestFolder()
    let notesFolder: URL
    let library: NotesLibrary

    init() throws {
        notesFolder = try folder.folder("Notes")
        let trash = try folder.folder("Trash")
        library = NotesLibrary(folder: notesFolder, trash: { url in
            try FileManager.default.moveItem(at: url, to: trash.appending(path: url.lastPathComponent))
        })
    }

    private func setModified(_ url: URL, _ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path(percentEncoded: false))
    }

    @Test func listsMarkdownNewestFirst() throws {
        let old = try folder.file("Notes/Old.md")
        let new = try folder.file("Notes/New.md")
        try folder.file("Notes/picture.png")
        try folder.file("Notes/.hidden.md")
        try setModified(old, Date(timeIntervalSinceNow: -3600))
        try setModified(new, Date(timeIntervalSinceNow: -60))
        #expect(library.notes().map(\.title) == ["New", "Old"])
    }

    @Test func createNamesAfterFirstLine() throws {
        let note = try library.create(text: "Groceries\nmilk")
        #expect(note.url.lastPathComponent == "Groceries.md")
        #expect(try library.read(note) == "Groceries\nmilk")
        #expect(try library.create(text: "Groceries\neggs").url.lastPathComponent == "Groceries 2.md")
    }

    @Test func saveOverwritesWhenUnchangedElsewhere() throws {
        let note = try library.create(text: "Groceries")
        let result = try library.save("Groceries\nmilk", to: note)
        guard case .saved(let saved) = result else { Issue.record("expected a plain save"); return }
        #expect(saved.url == note.url)
        #expect(try library.read(saved) == "Groceries\nmilk")
    }

    @Test func saveKeepsBothWhenChangedElsewhere() throws {
        let note = try library.create(text: "Groceries")
        // Another Mac edits it after we read it.
        try Data("Groceries\nfrom the other Mac".utf8).write(to: note.url)
        try setModified(note.url, note.modified.addingTimeInterval(5))

        let result = try library.save("Groceries\nfrom this Mac", to: note)
        guard case .savedAsCopy(let copy) = result else { Issue.record("expected a separate copy"); return }
        #expect(copy.url.lastPathComponent == "Groceries (edited here).md")
        #expect(try library.read(copy) == "Groceries\nfrom this Mac")
        #expect(try String(contentsOf: note.url, encoding: .utf8) == "Groceries\nfrom the other Mac")
    }

    @Test func renameFollowsFirstLine() throws {
        let note = try library.create(text: "Draft")
        let renamed = try library.renameToFirstLine(note, text: "Trip plan\nday 1")
        #expect(renamed.url.lastPathComponent == "Trip plan.md")
        #expect(!exists(note.url))
        #expect(try library.renameToFirstLine(renamed, text: "Trip plan\nday 2") == renamed)
    }

    @Test func renameAvoidsOtherNotes() throws {
        _ = try library.create(text: "Groceries")
        let note = try library.create(text: "Other")
        #expect(try library.renameToFirstLine(note, text: "Groceries\nmore").url.lastPathComponent == "Groceries 2.md")
    }

    @Test func renameCanChangeJustTheCase() throws {
        let note = try library.create(text: "groceries")
        let renamed = try library.renameToFirstLine(note, text: "Groceries")
        #expect(library.notes().map(\.url.lastPathComponent) == ["Groceries.md"])
        #expect(renamed.title == "Groceries")
    }

    @Test func deleteSendsToTrash() throws {
        let note = try library.create(text: "Groceries")
        try library.delete(note)
        #expect(library.notes().isEmpty)
        #expect(folder.names(in: folder.root.appending(path: "Trash")) == ["Groceries.md"])
    }

    @Test func noteSharingATitleKeepsItsNumberedName() throws {
        _ = try library.create(text: "Groceries\nmilk")
        var second = try library.create(text: "Groceries\neggs")
        #expect(second.title == "Groceries 2")
        for _ in 0..<3 { second = try library.renameToFirstLine(second, text: "Groceries\neggs") }
        #expect(second.title == "Groceries 2", "leaving it again and again doesn't rename it")
        #expect(library.notes().map(\.title).sorted() == ["Groceries", "Groceries 2"])
    }

    @Test func numberedNoteTakesThePlainNameOnceFree() throws {
        let first = try library.create(text: "Groceries\nmilk")
        let second = try library.create(text: "Groceries\neggs")
        try library.delete(first)
        #expect(try library.renameToFirstLine(second, text: "Groceries\neggs").title == "Groceries")
    }

    // MARK: Pinning

    @Test func pinnedNotesComeFirst() throws {
        let old = try folder.file("Notes/Old.md")
        let middle = try folder.file("Notes/Middle.md")
        try folder.file("Notes/New.md")
        try setModified(old, Date(timeIntervalSinceNow: -3600))
        try setModified(middle, Date(timeIntervalSinceNow: -1800))
        for name in ["Old", "Middle"] {
            try library.setPinned(try #require(library.notes().first { $0.title == name }), true)
        }
        #expect(library.notes().map(\.title) == ["Middle", "Old", "New"])
        #expect(library.notes().map(\.isPinned) == [true, true, false])
        #expect(library.note(at: old)?.isPinned == true)

        try library.setPinned(try #require(library.note(at: old)), false)
        #expect(library.notes().map(\.title) == ["Middle", "New", "Old"])
    }

    @Test func pinFollowsARenameAndLeavesWithTheTrash() throws {
        let note = try library.create(text: "Draft")
        try library.setPinned(note, true)
        let renamed = try library.renameToFirstLine(note, text: "Trip plan")
        #expect(renamed.isPinned)
        #expect(NotesManifest.read(in: notesFolder).pinned == ["Trip plan.md"])

        try library.delete(renamed)
        #expect(NotesManifest.read(in: notesFolder).pinned.isEmpty)
    }

    @Test func pinningTwiceKeepsOneEntry() throws {
        let note = try library.create(text: "Groceries")
        try library.setPinned(note, true)
        try library.setPinned(note, true)
        #expect(NotesManifest.read(in: notesFolder).pinned == ["Groceries.md"])
    }

    @Test func unreadablePinsAreLeftAlone() throws {
        let note = try library.create(text: "Groceries")
        let manifest = try folder.file("Notes/\(NotesManifest.fileName)", "{ not json")
        #expect(throws: ShelfManifestError.unreadable("Notes")) { try library.setPinned(note, true) }
        #expect(try text(manifest) == "{ not json")
        #expect(library.notes().map(\.title) == ["Groceries"])
    }

    @Test func pinsOfNotesGoneAreFoundWithTheList() throws {
        let kept = try library.create(text: "Kept")
        let gone = try library.create(text: "Gone")
        try library.setPinned(kept, true)
        try library.setPinned(gone, true)
        try FileManager.default.removeItem(at: gone.url)
        let contents = library.contents()
        #expect(contents.notes.map(\.title) == ["Kept"])
        #expect(contents.vanishedPins == ["Gone.md"])
    }

    @Test func savingKeepsThePin() throws {
        let note = try library.create(text: "Groceries")
        try library.setPinned(note, true)
        let pinned = try #require(library.note(at: note.url))
        #expect(try library.save("Groceries\nmilk", to: pinned).note.isPinned)
    }

    @MainActor @Test func pinsOfNotesGoneElsewhereAreForgottenAfterAWhile() async throws {
        let note = try library.create(text: "Groceries\nmilk")
        try library.setPinned(note, true)
        try FileManager.default.removeItem(at: note.url)  // deleted in Finder

        let store = NotesStore(library: library, pruneGrace: 0.3)
        #expect(NotesManifest.read(in: notesFolder).pinned == ["Groceries.md"], "kept during the grace period")
        for _ in 0..<30 where !NotesManifest.read(in: notesFolder).pinned.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(NotesManifest.read(in: notesFolder).pinned.isEmpty)
        #expect(try library.create(text: "Groceries\neggs").isPinned == false, "a new note of that name isn't pinned")
        withExtendedLifetime(store) {}
    }

    @MainActor @Test func aPinnedNoteBackWithinTheGraceKeepsItsPin() async throws {
        let note = try library.create(text: "Groceries\nmilk")
        try library.setPinned(note, true)
        let away = folder.root.appending(path: "Groceries.md")
        try FileManager.default.moveItem(at: note.url, to: away)

        let store = NotesStore(library: library, pruneGrace: 0.5)
        try FileManager.default.moveItem(at: away, to: note.url)  // e.g. iCloud catching up
        try await Task.sleep(for: .milliseconds(900))
        #expect(NotesManifest.read(in: notesFolder).pinned == ["Groceries.md"])
        withExtendedLifetime(store) {}
    }

    // MARK: Long names

    @Test func emojiTitlesStillSave() throws {
        let family = try library.create(text: String(repeating: "👨‍👩‍👧‍👦", count: 30))
        #expect(exists(family.url))
        // A note of 60 flags, changed on another Mac: this version goes to its
        // " (edited here)" copy, which must fit too.
        let flags = try library.create(text: String(repeating: "🇺🇸", count: 60))
        try Data("from the other Mac".utf8).write(to: flags.url)
        try setModified(flags.url, flags.modified.addingTimeInterval(5))
        guard case .savedAsCopy(let copy) = try library.save("from this Mac", to: flags) else {
            Issue.record("expected a separate copy")
            return
        }
        #expect(try library.read(copy) == "from this Mac")
    }
}
