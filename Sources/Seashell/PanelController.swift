import AppKit
import SeashellCore

/// The pull-down panel: slides out from under the menu bar on the display the
/// pointer is on. For now it holds a drop area for Main; Step 2 fills it with
/// shelf tabs and items.
@MainActor
final class PanelController {
    private(set) var isOpen = false
    /// The display it's open on.
    private var openDisplay: CGDirectDisplayID?
    /// Clicks for which this answers true don't count as "outside", e.g. on
    /// Seashell's own menu bar icon, which may live outside Seashell's process.
    var ignoresClick: ((NSPoint) -> Bool)?

    private let store: StashStore
    private let dropper: StashDropper
    private lazy var dropZone = DropZoneView(title: "Drop here to stash in Main", symbol: "tray.and.arrow.down") { [weak self] info in
        self?.stash(info) ?? false
    }
    private lazy var panel = makePanel()
    private var clickMonitor: Any?
    private let dragPasteboard = NSPasteboard(name: .drag)
    /// Drag pasteboard change count at a left press outside the panel, until its release.
    private var changeCountAtPressOutside: Int?

    init(store: StashStore, dropper: StashDropper) {
        self.store = store
        self.dropper = dropper
    }

    /// Open and actually on screen. Something else (Mission Control, say) can
    /// hide the panel while Seashell still thinks it's open.
    var isShowing: Bool {
        isOpen && panel.isVisible && panel.occlusionState.contains(.visible)
    }

    var stateDescription: String {
        "open: \(isOpen), visible: \(isOpen && panel.isVisible), on screen: \(isShowing)"
    }

    func toggle(reason: String) {
        isShowing ? close(reason: reason) : open(reason: reason)
    }

    /// Opens on `screen` (default: the one under the pointer). If already open
    /// on another screen, moves there.
    func open(on screen: NSScreen? = nil, reason: String) {
        guard let screen = screen ?? NSScreen.underPointer ?? NSScreen.main else { return }
        // Already open there: nothing to do (comparing frames would restart the
        // slide-in whenever they differ by a fraction of a point).
        if isShowing, screen.displayID == openDisplay { return }
        let frame = PanelGeometry.frame(in: screen.visibleFrame)

        dropZone.reset()
        if !isOpen {
            panel.setFrame(PanelGeometry.hiddenFrame(for: frame), display: false)
            panel.alphaValue = 0
        }
        // Becomes key without activating Seashell, so the app you're in stays in front.
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        }
        if !isOpen {
            isOpen = true
            watchForClicksOutside()
        }
        openDisplay = screen.displayID
        Log.info("Panel opened on \(screen.localizedName) (\(reason))")
    }

    func close(reason: String) {
        guard isOpen else { return }
        isOpen = false
        openDisplay = nil
        stopWatchingClicks()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panel.animator().setFrame(PanelGeometry.hiddenFrame(for: panel.frame), display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.finishClosing() }
        })
        Log.info("Panel closed (\(reason))")
    }

    private func finishClosing() {
        // Reopened while the close animation ran: leave it up.
        guard !isOpen else { return }
        panel.orderOut(nil)
    }

    private func stash(_ info: any NSDraggingInfo) -> Bool {
        guard let main = store.defaultShelf else {
            Log.error("No \(SeashellFolders.defaultShelfName) shelf to stash into")
            return false
        }
        return dropper.accept(info, into: main.url)
    }

    /// Global monitors only see clicks in other apps, which is exactly "outside".
    /// A left press closes the panel only once released without having dragged
    /// anything: pressing on a file to drag it into the panel must leave it open.
    private func watchForClicksOutside() {
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseDown]
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated { self?.handleOutside(event) }
        }
    }

    private func handleOutside(_ event: NSEvent) {
        if event.type != .leftMouseUp, ignoresClick?(NSEvent.mouseLocation) == true {
            changeCountAtPressOutside = nil
            Log.info("Click on the menu bar icon: panel left as it is")
            return
        }
        switch event.type {
        case .leftMouseDown:
            changeCountAtPressOutside = dragPasteboard.changeCount
        case .leftMouseUp:
            guard let pressed = changeCountAtPressOutside else { return }
            changeCountAtPressOutside = nil
            if dragPasteboard.changeCount == pressed {
                close(reason: "click outside")
            } else {
                Log.info("Panel kept open: a drag started outside it")
            }
        default:
            close(reason: "click outside")
        }
    }

    private func stopWatchingClicks() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        changeCountAtPressOutside = nil
    }

    private func makePanel() -> SeashellPanel {
        let panel = SeashellPanel(contentRect: NSRect(x: 0, y: 0, width: PanelGeometry.maxWidth, height: PanelGeometry.height),
                                  styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
        // Just below the menu bar's level, so it slides out from under it.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.onEscape = { [weak self] in self?.close(reason: "Esc") }

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 16
        background.layer?.masksToBounds = true

        dropZone.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(dropZone)
        NSLayoutConstraint.activate([
            dropZone.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 16),
            dropZone.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -16),
            dropZone.topAnchor.constraint(equalTo: background.topAnchor, constant: 16),
            dropZone.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -16),
        ])
        panel.contentView = background
        return panel
    }
}

/// A borderless panel that can take keys (Esc now; ⌘⌫ and Space in Step 2)
/// without making Seashell the active app.
final class SeashellPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {  // Esc
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}
