import AppKit
import SeashellCore
import UniformTypeIdentifiers

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
    private let ignoredApps = IgnoredAppsView()
    private let shortcutPopup = NSPopUpButton()

    /// The pull-down panel's frame while it's open, so Settings opens below it.
    var panelFrame: (() -> NSRect?)?

    func show() {
        let isNew = !window.isVisible
        refreshLoginItem()
        if isNew { place() }
        NSApp.activate()
        // A non-activating panel: it takes the keyboard even if macOS doesn't
        // bring Seashell forward (as when opened from the pull-down panel).
        window.makeKeyAndOrderFront(nil)
        Log.info("Settings opened")
    }

    /// Below the pull-down panel if it's open, so neither covers the other;
    /// otherwise in the middle of the screen.
    private func place() {
        guard let panel = panelFrame?(), let screen = NSScreen.screens.first(where: { $0.frame.intersects(panel) }) else {
            window.center()
            return
        }
        let size = window.frame.size
        let visible = screen.visibleFrame
        let x = min(max(panel.midX - size.width / 2, visible.minX + 16), visible.maxX - size.width - 16)
        let y = max(panel.minY - 16 - size.height, visible.minY + 16)
        window.setFrameOrigin(NSPoint(x: x, y: y))
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

    @objc private func shortcutChosen(_ sender: NSPopUpButton) {
        guard let shortcut = Self.chosen(PanelShortcut.self, in: sender) else { return }
        AppSettings.shared.panelShortcut = shortcut
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
        Self.select(settings.panelShortcut, in: shortcutPopup)
        pullDownCheckbox.state = settings.opensOnPullDown ? .on : .off
        ignoredApps.show(settings.shakeIgnoredApps)
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
        let window = SettingsPanelWindow(title: "Seashell Settings")

        Self.fill(themePopup, with: Theme.allCases, name: \.name, target: self, action: #selector(themeChosen))
        Self.fill(textSizePopup, with: TextSize.allCases, name: \.name, target: self, action: #selector(textSizeChosen))
        Self.fill(largeFilePopup, with: LargeFileLimit.allCases, name: \.name, target: self, action: #selector(largeFileLimitChosen))
        Self.fill(shakePopup, with: ShakeSensitivity.allCases, name: \.name, target: self, action: #selector(shakeChosen))
        Self.fill(shortcutPopup, with: PanelShortcut.allCases, name: \.name, target: self, action: #selector(shortcutChosen))
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
            [empty, Self.note("Shake while dragging something to drop it; ⌥-shake to grab from Stash.")],
            [Self.label("Ignore shakes in:"), ignoredApps],
            [Self.label("Top edge:"), pullDownCheckbox],
            [Self.label("Keyboard shortcut:"), shortcutPopup],
            [empty, Self.note("Opens and closes the panel from any app.")],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.rowAlignment = .firstBaseline
        grid.column(at: 0).xPlacement = .trailing
        // A little more room above each group.
        for row in [3, 5, 7, 10, 11] { grid.row(at: row).topPadding = 8 }
        // The list has no baseline: line its label up with the top of the list.
        grid.row(at: 9).rowAlignment = .none
        grid.row(at: 9).yPlacement = .top
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
/// Settings and Tips: an ordinary titled window that, like the pull-down panel,
/// takes the keyboard without making Seashell the active app. Other apps'
/// windows go over it as usual.
final class SettingsPanelWindow: NSPanel {
    init(title: String) {
        super.init(contentRect: .zero, styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        self.title = title
        isReleasedWhenClosed = false
        level = .normal
        isFloatingPanel = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }

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

/// The apps in which shakes are ignored: a short list with + and − below it.
@MainActor
final class IgnoredAppsView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private let buttons = NSSegmentedControl(images: [NSImage(systemSymbolName: "plus", accessibilityDescription: "Add an app")!,
                                                      NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove the app")!],
                                             trackingMode: .momentary, target: nil, action: nil)
    private let placeholder = NSTextField(wrappingLabelWithString: "None yet. The menu bar menu can add the app you’re in.")
    private var ids: [String] = []

    init() {
        super.init(frame: .zero)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 24
        table.style = .plain
        table.dataSource = self
        table.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        buttons.target = self
        buttons.action = #selector(buttonClicked)
        buttons.setEnabled(false, forSegment: 1)
        placeholder.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        placeholder.textColor = .tertiaryLabelColor
        placeholder.alignment = .center
        for view in [scroll, buttons, placeholder] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 280),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 80),
            buttons.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 4),
            buttons.leadingAnchor.constraint(equalTo: leadingAnchor),
            buttons.bottomAnchor.constraint(equalTo: bottomAnchor),
            placeholder.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            placeholder.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 16),
            placeholder.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -16),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ ids: [String]) {
        guard ids != self.ids else { return }
        self.ids = ids
        table.reloadData()
        placeholder.isHidden = !ids.isEmpty
        buttons.setEnabled(table.selectedRow >= 0, forSegment: 1)
    }

    @objc private func buttonClicked() {
        if buttons.selectedSegment == 0 {
            chooseApps()
        } else if ids.indices.contains(table.selectedRow) {
            AppSettings.shared.setShakesIgnored(false, in: ids[table.selectedRow])
        }
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Ignore Shakes"
        panel.message = "Choose apps where shaking the pointer shouldn’t open Seashell’s shelves."
        let add: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            for id in panel.urls.compactMap({ Bundle(url: $0)?.bundleIdentifier }) {
                AppSettings.shared.setShakesIgnored(true, in: id)
            }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: add) } else { add(panel.runModal()) }
    }

    // MARK: List

    func numberOfRows(in tableView: NSTableView) -> Int { ids.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let (name, icon) = Self.appInfo(ids[row])
        let cell = NSTableCellView()
        let image = NSImageView(image: icon ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)!)
        let label = NSTextField(labelWithString: name)
        label.lineBreakMode = .byTruncatingTail
        for view in [image, label] {
            view.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(view)
        }
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 18),
            image.heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        cell.toolTip = ids[row]
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        buttons.setEnabled(table.selectedRow >= 0, forSegment: 1)
    }

    /// Its name and icon, or just the bundle ID if it isn't on this Mac.
    private static func appInfo(_ id: String) -> (String, NSImage?) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return (id, nil) }
        let path = url.path(percentEncoded: false)
        var name = FileManager.default.displayName(atPath: path)
        if name.hasSuffix(".app") { name.removeLast(4) }
        return (name, NSWorkspace.shared.icon(forFile: path))
    }
}
