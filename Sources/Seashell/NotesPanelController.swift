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
/// - Pinned notes stay at the top of the list (right-click → Pin).
/// - A note can open in its own window (right-click); it's then edited only
///   there, and choosing it here brings that window forward.
/// - To-dos (`- [ ]`): click the box to tick it; done ones show grey and struck
///   through. Return continues the list, ⇧⌘L makes or unmakes to-dos.
@MainActor
final class NotesPanelController: NSViewController {
    /// Called when a note dragged out of the list was taken by a drop elsewhere.
    var onDraggedOut: ((NSPoint) -> Void)?

    private let store: NotesStore
    private let windows: NoteWindows
    private let table = NotesTableView()
    private let editor = NoteTextView.make()
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

    init(store: NotesStore, windows: NoteWindows) {
        self.store = store
        self.windows = windows
        super.init(nibName: nil, bundle: nil)
        windows.onChange = { [weak self] in self?.reloadList() }
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
           let note = store.notes.first(where: { $0.url.lastPathComponent == name }), !windows.contains(note) {
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
                clearEditor()
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
        if windows.contains(note) {
            windows.open(note)
            return selectCurrentRow()
        }
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
        editor.styleChecklists()
        updatePlaceholder()
    }


    /// Puts the keyboard in the editor.
    func focusEditor() {
        view.window?.makeFirstResponder(editor)
    }

    /// Opens `note` with the keyboard at its end, ready to add to it.
    func show(_ note: Note) {
        open(note)
        guard current?.url.lastPathComponent == note.url.lastPathComponent else { return }
        let end = NSRange(location: (editor.string as NSString).length, length: 0)
        editor.setSelectedRange(end)
        editor.scrollRangeToVisible(end)
        focusEditor()
    }

    @objc func newNote() {
        note("new note")
        guard leaveCurrent() else { return }
        isDraft = true
        clearEditor()
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
            clearEditor()
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

    /// Empties the editor, and forgets its typing: ⌘Z mustn't bring back
    /// another note's words.
    private func clearEditor() {
        editor.string = ""
        editor.undoManager?.removeAllActions()
    }

    // MARK: List actions

    private func noteMenu() -> NSMenu {
        let menu = NSMenu()
        @discardableResult
        func add(_ title: String, _ action: Selector?, for note: Note? = nil) -> NSMenuItem {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = note?.url
            return item
        }
        if rows.indices.contains(table.selectedRow), case .note(let selected) = rows[table.selectedRow] {
            add("Open in Its Own Window", #selector(openInWindow), for: selected)
            add("Open With", nil).submenu = openWithMenu(for: selected)
            add("Show in Finder", #selector(showInFinder), for: selected)
            menu.addItem(.separator())
            add("Copy", #selector(copyNote), for: selected)
            add("Duplicate", #selector(duplicateNote), for: selected)
            add(selected.isPinned ? "Unpin" : "Pin", #selector(togglePin), for: selected)
            menu.addItem(.separator())
        }
        add("Move to Trash", #selector(deleteSelectedNote))
        return menu
    }

    /// Apps that open Markdown files, the default one first.
    private func openWithMenu(for note: Note) -> NSMenu {
        let menu = NSMenu()
        let workspace = NSWorkspace.shared
        let preferred = workspace.urlForApplication(toOpen: note.url)?.standardizedFileURL
        // Without ".app", which Finder shows when it's set to show all extensions.
        let name = { (app: URL) -> String in
            let shown = FileManager.default.displayName(atPath: app.path(percentEncoded: false))
            return shown.hasSuffix(".app") ? String(shown.dropLast(4)) : shown
        }
        let apps = workspace.urlsForApplications(toOpen: note.url)
            .map(\.standardizedFileURL)
            .filter { $0 != Bundle.main.bundleURL.standardizedFileURL }
            .sorted { ($0 == preferred ? 0 : 1, name($0).lowercased()) < ($1 == preferred ? 0 : 1, name($1).lowercased()) }
        for app in apps {
            let item = menu.addItem(withTitle: app == preferred ? "\(name(app)) (default)" : name(app),
                                    action: #selector(openWith), keyEquivalent: "")
            item.target = self
            item.representedObject = [note.url, app]
            let icon = workspace.icon(forFile: app.path(percentEncoded: false))
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            if app == preferred, apps.count > 1 { menu.addItem(.separator()) }
        }
        if apps.isEmpty {
            menu.addItem(withTitle: "No Apps", action: nil, keyEquivalent: "").isEnabled = false
        }
        return menu
    }

    /// The note a menu item is about, as the list has it now.
    private func menuNote(_ sender: NSMenuItem) -> Note? {
        let url = (sender.representedObject as? URL) ?? (sender.representedObject as? [URL])?.first
        guard let name = url?.lastPathComponent else { return nil }
        return notes.first { $0.url.lastPathComponent == name }
    }

    /// Writes edits waiting for `note`, here or in its window, so other apps
    /// and copies get the latest text.
    private func flush(_ note: Note) {
        if note.url.lastPathComponent == current?.url.lastPathComponent { saveNow() }
        windows.saveNow(note)
    }

    @objc private func openInWindow(_ sender: NSMenuItem) {
        guard var target = menuNote(sender) else { return }
        note("Open in Its Own Window \(target.title)")
        if target.url.lastPathComponent == current?.url.lastPathComponent {
            // Leaving it saves it and renames it to its first line (or trashes it if empty).
            guard leaveCurrent(), let name = lastNoteName,
                  let left = store.notes.first(where: { $0.url.lastPathComponent == name }) else { return }
            target = left
            lastNoteName = nil
            updatePlaceholder()
        }
        windows.open(target, below: view.window?.frame)
    }

    @objc private func openWith(_ sender: NSMenuItem) {
        guard let target = menuNote(sender), let app = (sender.representedObject as? [URL])?.last else { return }
        note("Open With \(app.deletingPathExtension().lastPathComponent): \(target.title)")
        flush(target)
        NSWorkspace.shared.open([target.url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func showInFinder(_ sender: NSMenuItem) {
        guard let target = menuNote(sender) else { return }
        note("Show in Finder \(target.title)")
        flush(target)
        NSWorkspace.shared.activateFileViewerSelecting([target.url])
    }

    @objc private func copyNote(_ sender: NSMenuItem) {
        guard let target = menuNote(sender) else { return }
        note("Copy \(target.title)")
        flush(target)
        do {
            let text = try store.library.read(target)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        } catch {
            Alerts.showError("Couldn’t copy “\(target.title)”", error)
        }
    }

    /// A copy named after its first line ("Groceries 2"), opened here.
    @objc private func duplicateNote(_ sender: NSMenuItem) {
        guard let target = menuNote(sender) else { return }
        note("Duplicate \(target.title)")
        flush(target)
        do {
            let copy = try store.library.create(text: try store.library.read(target))
            store.reload()
            open(copy)
        } catch {
            Alerts.showError("Couldn’t duplicate “\(target.title)”", error)
        }
    }

    @objc private func togglePin(_ sender: NSMenuItem) {
        guard let target = menuNote(sender) else { return }
        note("\(target.isPinned ? "Unpin" : "Pin") \(target.title)")
        do {
            try store.library.setPinned(target, !target.isPinned)
        } catch {
            Alerts.showError("Couldn’t \(target.isPinned ? "unpin" : "pin") “\(target.title)”", error)
        }
        store.reload()
    }

    @objc private func deleteSelectedNote() {
        let selected = table.selectedRow
        guard rows.indices.contains(selected) else { return }
        guard case .note(let target) = rows[selected] else {
            note("new note discarded")
            saveTask?.cancel()
            hasUnsavedEdits = false
            isDraft = false
            clearEditor()
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
            clearEditor()
            lastNoteName = nil
        }
        // Its window saves what it has, then closes, so the Trash gets the latest.
        windows.closeForTrash(target)
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
        editor.styleChecklists()
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
            cell.show(title: typed ?? "New Note", detail: "Not saved yet", pinned: false, windowed: false)
        case .note(let note):
            let isOpen = note.url.lastPathComponent == current?.url.lastPathComponent
            cell.show(title: isOpen ? (typed ?? note.title) : note.title,
                      detail: note.modified.formatted(date: .abbreviated, time: .shortened),
                      pinned: note.isPinned, windowed: windows.contains(note))
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

/// A row in the notes list: title and when it was last edited, with a pin if
/// it's pinned and a window if it's open in its own.
@MainActor
final class NoteRowView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("NoteRow")
    private let title = NSTextField(labelWithString: "")
    private let date = NSTextField(labelWithString: "")
    private let pin = NSImageView()
    private let windowBadge = NSImageView()
    private lazy var badges = NSStackView(views: [windowBadge, pin])

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
        for badge in [pin, windowBadge] {
            badge.contentTintColor = .secondaryLabelColor
            badge.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        badges.spacing = 3
        badges.setContentCompressionResistancePriority(.required, for: .horizontal)
        for view in [stack, badges] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        // The badges sit at the end of the title line; the date can run on under them.
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: badges.leadingAnchor, constant: -3),
            badges.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            badges.centerYAnchor.constraint(equalTo: title.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(title text: String, detail: String, pinned: Bool, windowed: Bool) {
        title.font = UIScale.font(12, weight: .semibold)
        date.font = UIScale.font(10)
        title.stringValue = text
        date.stringValue = detail
        pin.image = pinned ? NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: UIScale.pt(9), weight: .semibold)) : nil
        pin.isHidden = !pinned
        windowBadge.image = windowed ? NSImage(systemSymbolName: "macwindow", accessibilityDescription: "In its own window")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: UIScale.pt(9), weight: .semibold)) : nil
        windowBadge.isHidden = !windowed
        let notes = [pinned ? "pinned" : nil, windowed ? "in its own window" : nil].compactMap { $0 }
        toolTip = notes.isEmpty ? text : "\(text) (\(notes.joined(separator: ", ")))"
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
