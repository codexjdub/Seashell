import Foundation

/// One note being edited, in the panel or in a note's own window: which note
/// it is (nil for a new one with no file yet), whether edits are waiting to be
/// saved, and what saving and changes in the Notes folder mean for it. The
/// editor itself, and saving a second after typing stops, are the app's.
@MainActor
public final class NoteSession {
    public let library: NotesLibrary
    public private(set) var note: Note?
    public private(set) var hasUnsavedEdits = false

    public init(library: NotesLibrary) {
        self.library = library
    }

    /// Edits `note` from now on, with nothing waiting; nil for a new note.
    public func start(_ note: Note?) {
        self.note = note
        hasUnsavedEdits = false
    }

    /// Reads `note` and edits it from now on, with nothing waiting; nil for a
    /// new note, with no text. If it can't be read (only in iCloud while
    /// offline, say, or not UTF-8), this throws, holding no note: shown blank,
    /// it would look emptied, and leaving an emptied note sends it to the Trash.
    public func open(_ note: Note?) throws -> String {
        start(nil)
        let text = try note.map(library.read) ?? ""
        start(note)
        return text
    }

    /// The text changed in the editor.
    public func edited() {
        hasUnsavedEdits = true
    }

    /// Forgets the waiting edits, e.g. when the note is about to go to the Trash.
    public func discardEdits() {
        hasUnsavedEdits = false
    }

    public enum Saved: Equatable, Sendable {
        /// Nothing was waiting, or the new note is still blank.
        case nothing
        case saved(Note)
        /// The file had changed elsewhere, so this text went to a separate
        /// note, which is now the one being edited.
        case savedAsCopy(Note)
        /// A new note got its file, named after its first line.
        case created(Note)
    }

    /// Writes `text` if edits are waiting: over the note, to a separate note if
    /// its file changed elsewhere since it was read, or as a new note unless it's
    /// blank. A note whose file has gone gets it back.
    public func save(_ text: String) throws -> Saved {
        guard hasUnsavedEdits else { return .nothing }
        let saved: Saved
        if let note {
            switch try library.save(text, to: note) {
            case .saved(let new):
                self.note = new
                saved = .saved(new)
            case .savedAsCopy(let copy):
                self.note = copy
                saved = .savedAsCopy(copy)
            }
        } else if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let created = try library.create(text: text)
            note = created
            saved = .created(created)
        } else {
            saved = .nothing
        }
        hasUnsavedEdits = false
        return saved
    }

    /// Renames the note's file to match its first line (see
    /// `NotesLibrary.renameToFirstLine`) and goes on editing it.
    @discardableResult
    public func renameToFirstLine(_ text: String) throws -> Note? {
        guard let note else { return nil }
        let renamed = try library.renameToFirstLine(note, text: text)
        self.note = renamed
        return renamed
    }

    public enum Change: Equatable, Sendable {
        case none
        /// Changed elsewhere (another Mac, another app): show this version, and
        /// `start(_:)` on it.
        case changed(Note)
        /// Renamed or deleted elsewhere, which can't be told apart. The session
        /// has let go of it.
        case gone
    }

    /// What the folder's latest list of notes means for this one. While edits
    /// are waiting nothing changes: they're saved as they are, bringing back a
    /// file that went rather than losing them.
    public func follow(_ notes: [Note]) -> Change {
        guard let note, !hasUnsavedEdits else { return .none }
        guard let onDisk = notes.first(where: { $0.url.lastPathComponent == note.url.lastPathComponent }) else {
            self.note = nil
            return .gone
        }
        return onDisk.modified.timeIntervalSince(note.modified) > 0.001 ? .changed(onDisk) : .none
    }
}
