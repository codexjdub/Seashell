import AppKit
import SeashellCore

/// Alerts that appear above Seashell's panels. The pull-down panel sits just
/// below the menu bar's level, so an ordinary alert would open behind it.
@MainActor
enum Alerts {
    static func run(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate()
        alert.layout()
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        return alert.runModal()
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

    static func showError(_ message: String, _ error: any Error) {
        Log.error("\(message): \(error.localizedDescription)")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = error.localizedDescription
        _ = run(alert)
    }
}
