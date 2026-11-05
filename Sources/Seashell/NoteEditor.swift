import AppKit
import SeashellCore

/// The note editor and the note in it, the same in the panel and in a note's
/// own window: loading a note, saving 1 s after typing stops (or when asked),
/// and following the Notes folder. NoteSession decides what saving and changes
/// in the folder mean; this keeps the text view in step.
@MainActor
final class NoteEditor {
    let textView = NoteTextView.make()
    /// After each save of waiting edits: what it did (a new note, a separate
    /// copy, or nothing for a new note that's still blank).
    var onSave: ((NoteSession.Saved) -> Void)?

    private let store: NotesStore
    private let session: NoteSession
    private var saveTask: Task<Void, Never>?

    init(store: NotesStore) {
        self.store = store
        session = NoteSession(library: store.library)
    }

    /// The note being edited; nil for a new one with no file yet.
    var note: Note? { session.note }
    var hasUnsavedEdits: Bool { session.hasUnsavedEdits }
    var text: String { textView.string }
    /// Nothing but white space: a note left like this goes to the Trash.
    var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Shows `note`, or nothing for a new note, with the cursor where it was (as
    /// far as the text goes) and ⌘Z starting afresh: it mustn't bring back
    /// another note's words. A note that can't be read throws, leaving the
    /// editor empty and holding no note (see NoteSession.open).
    func load(_ note: Note?) throws {
        saveTask?.cancel()
        let location = textView.selectedRange().location
        let text: String
        do {
            text = try session.open(note)
        } catch {
            show("", cursorAt: location)
            throw error
        }
        show(text, cursorAt: location)
    }

    /// Shows nothing, holding no note: ready for a new one.
    func clear() {
        try? load(nil)  // nothing to read, so nothing to fail
    }

    private func show(_ text: String, cursorAt location: Int) {
        textView.string = text
        textView.setSelectedRange(NSRange(location: min(location, (text as NSString).length), length: 0))
        textView.undoManager?.removeAllActions()
    }

    /// Call from the text view's textDidChange: saves a second after typing stops.
    func textChanged() {
        session.edited()
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Writes waiting edits now. False if they couldn't be saved; the error has
    /// been shown, and the edits are still waiting.
    @discardableResult
    func saveNow() -> Bool {
        saveTask?.cancel()
        saveTask = nil
        guard session.hasUnsavedEdits else { return true }
        let before = session.note
        do {
            let saved = try session.save(text)
            if case .savedAsCopy(let copy) = saved, let before {
                Log.info("Note \(before.title) changed elsewhere; this version saved as \(copy.title)")
            }
            store.reload()
            onSave?(saved)
            return true
        } catch {
            Alerts.showError("Couldn’t save the note", error)
            return false
        }
    }

    /// Drops waiting edits: the note is about to go to the Trash.
    func discardEdits() {
        saveTask?.cancel()
        saveTask = nil
        session.discardEdits()
    }

    /// Renames the note to match its first line, and goes on editing it.
    @discardableResult
    func renameToFirstLine() throws -> Note? {
        try session.renameToFirstLine(text)
    }

    /// What the folder's latest notes mean for this one (see NoteSession.follow).
    /// A version changed elsewhere is shown here; `.gone` is the caller's to
    /// handle, and so is one that can't be read, which the editor lets go of.
    func follow(_ notes: [Note]) -> NoteSession.Change {
        let change = session.follow(notes)
        guard case .changed(let onDisk) = change else { return change }
        do {
            try load(onDisk)
        } catch {
            Log.error("Couldn’t read \(onDisk.title) as changed elsewhere; letting go of it: \(error.localizedDescription)")
            return .gone
        }
        return change
    }
}
