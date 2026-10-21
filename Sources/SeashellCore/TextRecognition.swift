import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

public enum TextRecognitionError: LocalizedError, Equatable {
    case noText(String)
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .noText(let name): "Seashell found no text in “\(name)”."
        case .unreadable(let name): "“\(name)” couldn’t be opened as a picture or PDF."
        }
    }
}

/// Copy Text: the words in a picture or a PDF, read on this Mac. A PDF page
/// with a text layer is read as it is; pictures, and pages that are only
/// scans, go through Vision's text recognition (about a tenth of a second a
/// picture).
public enum TextRecognition {
    /// PDFs, and pictures in a format macOS can open (not SVG, say, which
    /// counts as a picture but isn't one ImageIO reads).
    public static func canRead(_ item: StashItem) -> Bool {
        guard item.kind == .file, let type = UTType(filenameExtension: item.url.pathExtension) else { return false }
        return type.conforms(to: .pdf) || pictureTypes.contains(type.identifier)
    }

    private static let pictureTypes = Set(CGImageSourceCopyTypeIdentifiers() as? [String] ?? [])

    /// The text, a picture's lines top to bottom, a PDF's (or multi-page TIFF's)
    /// pages one after another.
    public static func text(of url: URL) async throws -> String {
        let name = url.lastPathComponent
        guard let data = try? Coordinated.read(url, { try Data(contentsOf: $0) }) else { throw TextRecognitionError.unreadable(name) }
        let pages: [String]
        if UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true {
            guard let document = PDFDocument(data: data) else { throw TextRecognitionError.unreadable(name) }
            pages = try await text(of: document)
        } else {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw TextRecognitionError.unreadable(name) }
            // A TIFF can hold a scan's pages. Other formats' extra images are
            // the same picture again (icon sizes, animation frames), so only the first counts.
            let isTIFF = CGImageSourceGetType(source).map { UTType($0 as String)?.conforms(to: .tiff) == true } ?? false
            let count = isTIFF ? CGImageSourceGetCount(source) : min(CGImageSourceGetCount(source), 1)
            let images = (0..<count).compactMap { ImageConversion.upright(source, index: $0) }
            guard !images.isEmpty else { throw TextRecognitionError.unreadable(name) }
            var texts: [String] = []
            for image in images { texts.append(try await recognize(image)) }
            pages = texts
        }
        let text = pages.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        guard !text.isEmpty else { throw TextRecognitionError.noText(name) }
        return text
    }

    private static func text(of document: PDFDocument) async throws -> [String] {
        var pages: [String] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            if let text = page.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pages.append(text)
            } else if let image = picture(of: page) {
                pages.append(try await recognize(image))
            }
        }
        return pages
    }

    /// A scanned page as a picture, turned as it's shown, at about 200 dpi
    /// (at most 4,000 pixels on its long side).
    private static func picture(of page: PDFPage) -> CGImage? {
        var size = page.bounds(for: .mediaBox).size
        if page.rotation % 180 != 0 { size = NSSize(width: size.height, height: size.width) }
        let scale = min(200.0 / 72, 4000 / max(size.width, size.height, 1))
        let thumbnail = page.thumbnail(of: NSSize(width: size.width * scale, height: size.height * scale), for: .mediaBox)
        return thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private static func recognize(_ image: CGImage) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        return try await request.perform(on: image)
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
