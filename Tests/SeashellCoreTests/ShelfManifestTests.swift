import Foundation
import Testing
@testable import SeashellCore

struct ShelfManifestTests {
    let folder = TestFolder()

    @Test func missingManifestIsEmpty() {
        #expect(ShelfManifest.read(in: folder.root) == ShelfManifest())
    }

    @Test func corruptManifestIsEmpty() throws {
        try folder.file(ShelfManifest.fileName, "{ not json")
        #expect(ShelfManifest.read(in: folder.root) == ShelfManifest())
    }

    @Test func missingKeysUseDefaults() throws {
        try folder.file(ShelfManifest.fileName, #"{ "order": ["a.txt"] }"#)
        let manifest = ShelfManifest.read(in: folder.root)
        #expect(manifest.order == ["a.txt"])
        #expect(manifest.origins.isEmpty)
        #expect(manifest.version == 1)
    }

    @Test func updateWritesAndReadsBack() throws {
        try ShelfManifest.update(in: folder.root) { $0.add("a.txt", origin: "/Users/me/Downloads/") }
        try ShelfManifest.update(in: folder.root) { $0.add("b.txt", origin: nil) }
        let manifest = ShelfManifest.read(in: folder.root)
        #expect(manifest.order == ["b.txt", "a.txt"])
        #expect(manifest.origins == ["a.txt": "/Users/me/Downloads/"])
    }

    @Test func addingAgainMovesToFront() {
        var manifest = ShelfManifest()
        manifest.add("a", origin: "/x/")
        manifest.add("b", origin: nil)
        manifest.add("a", origin: "/y/")
        #expect(manifest.order == ["a", "b"])
        #expect(manifest.origins == ["a": "/y/"])
    }

    @Test func removeForgetsOrderAndOrigin() {
        var manifest = ShelfManifest()
        manifest.add("a", origin: "/x/")
        manifest.remove("a")
        #expect(manifest == ShelfManifest())
    }
}
