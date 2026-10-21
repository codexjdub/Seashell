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
            if let text = ItemContent.text(of: item) { return text as NSString }
        case .link:
            if let link = ItemContent.link(of: item) { return link as NSURL }
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

    /// Set once Copy Text has been used on this Mac: from then on its model is
    /// set up after each launch (see AppDelegate).
    static let copyTextUsedKey = "copyTextUsed"

    /// Copy Text: the words in the pictures and PDFs among `items`, read on this
    /// Mac in the background, onto the clipboard (several with a blank line
    /// between). Says so if there's no text, or if an item is only in iCloud
    /// (it starts downloading, to try again in a moment).
    static func copyText(_ items: [StashItem]) {
        let readable = items.filter(TextRecognition.canRead)
        guard !readable.isEmpty else { return }
        UserDefaults.standard.set(true, forKey: copyTextUsedKey)
        let inICloud = readable.filter { $0.cloud == .cloudOnly }
        guard inICloud.isEmpty else {
            inICloud.forEach { try? CloudStatus.startDownloading($0.url) }
            Log.info("Copy Text: \(inICloud.count) item(s) only in iCloud, downloading")
            Alerts.tell(inICloud.count == 1 ? "“\(inICloud[0].name)” is only in iCloud" : "\(inICloud.count) items are only in iCloud",
                        detail: "It’s downloading to this Mac now. Try Copy Text again in a moment.")
            return
        }
        Log.info("Copy Text from \(readable.count) item\(readable.count == 1 ? "" : "s")")
        Task {
            var texts: [String] = []
            var failure: (any Error)?
            for item in readable {
                let url = item.url
                do {
                    texts.append(try await Task.detached { try await TextRecognition.text(of: url) }.value)
                } catch {
                    Log.info("Copy Text: \(error.localizedDescription)")
                    failure = failure ?? error
                }
            }
            guard !texts.isEmpty else {
                if let failure { Alerts.showError("Couldn’t copy any text", failure) }
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(texts.joined(separator: "\n\n"), forType: .string)
            Log.info("Copy Text: copied \(texts.joined().count) characters")
        }
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
