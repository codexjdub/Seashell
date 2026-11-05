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

    /// Copy Texts asked for so far: only the latest one's text goes onto the clipboard.
    private static var copyTextRuns = 0

    /// Copy Text: the words in the pictures and PDFs among `items`, read on this
    /// Mac in the background, onto the clipboard (several with a blank line
    /// between). Says so if there's no text, or if an item is only in iCloud
    /// (it starts downloading, to try again in a moment).
    static func copyText(_ items: [StashItem]) {
        let readable = items.filter(TextRecognition.canRead)
        guard !readable.isEmpty, !onlyInICloud(readable, for: "Copy Text") else { return }
        Log.info("Copy Text from \(readable.count) item\(readable.count == 1 ? "" : "s")")
        copyTextRuns += 1
        let run = copyTextRuns
        let clipboard = NSPasteboard.general.changeCount
        Task {
            let (texts, failure) = await words(in: readable, for: "Copy Text")
            guard !texts.isEmpty else {
                if let failure { Alerts.showError("Couldn’t copy any text", failure) }
                return
            }
            // A long read can finish after you've copied something else, or
            // asked for Copy Text again: the newer one stays on the clipboard.
            guard run == copyTextRuns, NSPasteboard.general.changeCount == clipboard else {
                Log.info("Copy Text: the clipboard changed while reading; left as it is")
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(texts.joined(separator: "\n\n"), forType: .string)
            Log.info("Copy Text: copied \(texts.joined().count) characters")
        }
    }

    /// Text snippets, and the pictures and PDFs Copy Text can read.
    static func canReadAloud(_ item: StashItem) -> Bool {
        item.kind == .text || TextRecognition.canRead(item)
    }

    /// Read Aloud: the text snippets among `items` as they are, and the words
    /// in their pictures and PDFs (as Copy Text finds them), one after another.
    static func readAloud(_ items: [StashItem]) {
        let readable = items.filter(canReadAloud)
        guard !readable.isEmpty, !onlyInICloud(readable, for: "Read Aloud") else { return }
        Log.info("Read Aloud from \(readable.count) item\(readable.count == 1 ? "" : "s")")
        let run = ReadAloud.shared.begin()
        Task {
            let (texts, failure) = await words(in: readable, for: "Read Aloud")
            guard !texts.isEmpty else {
                ReadAloud.shared.cancel(run: run)
                if let failure { Alerts.showError("Couldn’t read anything aloud", failure) } else { NSSound.beep() }
                return
            }
            ReadAloud.shared.read(texts.joined(separator: "\n\n"), run: run)
        }
    }

    /// Items only in iCloud start downloading, with a note to try `action`
    /// again in a moment. True if there were any.
    private static func onlyInICloud(_ items: [StashItem], for action: String) -> Bool {
        let inICloud = items.filter { $0.cloud == .cloudOnly }
        guard !inICloud.isEmpty else { return false }
        startDownloading(inICloud)
        Log.info("\(action): \(inICloud.count) item(s) only in iCloud, downloading")
        Alerts.tell(inICloud.count == 1 ? "“\(inICloud[0].name)” is only in iCloud" : "\(inICloud.count) items are only in iCloud",
                    detail: "It’s downloading to this Mac now. Try \(action) again in a moment.")
        return true
    }

    /// The words in each item, in the background: a text snippet's text, a
    /// picture's or PDF's as Copy Text reads them. Failures are logged; the
    /// first is returned to show if nothing was found.
    private static func words(in items: [StashItem], for action: String) async -> (texts: [String], failure: (any Error)?) {
        var texts: [String] = []
        var failure: (any Error)?
        for item in items {
            do {
                let text = try await Task.detached {
                    item.kind == .text ? ItemContent.text(of: item) : try await TextRecognition.text(of: item.url)
                }.value
                if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { texts.append(text) }
            } catch {
                Log.info("\(action): \(error.localizedDescription)")
                failure = failure ?? error
            }
        }
        return (texts, failure)
    }

    /// What an item's right-click menu does that depends on the shelf it's in.
    struct MenuHandlers {
        var open: @MainActor () -> Void
        var quickLook: @MainActor () -> Void
        var paste: @MainActor () -> Void
        var rename: @MainActor (StashItem) -> Void
        var putBack: @MainActor ([StashItem]) -> Void
        var moveToTrash: @MainActor ([StashItem]) -> Void
    }

    /// The right-click menu for the selected items, the same in the panel and
    /// tear-off shelves. `note` logs what's chosen, saying where.
    static func menu(for selection: [StashItem], note: @escaping (String) -> Void, _ handlers: MenuHandlers) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        func add(_ title: String, enabled: Bool = true, _ action: @escaping @MainActor () -> Void) {
            let item = menu.addItem(withTitle: title, action: #selector(MenuAction.run), keyEquivalent: "")
            let handler = MenuAction(action)
            item.target = handler
            item.representedObject = handler  // keeps it alive while the menu is up
            item.isEnabled = enabled
        }
        let count = "\(selection.count) \(selection.count == 1 ? "item" : "items")"
        add("Open", handlers.open)
        add("Quick Look", handlers.quickLook)
        add("Show in Finder") {
            note("Show in Finder \(count)")
            NSWorkspace.shared.activateFileViewerSelecting(selection.map(\.url))
        }
        menu.addItem(.separator())
        add("Copy") {
            note("Copy \(count)")
            copy(selection)
        }
        if selection.contains(where: TextRecognition.canRead) {
            add("Copy Text") {
                note("Copy Text \(count)")
                copyText(selection)
            }
        }
        if ReadAloud.shared.isReading {
            add("Stop Reading") {
                note("Stop Reading")
                ReadAloud.shared.stop()
            }
        } else if selection.contains(where: canReadAloud) {
            add("Read Aloud") {
                note("Read Aloud \(count)")
                readAloud(selection)
            }
        }
        add("Paste", enabled: canPaste, handlers.paste)
        add("Rename…", enabled: selection.count == 1) { selection.first.map(handlers.rename) }
        menu.addItem(.separator())
        let returnable = selection.filter { $0.origin != nil }
        add("Put Back", enabled: !selection.isEmpty && returnable.count == selection.count) { handlers.putBack(returnable) }
        add("Move to Trash") { handlers.moveToTrash(selection) }
        return menu
    }

    /// Runs a file operation on the items at `urls` off the main thread,
    /// reports what failed, then re-reads where they were.
    static func perform<T: Sendable>(_ verb: String, _ urls: [URL], with mover: FileMover, store: StashStore,
                                     _ operation: @escaping @Sendable (FileMover, [URL]) -> [Result<T, any Error>]) {
        guard !urls.isEmpty else { return }
        Task {
            let results = await Task.detached { operation(mover, urls) }.value
            for (url, result) in zip(urls, results) {
                if case .failure(let error) = result { Alerts.showError("Couldn’t \(verb) “\(url.lastPathComponent)”", error) }
            }
            store.reload(around: urls)
        }
    }

    /// Those of `items` only in iCloud start downloading: dragged out, the
    /// copy lands sooner; for Copy Text or Read Aloud, they can be read next time.
    static func startDownloading(_ items: [StashItem]) {
        for item in items where item.cloud == .cloudOnly {
            try? CloudStatus.startDownloading(item.url)
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

/// A menu item's action as a closure. Menu items hold their target weakly,
/// so the item keeps it as its represented object too.
@MainActor
final class MenuAction: NSObject {
    private let action: @MainActor () -> Void

    init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    @objc func run() {
        action()
    }
}
