import AppKit
import SeashellCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var isSecondCopy = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if anotherCopyIsRunning() {
            isSecondCopy = true
            NSApp.terminate(nil)
            return
        }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        Log.info("Seashell \(version) launched from \(Bundle.main.bundlePath)")
        prepareFolders()
        setUpMenuBar()
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !isSecondCopy else { return }
        Log.info("Seashell quit")
    }

    /// Two copies would both react to every shake and edge scroll, so a second launch bows out.
    private func anotherCopyIsRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != NSRunningApplication.current }
        guard let running = others.first else { return false }
        Log.info("Seashell is already running (pid \(running.processIdentifier)); this copy quits")
        return true
    }

    private func prepareFolders() {
        do {
            for folder in try SeashellFolders.standard.createMissing() {
                Log.info("Created \(folder.path(percentEncoded: false))")
            }
        } catch {
            Log.error("Could not create Seashell folders: \(error.localizedDescription)")
        }
    }

    private func setUpMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "tray.full", accessibilityDescription: "Seashell")

        let menu = NSMenu()
        // No action yet, so the menu shows it disabled. The panel arrives in Milestone 3.
        menu.addItem(NSMenuItem(title: "Open Seashell", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Seashell", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }
}
