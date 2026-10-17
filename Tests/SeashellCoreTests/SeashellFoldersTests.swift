import Foundation
import Testing
@testable import SeashellCore

/// Each test works in its own temporary folder, never in the real Documents.
final class SeashellFoldersTests {
    private let base = FileManager.default.temporaryDirectory
        .appending(path: "SeashellTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    private lazy var folders = SeashellFolders(
        root: base.appending(path: "Documents/Seashell", directoryHint: .isDirectory),
        support: base.appending(path: "Application Support/Seashell", directoryHint: .isDirectory)
    )

    deinit {
        try? FileManager.default.removeItem(at: base)
    }

    @Test func createsMainShelfNotesAndSupport() throws {
        let created = try folders.createMissing()
        #expect(Set(created) == [folders.defaultShelf, folders.notes, folders.support])
        for folder in created {
            var isDirectory: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: folder.path(percentEncoded: false), isDirectory: &isDirectory))
            #expect(isDirectory.boolValue)
        }
    }

    @Test func secondRunCreatesNothing() throws {
        try folders.createMissing()
        #expect(try folders.createMissing().isEmpty)
    }

    @Test func leavesExistingFilesAlone() throws {
        try folders.createMissing()
        let file = folders.defaultShelf.appending(path: "report.pdf")
        try Data("report".utf8).write(to: file)
        try folders.createMissing()
        #expect(try Data(contentsOf: file) == Data("report".utf8))
    }

    @Test func recreatesMainIfItWasRemoved() throws {
        try folders.createMissing()
        try FileManager.default.removeItem(at: folders.defaultShelf)
        #expect(try folders.createMissing() == [folders.defaultShelf])
    }

    @Test func standardLocations() {
        let standard = SeashellFolders.standard
        #expect(standard.defaultShelf.path(percentEncoded: false).hasSuffix("/Documents/Seashell/Stash/Main/"))
        #expect(standard.notes.path(percentEncoded: false).hasSuffix("/Documents/Seashell/Notes/"))
        #expect(standard.support.path(percentEncoded: false).hasSuffix("/Library/Application Support/Seashell/"))
    }
}
