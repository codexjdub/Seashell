import Foundation
import Observation

/// The live list of notes for the UI, refreshed whenever the Notes folder
/// changes on disk (including iCloud bringing in another Mac's edits).
@MainActor @Observable
public final class NotesStore {
    public private(set) var notes: [Note] = []

    @ObservationIgnored public let library: NotesLibrary
    @ObservationIgnored private var watcher: FolderWatcher?
    /// Pins whose notes have gone.
    @ObservationIgnored private let vanishedPins: VanishedEntries

    /// `pruneGrace`: how long a pinned note must stay gone before its pin is
    /// forgotten (see VanishedEntries).
    public init(library: NotesLibrary, pruneGrace: TimeInterval = 60) {
        self.library = library
        vanishedPins = VanishedEntries(grace: pruneGrace)
        reload()
    }

    /// Re-reads the folder; only a real difference is published.
    public func reload() {
        let newNotes = library.notes()
        if newNotes != notes { notes = newNotes }
        forgetVanishedPins()
    }

    public func startWatching() {
        watcher = FolderWatcher(folder: library.folder) { [weak self] in self?.reload() }
    }

    /// A pin whose note has stayed gone (deleted or renamed in Finder, say) is
    /// forgotten, so a later note of that name doesn't come back pinned.
    private func forgetVanishedPins() {
        let expired = vanishedPins.expired(among: library.vanishedPins()) { [weak self] in self?.reload() }
        guard !expired.isEmpty else { return }
        do {
            try library.forgetPins(expired)
            Log.info("Forgot the pins of \(expired.count) note(s) no longer in Notes: \(expired.sorted().joined(separator: ", "))")
        } catch {
            Log.error("Couldn’t update Notes’ \(NotesManifest.fileName): \(error.localizedDescription)")
        }
    }
}
