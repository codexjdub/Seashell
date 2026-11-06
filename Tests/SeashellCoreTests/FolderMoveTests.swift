import Foundation
import Testing
@testable import SeashellCore

/// Each test works in its own temporary folder, never in the real Documents.
final class FolderMoveTests {
    private let base = FileManager.default.temporaryDirectory
        .appending(path: "SeashellFolderMoveTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    private var documents: URL { base.appending(path: "Documents", directoryHint: .isDirectory) }
    private var current: URL { SeashellFolders.root(in: documents) }
    private var other: URL { base.appending(path: "Other", directoryHint: .isDirectory) }
    /// Stands in for the Trash: never the real one.
    private var trashFolder: URL { base.appending(path: "Trash", directoryHint: .isDirectory) }
    private var trash: FileMover.Trash {
        let folder = trashFolder
        return { url in try FileManager.default.moveItem(at: url, to: folder.appending(path: UUID().uuidString)) }
    }

    init() throws {
        for folder in [documents, other, trashFolder] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
    }

    deinit {
        // A test may have locked a file away; unlock everything so it all goes.
        if let enumerator = FileManager.default.enumerator(atPath: base.path(percentEncoded: false)) {
            for case let path as String in enumerator {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: base.appending(path: path).path(percentEncoded: false))
            }
        }
        try? FileManager.default.removeItem(at: base)
    }

    /// Seashell's folder with a shelf item and a note in it.
    private func makeCurrent() throws {
        try SeashellFolders.inside(documents).createMissing()
        try Data("report".utf8).write(to: current.appending(path: "Stash/Main/report.txt"))
        try Data("# Groceries".utf8).write(to: current.appending(path: "Notes/Groceries.md"))
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    // MARK: Planning

    @Test func choosingTheFolderItsInDoesNothing() throws {
        try makeCurrent()
        #expect(try FolderMove.plan(from: current, toParent: documents) == .nothing)
    }

    @Test func anotherNameForTheSameFolderDoesNothing() throws {
        try makeCurrent()
        let link = base.appending(path: "Link", directoryHint: .isDirectory)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: documents)
        #expect(try FolderMove.plan(from: current, toParent: link) == .nothing)
    }

    @Test func anotherFolderMovesItThere() throws {
        try makeCurrent()
        #expect(try FolderMove.plan(from: current, toParent: other) == .move(from: current, to: SeashellFolders.root(in: other)))
    }

    @Test func aSeashellFolderWithThingsInItIsUsedAsItIs() throws {
        try makeCurrent()
        let existing = SeashellFolders.root(in: other)
        try SeashellFolders.inside(other).createMissing()
        try Data("# Elsewhere".utf8).write(to: existing.appending(path: "Notes/Elsewhere.md"))
        #expect(try FolderMove.plan(from: current, toParent: other) == .useExisting(existing))
    }

    @Test func aSeashellFolderOfEmptyShelvesIsMovedInto() throws {
        try makeCurrent()
        // As another Mac's Seashell leaves it in iCloud: Main, a shelf, their list, Notes.
        let shelves = SeashellFolders.inside(other)
        try shelves.createMissing()
        try FileManager.default.createDirectory(at: shelves.stash.appending(path: "Work"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: shelves.stash.appending(path: ShelfManifest.fileName))
        #expect(try FolderMove.plan(from: current, toParent: other) == .move(from: current, to: shelves.root))
    }

    @Test func anEmptySeashellFolderIsMovedInto() throws {
        try makeCurrent()
        let empty = SeashellFolders.root(in: other)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        try Data().write(to: empty.appending(path: ".DS_Store"))
        #expect(try FolderMove.plan(from: current, toParent: other) == .move(from: current, to: empty))
    }

    @Test func aFolderInsideItsOwnIsRefused() throws {
        try makeCurrent()
        #expect(throws: FolderMove.Problem.insideCurrent) { try FolderMove.plan(from: current, toParent: current) }
        #expect(throws: FolderMove.Problem.insideCurrent) {
            try FolderMove.plan(from: current, toParent: current.appending(path: "Stash", directoryHint: .isDirectory))
        }
    }

    @Test func aFileCalledSeashellIsInTheWay() throws {
        try makeCurrent()
        try Data("not a folder".utf8).write(to: other.appending(path: SeashellFolders.folderName))
        #expect(throws: FolderMove.Problem.fileInTheWay(other.path(percentEncoded: false))) {
            try FolderMove.plan(from: current, toParent: other)
        }
    }

    @Test func nothingToMoveStartsAfresh() throws {
        #expect(try FolderMove.plan(from: current, toParent: other) == .startNew(SeashellFolders.root(in: other)))
    }

    // MARK: Moving

    private func expectMoved(to destination: URL) throws {
        #expect(!exists(current))
        #expect(try Data(contentsOf: destination.appending(path: "Stash/Main/report.txt")) == Data("report".utf8))
        #expect(try Data(contentsOf: destination.appending(path: "Notes/Groceries.md")) == Data("# Groceries".utf8))
        // Nothing half-made left beside it.
        let names = try FileManager.default.contentsOfDirectory(atPath: destination.deletingLastPathComponent().path(percentEncoded: false))
        #expect(names == [SeashellFolders.folderName])
    }

    @Test func onTheSameDiskItsRenamed() throws {
        try makeCurrent()
        let destination = SeashellFolders.root(in: other)
        #expect(FolderMove.onSameVolume(current, other))
        #expect(try FolderMove.move(from: current, to: destination, trash: trash) == nil)
        try expectMoved(to: destination)
    }

    @Test func acrossDisksItsCopiedThenTheOriginalGoes() throws {
        try makeCurrent()
        let destination = SeashellFolders.root(in: other)
        #expect(try FolderMove.move(from: current, to: destination, copying: true, trash: trash) == nil)
        try expectMoved(to: destination)
    }

    @Test func aSeashellFolderWithNoFilesThereGoesToTheTrash() throws {
        try makeCurrent()
        let shelves = SeashellFolders.inside(other)
        try shelves.createMissing()
        try Data().write(to: shelves.root.appending(path: ".DS_Store"))
        try FolderMove.move(from: current, to: shelves.root, copying: true, trash: trash)
        try expectMoved(to: shelves.root)
        let trashed = try FileManager.default.contentsOfDirectory(at: trashFolder, includingPropertiesForKeys: nil)
        #expect(trashed.count == 1)
        #expect(exists(trashed[0].appending(path: "Stash/Main")))
    }

    @Test func filesTurningUpThereStopTheMove() throws {
        try makeCurrent()
        let destination = SeashellFolders.root(in: other)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("theirs".utf8).write(to: destination.appending(path: "theirs.txt"))
        #expect(throws: FolderMove.Problem.destinationInUse) { try FolderMove.move(from: current, to: destination, copying: false, trash: trash) }
        #expect(try Data(contentsOf: current.appending(path: "Stash/Main/report.txt")) == Data("report".utf8))
        #expect(try Data(contentsOf: destination.appending(path: "theirs.txt")) == Data("theirs".utf8))
    }

    @Test func aCopyThatFailsLeavesBothPlacesAsTheyWere() throws {
        try makeCurrent()
        // One file can't be read, so the copy fails partway.
        let locked = current.appending(path: "Stash/Main/locked.txt")
        try Data("secret".utf8).write(to: locked)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path(percentEncoded: false))
        #expect(throws: (any Error).self) { try FolderMove.move(from: current, to: SeashellFolders.root(in: other), copying: true, trash: trash) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: other.path(percentEncoded: false)).isEmpty)
        #expect(try Data(contentsOf: current.appending(path: "Stash/Main/report.txt")) == Data("report".utf8))
        #expect(exists(locked))
    }
}
