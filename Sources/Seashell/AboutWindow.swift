import AppKit
import SeashellCore

/// About Seashell: the icon, big (the standard About window keeps it at 64
/// points), the version, where Seashell lives, and Check for Updates….
@MainActor
final class AboutWindow: NSObject {
    private static let page = URL(string: "https://github.com/codexjdub/Seashell")!
    private static let iconSize: CGFloat = 128
    private lazy var window = makeWindow()

    func show() {
        Log.info("About Seashell shown")
        if !window.isVisible { window.center() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
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
