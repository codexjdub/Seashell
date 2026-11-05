import Foundation
import Testing
@testable import SeashellCore

/// What counts as new on a shelf (the shell's pearl): items Seashell on this
/// Mac didn't put there.
@MainActor
struct ArrivalsTests {
    let folder = TestFolder()
    let stash: URL
    let main: Shelf
    let mover: FileMover
    let store: StashStore

    init() throws {
        main = Shelf(url: try folder.folder("Stash/Main"))
        try folder.file("Stash/Main/already here.txt")
        stash = folder.root.appending(path: "Stash")
        mover = try folder.mover()
        store = StashStore(library: StashLibrary(stash: stash, mover: mover))
    }

    @Test func whatWasThereAtLaunchIsntNew() {
        #expect(store.arrivals.isEmpty)
    }

    @Test func somethingAddedElsewhereIsNew() throws {
        try folder.file("Stash/Main/from iPhone.jpg")  // iCloud, or Finder: not through Seashell
        store.reload()
        #expect(store.arrivals == ["Main": ["from iPhone.jpg"]])
    }

    @Test func whatSeashellPutsThereIsnt() throws {
        let work = try folder.folder("Stash/Work")
        store.reload()
        let stashed = try mover.stash(try folder.file("Downloads/report.pdf"), into: main.url)
        try mover.stashCopy(try folder.file("Downloads/copy.pdf"), into: main.url)
        try mover.stash(text: "Remember the milk", into: main.url)
        try mover.stash(link: try #require(URL(string: "https://example.com")), title: "Example", into: main.url)
        let renamed = try mover.rename(stashed, to: "renamed.pdf")
        try mover.move(renamed, toShelf: work)
        store.reload()
        #expect(store.arrivals.isEmpty)
    }

    @Test func seeingThemClearsThem() throws {
        try folder.file("Stash/Main/new.txt")
        store.reload()
        store.markArrivalsSeen()
        #expect(store.arrivals.isEmpty)
        store.reload()
        #expect(store.arrivals.isEmpty, "still seen after another look")
    }

    @Test func oneGoneAgainIsntNewAnyMore() throws {
        let arrived = try folder.file("Stash/Main/new.txt")
        try folder.file("Stash/Main/other.txt")
        store.reload()
        try FileManager.default.removeItem(at: arrived)
        store.reload()
        #expect(store.arrivals == ["Main": ["other.txt"]])
    }

    @Test func aShelfRenamedHereDoesntArriveWhole() throws {
        let work = Shelf(url: try folder.folder("Stash/Work"))
        try mover.stash(try folder.file("Downloads/a.txt"), into: work.url)
        store.reload()
        try store.library.renameShelf(work, to: "Projects")
        store.reload()
        #expect(store.arrivals.isEmpty)
    }

    @Test func aBackgroundReadFindsThemToo() async throws {
        var changes = 0
        store.onChange = { changes += 1 }
        try folder.file("Stash/Main/from the other Mac.pdf")
        store.reload(around: [main.url])
        for _ in 0..<50 where changes == 0 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(store.arrivals == ["Main": ["from the other Mac.pdf"]])
    }

    @Test func aWriteIsRememberedOnce() {
        let writes = LocalWrites()
        let url = folder.root.appending(path: "Stash/Main/folder", directoryHint: .isDirectory)
        writes.note(url)
        #expect(writes.claim(folder.root.appending(path: "Stash/Main/folder", directoryHint: .notDirectory)), "however it's spelled")
        #expect(!writes.claim(url), "asked once")
        writes.note(url, now: .now.addingTimeInterval(-601))
        #expect(!writes.claim(url), "too long ago to be the one")
    }

    @Test func aWriteThatFailedIsntRemembered() throws {
        let writes = LocalWrites()
        let mover = FileMover(trash: { _ in }, localWrites: writes)
        let gone = main.url.appending(path: "gone.txt")
        #expect(throws: (any Error).self) { try mover.rename(gone, to: "renamed.txt") }
        // Else an item of that name saved from an iPhone within ten minutes would count as Seashell's own.
        #expect(!writes.claim(main.url.appending(path: "renamed.txt")))

        let renamed = try mover.rename(main.url.appending(path: "already here.txt"), to: "kept.txt")
        #expect(writes.claim(renamed))
    }
}
