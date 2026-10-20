import AppKit
import SeashellCore

/// About Seashell: the icon, big (the standard About window keeps it at 64
/// points), the version, where Seashell lives, and Check for Updates….
/// Typing 1 1 1 and Return here shows the easter egg.
@MainActor
final class AboutWindow: NSObject {
    private static let page = URL(string: "https://github.com/codexjdub/Seashell")!
    private static let iconSize: CGFloat = 128
    private lazy var window = makeWindow()
    private let egg = EasterEgg()
    private var code = SecretCode("111\r")
    private var keyWatcher: Any?

    func show() {
        Log.info("About Seashell shown")
        if !window.isVisible { window.center() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        watchForCode()
    }

    /// Keys typed while About is in front, for the easter egg. Only Seashell's
    /// own key presses reach it, and only About's are looked at.
    private func watchForCode() {
        guard keyWatcher == nil else { return }
        keyWatcher = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let taken = MainActor.assumeIsolated { self?.takes(event) ?? false }
            return taken ? nil : event
        }
    }

    /// 1 1 1 then Return shows the easter egg. True for the keys About takes
    /// quietly, the 1s and Return: nothing in About uses them, so they'd only beep.
    private func takes(_ event: NSEvent) -> Bool {
        guard event.window === window, event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let typed = event.characters, typed.count == 1, var key = typed.first else { return false }
        if key == "\u{3}" { key = "\r" }  // Enter on a number pad
        if code.type(key) {
            egg.show(over: window.frame)
            return true
        }
        return code.isPart(key)
    }

    @objc private func checkForUpdates() {
        UpdateChecker.check()
    }

    @objc private func openPage() {
        NSWorkspace.shared.open(Self.page)
    }

    private func makeWindow() -> NSWindow {
        let window = SettingsPanelWindow(title: "")
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: Self.iconSize),
                                     icon.heightAnchor.constraint(equalToConstant: Self.iconSize)])

        let name = NSTextField(labelWithString: "Seashell")
        name.font = .systemFont(ofSize: 22, weight: .semibold)
        let versionLabel = NSTextField(labelWithString: build.map { "Version \(version) (\($0))" } ?? "Version \(version)")
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.isSelectable = true  // for copying into a bug report
        let blurb = NSTextField(wrappingLabelWithString: "A shelf for your Mac that slides down from under the menu bar.")
        blurb.alignment = .center
        blurb.preferredMaxLayoutWidth = 260
        let link = NSButton(title: "github.com/codexjdub/Seashell", target: self, action: #selector(openPage))
        link.isBordered = false
        link.contentTintColor = .linkColor
        let updates = NSButton(title: "Check for Updates…", target: self, action: #selector(checkForUpdates))
        let copyright = NSTextField(labelWithString: [info?["NSHumanReadableCopyright"] as? String, "MIT License"]
            .compactMap { $0 }.joined(separator: " · "))
        copyright.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        copyright.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [icon, name, versionLabel, blurb, link, updates, copyright])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.setCustomSpacing(12, after: icon)
        stack.setCustomSpacing(10, after: versionLabel)
        stack.setCustomSpacing(14, after: link)
        stack.setCustomSpacing(16, after: updates)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32),
        ])
        window.contentView = content
        window.setContentSize(content.fittingSize)
        return window
    }
}
