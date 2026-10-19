import AppKit
import SeashellCore

/// The note editor, in the panel and in a note's own window. Plain text, kept
/// exactly as typed, with help for lists and to-dos:
///
/// - Click a to-do's `- [ ]` to tick it; done ones show grey and struck through.
/// - Return continues a list (bullets, numbers, to-dos); on an empty item it
///   moves out a level or ends the list.
/// - Tab and ⇧Tab move list lines in and out; ⇧⌘L makes or unmakes to-dos.
///
/// Esc goes to the window (the panel saves and closes) instead of the text
/// view's usual "suggest completions".
final class NoteTextView: NSTextView {
    static func make() -> NoteTextView {
        let editor = NoteTextView()
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
        return editor
    }

    override func cancelOperation(_ sender: Any?) {
        window?.cancelOperation(sender)
    }

    /// Done to-dos in grey with a line through their words. Only how they look:
    /// the file stays plain text. Called after loading and after each change.
    func styleChecklists() {
        guard let storage = textStorage else { return }
        let all = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.removeAttribute(.strikethroughStyle, range: all)
        storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: all)
        for item in Checklist.items(in: storage.string) where item.isDone {
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: item.line)
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: item.words)
        }
        storage.endEditing()
    }

    // MARK: To-dos and lists

    /// A click on a to-do's `- [ ]` ticks or unticks it.
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 1, event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty,
           let item = checklistItem(at: event) {
            window?.makeFirstResponder(self)
            apply(Checklist.toggle(item))
            return
        }
        super.mouseDown(with: event)
    }

    /// The to-do whose marker is under the pointer. Checked against where the
    /// marker is drawn, since a click past the end of a line lands on it too.
    private func checklistItem(at event: NSEvent) -> Checklist.Item? {
        guard let window else { return nil }
        let index = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        guard let item = Checklist.item(at: index, in: string) else { return nil }
        let marker = firstRect(forCharacterRange: item.marker, actualRange: nil).insetBy(dx: -2, dy: 0)
        return marker.contains(window.convertPoint(toScreen: event.locationInWindow)) ? item : nil
    }

    /// Return on a list item or to-do starts the next one.
    override func insertNewline(_ sender: Any?) {
        if !hasMarkedText(), let edit = MarkdownList.newline(in: string, selection: selectedRange()) {
            apply(edit)
        } else {
            super.insertNewline(sender)
        }
    }

    /// Tab moves a list line, or several selected lines, in a level; otherwise it types a tab.
    override func insertTab(_ sender: Any?) {
        if !hasMarkedText(), let edit = MarkdownList.indent(in: string, selection: selectedRange()) {
            apply(edit)
        } else {
            super.insertTab(sender)
        }
    }

    /// ⇧Tab moves the line, or the selected lines, out a level.
    override func insertBacktab(_ sender: Any?) {
        if !hasMarkedText(), let edit = MarkdownList.outdent(in: string, selection: selectedRange()) {
            apply(edit)
        } else {
            super.insertBacktab(sender)
        }
    }

    /// ⇧⌘L: the line, or the selected lines, become to-dos, or plain lines again.
    @objc func toggleChecklist(_ sender: Any?) {
        apply(Checklist.toggleLines(in: string, selection: selectedRange()))
    }

    /// Makes the change as typing would: ⌘Z takes it back, and it's saved.
    private func apply(_ edit: NoteEdit) {
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        if let selection = edit.selection { setSelectedRange(selection) }
    }
}

/// Edit shortcuts for Seashell's own windows. A menu bar app has no Edit menu,
/// which is where text views normally get ⌘X ⌘C ⌘V ⌘A ⌘Z ⇧⌘Z from, so they're
/// sent by hand to whatever has focus; plus ⇧⌘L for to-dos and ⌘+ / ⌘− / ⌘0
/// for the text size.
@MainActor
enum EditShortcuts {
    /// True if `event` was one of them and something took it.
    static func perform(_ event: NSEvent, from sender: Any) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased()
        // Text size: ⌘+ (also ⌘= and ⇧⌘=), ⌘−, ⌘0.
        let setting = TextSizeSetting.shared
        switch (modifiers, key) {
        case (.command, "="), (.command, "+"), ([.command, .shift], "+"), ([.command, .shift], "="):
            setting.size = setting.size.larger
            return true
        case (.command, "-"):
            setting.size = setting.size.smaller
            return true
        case (.command, "0"):
            setting.size = .standard
            return true
        default:
            break
        }
        let action: Selector? = switch (modifiers, key) {
        case (.command, "x"): #selector(NSText.cut(_:))
        case (.command, "c"): #selector(NSText.copy(_:))
        case (.command, "v"): #selector(NSText.paste(_:))
        case (.command, "a"): #selector(NSText.selectAll(_:))
        case (.command, "z"): Selector(("undo:"))
        case ([.command, .shift], "z"): Selector(("redo:"))
        case ([.command, .shift], "l"): #selector(NoteTextView.toggleChecklist(_:))
        default: nil
        }
        guard let action else { return false }
        return NSApp.sendAction(action, to: nil, from: sender)
    }
}
