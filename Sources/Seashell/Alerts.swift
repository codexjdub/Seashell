import AppKit
import SeashellCore

/// Alerts that appear above Seashell's panels. The pull-down panel sits just
/// below the menu bar's level, so an ordinary alert would open behind it.
@MainActor
enum Alerts {
    static func run(_ alert: NSAlert) -> NSApplication.ModalResponse {
        let window = alert.window
        open.append(window)
        defer { open.removeAll { $0 === window } }
        NSApp.activate()
        raiseOnceShown(window)
        return alert.runModal()
    }

    /// Above the panel and the shelves.
    private static let level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)

    /// Alerts showing now; one can open from another.
    private static var open: [NSWindow] = []

    /// Clicking a panel doesn't make Seashell the active app, so an alert
    /// opened from one makes it active. That can finish after the alert was
    /// raised, putting it back at the modal panel level, so it's raised again
    /// (seen on macOS 27: the New shelf dialog at 8 when its click activated
    /// Seashell, at 25 when Seashell was already active).
    static func appBecameActive() {
        open.forEach(raiseOnceShown)
    }

    /// `runModal` puts its window at the modal panel level (8), below the panel
    /// (23), whatever level it had before; so it's raised once the modal session
    /// runs. Checked on macOS 27: set before, it stays at 8; raised then, 25.
    private static func raiseOnceShown(_ window: NSWindow) {
        RunLoop.main.perform(inModes: [.modalPanel]) {
            MainActor.assumeIsolated { window.level = level }
        }
    }

    /// Asks for a confirmation; true if the first button was chosen.
    static func confirm(_ message: String, detail: String, confirm: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "Cancel")
        return run(alert) == .alertFirstButtonReturn
    }

    /// Asks for a name; nil if cancelled.
    static func askForName(_ message: String, initial: String = "", confirm: String) -> String? {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: initial)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        return run(alert) == .alertFirstButtonReturn ? field.stringValue : nil
    }

    /// Just tells you something.
    static func tell(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        _ = run(alert)
    }

    static func showError(_ message: String, _ error: any Error) {
        Log.error("\(message): \(error.localizedDescription)")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = error.localizedDescription
        _ = run(alert)
    }
}
