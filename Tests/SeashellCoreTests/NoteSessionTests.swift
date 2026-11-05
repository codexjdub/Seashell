import Foundation
import Testing
@testable import SeashellCore

@MainActor
struct NoteSessionTests {
    let folder = TestFolder()
    let library: NotesLibrary
    let session: NoteSession

    init() throws {
        let trash = try folder.folder("Trash")
        library = NotesLibrary(folder: try folder.folder("Notes"), trash: { url in
            try FileManager.default.moveItem(at: url, to: trash.appending(path: url.lastPathComponent))
        })
        session = NoteSession(library: library)
    }

    private func changeElsewhere(_ note: Note, to text: String) throws {
        try Data(text.utf8).write(to: note.url)
        try FileManager.default.setAttributes([.modificationDate: note.modified.addingTimeInterval(5)],
                                              ofItemAtPath: note.url.path(percentEncoded: false))
    }

    @Test func savesOnlyWhenEditsAreWaiting() throws {
        let note = try library.create(text: "Groceries")
        session.start(note)
        #expect(try session.save("Groceries\nmilk") == .nothing)
        #expect(try library.read(note) == "Groceries")

        session.edited()
        guard case .saved(let saved) = try session.save("Groceries\nmilk") else { Issue.record("expected a save"); return }
        #expect(try library.read(saved) == "Groceries\nmilk")
        #expect(session.note == saved)
        #expect(!session.hasUnsavedEdits)
    }

    @Test func aNewNoteGetsItsFileOnceItHasWords() throws {
        session.start(nil)
        session.edited()
        #expect(try session.save("  \n") == .nothing)
        #expect(session.note == nil)
        #expect(library.notes().isEmpty)

        session.edited()
        guard case .created(let created) = try session.save("Trip plan\nday 1") else { Issue.record("expected a new note"); return }
        #expect(created.url.lastPathComponent == "Trip plan.md")
        #expect(session.note == created)
    }

    @Test func changedElsewhereSavesACopyAndGoesOnWithIt() throws {
        let note = try library.create(text: "Groceries")
        session.start(note)
        try changeElsewhere(note, to: "Groceries\nfrom the other Mac")
        session.edited()
        guard case .savedAsCopy(let copy) = try session.save("Groceries\nfrom this Mac") else {
            Issue.record("expected a separate copy")
            return
        }
        #expect(session.note == copy)
        #expect(try library.read(note) == "Groceries\nfrom the other Mac")
    }

    @Test func followsChangesAndGoingsWhenNothingIsWaiting() throws {
        let note = try library.create(text: "Groceries")
        session.start(note)
        #expect(session.follow(library.notes()) == .none)

        try changeElsewhere(note, to: "Groceries\nfrom the other Mac")
        guard case .changed(let onDisk) = session.follow(library.notes()) else { Issue.record("expected a change"); return }
        session.start(onDisk)

        try FileManager.default.removeItem(at: note.url)  // renamed or deleted in Finder
        #expect(session.follow(library.notes()) == .gone)
        #expect(session.note == nil)
    }

    @Test func waitingEditsOutliveTheirFileGoing() throws {
        let note = try library.create(text: "Groceries")
        session.start(note)
        session.edited()
        try FileManager.default.removeItem(at: note.url)

        #expect(session.follow(library.notes()) == .none, "kept while edits wait")
        #expect(session.note == note)
        _ = try session.save("Groceries\nmilk")
        #expect(try library.read(note) == "Groceries\nmilk", "saved back where it was")
    }

    @Test func renameToFirstLineGoesOnWithTheRenamedNote() throws {
        session.start(try library.create(text: "Draft"))
        let renamed = try session.renameToFirstLine("Trip plan\nday 1")
        #expect(renamed?.url.lastPathComponent == "Trip plan.md")
        #expect(session.note == renamed)
    }

    @Test func opensANoteWithItsText() throws {
        let note = try library.create(text: "Groceries\nmilk")
        #expect(try session.open(note) == "Groceries\nmilk")
        #expect(session.note == note)
        #expect(try session.open(nil) == "")
        #expect(session.note == nil)
    }

    @Test func aNoteThatCantBeReadIsntHeld() throws {
        let earlier = try library.create(text: "Earlier")
        _ = try session.open(earlier)
        // Saved by another app in UTF-16: shown blank, it would look emptied and go to the Trash on leaving.
        let wide = library.folder.appending(path: "Wide.md")
        try #require("Wide\nnote".data(using: .utf16)).write(to: wide)
        let note = try #require(library.note(at: wide))
        #expect(throws: (any Error).self) { try session.open(note) }
        #expect(session.note == nil, "not this one, nor the one before")
        #expect(exists(wide))
    }
}
