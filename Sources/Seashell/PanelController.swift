import AppKit
import SeashellCore

/// The pull-down panel: slides out from under the menu bar on the display the
/// pointer is on, and shows Stash (shelf tabs and items).
@MainActor
final class PanelController: NSObject {
    private static let pinnedKey = "panelPinned"

    private(set) var isOpen = false
    /// Pinned: clicking elsewhere doesn't close it (Esc, pushing up and the menu
    /// still do). Remembered until unpinned, across closes and launches.
    private var isPinned = UserDefaults.standard.bool(forKey: PanelController.pinnedKey) {
        didSet {
            UserDefaults.standard.set(isPinned, forKey: Self.pinnedKey)
            updatePinButton()
        }
    }
    /// The display it's open on.
    private var openDisplay: CGDirectDisplayID?
    /// Clicks for which this answers true don't count as "outside", e.g. on
    /// Seashell's own menu bar icon, which may live outside Seashell's process.
    var ignoresClick: ((NSPoint) -> Bool)?

    private let stash: StashPanelController
    private lazy var panel = makePanel()
    private lazy var closeButton: NSButton = {
        let button = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")!,
                              target: self, action: #selector(closeButtonClicked))
        button.bezelStyle = .accessoryBarAction
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = "Close (also when pinned)"
        return button
    }()
    private lazy var pinButton: NSButton = {
        let button = NSButton(image: NSImage(), target: self, action: #selector(togglePin))
        button.bezelStyle = .accessoryBarAction
        button.setButtonType(.momentaryPushIn)
        return button
    }()
    private var clickMonitor: Any?
    private let dragPasteboard = NSPasteboard(name: .drag)
    /// Drag pasteboard change count at a left press outside the panel, until its release.
    private var changeCountAtPressOutside: Int?

    init(store: StashStore, mover: FileMover, dropper: StashDropper) {
        stash = StashPanelController(store: store, mover: mover, dropper: dropper)
        super.init()
        stash.onDraggedOut = { [weak self] point in self?.droppedElsewhere(at: point) }
    }

    /// Open and actually on screen. Something else (Mission Control, say) can
    /// hide the panel while Seashell still thinks it's open.
    var isShowing: Bool {
        isOpen && panel.isVisible && panel.occlusionState.contains(.visible)
    }

    var stateDescription: String {
        "open: \(isOpen), visible: \(isOpen && panel.isVisible), on screen: \(isShowing), pinned: \(isPinned)"
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

        if !isOpen {
            panel.setFrame(PanelGeometry.hiddenFrame(for: frame), display: false)
            panel.alphaValue = 0
        }
        // Becomes key without activating Seashell, so the app you're in stays in front.
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(stash.grid)
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
        stash.willHide()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panel.animator().setFrame(PanelGeometry.hiddenFrame(for: panel.frame), display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.finishClosing() }
        })
        Log.info("Panel closed (\(reason))")
    }

    /// After an item is dropped into another app, typing should go there, not to
    /// the panel (which holds keyboard focus). Close the panel, or if it's pinned
    /// just let go of focus, and bring the app that took the drop to the front.
    private func droppedElsewhere(at point: NSPoint) {
        guard isOpen, !panel.frame.contains(point) else { return }  // onto the panel's own tabs
        let target = Self.app(at: point)
        let name = target?.localizedName ?? "another app"
        if isPinned {
            // Ordering out and straight back in keeps it on screen without focus.
            panel.orderOut(nil)
            panel.orderFront(nil)
        } else {
            close(reason: "dropped into \(name)")
        }
        guard let target, target != NSRunningApplication.current else { return }
        let brought = target.activate()
        Log.info(brought ? "Brought \(name) to the front after the drop" : "macOS didn’t let Seashell bring \(name) to the front")
    }

    /// The app owning the frontmost ordinary window at `point`. Window owner and
    /// bounds don't need Screen Recording permission.
    private static func app(at point: NSPoint) -> NSRunningApplication? {
        // Window list coordinates start at the top left of the main display.
        guard let mainHeight = NSScreen.screens.first?.frame.maxY,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        let flipped = CGPoint(x: point.x, y: mainHeight - point.y)
        for info in windows {  // front to back
            guard info[kCGWindowLayer as String] as? Int == 0,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo), bounds.contains(flipped),
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t
            else { continue }
            return NSRunningApplication(processIdentifier: pid)
        }
        return nil
    }

    private func finishClosing() {
        // Reopened while the close animation ran: leave it up.
        guard !isOpen else { return }
        panel.orderOut(nil)
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
        if isPinned {
            changeCountAtPressOutside = nil
            return
        }
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

    @objc private func closeButtonClicked() {
        close(reason: "close button")
    }

    @objc private func togglePin() {
        isPinned.toggle()
        Log.info(isPinned ? "Panel pinned: clicking elsewhere won’t close it" : "Panel unpinned")
    }

    private func updatePinButton() {
        pinButton.image = NSImage(systemSymbolName: isPinned ? "pin.fill" : "pin",
                                  accessibilityDescription: isPinned ? "Unpin" : "Pin")
        pinButton.contentTintColor = isPinned ? .controlAccentColor : .secondaryLabelColor
        pinButton.toolTip = isPinned ? "Unpin: close when clicking elsewhere"
                                     : "Pin: stay open when clicking elsewhere (Esc or pushing up still close it)"
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
        // Esc closes an open preview first, then the panel.
        panel.onEscape = { [weak self] in
            guard let self, !self.stash.closePreview() else { return }
            self.close(reason: "Esc")
        }

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 16
        background.layer?.masksToBounds = true

        let content = stash.view
        content.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            content.topAnchor.constraint(equalTo: background.topAnchor),
            content.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        updatePinButton()
        for button in [pinButton, closeButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(button)
        }
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: background.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -14),
            pinButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            pinButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -6),
        ])
        panel.contentView = background
        return panel
    }
}

/// A borderless panel that can take keys (Esc, Space, ⌘⌫, ⌘A)
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
