import AppKit
import SeashellCore

/// Copy and rename for stashed items, used by the panel and tear-off
/// shelves. (Paste goes through `StashDropper`, like a drop.)
@MainActor
enum ItemActions {
    /// What an item is on the clipboard: a text snippet's text, a link's
    /// address, otherwise the file itself.
    static func object(for item: StashItem) -> any NSPasteboardWriting {
        switch item.kind {
        case .text:
            if let text = ItemContent.text(of: item.url) { return text as NSString }
        case .link:
            if let link = ItemContent.link(of: item.url) { return link as NSURL }
        case .file, .folder:
            break
        }
        return item.url as NSURL
    }

    static func copy(_ items: [StashItem]) {
        guard !items.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(items.map(object(for:)))
        Log.info("Copied \(items.count) item\(items.count == 1 ? "" : "s") to the clipboard")
    }

    /// Whether the clipboard holds something a shelf can take.
    static var canPaste: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSURL.self, NSImage.self, NSString.self], options: nil)
    }

    /// Asks for a new name, then renames the item where it is.
    static func rename(_ item: StashItem, with mover: FileMover) {
        guard let name = Alerts.askForName("Rename “\(item.name)”", initial: item.name, confirm: "Rename"), name != item.name else { return }
        do {
            try mover.rename(item.url, to: name)
        } catch {
            Alerts.showError("Couldn’t rename “\(item.name)”", error)
        }
    }
}
