import Foundation
import Testing
@testable import SeashellCore

struct ItemContentTests {
    let folder = TestFolder()

    @Test func kindsByExtension() throws {
        let main = Shelf(url: try folder.folder("Stash/Main"))
        try folder.file("Stash/Main/note.txt")
        try folder.file("Stash/Main/LOUD.TXT")
        try folder.file("Stash/Main/site.webloc")
        try folder.file("Stash/Main/photo.png")
        _ = try folder.folder("Stash/Main/Trip")
        _ = try folder.folder("Stash/Main/Tool.app")

        let kinds = Dictionary(uniqueKeysWithValues: StashLibrary(stash: main.url.deletingLastPathComponent(), mover: try folder.mover())
            .items(in: main).map { ($0.name, $0.kind) })
        #expect(kinds == ["note.txt": .text, "LOUD.TXT": .text, "site.webloc": .link,
                          "photo.png": .file, "Trip": .folder, "Tool.app": .file])
    }

    @Test func textOfSnippet() throws {
        let shelf = try folder.folder("Main")
        let snippet = try folder.mover().stash(text: "Héllo, wörld\nsecond line", into: shelf)
        #expect(ItemContent.text(of: snippet) == "Héllo, wörld\nsecond line")
    }

    @Test func bigTextIsLeftAsAFile() throws {
        let big = try folder.file("big.txt", String(repeating: "a", count: ItemContent.maxTextBytes + 1))
        #expect(ItemContent.text(of: big) == nil)
    }

    @Test func previewOfShortText() throws {
        let note = try folder.file("note.txt", "\n  Buy milk\nand eggs  \n")
        #expect(ItemContent.preview(of: note) == "Buy milk\nand eggs")
    }

    @Test func previewOfLongTextIsCut() throws {
        let long = try folder.file("long.txt", String(repeating: "word ", count: 2_000))
        let preview = try #require(ItemContent.preview(of: long, maxCharacters: 50))
        #expect(preview.count == 51)
        #expect(preview.hasSuffix("…"))
    }

    @Test func linkOfWebloc() throws {
        let shelf = try folder.folder("Main")
        let address = try #require(URL(string: "https://example.com/page?q=1"))
        let webloc = try folder.mover().stash(link: address, title: "Example", into: shelf)
        #expect(ItemContent.link(of: webloc) == address)
    }

    @Test func brokenWeblocHasNoLink() throws {
        #expect(ItemContent.link(of: try folder.file("broken.webloc", "not a plist")) == nil)
    }
}
