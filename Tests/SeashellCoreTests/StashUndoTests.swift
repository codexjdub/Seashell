import Foundation
import Testing
@testable import SeashellCore

struct StashUndoTests {
    let folder = TestFolder()
    let shelf: URL
    let source: URL

    init() throws {
        shelf = try folder.folder("Stash/Main")
        source = try folder.folder("Downloads")
    }

    // MARK: Taking changes back

    @Test func movedInGoesBackUnderItsOldName() throws {
        let mover = try folder.mover()
        try folder.file("Stash/Main/report.pdf", "already here")
        let original = try folder.file("Downloads/report.pdf", "PDF")
        let stashed = try mover.stash(original, into: shelf)
        #expect(stashed.lastPathComponent == "report 2.pdf")

        let back = try mover.undo(.movedIn(stashed, from: original))
        #expect(back?.lastPathComponent == "report.pdf")
        #expect(try text(original) == "PDF")
        #expect(!exists(stashed))
        #expect(ShelfManifest.read(in: shelf).order.isEmpty)
    }

    @Test func movedInGetsANumberIfItsOldNameIsTaken() throws {
        let mover = try folder.mover()
        let original = try folder.file("Downloads/report.pdf", "PDF")
        let stashed = try mover.stash(original, into: shelf)
        try folder.file("Downloads/report.pdf", "a new one")

        let back = try mover.undo(.movedIn(stashed, from: original))
        #expect(back?.lastPathComponent == "report 2.pdf")
        #expect(try text(original) == "a new one")
    }

    @Test func movedInWhoseFolderIsGoneStays() throws {
        let mover = try folder.mover()
        let original = try folder.file("Downloads/Old/report.pdf", "PDF")
        let stashed = try mover.stash(original, into: shelf)
        try FileManager.default.removeItem(at: original.deletingLastPathComponent())

        #expect(throws: FileMoverError.self) { try mover.undo(.movedIn(stashed, from: original)) }
        #expect(exists(stashed))
    }

    @Test func addedGoesToTheTrash() throws {
        let mover = try folder.mover()
        let snippet = try mover.stash(text: "Remember the milk", into: shelf)

        #expect(try mover.undo(.added(snippet)) == nil)
        #expect(!exists(snippet))
        #expect(folder.names(in: try folder.folder("Trash")) == [snippet.lastPathComponent])
        #expect(ShelfManifest.read(in: shelf).order.isEmpty)
    }

    @Test func movedBetweenShelvesGoesBackWithItsOriginAndName() throws {
        let mover = try folder.mover()
        let work = try folder.folder("Stash/Work")
        try folder.file("Stash/Work/report.pdf", "Work's own")
        let original = try folder.file("Downloads/report.pdf", "PDF")
        let stashed = try mover.stash(original, into: shelf)
        let moved = try mover.move(stashed, toShelf: work)
        #expect(moved.lastPathComponent == "report 2.pdf")

        let back = try mover.undo(.movedBetweenShelves(moved, from: stashed))
        #expect(back == stashed)
        #expect(try text(stashed) == "PDF")
        #expect(ShelfManifest.read(in: shelf).origins["report.pdf"] == source.path(percentEncoded: false))
        #expect(ShelfManifest.read(in: work).order.isEmpty)
    }

    @Test func somethingAlreadyGoneThrows() throws {
        let mover = try folder.mover()
        let missing = shelf.appending(path: "gone.txt")
        #expect(throws: FileMoverError.missing("gone.txt")) { try mover.undo(.added(missing)) }
    }

    // MARK: History

    @MainActor @Test func newestStepComesBackFirst() {
        let history = StashUndoHistory()
        let first = history.begin()
        first.record(.added(URL(filePath: "/a")))
        let second = history.begin()
        second.record(.added(URL(filePath: "/b")))
        second.record(.added(URL(filePath: "/c")))

        #expect(history.popLatest() == [.added(URL(filePath: "/b")), .added(URL(filePath: "/c"))])
        #expect(history.popLatest() == [.added(URL(filePath: "/a"))])
        #expect(history.popLatest() == nil)
    }

    @MainActor @Test func stepsThatChangedNothingAreSkipped() {
        let history = StashUndoHistory()
        history.begin().record(.added(URL(filePath: "/a")))
        _ = history.begin()  // a drop that was declined
        #expect(history.popLatest() == [.added(URL(filePath: "/a"))])
    }

    @MainActor @Test func keepsOnlyTheLatestSteps() {
        let history = StashUndoHistory()
        for index in 0..<(StashUndoHistory.limit + 5) {
            history.begin().record(.added(URL(filePath: "/\(index)")))
        }
        var count = 0
        while history.popLatest() != nil { count += 1 }
        #expect(count == StashUndoHistory.limit)
    }
}
