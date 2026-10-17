import Foundation
import Testing
@testable import SeashellCore

struct StashLibraryTests {
    let folder = TestFolder()
    let stash: URL
    let library: StashLibrary

    init() throws {
        stash = try folder.folder("Stash")
        library = StashLibrary(stash: stash, mover: try folder.mover())
    }

    @Test func mainComesFirstThenFinderOrder() throws {
        for name in ["Work", "Main", "archive", "Shelf 10", "Shelf 9"] { _ = try folder.folder("Stash/\(name)") }
        try folder.file("Stash/loose file.txt")
        _ = try folder.folder("Stash/.hidden")
        #expect(library.shelves().map(\.name) == ["Main", "archive", "Shelf 9", "Shelf 10", "Work"])
    }

    @Test func itemsAddedInFinderComeBeforeManifestOrder() throws {
        let main = Shelf(url: try folder.folder("Stash/Main"))
        let mover = try folder.mover()
        try mover.stash(text: "first", into: main.url)
        try mover.stash(text: "second", into: main.url)
        try folder.file("Stash/Main/from finder.txt")

        #expect(library.items(in: main).map(\.name) == ["from finder.txt", "second.txt", "first.txt"])
    }

    @Test func itemsSkipHiddenFilesAndKnowFolders() throws {
        let main = Shelf(url: try folder.folder("Stash/Main"))
        try folder.file("Stash/Main/.DS_Store")
        _ = try folder.folder("Stash/Main/Trip")
        _ = try folder.folder("Stash/Main/Tool.app")

        let items = library.items(in: main)
        #expect(Set(items.map(\.name)) == ["Trip", "Tool.app"])
        #expect(items.first { $0.name == "Trip" }?.isFolder == true)
        #expect(items.first { $0.name == "Tool.app" }?.isFolder == false)
    }

    @Test func itemsCarryOrigin() throws {
        let main = Shelf(url: try folder.folder("Stash/Main"))
        let original = try folder.file("Downloads/report.pdf")
        try folder.mover().stash(original, into: main.url)
        #expect(library.items(in: main).first?.origin == original.deletingLastPathComponent().path(percentEncoded: false))
    }

    @Test func vanishedEntriesAreFoundAndForgotten() throws {
        let main = Shelf(url: try folder.folder("Stash/Main"))
        let mover = try folder.mover()
        let stashed = try mover.stash(try folder.file("Downloads/report.pdf"), into: main.url)
        try mover.stash(text: "keep me", into: main.url)
        try FileManager.default.removeItem(at: stashed)  // moved out in Finder

        #expect(library.vanishedEntries(in: main) == ["report.pdf"])
        try library.forget(["report.pdf"], in: main)
        let manifest = ShelfManifest.read(in: main.url)
        #expect(manifest.order == ["keep me.txt"])
        #expect(manifest.origins.isEmpty)
    }

    @Test func createRenameDeleteShelf() throws {
        let work = try library.createShelf(named: "Work")
        #expect(exists(work.url))

        let renamed = try library.renameShelf(work, to: "Projects")
        #expect(renamed.name == "Projects")
        #expect(!exists(work.url))

        try library.deleteShelf(renamed)
        #expect(!exists(renamed.url))
        #expect(folder.names(in: folder.root.appending(path: "Trash")) == ["Projects"])
    }

    @Test func shelfNamesAreChecked() throws {
        _ = try library.createShelf(named: "Work")
        #expect(throws: ShelfError.nameTaken("Work")) { try library.createShelf(named: "Work") }
        #expect(throws: ShelfError.nameTaken("work")) { try library.createShelf(named: "work") }
        #expect(throws: ShelfError.invalidName("a/b")) { try library.createShelf(named: "a/b") }
        #expect(throws: ShelfError.invalidName(".secret")) { try library.createShelf(named: ".secret") }
        #expect(throws: ShelfError.invalidName("   ")) { try library.createShelf(named: "   ") }
    }

    @Test func mainCannotBeRenamedOrDeleted() throws {
        let main = Shelf(url: try folder.folder("Stash/Main"))
        #expect(throws: ShelfError.defaultShelf) { try library.renameShelf(main, to: "Other") }
        #expect(throws: ShelfError.defaultShelf) { try library.deleteShelf(main) }
    }
}
