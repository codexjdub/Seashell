import AppKit
import SeashellCore

/// Seashell's entries in the Services menu, declared under NSServices in
/// Info.plist (see bundle.sh):
///
/// - "Stash in Seashell" for files, folders or text selected in another app;
///   Finder shows it at the bottom of its right-click menu.
/// - "New Seashell Note" for selected text.
@MainActor
final class ServiceProvider: NSObject {
    private let store: StashStore
    private let notesStore: NotesStore
    private let dropper: StashDropper
    private let panel: PanelController

    init(store: StashStore, notesStore: NotesStore, dropper: StashDropper, panel: PanelController) {
        self.store = store
        self.notesStore = notesStore
        self.dropper = dropper
        self.panel = panel
    }

    /// Like dropping onto the menu bar icon: into Main, files moved (Put Back
    /// works) and big ones asked about first. Quiet: the files simply leave Finder.
    @objc func stashInSeashell(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        Log.info("Service: Stash in Seashell")
        guard let main = store.defaultShelf else {
            error.pointee = "Seashell has no \(SeashellFolders.defaultShelfName) shelf to stash into." as NSString
            return
        }
        if !dropper.stash(pasteboard, into: main.url) {
            error.pointee = "Seashell couldn’t stash what was selected." as NSString
        }
    }

    /// A new note holding the selected text, opened in the panel so you can keep typing.
    @objc func newSeashellNote(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        Log.info("Service: New Seashell Note")
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = "There was no text to make a note of." as NSString
            return
        }
        do {
            let note = try notesStore.library.create(text: text)
            notesStore.reload()
            panel.open(note: note, reason: "New Seashell Note")
        } catch let failure {
            Alerts.showError("Couldn’t create the note", failure)
        }
    }
}
