import AppKit
import SeashellCore

/// Copy, rename and share for stashed items, shared by the panel and tear-off
/// shelves. (Paste goes through `StashDropper`, like a drop.)
@MainActor
enum ItemActions {
    /// What an item is on the clipboard or in a share sheet: a text snippet's
    /// text, a link's address, otherwise the file itself.
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

    /// The system's Share submenu (AirDrop, Mail, Messages…) for these items.
    /// `window` is what a sharing sheet attaches to.
    static func shareMenuItem(for items: [StashItem], from window: NSWindow?) -> NSMenuItem {
        let share = Share(items: items.map(object(for:)), window: window)
        let item = share.picker.standardShareMenuItem
        // The picker runs the chosen service, so it must outlive this call:
        // the menu item holds it for as long as the menu is up.
        item.representedObject = share
        return item
    }
}

/// Keeps a sharing picker alive and tells the chosen service where to show itself.
@MainActor
final class Share: NSObject, NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    let picker: NSSharingServicePicker
    /// Read from the sharing service's callbacks, which come on the main thread.
    nonisolated(unsafe) private weak var window: NSWindow?

    init(items: [Any], window: NSWindow?) {
        picker = NSSharingServicePicker(items: items)
        self.window = window
        super.init()
        picker.delegate = self
    }

    nonisolated func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker,
                                          delegateFor sharingService: NSSharingService) -> (any NSSharingServiceDelegate)? {
        self
    }

    nonisolated func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        guard let title = service?.title else { return }
        Log.info("Share: \(title)")
    }

    nonisolated func sharingService(_ sharingService: NSSharingService, sourceWindowForShareItems items: [Any],
                                    sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>) -> NSWindow? {
        window
    }

    nonisolated func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {
        Log.error("Share via \(sharingService.title) failed: \(error.localizedDescription)")
    }

    nonisolated func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        Log.info("Shared via \(sharingService.title)")
    }
}
