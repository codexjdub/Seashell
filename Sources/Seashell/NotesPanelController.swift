import AppKit
import SeashellCore

/// Notes inside the pull-down panel: a list of notes beside a plain-text editor.
///
/// - The first line is the title; the file is renamed to match when you leave
///   the note (switch notes, close the panel, quit).
/// - Saves 1 s after you stop typing, and whenever you leave the note.
/// - A new note shows as a selected "New Note" row at once, but has no file until
///   you type; left empty it just disappears. An existing note left empty goes to the Trash.
/// - Rows show live titles: the open note's row follows its first line as you type.
/// - Follows the folder: another Mac's edits show up when you have none pending.
@MainActor
final class NotesPanelController: NSViewController {
    /// Called when a note dragged out of the list was taken by a drop elsewhere.
    var onDraggedOut: ((NSPoint) -> Void)?

    private let store: NotesStore
    private let table = NotesTableView()
    private let editor = NoteTextView()
    private let placeholder = PassThroughLabel(labelWithString: "Type to start a note")
    private var notes: [Note] = []
    /// The note in the editor. Nil while it's a new note with no file yet.
    private var current: Note?
    /// A new note is in the editor that has no file yet; it has its own row.
    private var isDraft = false

    private enum Row {
        case draft
        case note(Note)
    }

    private var rows: [Row] {
        (isDraft ? [.draft] : []) + notes.map(Row.note)
    }
    /// The note to show again when the panel reopens.
    private var lastNoteName: String?
    private var hasUnsavedEdits = false
    private var saveTask: Task<Void, Never>?
    private var isSelectingProgrammatically = false
    /// While a note is dragged out of the list, the list holds still (reloading
    /// it would change the rows under the drag); it catches up when the drag ends.
    private var isDraggingOut = false
    private var listIsStale = false
    private let headerTitle = NSTextField(labelWithString: "Notes")
    private var headerHeight: NSLayoutConstraint?
    private var listWidth: NSLayoutConstraint?

    init(store: NotesStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Layout

    override func loadView() {
        let root = NSView()

        let add = NSButton(image: NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "New note")!,
                           target: self, action: #selector(newNote))
        add.bezelStyle = .accessoryBarAction
        add.toolTip = "New note (⌘N)"
        let header = NSStackView(views: [headerTitle, add])
        header.orientation = .horizontal
        header.spacing = 8

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("note"))
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .plain
        table.backgroundColor = .clear
        table.allowsMultipleSelection = false
        table.dataSource = self
        table.delegate = self
        table.registerForDraggedTypes([.string])
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.onDelete = { [weak self] in self?.deleteSelectedNote() }
        table.contextMenu = { [weak self] in self?.noteMenu() }
        let listScroll = NSScrollView()
        listScroll.documentView = table
        listScroll.drawsBackground = false
        listScroll.hasVerticalScroller = true
        listScroll.autohidesScrollers = true

        editor.isRichText = false
        editor.allowsUndo = true
        editor.textContainerInset = NSSize(width: 6, height: 8)
        editor.drawsBackground = false
        // Markdown is typed as is: no curly quotes or long dashes.
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = self
        let editorScroll = NSScrollView()
        editorScroll.documentView = editor
        editorScroll.drawsBackground = false
        editorScroll.hasVerticalScroller = true
        editorScroll.autohidesScrollers = true

        placeholder.textColor = .tertiaryLabelColor

        let divider = NSBox()
        divider.boxType = .separator
        // A separator wants to stay a few points tall; tied to the list, it would squash it.
        divider.setContentHuggingPriority(.defaultLow, for: .vertical)

        for subview in [header, listScroll, divider, editorScroll, placeholder] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(subview)
        }
        // Without a height the header stretches and squashes the list and editor.
        let headerHeight = header.heightAnchor.constraint(equalToConstant: 28)
        let listWidth = listScroll.widthAnchor.constraint(equalToConstant: 150)
        self.headerHeight = headerHeight
        self.listWidth = listWidth
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            headerHeight,
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -12),
            listScroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            listScroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            listScroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            listWidth,
            divider.leadingAnchor.constraint(equalTo: listScroll.trailingAnchor, constant: 4),
            divider.topAnchor.constraint(equalTo: listScroll.topAnchor),
            divider.bottomAnchor.constraint(equalTo: listScroll.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            editorScroll.topAnchor.constraint(equalTo: listScroll.topAnchor),
            editorScroll.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: 4),
            editorScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            editorScroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            placeholder.topAnchor.constraint(equalTo: editorScroll.topAnchor, constant: 8),
            placeholder.leadingAnchor.constraint(equalTo: editorScroll.leadingAnchor, constant: 11),
        ])
        view = root
        observeChanges { [weak self] in self?.refresh() }
        observeChanges { [weak self] in self?.applyTextSize() }
    }

    /// Re-sizes text, rows and the list. Reads the text size, so it runs again when that changes.
    private func applyTextSize() {
        _ = TextSizeSetting.shared.size
        headerTitle.font = UIScale.font(13, weight: .semibold)
        headerHeight?.constant = UIScale.pt(28)
        listWidth?.constant = UIScale.pt(150)
        table.rowHeight = UIScale.pt(38)
        editor.font = UIScale.font(13)
        placeholder.font = UIScale.font(13)
        table.reloadData()
        selectCurrentRow()
    }

    // MARK: Panel showing and hiding

    func willShow() {
        if current == nil, editor.string.isEmpty, let name = lastNoteName,
           let note = store.notes.first(where: { $0.url.lastPathComponent == name }) {
            open(note)
        }
    }

    /// Closing the panel (or quitting) leaves the note: saved, renamed, or trashed if empty.
    func willHide() {
        leaveCurrent()
    }

    // MARK: Following the store

    private func refresh() {
        let newNotes = store.notes  // read first: that's what keeps this running on changes
        guard !isDraggingOut else {
            listIsStale = true
            return
        }
        if let current, !hasUnsavedEdits {
            if let onDisk = newNotes.first(where: { $0.url.lastPathComponent == current.url.lastPathComponent }) {
                if onDisk.modified.timeIntervalSince(current.modified) > 0.001 {
                    note("\(current.title) changed elsewhere; showing the new version")
                    load(onDisk)
                }
            } else {
                note("\(current.title) was renamed or deleted elsewhere")
                self.current = nil
                editor.string = ""
            }
        }
        notes = newNotes
        reloadList()
        updatePlaceholder()
    }

    private func reloadList() {
        table.reloadData()
        selectCurrentRow()
    }

    /// The row of what's in the editor: the draft, or the open note.
    private var currentRow: Int? {
        if isDraft { return 0 }
        guard let name = current?.url.lastPathComponent,
              let index = notes.firstIndex(where: { $0.url.lastPathComponent == name }) else { return nil }
        return index
    }

    private func selectCurrentRow() {
        isSelectingProgrammatically = true
        defer { isSelectingProgrammatically = false }
        if let row = currentRow {
            table.selectRowIndexes([row], byExtendingSelection: false)
            table.scrollRowToVisible(row)
        } else {
            table.deselectAll(nil)
        }
    }

    /// Redraws just the open note's row, for its live title.
    private func refreshCurrentRow() {
        guard let row = currentRow else { return }
        table.reloadData(forRowIndexes: [row], columnIndexes: [0])
    }

    private func updatePlaceholder() {
        placeholder.isHidden = !editor.string.isEmpty
        placeholder.stringValue = isDraft ? "Type your new note"
            : notes.isEmpty ? "No notes yet. Type here, or press ⌘N." : "Type to start a note"
    }

    // MARK: Opening, saving, leaving

    private func open(_ note: Note) {
        guard leaveCurrent() else { return selectCurrentRow() }
        guard let fresh = store.library.note(at: note.url) else { return }
        load(fresh)
        lastNoteName = fresh.url.lastPathComponent
        selectCurrentRow()
    }

    private func load(_ note: Note) {
        let text = (try? store.library.read(note)) ?? ""
        let selection = editor.selectedRange()
        current = note
        hasUnsavedEdits = false
        editor.string = text
        editor.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
        editor.undoManager?.removeAllActions()
        updatePlaceholder()
    }

    /// Puts the keyboard in the editor.
    func focusEditor() {
        view.window?.makeFirstResponder(editor)
    }

    @objc func newNote() {
        note("new note")
        guard leaveCurrent() else { return }
        isDraft = true
        editor.string = ""
        reloadList()
        updatePlaceholder()
        view.window?.makeFirstResponder(editor)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Writes pending edits. A new note gets its file now, named after its first
    /// line. False if they couldn't be saved.
    @discardableResult
    private func saveNow() -> Bool {
        saveTask?.cancel()
        saveTask = nil
        guard hasUnsavedEdits else { return true }
        let text = editor.string
        do {
            if let current {
                let result = try store.library.save(text, to: current)
                self.current = result.note
                if case .savedAsCopy = result {
                    note("\(current.title) changed elsewhere; this version saved as \(result.note.title)")
                }
            } else if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                current = try store.library.create(text: text)
                isDraft = false
            }
            hasUnsavedEdits = false
            lastNoteName = current?.url.lastPathComponent
            store.reload()
            if isDraggingOut {
                listIsStale = true
            } else {
                notes = store.notes
                reloadList()
            }
            return true
        } catch {
            Alerts.showError("Couldn’t save the note", error)
            return false
        }
    }

    /// Saves, then renames the note to its first line, or trashes it if it's empty.
    /// If it couldn't be saved, it stays open with its text, and this returns false.
    @discardableResult
    private func leaveCurrent() -> Bool {
        guard saveNow() else { return false }
        defer {
            editor.string = ""
            reloadList()
        }
        if isDraft {
            // Still no file: it was left empty, so it simply disappears.
            isDraft = false
            note("empty new note discarded")
        }
        guard let leaving = current else { return true }
        current = nil
        do {
            if editor.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try store.library.delete(leaving)
                lastNoteName = nil
            } else {
                lastNoteName = try store.library.renameToFirstLine(leaving, text: editor.string).url.lastPathComponent
            }
        } catch {
            Log.error("Couldn’t tidy up note \(leaving.title): \(error.localizedDescription)")
        }
        store.reload()
        return true
    }

    // MARK: List actions

    private func noteMenu() -> NSMenu {
        let menu = NSMenu()
        let trash = menu.addItem(withTitle: "Move to Trash", action: #selector(deleteSelectedNote), keyEquivalent: "")
        trash.target = self
        return menu
    }

    @objc private func deleteSelectedNote() {
        let selected = table.selectedRow
        guard rows.indices.contains(selected) else { return }
        guard case .note(let target) = rows[selected] else {
            note("new note discarded")
            saveTask?.cancel()
            hasUnsavedEdits = false
            isDraft = false
            editor.string = ""
            reloadList()
            updatePlaceholder()
            return
        }
        note("Move to Trash \(target.title)")
        if target.url.lastPathComponent == current?.url.lastPathComponent {
            // Don't save or rename what's about to go.
            saveTask?.cancel()
            hasUnsavedEdits = false
            current = nil
            editor.string = ""
            lastNoteName = nil
        }
        do {
            try store.library.delete(target)
        } catch {
            Alerts.showError("Couldn’t move “\(target.title)” to the Trash", error)
        }
        store.reload()
    }

    private func note(_ message: String) {
        Log.info("Notes: \(message)")
    }
}

// MARK: Editor

extension NotesPanelController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        hasUnsavedEdits = true
        if current == nil, !isDraft {
            // Typing with nothing open starts a new note.
            isDraft = true
            reloadList()
        } else {
            refreshCurrentRow()
        }
        updatePlaceholder()
        scheduleSave()
    }
}

// MARK: List

extension NotesPanelController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: NoteRowView.identifier, owner: nil) as? NoteRowView ?? NoteRowView()
        let typed = editor.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : NoteNaming.title(for: editor.string)
        switch rows[row] {
        case .draft:
            cell.show(title: typed ?? "New Note", detail: "Not saved yet")
        case .note(let note):
            let isOpen = note.url.lastPathComponent == current?.url.lastPathComponent
            cell.show(title: isOpen ? (typed ?? note.title) : note.title,
                      detail: note.modified.formatted(date: .abbreviated, time: .shortened))
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        NoteSelectionRowView()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isSelectingProgrammatically, rows.indices.contains(table.selectedRow),
              case .note(let selected) = rows[table.selectedRow] else { return }
        guard selected.url.lastPathComponent != current?.url.lastPathComponent else { return }
        note("opened \(selected.title)")
        open(selected)
    }

    // Dragging a note out: its text, plus its .md for Finder.

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        guard case .note(let dragged) = rows[row] else { return nil }  // a new note has nothing to drag yet
        isDraggingOut = true
        if dragged.url.lastPathComponent == current?.url.lastPathComponent { saveNow() }
        let text = (try? store.library.read(dragged)) ?? ""
        note("dragging out \(dragged.title)")
        return DragOut.writer(forNote: dragged.url, text: text)
    }

    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession,
                   endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDraggingOut = false
        if listIsStale {
            listIsStale = false
            refresh()
        }
        note(operation.isEmpty ? "drag out ended: not taken" : "drag out ended: taken")
        if !operation.isEmpty { onDraggedOut?(screenPoint) }
    }

    // Dropping text onto the list starts a new note with it.

    func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard info.draggingSource as? NSTableView !== table,
              info.draggingPasteboard.canReadObject(forClasses: [NSString.self], options: nil)
        else { return [] }
        tableView.setDropRow(-1, dropOperation: .on)  // the whole list
        return .copy
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard let text = info.draggingPasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        note("text dropped onto the list")
        guard leaveCurrent() else { return false }
        do {
            let created = try store.library.create(text: text)
            store.reload()
            open(created)
            return true
        } catch {
            Alerts.showError("Couldn’t create a note from the dropped text", error)
            return false
        }
    }
}

/// A row in the notes list: title and when it was last edited.
@MainActor
final class NoteRowView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("NoteRow")
    private let title = NSTextField(labelWithString: "")
    private let date = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        date.font = .systemFont(ofSize: 10)
        date.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, date])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(title text: String, detail: String) {
        title.font = UIScale.font(12, weight: .semibold)
        date.font = UIScale.font(10)
        title.stringValue = text
        date.stringValue = detail
        toolTip = text
    }
}

/// The selected note is a stronger yellow than the Notes card, whether or not
/// the list has focus.
final class NoteSelectionRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 5, yRadius: 5)
        NoteTint.color.withAlphaComponent(NoteTint.selection.value(in: effectiveAppearance)).setFill()
        path.fill()
    }

    /// Keeps the title in the normal text color; the default turns it white,
    /// which is unreadable on pale yellow in light mode.
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}

/// The notes list: ⌘⌫ deletes, and right-clicking a row selects it first.
@MainActor
final class NotesTableView: NSTableView {
    var onDelete: (() -> Void)?
    var contextMenu: (() -> NSMenu?)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51, event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command {
            onDelete?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else { return nil }
        selectRowIndexes([row], byExtendingSelection: false)
        return contextMenu?()
    }
}

/// The note editor. Esc goes to the panel (which saves and closes) instead of
/// the text view's usual "suggest completions".
final class NoteTextView: NSTextView {
    override func cancelOperation(_ sender: Any?) {
        window?.cancelOperation(sender)
    }
}
