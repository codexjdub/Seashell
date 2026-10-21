import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SeashellCore

struct FileMoverTests {
    let folder = TestFolder()
    let shelf: URL
    let source: URL

    init() throws {
        shelf = try folder.folder("Stash/Main")
        source = try folder.folder("Downloads")
    }

    // MARK: Into Stash

    @Test func stashMovesFileAndRemembersOrigin() throws {
        let original = try folder.file("Downloads/report.pdf", "PDF")
        let stashed = try folder.mover().stash(original, into: shelf)

        #expect(stashed.lastPathComponent == "report.pdf")
        #expect(!exists(original))
        #expect(try text(stashed) == "PDF")
        let manifest = ShelfManifest.read(in: shelf)
        #expect(manifest.order == ["report.pdf"])
        #expect(manifest.origins["report.pdf"] == source.path(percentEncoded: false))
    }

    @Test func nameClashGetsNumber() throws {
        let mover = try folder.mover()
        try mover.stash(try folder.file("Downloads/report.pdf", "one"), into: shelf)
        let second = try mover.stash(try folder.file("Downloads/report.pdf", "two"), into: shelf)
        #expect(second.lastPathComponent == "report 2.pdf")
        #expect(ShelfManifest.read(in: shelf).order == ["report 2.pdf", "report.pdf"])
    }

    @Test func stashMovesWholeFolder() throws {
        try folder.file("Downloads/Trip/day1/photo.jpg", "jpg")
        try folder.file("Downloads/Trip/notes.txt", "notes")
        let stashed = try folder.mover().stash(source.appending(path: "Trip"), into: shelf)
        #expect(try text(stashed.appending(path: "day1/photo.jpg")) == "jpg")
        #expect(!exists(source.appending(path: "Trip")))
    }

    @Test func otherVolumeCopiesChecksThenDeletesOriginal() throws {
        try folder.file("Downloads/Trip/day1/photo.jpg", "jpg")
        try folder.file("Downloads/Trip/notes.txt", "notes")
        let original = source.appending(path: "Trip")
        let stashed = try folder.mover(simulateOtherVolume: true).stash(original, into: shelf)

        #expect(try text(stashed.appending(path: "day1/photo.jpg")) == "jpg")
        #expect(try text(stashed.appending(path: "notes.txt")) == "notes")
        #expect(!exists(original))
        // No staging leftovers: only the item and the manifest.
        #expect(folder.names(in: shelf) == [ShelfManifest.fileName, "Trip"])
    }

    @Test func missingSourceThrows() throws {
        #expect(throws: FileMoverError.missing("ghost.txt")) {
            try folder.mover().stash(source.appending(path: "ghost.txt"), into: shelf)
        }
    }

    @Test func stashText() throws {
        let stashed = try folder.mover().stash(text: "Recently, I lived for a few years in India", into: shelf)
        #expect(stashed.lastPathComponent == "Recently, I lived for a few.txt")
        #expect(try text(stashed) == "Recently, I lived for a few years in India")
        #expect(ShelfManifest.read(in: shelf).origins.isEmpty)
    }

    @Test func stashLinkWritesWebloc() throws {
        let link = try #require(URL(string: "https://example.com/page"))
        let stashed = try folder.mover().stash(link: link, title: "Example", into: shelf)
        #expect(stashed.lastPathComponent == "Example.webloc")
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: stashed), format: nil) as? [String: String]
        #expect(plist == ["URL": "https://example.com/page"])
    }

    @Test func stashImageConvertsToPNG() throws {
        let tiff = try Self.tinyImage(as: .tiff)
        let stashed = try folder.mover().stash(imageData: tiff, into: shelf)
        #expect(stashed.pathExtension == "png")
        let data = try Data(contentsOf: stashed)
        #expect(data.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
    }

    @Test func unreadableImageThrows() throws {
        #expect(throws: FileMoverError.unreadableImage) {
            try folder.mover().stash(imageData: Data("not an image".utf8), into: shelf)
        }
    }

    // MARK: Within and out of Stash

    @Test func moveBetweenShelvesKeepsOrigin() throws {
        let work = try folder.folder("Stash/Work")
        let mover = try folder.mover()
        let stashed = try mover.stash(try folder.file("Downloads/report.pdf"), into: shelf)
        let moved = try mover.move(stashed, toShelf: work)

        #expect(moved.deletingLastPathComponent().lastPathComponent == "Work")
        #expect(ShelfManifest.read(in: shelf).order.isEmpty)
        #expect(ShelfManifest.read(in: work).origins["report.pdf"] == source.path(percentEncoded: false))
    }

    @Test func deleteSendsToTrash() throws {
        let mover = try folder.mover()
        let stashed = try mover.stash(try folder.file("Downloads/report.pdf"), into: shelf)
        try mover.delete(stashed)

        #expect(!exists(stashed))
        #expect(folder.names(in: folder.root.appending(path: "Trash")) == ["report.pdf"])
        #expect(ShelfManifest.read(in: shelf) == ShelfManifest())
    }

    @Test func pastingCopiesAndLeavesTheOriginal() throws {
        let original = try folder.file("Downloads/report.pdf", "PDF")
        _ = try folder.file("Stash/Main/report.pdf", "older")
        let copy = try folder.mover().stashCopy(original, into: shelf)

        #expect(exists(original), "the original stays where it was")
        #expect(copy.lastPathComponent == "report 2.pdf")
        #expect(try text(copy) == "PDF")
        #expect(ShelfManifest.read(in: shelf).origins[copy.lastPathComponent] == nil, "nothing to put back")
    }

    @Test func renameKeepsPlaceAndOrigin() throws {
        let mover = try folder.mover()
        let first = try mover.stash(try folder.file("Downloads/a.txt", "A"), into: shelf)
        _ = try mover.stash(try folder.file("Downloads/b.txt", "B"), into: shelf)

        let renamed = try mover.rename(first, to: "Alpha.txt")
        #expect(renamed.lastPathComponent == "Alpha.txt")
        #expect(!exists(first))
        let manifest = ShelfManifest.read(in: shelf)
        #expect(manifest.order == ["b.txt", "Alpha.txt"])
        #expect(manifest.origins["Alpha.txt"] == source.path(percentEncoded: false))
    }

    @Test func renameRefusesTakenAndBadNames() throws {
        let mover = try folder.mover()
        let a = try mover.stash(try folder.file("Downloads/a.txt"), into: shelf)
        _ = try mover.stash(try folder.file("Downloads/b.txt"), into: shelf)
        #expect(throws: FileMoverError.nameTaken("b.txt")) { try mover.rename(a, to: "b.txt") }
        #expect(throws: FileMoverError.invalidName("")) { try mover.rename(a, to: "") }
        #expect(try mover.rename(a, to: "A.txt").lastPathComponent == "A.txt", "a change of case alone is fine")
    }

    @Test func renameOntoANameStillListedKeepsOneEntry() throws {
        let mover = try folder.mover()
        let gone = try mover.stash(try folder.file("Downloads/a.txt", "A"), into: shelf)
        try FileManager.default.removeItem(at: gone)  // deleted in Finder; its entry waits out the prune grace
        let b = try mover.stash(text: "b", into: shelf)

        try mover.rename(b, to: "a.txt")
        let manifest = ShelfManifest.read(in: shelf)
        #expect(manifest.order == ["a.txt"])
        #expect(manifest.origins["a.txt"] == nil, "not the deleted item's Put Back")
        let items = StashLibrary(stash: shelf.deletingLastPathComponent(), mover: mover).items(in: Shelf(url: shelf))
        #expect(items.map(\.name) == ["a.txt"])
    }

    @Test func putBackReturnsToOrigin() throws {
        let mover = try folder.mover()
        let original = try folder.file("Downloads/report.pdf", "PDF")
        let stashed = try mover.stash(original, into: shelf)
        let returned = try mover.putBack(stashed)

        #expect(returned == original)
        #expect(try text(original) == "PDF")
        #expect(ShelfManifest.read(in: shelf) == ShelfManifest())
    }

    @Test func putBackAvoidsClash() throws {
        let mover = try folder.mover()
        let stashed = try mover.stash(try folder.file("Downloads/report.pdf", "old"), into: shelf)
        try folder.file("Downloads/report.pdf", "new one in the way")
        #expect(try mover.putBack(stashed).lastPathComponent == "report 2.pdf")
    }

    @Test func putBackFailsWhenOriginIsGone() throws {
        let mover = try folder.mover()
        let stashed = try mover.stash(try folder.file("Downloads/report.pdf"), into: shelf)
        try FileManager.default.removeItem(at: source)
        #expect(throws: FileMoverError.originMissing(source.path(percentEncoded: false))) {
            try mover.putBack(stashed)
        }
        #expect(exists(stashed))
    }

    @Test func putBackFailsWithoutOrigin() throws {
        let mover = try folder.mover()
        let stashed = try mover.stash(text: "hello", into: shelf)
        #expect(throws: FileMoverError.noOrigin("hello.txt")) {
            try mover.putBack(stashed)
        }
    }

    // MARK: Sizes

    @Test func folderSizeAddsUpFiles() throws {
        try folder.file("Downloads/Trip/a.txt", "12345")
        try folder.file("Downloads/Trip/day1/b.txt", "123")
        #expect(try FileSize.of(source.appending(path: "Trip")) == 8)
        #expect(try FileSize.measure(source.appending(path: "Trip")).items == 4)
    }

    static func tinyImage(as type: UTType, width: Int = 2, height: Int = 2, orientation: Int = 1) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data as CFMutableData, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    // MARK: Several at once

    @Test func batchesWriteEachManifestOnce() throws {
        let mover = try folder.mover()
        let work = try folder.folder("Stash/Work")
        let sources = try ["a.txt", "b.txt", "c.txt"].map { try folder.file("Downloads/\($0)", $0) }
        let stashed = try mover.stash(sources, into: shelf).map { try $0.get() }
        #expect(stashed.map(\.lastPathComponent) == ["a.txt", "b.txt", "c.txt"])
        #expect(ShelfManifest.read(in: shelf).order == ["c.txt", "b.txt", "a.txt"], "newest first, as one by one")
        #expect(ShelfManifest.read(in: shelf).origins.count == 3)

        let moved = try mover.move(Array(stashed.prefix(2)), toShelf: work).map { try $0.get() }
        #expect(ShelfManifest.read(in: shelf).order == ["c.txt"])
        #expect(ShelfManifest.read(in: work).order == ["b.txt", "a.txt"])
        #expect(ShelfManifest.read(in: work).origins["a.txt"] == source.path(percentEncoded: false), "Put Back moves with them")

        let back = try mover.putBack(moved).map { try $0.get() }
        #expect(back == Array(sources.prefix(2)))
        #expect(ShelfManifest.read(in: work) == ShelfManifest())

        for result in mover.delete([stashed[2]]) { try result.get() }
        #expect(ShelfManifest.read(in: shelf) == ShelfManifest())
        #expect(folder.names(in: folder.root.appending(path: "Trash")) == ["c.txt"])
    }

    @Test func batchReportsEachItemsOwnFailure() throws {
        let mover = try folder.mover()
        let kept = try mover.stash(text: "keep", into: shelf)
        let results = mover.delete([shelf.appending(path: "gone.txt"), kept])
        #expect(throws: (any Error).self) { try results[0].get() }
        #expect(throws: Never.self) { try results[1].get() }
        #expect(!exists(kept))
    }

    @Test func batchFailsWhereTheManifestCantBeWritten() throws {
        let mover = try folder.mover()
        let a = try folder.file("Stash/Main/a.txt")
        let b = try folder.file("Stash/Main/b.txt")
        try folder.file("Stash/Main/\(ShelfManifest.fileName)", "{ not json")
        for result in mover.delete([a, b]) {
            #expect(throws: ShelfManifestError.unreadable("Main")) { try result.get() }
        }
        #expect(!exists(a) && !exists(b), "trashed all the same, as one at a time did")
    }

    @Test func undoingADropTakesBackEveryFile() throws {
        let mover = try folder.mover()
        let sources = try ["a.txt", "b.txt"].map { try folder.file("Downloads/\($0)") }
        let stashed = try mover.stash(sources, into: shelf).map { try $0.get() }
        let snippet = try mover.stash(text: "note", into: shelf)
        let changes = zip(stashed, sources).map { StashChange.movedIn($0, from: $1) } + [.added(snippet)]
        for result in mover.undo(changes.reversed()) { _ = try result.get() }
        #expect(sources.allSatisfy(exists))
        #expect(ShelfManifest.read(in: shelf) == ShelfManifest())
    }

    @Test func sizeTakenEarlierSkipsWalkingAgainButStillChecks() throws {
        try folder.file("Downloads/Trip/a.txt", "12345")
        let trip = source.appending(path: "Trip")
        let mover = try folder.mover(simulateOtherVolume: true)
        let measured = try FileSize.measure(trip)
        try folder.file("Downloads/Trip/b.txt", "added after it was measured")

        let result = mover.stash([trip], into: shelf, measured: [trip: measured])
        #expect(throws: FileMoverError.copyMismatch("Trip")) { try result[0].get() }
        #expect(exists(trip.appending(path: "b.txt")), "the original stays")
        #expect(try mover.stash([trip], into: shelf, measured: [trip: FileSize.measure(trip)])[0].get().lastPathComponent == "Trip")
    }

    @Test func photosStoredOnTheirSideComeOutUpright() throws {
        let wide = try Self.tinyImage(as: .jpeg, width: 4, height: 2, orientation: 6)  // stored 4 × 2, shown turned
        let png = try ImageConversion.png(from: wide)
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect((image.width, image.height) == (2, 4))
    }

    @Test func stashingAFileAlreadyInTheShelfLeavesIt() throws {
        let original = try folder.file("Downloads/report.pdf", "PDF")
        let mover = try folder.mover()
        let stashed = try mover.stash(original, into: shelf)
        let again = try mover.stash(stashed, into: shelf)
        #expect(again == stashed)
        #expect(folder.names(in: shelf).filter { !$0.hasPrefix(".") } == ["report.pdf"])
        #expect(ShelfManifest.read(in: shelf).origins["report.pdf"] == source.path(percentEncoded: false), "keeps its real origin")
    }
}
