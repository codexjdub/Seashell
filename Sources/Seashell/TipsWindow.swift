import AppKit
import SeashellCore

/// A short welcome: Seashell's gestures are invisible until someone tells you
/// about them. Shown on first launch, and from "Tips…" in the menu bar menu.
@MainActor
final class TipsWindow: NSObject {
    private static let shownKey = "tipsShown"

    var onOpenPanel: (() -> Void)?
    private var window: NSWindow?

    /// The first time Seashell runs.
    func showIfFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: Self.shownKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.shownKey)
        show()
    }

    func show() {
        // Rebuilt each time, so the keyboard shortcut shown is the current one.
        window?.orderOut(nil)
        let window = makeWindow()
        self.window = window
        NSApp.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
        Log.info("Tips shown")
    }

    @objc private func gotIt() {
        window?.performClose(nil)
    }

    @objc private func openPanel() {
        window?.performClose(nil)
        onOpenPanel?()
    }

    private static func tips() -> [(symbol: String, title: String, detail: String)] {
        let shortcut = AppSettings.shared.panelShortcut
        return [
            ("arrow.down.to.line", "Pull down at the top edge",
             "With the pointer at the very top of the screen, scroll down (two fingers, or the wheel) to open the panel. Push up to close it."),
            ("hand.draw", "Shake while dragging",
             "Shake a file, text or link as you drag it, and your shelves pop up to drop it on."),
            ("option", "⌥-shake to grab",
             "Hold ⌥ and shake the pointer to see your most recent items, then drag one out."),
            ("keyboard", shortcut == .off ? "Keyboard shortcut" : shortcut.name,
             shortcut == .off ? "Set one in Settings to open the panel from any app."
                              : "Opens and closes the panel from any app. Change it in Settings."),
            ("rectangle.portrait.on.rectangle.portrait", "Tear off a shelf",
             "Drag a shelf’s tab out of the panel to keep it in its own window."),
            ("menubar.arrow.up.rectangle", "Drop on the menu bar icon",
             "Anything dropped on Seashell’s icon goes into Main."),
        ]
    }

    private func makeWindow() -> NSWindow {
        let window = SettingsPanelWindow(title: "Welcome to Seashell")

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 72), icon.heightAnchor.constraint(equalToConstant: 72)])
        let title = NSTextField(labelWithString: "Welcome to Seashell")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let subtitle = NSTextField(wrappingLabelWithString:
            "A shelf for files, text, links and notes, kept in Documents so iCloud syncs it. Here’s how to reach it:")
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        subtitle.preferredMaxLayoutWidth = 420

        let rows = Self.tips().map { tip -> NSView in
            let symbol = NSImageView(image: NSImage(systemSymbolName: tip.symbol, accessibilityDescription: nil) ?? NSImage())
            symbol.symbolConfiguration = .init(pointSize: 20, weight: .regular)
            symbol.contentTintColor = .controlAccentColor
            symbol.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([symbol.widthAnchor.constraint(equalToConstant: 30)])
            let heading = NSTextField(labelWithString: tip.title)
            heading.font = .systemFont(ofSize: 13, weight: .semibold)
            let detail = NSTextField(wrappingLabelWithString: tip.detail)
            detail.textColor = .secondaryLabelColor
            detail.preferredMaxLayoutWidth = 370
            let text = NSStackView(views: [heading, detail])
            text.orientation = .vertical
            text.alignment = .leading
            text.spacing = 2
            let row = NSStackView(views: [symbol, text])
            row.orientation = .horizontal
            row.alignment = .top
            row.spacing = 10
            return row
        }
        let list = NSStackView(views: rows)
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 14

        let open = NSButton(title: "Open Seashell", target: self, action: #selector(openPanel))
        let done = NSButton(title: "Got It", target: self, action: #selector(gotIt))
        done.keyEquivalent = "\r"
        let buttons = NSStackView(views: [open, done])
        buttons.spacing = 10

        let stack = NSStackView(views: [icon, title, subtitle, list, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.setCustomSpacing(18, after: subtitle)
        stack.setCustomSpacing(22, after: list)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
        ])
        window.contentView = content
        window.setContentSize(content.fittingSize)
        return window
    }
}
