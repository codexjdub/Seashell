import Foundation
import Testing
@testable import SeashellCore

@MainActor
struct WatchingTests {
    let folder = TestFolder()

    @Test func storeRefreshesWhenFolderChanges() async throws {
        let main = try folder.folder("Stash/Main")
        let store = StashStore(library: StashLibrary(stash: folder.root.appending(path: "Stash"), mover: try folder.mover()))
        var changes = 0
        store.onChange = { changes += 1 }
        store.startWatching()
        #expect(store.items(in: Shelf(url: main)).isEmpty)

        try folder.file("Stash/Main/dropped in Finder.txt")
        for _ in 0..<50 where changes == 0 {
            try await Task.sleep(for: .milliseconds(100))
        }

        #expect(changes > 0)
        #expect(store.items(in: Shelf(url: main)).map(\.name) == ["dropped in Finder.txt"])
    }

    @Test func reloadingAroundAChangeReadsJustThoseShelves() async throws {
        let main = Shelf(url: try folder.folder("Stash/Main"))
        let work = Shelf(url: try folder.folder("Stash/Work"))
        let store = StashStore(library: StashLibrary(stash: folder.root.appending(path: "Stash"), mover: try folder.mover()))
        var changes = 0
        store.onChange = { changes += 1 }
        try folder.file("Stash/Main/a.txt")
        try folder.file("Stash/Work/b.txt")

        store.reload(around: [work.url])
        for _ in 0..<50 where changes == 0 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(store.items(in: work).map(\.name) == ["b.txt"])
        #expect(store.items(in: main).isEmpty, "not read again")

        store.reload(around: [main.url.appending(path: "a.txt")])
        for _ in 0..<50 where changes == 1 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(store.items(in: main).map(\.name) == ["a.txt"])
    }

    @Test func aNewShelfShowsUpWhenStashChanges() async throws {
        _ = try folder.folder("Stash/Main")
        let stash = folder.root.appending(path: "Stash")
        let store = StashStore(library: StashLibrary(stash: stash, mover: try folder.mover()))
        var changes = 0
        store.onChange = { changes += 1 }
        try folder.file("Stash/Ideas/c.txt")

        store.reload(around: [stash])
        for _ in 0..<50 where changes == 0 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(store.shelves.map(\.name) == ["Main", "Ideas"])
        #expect(store.items(in: Shelf(url: stash.appending(path: "Ideas"))).map(\.name) == ["c.txt"])

        try FileManager.default.removeItem(at: stash.appending(path: "Ideas"))
        store.reload(around: [stash.appending(path: "Ideas")])  // as if only the shelf's own folder were reported
        for _ in 0..<50 where changes == 1 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(store.shelves.map(\.name) == ["Main"])
    }

    @Test func vanishedEntriesArePrunedAfterGrace() async throws {
        let main = try folder.folder("Stash/Main")
        let stashed = try folder.mover().stash(try folder.file("Downloads/report.pdf"), into: main)
        try FileManager.default.removeItem(at: stashed)

        let store = StashStore(library: StashLibrary(stash: folder.root.appending(path: "Stash"), mover: try folder.mover()),
                               pruneGrace: 0.3)
        #expect(ShelfManifest.read(in: main).order == ["report.pdf"], "kept during the grace period")
        for _ in 0..<30 where !ShelfManifest.read(in: main).order.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(ShelfManifest.read(in: main) == ShelfManifest())
        withExtendedLifetime(store) {}
    }

    @Test func itemBackWithinGraceKeepsItsEntry() async throws {
        let main = try folder.folder("Stash/Main")
        let stashed = try folder.mover().stash(try folder.file("Downloads/report.pdf"), into: main)
        let away = folder.root.appending(path: "report.pdf")
        try FileManager.default.moveItem(at: stashed, to: away)

        let store = StashStore(library: StashLibrary(stash: folder.root.appending(path: "Stash"), mover: try folder.mover()),
                               pruneGrace: 0.5)
        try FileManager.default.moveItem(at: away, to: stashed)  // e.g. iCloud catching up
        try await Task.sleep(for: .milliseconds(900))

        #expect(ShelfManifest.read(in: main).origins["report.pdf"] != nil)
        withExtendedLifetime(store) {}
    }

    @Test func localFilesAreNotInICloud() throws {
        #expect(CloudStatus.state(of: try folder.file("local.txt")) == .local)
    }
}
