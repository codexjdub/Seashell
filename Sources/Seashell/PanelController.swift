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
    private let notes: NotesPanelController
    private lazy var panel = makePanel()
    private let stashCard = PanelCard()
    /// The yellow of the note cards in Stash, so notes look alike in both.
    private let notesCard = PanelCard(isNotes: true)
    private var splitConstraint: NSLayoutConstraint?
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

    init(store: StashStore, notesStore: NotesStore, mover: FileMover, dropper: StashDropper) {
        stash = StashPanelController(store: store, mover: mover, dropper: dropper)
        notes = NotesPanelController(store: notesStore)
        super.init()
        stash.onDraggedOut = { [weak self] point in self?.droppedElsewhere(at: point) }
        notes.onDraggedOut = { [weak self] point in self?.droppedElsewhere(at: point) }
        observeChanges { [weak self] in self?.textSizeChanged() }
    }

    /// An open panel grows or shrinks with the text size, on the display it's on.
    private func textSizeChanged() {
        let scale = UIScale.factor
        guard isOpen, let screen = panel.screen else { return }
        stash.closePreview()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().setFrame(PanelGeometry.frame(in: screen.visibleFrame, scale: scale,
                                                          size: PanelLayoutMemory.size(on: screen)), display: true)
        }
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
        let frame = PanelGeometry.frame(in: screen.visibleFrame, scale: UIScale.factor, size: PanelLayoutMemory.size(on: screen))

        if !isOpen {
            panel.setFrame(PanelGeometry.hiddenFrame(for: frame), display: false)
            panel.alphaValue = 0
        }
        // Becomes key without activating Seashell, so the app you're in stays in front.
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(stash.grid)
        notes.willShow()
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
        notes.willHide()
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

    // MARK: Resizing

    /// Invisible strips: the bottom edge sets the height, the side edges the
    /// width (staying centered), and the gap between the cards the split.
    private func addDragHandles(to background: NSView) {
        let bottom = DragHandle(.vertical)
        let left = DragHandle(.horizontal)
        let right = DragHandle(.horizontal)
        let split = DragHandle(.horizontal)
        for handle in [bottom, left, right, split] { background.addSubview(handle) }
        NSLayoutConstraint.activate([
            bottom.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 16),
            bottom.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -16),
            bottom.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            bottom.heightAnchor.constraint(equalToConstant: 7),
            left.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            left.widthAnchor.constraint(equalToConstant: 7),
            left.topAnchor.constraint(equalTo: background.topAnchor, constant: 16),
            left.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -16),
            right.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            right.widthAnchor.constraint(equalToConstant: 7),
            right.topAnchor.constraint(equalTo: background.topAnchor, constant: 16),
            right.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -16),
            split.leadingAnchor.constraint(equalTo: stashCard.trailingAnchor),
            split.trailingAnchor.constraint(equalTo: notesCard.leadingAnchor),
            split.topAnchor.constraint(equalTo: stashCard.topAnchor),
            split.bottomAnchor.constraint(equalTo: stashCard.bottomAnchor),
        ])
        bottom.onDrag = { [weak self] _, dy in self?.resize(by: CGSize(width: 0, height: dy)) }
        left.onDrag = { [weak self] dx, _ in self?.resize(by: CGSize(width: -2 * dx, height: 0)) }
        right.onDrag = { [weak self] dx, _ in self?.resize(by: CGSize(width: 2 * dx, height: 0)) }
        for handle in [bottom, left, right] {
            handle.onEnd = { [weak self] in self?.rememberSize() }
        }
        split.onDrag = { [weak self] dx, _ in self?.moveSplit(by: dx) }
        split.onEnd = { [weak self] in self?.rememberSplit() }
    }

    private func resize(by delta: CGSize) {
        guard let screen = panel.screen else { return }
        stash.closePreview()
        panel.setFrame(PanelGeometry.resized(panel.frame, by: delta, scale: UIScale.factor, in: screen.visibleFrame), display: true)
    }

    /// Stored at Small text, so it still grows and shrinks with the text size.
    private func rememberSize() {
        guard let screen = panel.screen else { return }
        let scale = UIScale.factor
        let size = CGSize(width: panel.frame.width / scale, height: panel.frame.height / scale)
        PanelLayoutMemory.setSize(size, on: screen)
        Log.info("Panel resized to \(Int(panel.frame.width)) × \(Int(panel.frame.height)) on \(screen.localizedName)")
    }

    private var currentSplit = PanelGeometry.defaultSplit

    private func moveSplit(by dx: CGFloat) {
        applySplit(PanelGeometry.split(currentSplit, movedBy: dx, across: stashCard.frame.width + notesCard.frame.width))
    }

    /// Stash takes `fraction` of the cards' width, Notes the rest.
    private func applySplit(_ fraction: CGFloat) {
        currentSplit = fraction
        splitConstraint?.isActive = false
        splitConstraint = stashCard.widthAnchor.constraint(equalTo: notesCard.widthAnchor, multiplier: fraction / (1 - fraction))
        splitConstraint?.isActive = true
    }

    private func rememberSplit() {
        PanelLayoutMemory.split = currentSplit
        Log.info("Panel split: Stash \(Int((currentSplit * 100).rounded()))%, Notes \(Int(((1 - currentSplit) * 100).rounded()))%")
    }

    /// Saves the open note, e.g. when Seashell quits.
    func saveNotes() {
        notes.willHide()
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

        // Stash (55%) and Notes each on their own card, with a small gap.
        for (card, content) in [(stashCard, stash.view), (notesCard, notes.view)] {
            content.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: card.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: card.trailingAnchor),
                content.topAnchor.constraint(equalTo: card.topAnchor),
                content.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            ])
            card.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(card)
        }
        let inset: CGFloat = 8
        NSLayoutConstraint.activate([
            stashCard.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: inset),
            stashCard.topAnchor.constraint(equalTo: background.topAnchor, constant: inset),
            stashCard.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -inset),
            notesCard.leadingAnchor.constraint(equalTo: stashCard.trailingAnchor, constant: inset),
            notesCard.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -inset),
            notesCard.topAnchor.constraint(equalTo: background.topAnchor, constant: inset),
            notesCard.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -inset),
        ])
        applySplit(PanelLayoutMemory.split)
        addDragHandles(to: background)
        panel.onNewNote = { [weak self] in self?.notes.newNote() }
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

/// The rounded, lightly tinted card each area of the panel sits on. Drawn, so
/// its colors follow light and dark mode.
final class PanelCard: NSView {
    /// Notes' card is washed in `NoteTint`, card and border alike.
    private let isNotes: Bool

    init(isNotes: Bool = false) {
        self.isNotes = isNotes
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        NSColor.windowBackgroundColor.withAlphaComponent(0.55).setFill()
        path.fill()
        if isNotes {
            NoteTint.color.withAlphaComponent(NoteTint.fill).setFill()
            path.fill()
        }
        (isNotes ? NoteTint.color.withAlphaComponent(NoteTint.border) : .separatorColor).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

/// A borderless panel that can take keys (Esc, Space, ⌘⌫, ⌘A)
/// without making Seashell the active app.
final class SeashellPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onNewNote: (() -> Void)?

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

    /// A menu bar app has no Edit menu, which is where text views normally get
    /// ⌘X ⌘C ⌘V ⌘A ⌘Z ⇧⌘Z from; send those to whatever has focus. Plus ⌘N.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased()
        if modifiers == .command, key == "n", let onNewNote {
            onNewNote()
            return true
        }
        // Text size: ⌘+ (also ⌘= and ⇧⌘=), ⌘−, ⌘0.
        let setting = TextSizeSetting.shared
        switch (modifiers, key) {
        case (.command, "="), (.command, "+"), ([.command, .shift], "+"), ([.command, .shift], "="):
            setting.size = setting.size.larger
            return true
        case (.command, "-"):
            setting.size = setting.size.smaller
            return true
        case (.command, "0"):
            setting.size = .standard
            return true
        default:
            break
        }
        let action: Selector? = switch (modifiers, key) {
        case (.command, "x"): #selector(NSText.cut(_:))
        case (.command, "c"): #selector(NSText.copy(_:))
        case (.command, "v"): #selector(NSText.paste(_:))
        case (.command, "a"): #selector(NSText.selectAll(_:))
        case (.command, "z"): Selector(("undo:"))
        case ([.command, .shift], "z"): Selector(("redo:"))
        default: nil
        }
        if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }
}
