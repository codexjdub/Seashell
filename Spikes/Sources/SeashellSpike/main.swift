import AppKit

// Throwaway spike. Proves, with a log you can read afterwards:
//   1. Cut drag-out: does Finder honour a move-only mask (same volume / other volume / other apps)?
//   2. Global scroll monitor at the top screen edge without Accessibility permission.
//   3. Shake detection while another app is dragging (global monitor vs polling).
//   4. Documents access from a bundle signed with a stable identity.
// Everything is logged to ~/Library/Logs/SeashellSpike.log and shown in the window.

// MARK: - Log

enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/SeashellSpike.log")
    static weak var textView: NSTextView?

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    static func line(_ message: String) {
        let text = "[\(stamp.string(from: Date()))] \(message)\n"
        let data = Data(text.utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
        guard let textView else { return }
        textView.textStorage?.append(NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ]))
        textView.scrollToEndOfDocument(nil)
    }
}

func describe(_ operation: NSDragOperation) -> String {
    if operation.isEmpty { return "none" }
    var parts: [String] = []
    if operation.contains(.copy) { parts.append("copy") }
    if operation.contains(.link) { parts.append("link") }
    if operation.contains(.generic) { parts.append("generic") }
    if operation.contains(.private) { parts.append("private") }
    if operation.contains(.move) { parts.append("move") }
    if operation.contains(.delete) { parts.append("delete") }
    return parts.joined(separator: "+")
}

// MARK: - Test files (spike 4: Documents access)

enum TestFiles {
    static let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/Seashell-spike")
    static let source = root.appendingPathComponent("source")
    private static var counter = 0
    private static let run = Int(Date().timeIntervalSince1970) % 100_000

    static func prepare() {
        do {
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            let probe = root.appendingPathComponent("write-probe.txt")
            try "written \(Date())\n".write(to: probe, atomically: true, encoding: .utf8)
            Log.line("Documents: write OK → \(probe.path)")
        } catch {
            Log.line("Documents: write FAILED → \(error.localizedDescription)")
        }
    }

    static func make(_ prefix: String) -> URL {
        counter += 1
        let url = source.appendingPathComponent("\(prefix)-\(run)-\(counter).txt")
        try? "Seashell spike test file: \(url.lastPathComponent)\n".write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - Drag source tiles (spike 1: Cut / Copy drag-out)

final class DragTile: NSView, NSDraggingSource {
    let title: String
    let mask: NSDragOperation
    private let makeFile: () -> URL
    private(set) var file: URL
    private var dragging = false
    private let label = NSTextField(labelWithString: "")

    init(title: String, mask: NSDragOperation, makeFile: @escaping () -> URL) {
        self.title = title
        self.mask = mask
        self.makeFile = makeFile
        self.file = makeFile()
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        label.alignment = .center
        label.maximumNumberOfLines = 3
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 220),
            heightAnchor.constraint(equalToConstant: 64),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -12),
        ])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func renew() {
        file = makeFile()
        refresh()
    }

    private func refresh() {
        label.stringValue = "\(title) — drag me\n\(file.lastPathComponent)"
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseDragged(with event: NSEvent) {
        guard !dragging else { return }
        dragging = true
        let item = NSDraggingItem(pasteboardWriter: file as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: file.path)
        icon.size = NSSize(width: 48, height: 48)
        let point = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: point.x - 24, y: point.y - 24, width: 48, height: 48), contents: icon)
        Log.line("\(title): drag started, offering [\(describe(mask))] for \(file.lastPathComponent)")
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        mask
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragging = false
        let original = file
        let title = title
        Log.line("\(title): drag ended, destination chose [\(describe(operation))]")
        // Finder may finish a move after the session ends, so look more than once.
        for delay in [0.0, 1.0, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                let exists = FileManager.default.fileExists(atPath: original.path)
                Log.line("\(title):   +\(Int(delay))s original \(exists ? "still exists" : "GONE")")
                if delay == 3.0, !exists { self?.renew() }
            }
        }
    }
}

// MARK: - Top-edge scroll (spike 2)

final class EdgeScrollProbe {
    private var monitor: Any?
    private var received = 0
    private var lastLog = Date.distantPast

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handle(event)
        }
        Log.line("Edge scroll: global scroll monitor \(monitor == nil ? "FAILED to install" : "installed")")
    }

    private func handle(_ event: NSEvent) {
        received += 1
        if received == 1 { Log.line("Edge scroll: first global scroll event received ✓") }
        let location = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: {
            let frame = $0.frame
            return location.x >= frame.minX && location.x < frame.maxX && location.y >= frame.minY && location.y <= frame.maxY
        }) else { return }
        guard screen.frame.maxY - location.y <= 4 else { return }
        guard Date().timeIntervalSince(lastLog) > 0.4 else { return }
        lastLog = Date()
        Log.line(String(format: "Edge scroll: TOP EDGE scroll on \"%@\" dy=%.1f precise=%@",
                        screen.localizedName, event.scrollingDeltaY,
                        event.hasPreciseScrollingDeltas ? "yes (trackpad)" : "no (wheel)"))
    }
}

// MARK: - Shake detection (spike 3)

final class ShakeDetector {
    var onShake: (() -> Void)?
    private var lastPoint: NSPoint?
    private var lastSign = 0
    private var travel: CGFloat = 0
    private var reversals: [TimeInterval] = []
    private var cooldownUntil: TimeInterval = 0

    func reset() {
        lastPoint = nil
        lastSign = 0
        travel = 0
        reversals = []
    }

    /// Three left/right reversals of at least 20 pt each within 0.6 s.
    func feed(_ point: NSPoint, at time: TimeInterval) {
        defer { lastPoint = point }
        guard let last = lastPoint else { return }
        let dx = point.x - last.x
        guard abs(dx) >= 1 else { return }
        let sign = dx > 0 ? 1 : -1
        if sign == lastSign || lastSign == 0 {
            travel += abs(dx)
            lastSign = sign
            return
        }
        if travel >= 20 { reversals.append(time) }
        travel = abs(dx)
        lastSign = sign
        reversals.removeAll { time - $0 > 0.6 }
        if reversals.count >= 3, time >= cooldownUntil {
            cooldownUntil = time + 1
            reversals = []
            onShake?()
        }
    }
}

final class DragWatcher {
    /// Called once per mouse press, at the first shake while content is being dragged.
    var onShake: ((NSPoint) -> Void)?

    private let viaMonitor = ShakeDetector()
    private let viaPolling = ShakeDetector()
    private let dragPasteboard = NSPasteboard(name: .drag)
    private var monitor: Any?
    private var timer: Timer?

    private var pressed = false
    private var changeCountAtPress = 0
    private var contentDrag = false
    private var shownThisPress = false
    private var monitorEvents = 0
    private var pollSamples = 0
    private var shakes: [String] = []

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            guard let self, self.pressed else { return }
            self.monitorEvents += 1
            self.viaMonitor.feed(NSEvent.mouseLocation, at: event.timestamp)
        }
        viaMonitor.onShake = { [weak self] in self?.shook(by: "global monitor") }
        viaPolling.onShake = { [weak self] in self?.shook(by: "polling") }
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Log.line("Shake: global drag monitor \(monitor == nil ? "FAILED to install" : "installed"), polling at 120 Hz")
    }

    private func tick() {
        let down = NSEvent.pressedMouseButtons & 1 != 0
        if down, !pressed {
            pressed = true
            changeCountAtPress = dragPasteboard.changeCount
            contentDrag = false
            shownThisPress = false
            monitorEvents = 0
            pollSamples = 0
            shakes = []
            viaMonitor.reset()
            viaPolling.reset()
        } else if !down, pressed {
            pressed = false
            if contentDrag || !shakes.isEmpty {
                Log.line("Shake: press ended — content drag: \(contentDrag ? "yes" : "no"), "
                         + "global monitor events: \(monitorEvents), polling samples: \(pollSamples), "
                         + "shakes: \(shakes.isEmpty ? "none" : shakes.joined(separator: ", "))")
            }
        }
        guard down else { return }
        pollSamples += 1
        viaPolling.feed(NSEvent.mouseLocation, at: ProcessInfo.processInfo.systemUptime)
        if !contentDrag, dragPasteboard.changeCount != changeCountAtPress {
            contentDrag = true
            let types = dragPasteboard.types?.map(\.rawValue).joined(separator: ", ") ?? "none"
            Log.line("Shake: content drag started. Pasteboard types: \(types)")
        }
    }

    private func shook(by source: String) {
        shakes.append(source)
        Log.line("Shake: SHAKE detected by \(source) (content drag: \(contentDrag ? "yes" : "no"))")
        guard contentDrag, !shownThisPress else { return }
        shownThisPress = true
        onShake?(NSEvent.mouseLocation)
    }
}

// MARK: - Floating shelf with three drop zones

final class DropZone: NSView {
    let name: String
    private let onDrop: () -> Void

    init(name: String, onDrop: @escaping () -> Void) {
        self.name = name
        self.onDrop = onDrop
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1.5
        layer?.borderColor = NSColor.tertiaryLabelColor.cgColor
        let label = NSTextField(labelWithString: name)
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        registerForDraggedTypes([.fileURL, .URL, .string, .rtf, .png, .tiff])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func setHighlighted(_ on: Bool) {
        layer?.backgroundColor = on ? NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor : nil
    }

    private func chosenOperation(_ offered: NSDragOperation) -> NSDragOperation {
        if name == "Stash", offered.contains(.move) { return .move }
        if offered.contains(.copy) { return .copy }
        if offered.contains(.generic) { return .generic }
        return offered.contains(.move) ? .move : []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        setHighlighted(true)
        Log.line("Floating [\(name)]: drag entered, source offers [\(describe(sender.draggingSourceOperationMask))]")
        return chosenOperation(sender.draggingSourceOperationMask)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        chosenOperation(sender.draggingSourceOperationMask)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setHighlighted(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        setHighlighted(false)
        let pasteboard = sender.draggingPasteboard
        let operation = chosenOperation(sender.draggingSourceOperationMask)
        let files = (pasteboard.readObjects(forClasses: [NSURL.self],
                                            options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !files.isEmpty {
            Log.line("Floating [\(name)]: DROPPED \(files.count) file(s) as [\(describe(operation))]: "
                     + files.map(\.lastPathComponent).joined(separator: ", "))
            // Does the source delete the original when we answer "move"? Seashell must do the move itself.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                for file in files {
                    let exists = FileManager.default.fileExists(atPath: file.path)
                    Log.line("Floating [\(self.name)]:   +1.5s \(file.lastPathComponent) \(exists ? "still at source" : "GONE from source")")
                }
            }
        } else if let text = pasteboard.string(forType: .string) {
            let preview = text.prefix(60).replacingOccurrences(of: "\n", with: "⏎")
            Log.line("Floating [\(name)]: DROPPED text (\(text.count) chars): \"\(preview)\"")
        } else {
            Log.line("Floating [\(name)]: DROPPED types: \(pasteboard.types?.map(\.rawValue).joined(separator: ", ") ?? "none")")
        }
        onDrop()
        return true
    }
}

final class FloatingShelf {
    private lazy var panel: NSPanel = makePanel()
    private var hideWork: DispatchWorkItem?
    private let size = NSSize(width: 380, height: 110)

    func show(at point: NSPoint) {
        var origin = NSPoint(x: point.x - size.width / 2, y: point.y + 40)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        Log.line("Floating: shelf shown near cursor")
        hide(after: 8)
    }

    private func hide(after seconds: Double) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true

        let zones = ["Stash", "Copy", "Cut"].map { DropZone(name: $0) { [weak self] in self?.hide(after: 1.5) } }
        let stack = NSStackView(views: zones)
        stack.distribution = .fillEqually
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: background.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -10),
        ])
        panel.contentView = background
        return panel
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let edgeProbe = EdgeScrollProbe()
    private let dragWatcher = DragWatcher()
    private let floatingShelf = FloatingShelf()
    private var tiles: [DragTile] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        let bundle = Bundle.main
        Log.line("──── SeashellSpike launched ────")
        Log.line("Bundle: \(bundle.bundleIdentifier ?? "none (not running from .app)") at \(bundle.bundlePath)")
        Log.line("macOS \(ProcessInfo.processInfo.operatingSystemVersionString), Accessibility trusted: \(AXIsProcessTrusted() ? "YES" : "no")")
        TestFiles.prepare()
        tiles = [
            DragTile(title: "CUT test (move only)", mask: .move) { TestFiles.make("cut-me") },
            DragTile(title: "COPY test (copy only)", mask: .copy) { TestFiles.make("copy-me") },
        ]
        tileRow.setViews(tiles, in: .leading)
        edgeProbe.start()
        dragWatcher.onShake = { [weak self] point in self?.floatingShelf.show(at: point) }
        dragWatcher.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private let tileRow = NSStackView()

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 640),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "Seashell Spike"

        let instructions = NSTextField(wrappingLabelWithString: """
        1. Cut: drag the CUT tile into a Finder folder. Then (if you have one) onto an external drive. Then into Mail, Slack or a browser.
        2. Copy: drag the COPY tile into a Finder folder and into another app.
        3. Edge scroll: put the pointer at the very top of the screen and scroll (trackpad and/or mouse wheel).
        4. Shake: in Finder, drag a file and shake left–right. A shelf with Stash / Copy / Cut appears — drop on each zone. \
        Repeat with highlighted text dragged from Safari, Notes or TextEdit.
        Everything is logged below and to ~/Library/Logs/SeashellSpike.log.
        """)

        tileRow.orientation = .horizontal
        tileRow.spacing = 12

        let reveal = NSButton(title: "Show test files", target: self, action: #selector(revealFiles))
        let renew = NSButton(title: "New test files", target: self, action: #selector(renewTiles))
        let buttons = NSStackView(views: [reveal, renew])

        let scroll = NSTextView.scrollableTextView()
        let textView = scroll.documentView as! NSTextView
        textView.isEditable = false
        Log.textView = textView

        let stack = NSStackView(views: [instructions, tileRow, buttons, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 280),
            instructions.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
        ])
        window.contentView = content
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    @objc private func revealFiles() {
        NSWorkspace.shared.activateFileViewerSelecting(tiles.map(\.file))
    }

    @objc private func renewTiles() {
        tiles.forEach { $0.renew() }
        Log.line("New test files created")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
