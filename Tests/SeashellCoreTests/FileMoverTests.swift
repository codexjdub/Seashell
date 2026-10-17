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

    static func tinyImage(as type: UTType) throws -> Data {
        let context = try #require(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data as CFMutableData, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
