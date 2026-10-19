import AppKit
import SeashellCore

/// Notes in their own windows, opened from a note's right-click menu ("Open in
/// Its Own Window"). Like a torn-off shelf: a small window floating above other
/// windows on every Space, until closed; open ones come back after a restart
/// where they were. A note in a window is edited only there: choosing it in the
/// panel's list brings its window forward.
@MainActor
final class NoteWindows {
    private static let key = "noteWindows"

    /// A window opened, closed, or its note renamed: the panel's list marks them.
    var onChange: (() -> Void)?

    private let store: NotesStore
    /// By the note's file name.
    private var windows: [String: NoteWindow] = [:]

    init(store: NotesStore) {
        self.store = store
    }

    func contains(_ note: Note) -> Bool {
        windows[note.url.lastPathComponent] != nil
    }

    /// Opens `note` in its own window by the pointer, or brings its window
    /// forward. Opened from the panel (`below` its frame), it goes under the
    /// panel rather than behind it.
    func open(_ note: Note, below panel: NSRect? = nil) {
        if let window = windows[note.url.lastPathComponent] {
            window.bringForward()
            return
        }
        let window = make(note)
        window.show(frame: nil, below: panel)
        window.bringForward()
        save()
        onChange?()
        Log.info("Note window: \(note.title) opened")
    }

    /// Writes any edits waiting in `note`'s window, so others see the latest text.
    func saveNow(_ note: Note) {
        windows[note.url.lastPathComponent]?.saveNow()
    }

    /// `note` is going to the Trash from the panel: its window saves and closes.
    func closeForTrash(_ note: Note) {
        windows[note.url.lastPathComponent]?.close(trashingIfEmpty: false)
    }

    /// The ones open when Seashell quit, where they were.
    func restore() {
        guard let saved = UserDefaults.standard.array(forKey: Self.key) as? [[String: Any]] else { return }
        for entry in saved {
            guard let name = entry["name"] as? String,
                  let note = store.notes.first(where: { $0.url.lastPathComponent == name }),
                  let x = entry["x"] as? Double, let y = entry["y"] as? Double,
                  let width = entry["width"] as? Double, let height = entry["height"] as? Double else { continue }
            make(note).show(frame: NSRect(x: x, y: y, width: width, height: height))
            Log.info("Note window: \(note.title) restored")
        }
        onChange?()
    }

    /// Quitting: each window's note saved and renamed to its first line. They stay open for next time.
    func tidyAll() {
        windows.values.forEach { $0.tidy() }
        save()
    }

    private func make(_ note: Note) -> NoteWindow {
        let window = NoteWindow(note: note, store: store)
        window.onMove = { [weak self] in self?.save() }
        window.onRenamed = { [weak self, weak window] old in
            guard let self, let window else { return }
            self.windows[old] = nil
            self.windows[window.name] = window
            self.save()
            self.onChange?()
        }
        window.onClose = { [weak self, weak window] in
            guard let self, let window else { return }
            self.windows[window.name] = nil
            self.save()
            self.onChange?()
            Log.info("Note window: \(window.name) closed")
        }
        windows[note.url.lastPathComponent] = window
        return window
    }

    /// Names and frames, in screen coordinates.
    private func save() {
        let entries: [[String: Any]] = windows.values.map { window in
            let frame = window.frame
            return ["name": window.name, "x": Double(frame.minX), "y": Double(frame.minY),
                    "width": Double(frame.width), "height": Double(frame.height)]
        }
        UserDefaults.standard.set(entries, forKey: Self.key)
    }
}

/// One note in its own window: its title along the top, then the same editor
/// as the panel's (to-dos, lists, ⌘Z). Saves 1 s after you stop typing; renamed
/// to its first line when you click away; closing an emptied one sends it to the
/// Trash, as leaving it in the panel does.
@MainActor
final class NoteWindow: NSObject, NSWindowDelegate, NSTextViewDelegate {
    private(set) var note: Note
    var name: String { note.url.lastPathComponent }
    var frame: NSRect { window.frame }

    /// The note was renamed (to its first line, or saved as a separate copy): its old file name.
    var onRenamed: ((String) -> Void)?
    var onClose: (() -> Void)?
    /// Moved or resized.
    var onMove: (() -> Void)?

    private static let size = NSSize(width: 280, height: 260)
    private static let titleBarHeight: CGFloat = 28

    private let store: NotesStore
    private let editor = NoteTextView.make()
    private let title = NSTextField(labelWithString: "")
    private var hasUnsavedEdits = false
    private var saveTask: Task<Void, Never>?
    private var isClosing = false
    private lazy var window = makeWindow()

    init(note: Note, store: NotesStore) {
        self.note = note
        self.store = store
        super.init()
        load(note)
        observeChanges { [weak self] in self?.followStore() }
        observeChanges { [weak self] in self?.applyTextSize() }
    }

    /// At `frame` (kept on a screen), or by the pointer: just below `panel`
    /// if the pointer is on it, since the panel would cover it.
    func show(frame: NSRect?, below panel: NSRect? = nil) {
        var target = frame ?? NSRect(origin: .zero, size: NSSize(width: UIScale.pt(Self.size.width),
                                                                 height: UIScale.pt(Self.size.height)))
        if frame == nil {
            let pointer = NSEvent.mouseLocation
            target.origin = NSPoint(x: pointer.x + 12, y: pointer.y - target.height - 12)
            if let panel, panel.contains(pointer) {
                target.origin = NSPoint(x: pointer.x - target.width / 2, y: panel.minY - target.height - 8)
            }
        }
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(target) } ?? NSScreen.containing(NSEvent.mouseLocation)
        if let visible = screen?.visibleFrame {
            target.size.width = min(target.width, visible.width)
            target.size.height = min(target.height, visible.height)
            target.origin.x = min(max(target.minX, visible.minX), visible.maxX - target.width)
            target.origin.y = min(max(target.minY, visible.minY), visible.maxY - target.height)
        }
        window.setFrame(target, display: true)
        window.orderFrontRegardless()
    }

    func bringForward() {
        window.orderFrontRegardless()
        window.makeKey()
        window.makeFirstResponder(editor)
    }

    // MARK: Saving

    /// Writes pending edits. False if they couldn't be saved.
    @discardableResult
    func saveNow() -> Bool {
        saveTask?.cancel()
        saveTask = nil
        guard hasUnsavedEdits else { return true }
        do {
            let result = try store.library.save(editor.string, to: note)
            if case .savedAsCopy = result {
                Log.info("Note window: \(note.title) changed elsewhere; this version saved as \(result.note.title)")
            }
            hasUnsavedEdits = false
            setNote(result.note)
            store.reload()
            return true
        } catch {
            Alerts.showError("Couldn’t save the note", error)
            return false
        }
    }

    /// Saved, and renamed to its first line: when you click away, and on quit.
    func tidy() {
        guard saveNow(), !isEmpty else { return }
        do {
            setNote(try store.library.renameToFirstLine(note, text: editor.string))
        } catch {
            Log.error("Couldn’t rename note \(note.title): \(error.localizedDescription)")
        }
        store.reload()
    }

    /// Saved and renamed, then closed; an emptied note goes to the Trash. If it
    /// can't be saved, it stays open with its text.
    func close(trashingIfEmpty: Bool = true) {
        guard !isClosing, saveNow() else { return }
        if trashingIfEmpty, isEmpty {
            do {
                try store.library.delete(note)
            } catch {
                Alerts.showError("Couldn’t move “\(note.title)” to the Trash", error)
            }
            store.reload()
        } else if trashingIfEmpty {
            tidy()
        }
        dismiss()
    }

    private var isEmpty: Bool {
        editor.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func dismiss() {
        isClosing = true
        saveTask?.cancel()
        window.orderOut(nil)
        onClose?()
    }

    private func setNote(_ new: Note) {
        let old = name
        note = new
        title.stringValue = new.title
        if new.url.lastPathComponent != old { onRenamed?(old) }
    }

    private func load(_ note: Note) {
        self.note = note
        editor.string = (try? store.library.read(note)) ?? ""
        editor.undoManager?.removeAllActions()
        editor.styleChecklists()
        hasUnsavedEdits = false
        title.stringValue = note.title
    }

    /// Another Mac's (or app's) edits show up when there are none waiting here.
    /// Deleted or renamed elsewhere (which can't be told apart), the window closes.
    private func followStore() {
        let notes = store.notes  // read first: that's what keeps this running on changes
        guard !isClosing else { return }
        guard let onDisk = notes.first(where: { $0.url.lastPathComponent == name }) else {
            Log.info("Note window: \(note.title) was renamed or deleted elsewhere")
            dismiss()
            return
        }
        if !hasUnsavedEdits, onDisk.modified.timeIntervalSince(note.modified) > 0.001 {
            Log.info("Note window: \(note.title) changed elsewhere; showing the new version")
            let selection = editor.selectedRange()
            load(onDisk)
            editor.setSelectedRange(NSRange(location: min(selection.location, (editor.string as NSString).length), length: 0))
        }
    }

    // MARK: Editor and window

    func textDidChange(_ notification: Notification) {
        hasUnsavedEdits = true
        editor.styleChecklists()
        title.stringValue = isEmpty ? note.title : NoteNaming.title(for: editor.string)
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !isClosing else { return }
        tidy()
    }

    /// The close button and ⌘W.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        close()
        return false
    }

    func windowDidMove(_ notification: Notification) {
        onMove?()
    }

    func windowDidResize(_ notification: Notification) {
        onMove?()
    }

    private func applyTextSize() {
        _ = TextSizeSetting.shared.size
        title.font = UIScale.font(12, weight: .semibold)
        editor.font = UIScale.font(13)
    }

    private func makeWindow() -> NSPanel {
        let window = NoteWindowPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                                     styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        // isFloatingPanel resets the level, so it goes first.
        window.isFloatingPanel = true
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 180, height: 120)
        window.delegate = self

        let card = NoteCardView()
        editor.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = editor
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        title.textColor = .secondaryLabelColor
        title.lineBreakMode = .byTruncatingTail
        title.alignment = .center

        for view in [title, scroll] {
            view.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(view)
        }
        NSLayoutConstraint.activate([
            // In the title bar, clear of the close button.
            title.centerYAnchor.constraint(equalTo: card.topAnchor, constant: Self.titleBarHeight / 2),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 44),
            title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -44),
            scroll.topAnchor.constraint(equalTo: card.topAnchor, constant: Self.titleBarHeight),
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -4),
            scroll.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -6),
        ])
        window.contentView = card
        return window
    }
}

/// A note window's background: the window's own color washed in the note yellow.
private final class NoteCardView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NoteTint.color.withAlphaComponent(NoteTint.selection.value(in: effectiveAppearance)).setFill()
        bounds.fill()
    }
}

/// A note window takes the keyboard without making Seashell the active app,
/// like the panel. Its own edit shortcuts, since there's no Edit menu.
private final class NoteWindowPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Esc does nothing here (the panel uses it to close).
    override func cancelOperation(_ sender: Any?) {}

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return EditShortcuts.perform(event, from: self) || super.performKeyEquivalent(with: event)
    }
}
