import AppKit
import SeashellCore

/// The Settings window, from "Settings…" in the menu bar menu or ⌘, in the panel.
/// The only place to choose the theme and text size besides ⌘+ / ⌘− / ⌘0.
@MainActor
final class SettingsWindow: NSObject {
    private lazy var window = makeWindow()
    private let themePopup = NSPopUpButton()
    private let textSizePopup = NSPopUpButton()
    private let loginCheckbox = NSButton(checkboxWithTitle: "Open Seashell when you log in", target: nil, action: nil)
    private let loginNote = SettingsWindow.note("Allow Seashell in System Settings → General → Login Items.")
    private var loginNoteRow: NSGridRow?
    private let largeFilePopup = NSPopUpButton()
    private let shakePopup = NSPopUpButton()
    private let pullDownCheckbox = NSButton(checkboxWithTitle: "Pull down at the top edge to open the panel", target: nil, action: nil)

    func show() {
        let isNew = !window.isVisible
        refreshLoginItem()
        NSApp.activate()
        if isNew { window.center() }
        window.makeKeyAndOrderFront(nil)
        Log.info("Settings opened")
    }

    // MARK: Changes

    @objc private func themeChosen(_ sender: NSPopUpButton) {
        guard let theme = Self.chosen(Theme.self, in: sender) else { return }
        AppSettings.shared.theme = theme
    }

    @objc private func textSizeChosen(_ sender: NSPopUpButton) {
        guard let size = Self.chosen(TextSize.self, in: sender) else { return }
        TextSizeSetting.shared.size = size
    }

    @objc private func largeFileLimitChosen(_ sender: NSPopUpButton) {
        guard let limit = Self.chosen(LargeFileLimit.self, in: sender) else { return }
        AppSettings.shared.largeFileLimit = limit
    }

    @objc private func shakeChosen(_ sender: NSPopUpButton) {
        guard let sensitivity = Self.chosen(ShakeSensitivity.self, in: sender) else { return }
        AppSettings.shared.shakeSensitivity = sensitivity
    }

    @objc private func pullDownToggled(_ sender: NSButton) {
        AppSettings.shared.opensOnPullDown = sender.state == .on
    }

    @objc private func loginToggled(_ sender: NSButton) {
        do {
            try LoginItem.set(sender.state == .on)
        } catch {
            Alerts.showError(sender.state == .on ? "Couldn’t make Seashell open at login" : "Couldn’t stop Seashell opening at login", error)
        }
        refreshLoginItem()
        // macOS may want you to allow it first.
        if LoginItem.needsApproval { LoginItem.openSystemSettings() }
    }

    // MARK: Showing the current settings

    /// Runs again whenever a setting changes, from here, the menu or ⌘+ / ⌘−.
    private func refresh() {
        let settings = AppSettings.shared
        Self.select(settings.theme, in: themePopup)
        Self.select(TextSizeSetting.shared.size, in: textSizePopup)
        Self.select(settings.largeFileLimit, in: largeFilePopup)
        Self.select(settings.shakeSensitivity, in: shakePopup)
        pullDownCheckbox.state = settings.opensOnPullDown ? .on : .off
    }

    /// Not observable: macOS owns it, and you can change it in System Settings.
    private func refreshLoginItem() {
        loginCheckbox.state = LoginItem.isOn || LoginItem.needsApproval ? .on : .off
        let hideNote = !LoginItem.needsApproval
        guard let loginNoteRow, loginNoteRow.isHidden != hideNote, let content = window.contentView else { return }
        loginNoteRow.isHidden = hideNote
        window.setContentSize(content.fittingSize)
    }

    // MARK: Building

    private func makeWindow() -> NSWindow {
        let window = SettingsPanelWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Seashell Settings"
        window.isReleasedWhenClosed = false
        // Above the pull-down panel, which sits just below the menu bar. Hidden
        // when you switch to another app, so it doesn't float over that app.
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
        window.hidesOnDeactivate = true

        Self.fill(themePopup, with: Theme.allCases, name: \.name, target: self, action: #selector(themeChosen))
        Self.fill(textSizePopup, with: TextSize.allCases, name: \.name, target: self, action: #selector(textSizeChosen))
        Self.fill(largeFilePopup, with: LargeFileLimit.allCases, name: \.name, target: self, action: #selector(largeFileLimitChosen))
        Self.fill(shakePopup, with: ShakeSensitivity.allCases, name: \.name, target: self, action: #selector(shakeChosen))
        for (checkbox, action) in [(loginCheckbox, #selector(loginToggled)), (pullDownCheckbox, #selector(pullDownToggled))] {
            checkbox.target = self
            checkbox.action = action
        }

        let empty = NSGridCell.emptyContentView
        let grid = NSGridView(views: [
            [Self.label("Theme:"), themePopup],
            [Self.label("Text size:"), textSizePopup],
            [empty, Self.note("In the panel: ⌘+ bigger, ⌘− smaller, ⌘0 Medium.")],
            [Self.label("Startup:"), loginCheckbox],
            [empty, loginNote],
            [Self.label("Ask before stashing:"), largeFilePopup],
            [empty, Self.note("Everything in Stash uploads to iCloud and counts against your storage.")],
            [Self.label("Shake to show the shelf:"), shakePopup],
            [empty, Self.note("Shake the pointer while dragging something.")],
            [Self.label("Top edge:"), pullDownCheckbox],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.rowAlignment = .firstBaseline
        grid.column(at: 0).xPlacement = .trailing
        // A little more room above each group.
        for row in [3, 5, 7, 9] { grid.row(at: row).topPadding = 8 }
        loginNoteRow = grid.row(at: 4)
        loginNoteRow?.isHidden = true
        grid.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
        ])
        window.contentView = content
        window.setContentSize(content.fittingSize)
        observeChanges { [weak self] in self?.refresh() }
        return window
    }

    private static func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
    }

    private static func note(_ text: String) -> NSTextField {
        let note = NSTextField(wrappingLabelWithString: text)
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 280
        return note
    }

    private static func fill<Choice: RawRepresentable>(_ popup: NSPopUpButton, with choices: [Choice], name: (Choice) -> String,
                                                        target: AnyObject, action: Selector) where Choice.RawValue == String {
        popup.removeAllItems()
        for choice in choices {
            popup.addItem(withTitle: name(choice))
            popup.lastItem?.representedObject = choice.rawValue
        }
        popup.target = target
        popup.action = action
    }

    private static func select<Choice: RawRepresentable>(_ choice: Choice, in popup: NSPopUpButton) where Choice.RawValue == String {
        popup.selectItem(at: popup.indexOfItem(withRepresentedObject: choice.rawValue))
    }

    private static func chosen<Choice: RawRepresentable>(_ type: Choice.Type, in popup: NSPopUpButton) -> Choice? where Choice.RawValue == String {
        guard let raw = popup.selectedItem?.representedObject as? String else { return nil }
        return Choice(rawValue: raw)
    }
}

/// A menu bar app has no menu with ⌘W, so the window handles it, and Esc too.
final class SettingsPanelWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(nil)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
