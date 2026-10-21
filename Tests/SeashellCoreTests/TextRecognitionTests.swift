import AppKit
import PDFKit
import UniformTypeIdentifiers
import Testing
@testable import SeashellCore

struct TextRecognitionTests {
    let folder = TestFolder()

    @Test func readsAPicture() async throws {
        let picture = try save(Self.words("Remember the milk", "Gate B12 boards 9:40"), as: "screenshot.png")
        #expect(try await TextRecognition.text(of: picture) == "Remember the milk\nGate B12 boards 9:40")
    }

    @Test func readsAPDFsTextLayerAsItIs() async throws {
        let pdf = folder.root.appending(path: "letter.pdf")
        try Self.pdf(at: pdf) { context, box in
            ("Dear Sam, see you at noon." as NSString).draw(at: NSPoint(x: 40, y: box.height - 80),
                                                           withAttributes: [.font: NSFont.systemFont(ofSize: 18)])
        }
        #expect(try await TextRecognition.text(of: pdf).contains("Dear Sam, see you at noon."))
    }

    @Test func readsAScannedPDFPage() async throws {
        // Only a picture on the page, as a scanner makes it: no text layer to read.
        let scan = try #require(Self.words("Invoice 4417", "Total due 86.50"))
        let pdf = folder.root.appending(path: "scan.pdf")
        try Self.pdf(at: pdf) { context, box in
            context.draw(scan, in: CGRect(x: 20, y: box.height - 300, width: CGFloat(scan.width) / 2, height: CGFloat(scan.height) / 2))
        }
        let text = try await TextRecognition.text(of: pdf)
        #expect(text.contains("Invoice 4417") && text.contains("Total due 86.50"))
    }

    @Test func readsAScanUnderAStampedPageNumber() async throws {
        // A scan whose only text layer is a page number stamped on it.
        let scan = try #require(Self.words("Invoice 4417", "Total due 86.50"))
        let pdf = folder.root.appending(path: "stamped.pdf")
        try Self.pdf(at: pdf) { context, box in
            context.draw(scan, in: CGRect(x: 20, y: box.height - 300, width: CGFloat(scan.width) / 2, height: CGFloat(scan.height) / 2))
            ("Page 1 of 3" as NSString).draw(at: NSPoint(x: 260, y: 30), withAttributes: [.font: NSFont.systemFont(ofSize: 10)])
        }
        let text = try await TextRecognition.text(of: pdf)
        #expect(text.contains("Invoice 4417") && text.contains("Total due 86.50"))
    }

    @Test func aLockedPDFSaysSo() async throws {
        let plain = folder.root.appending(path: "plain.pdf")
        try Self.pdf(at: plain) { _, box in
            ("Account 12345" as NSString).draw(at: NSPoint(x: 40, y: box.height - 80), withAttributes: [.font: NSFont.systemFont(ofSize: 18)])
        }
        let locked = folder.root.appending(path: "statement.pdf")
        let document = try #require(PDFDocument(url: plain))
        #expect(document.write(to: locked, withOptions: [.userPasswordOption: "secret", .ownerPasswordOption: "owner"]))
        await #expect(throws: TextRecognitionError.locked("statement.pdf")) { try await TextRecognition.text(of: locked) }
    }

    @Test func readsEveryPageOfAMultiPageTIFF() async throws {
        let url = folder.root.appending(path: "fax.tiff")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 2, nil))
        for page in [Self.words("Page one says hello"), Self.words("Page two says goodbye")] {
            CGImageDestinationAddImage(destination, try #require(page), nil)
        }
        #expect(CGImageDestinationFinalize(destination))
        #expect(try await TextRecognition.text(of: url) == "Page one says hello\n\nPage two says goodbye")
    }

    @Test func aPictureWithoutWordsSaysSo() async throws {
        let blank = try save(Self.words(), as: "blank.png")
        await #expect(throws: TextRecognitionError.noText("blank.png")) { try await TextRecognition.text(of: blank) }
    }

    @Test func notAPictureCantBeOpened() async throws {
        let fake = try folder.file("fake.png", "not a picture")
        await #expect(throws: TextRecognitionError.unreadable("fake.png")) { try await TextRecognition.text(of: fake) }
    }

    @Test func onlyPicturesAndPDFs() throws {
        func item(_ name: String, _ kind: StashItem.Kind = .file) -> StashItem {
            StashItem(url: folder.root.appending(path: name), kind: kind, origin: nil, modified: nil, added: nil, cloud: .local)
        }
        #expect(TextRecognition.canRead(item("photo.HEIC")))
        #expect(TextRecognition.canRead(item("raw.CR2")))
        #expect(!TextRecognition.canRead(item("logo.svg")), "a picture, but not one macOS can open to read")
        #expect(TextRecognition.canRead(item("shot.png")))
        #expect(TextRecognition.canRead(item("form.pdf")))
        #expect(!TextRecognition.canRead(item("note.txt", .text)))
        #expect(!TextRecognition.canRead(item("song.mp3")))
        #expect(!TextRecognition.canRead(item("Photos.png", .folder)), "a folder, whatever its name")
    }

    // MARK: Helpers

    /// Black words on white, one line each; none gives a blank picture.
    static func words(_ lines: String...) -> CGImage? {
        let image = NSImage(size: NSSize(width: 900, height: 300), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            (lines.joined(separator: "\n") as NSString).draw(at: NSPoint(x: 30, y: 60),
                                                            withAttributes: [.font: NSFont.systemFont(ofSize: 44), .foregroundColor: NSColor.black])
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private func save(_ image: CGImage?, as name: String) throws -> URL {
        let url = folder.root.appending(path: name)
        let image = try #require(image)
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try png.write(to: url)
        return url
    }

    /// A one-page US Letter PDF, drawn by `draw`.
    static func pdf(at url: URL, _ draw: (CGContext, CGRect) -> Void) throws {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        draw(context, box)
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
    }
}
