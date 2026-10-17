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
