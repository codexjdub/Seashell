import AppKit
import SeashellCore
import UniformTypeIdentifiers

/// What goes on the drag pasteboard for an item dragged out of a shelf.
///
/// Files and folders go as file URLs. Text and links go as their content (the
/// words, or the address) plus a *file promise*: Finder asks Seashell to write
/// the `.txt` or `.webloc` when you drop there. A plain file URL alongside the
/// text wouldn't do: browsers and rich-text editors take the file and ignore the text.
@MainActor
enum DragOut {
    private static let promiseWriter = PromiseWriter()
    private static let urlNameType = NSPasteboard.PasteboardType("public.url-name")

    static func writer(for item: StashItem) -> any NSPasteboardWriting {
        switch item.kind {
        case .text:
            if let text = ItemContent.text(of: item.url) {
                return promise(for: item, type: .plainText, content: [.string: text])
            }
        case .link:
            if let link = ItemContent.link(of: item.url) {
                let title = item.url.deletingPathExtension().lastPathComponent
                return promise(for: item, type: .internetLocation,
                               content: [.URL: link.absoluteString, .string: link.absoluteString, urlNameType: title])
            }
        case .file, .folder:
            break
        }
        return item.url as NSURL
    }

    private static func promise(for item: StashItem, type: UTType,
                                content: [NSPasteboard.PasteboardType: String]) -> ContentPromise {
        let provider = ContentPromise(fileType: type.identifier, delegate: promiseWriter)
        provider.userInfo = item.url
        provider.content = content
        return provider
    }
}

/// A file promise that also carries the item's content in other types.
final class ContentPromise: NSFilePromiseProvider {
    var content: [NSPasteboard.PasteboardType: String] = [:]

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        super.writableTypes(for: pasteboard) + Array(content.keys)
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        content[type] ?? super.pasteboardPropertyList(forType: type)
    }
}

/// Keeps a file promise by copying the stashed item to where it was dropped.
/// Called on its own queue, off the main thread.
final class PromiseWriter: NSObject, NSFilePromiseProviderDelegate {
    private let queue = OperationQueue()

    func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        (provider.userInfo as? URL)?.lastPathComponent ?? "Untitled"
    }

    func filePromiseProvider(_ provider: NSFilePromiseProvider, writePromiseTo url: URL,
                             completionHandler: @escaping ((any Error)?) -> Void) {
        guard let source = provider.userInfo as? URL else {
            completionHandler(CocoaError(.fileNoSuchFile))
            return
        }
        do {
            try FileManager.default.copyItem(at: source, to: url)
            completionHandler(nil)
        } catch {
            Log.error("Couldn’t write \(source.lastPathComponent) where it was dropped: \(error.localizedDescription)")
            completionHandler(error)
        }
    }

    func operationQueue(for provider: NSFilePromiseProvider) -> OperationQueue {
        queue
    }
}
