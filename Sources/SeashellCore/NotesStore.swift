import Foundation
import Observation

/// The live list of notes for the UI, refreshed whenever the Notes folder
/// changes on disk (including iCloud bringing in another Mac's edits).
@MainActor @Observable
public final class NotesStore {
    public private(set) var notes: [Note] = []

    @ObservationIgnored public let library: NotesLibrary
    @ObservationIgnored private var watcher: FolderWatcher?

    public init(library: NotesLibrary) {
        self.library = library
        reload()
    }

    /// Re-reads the folder; only a real difference is published.
    public func reload() {
        let newNotes = library.notes()
        if newNotes != notes { notes = newNotes }
    }

    public func startWatching() {
        watcher = FolderWatcher(folder: library.folder) { [weak self] in self?.reload() }
    }
}
