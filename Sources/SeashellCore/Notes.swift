import Foundation

/// A note: one Markdown file in `Documents/Seashell/Notes`.
public struct Note: Identifiable, Hashable, Sendable {
    public let url: URL
    /// When it was last edited, as of reading it from disk.
    public let modified: Date
    public var id: URL { url }
    /// The file name without `.md`, which Seashell keeps matching the first line.
    public var title: String { url.deletingPathExtension().lastPathComponent }
}

public enum NoteNaming {
    public static let untitled = "Untitled"
    public static let maxTitleLength = 60

    /// A note's title: its first non-empty line, without Markdown heading marks.
    public static func title(for text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        var title = firstLine
        while title.hasPrefix("#") { title.removeFirst() }
        title = FileNaming.sanitized(title)
        if title.count > maxTitleLength {
            title = String(title.prefix(maxTitleLength)).trimmingCharacters(in: .whitespaces)
        }
        return title.isEmpty ? untitled : title
    }
}

public enum NoteSaveResult: Equatable, Sendable {
    case saved(Note)
    /// The file had changed on disk since it was read (another Mac, another app),
    /// so this version went to a separate note and nothing was overwritten.
    case savedAsCopy(Note)

    public var note: Note {
        switch self {
        case .saved(let note), .savedAsCopy(let note): note
        }
    }
}

/// Reads and writes notes. The folder is the source of truth.
public struct NotesLibrary: Sendable {
    public let folder: URL
    private let trash: FileMover.Trash

    public init(folder: URL, trash: @escaping FileMover.Trash = FileMover.systemTrash) {
        self.folder = folder
        self.trash = trash
    }

    /// Markdown files, most recently edited first.
    public func notes() -> [Note] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
                                                                  options: [.skipsHiddenFiles])) ?? []
        return urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .compactMap(note(at:))
            .sorted { $0.modified > $1.modified }
    }

    public func note(at url: URL) -> Note? {
        Self.modified(url).map { Note(url: url, modified: $0) }
    }

    public func read(_ note: Note) throws -> String {
        try Coordinated.read(note.url) { try String(contentsOf: $0, encoding: .utf8) }
    }

    /// Writes a new note, named after its first line.
    public func create(text: String) throws -> Note {
        let url = FileNaming.uniqueDestination(for: NoteNaming.title(for: text) + ".md", in: folder, isDirectory: false)
        try write(text, to: url)
        let note = try existing(url)
        Log.info("Created note \(note.title)")
        return note
    }

    /// Saves `text` over `note`, unless the file changed on disk since `note`
    /// was read: then the text goes to a separate note, so nothing is overwritten.
    public func save(_ text: String, to note: Note) throws -> NoteSaveResult {
        if let onDisk = Self.modified(note.url), onDisk.timeIntervalSince(note.modified) > 0.001 {
            let url = FileNaming.uniqueDestination(for: "\(note.title) (edited here).md", in: folder, isDirectory: false)
            try write(text, to: url)
            Log.info("Note \(note.title) changed elsewhere; saved this version as \(url.lastPathComponent)")
            return .savedAsCopy(try existing(url))
        }
        try write(text, to: note.url)
        return .saved(try existing(note.url))
    }

    /// Renames the note to match its first line, and returns it as it is afterwards.
    public func renameToFirstLine(_ note: Note, text: String) throws -> Note {
        let name = NoteNaming.title(for: text) + ".md"
        let current = note.url.lastPathComponent
        guard name != current else { return note }
        // Already a numbered copy ("Groceries 2.md") because another note has the
        // plain name: it stays put, or every visit would rename it again.
        if FileNaming.isNumberedCopy(current, of: name),
           FileManager.default.fileExists(atPath: folder.appending(path: name).path(percentEncoded: false)) {
            return note
        }
        // A change of case only: the unique-name check would see the note itself.
        let destination = name.lowercased() == current.lowercased()
            ? folder.appending(path: name)
            : FileNaming.uniqueDestination(for: name, in: folder, isDirectory: false)
        try Coordinated.move(note.url, to: destination)
        Log.info("Renamed note \(note.title) → \(destination.deletingPathExtension().lastPathComponent)")
        return try existing(destination)
    }

    /// Sends a note to the Trash.
    public func delete(_ note: Note) throws {
        try Coordinated.write(note.url, options: .forDeleting) { try trash($0) }
        Log.info("Moved note \(note.title) to the Trash")
    }

    private func write(_ text: String, to url: URL) throws {
        try Coordinated.write(url, options: .forReplacing) { try Data(text.utf8).write(to: $0, options: .atomic) }
    }

    private func existing(_ url: URL) throws -> Note {
        guard let note = note(at: url) else { throw CocoaError(.fileNoSuchFile) }
        return note
    }

    /// A fresh URL each time: URLs cache resource values, and a cached date
    /// would hide a change made elsewhere.
    static func modified(_ url: URL) -> Date? {
        try? URL(filePath: url.path(percentEncoded: false))
            .resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
