import AppKit
import SeashellCore

/// Watches mouse drags in every app, while something is actually being dragged
/// (dragging a window or selecting text leaves the drag pasteboard alone), and
/// reports, at most once per drag each:
/// - a shake of the pointer (`onShake`), unless shaking is off in Settings, and
/// - the pointer held at the top edge, away from the corners, for half a second
///   (`onHoldAtTopEdge`).
@MainActor
final class DragWatcher {
    var onShake: ((NSPoint) -> Void)?
    var onHoldAtTopEdge: ((NSPoint) -> Void)?

    private static let holdDelay: Duration = .milliseconds(500)

    /// Nil when shaking is off.
    private var detector = ShakeSensitivity.standard.detector
    private let dragPasteboard = NSPasteboard(name: .drag)
    private var changeCountAtPress = 0
    private var shookThisDrag = false
    private var heldThisDrag = false
    private var holdTask: Task<Void, Never>?
    private var monitors: [Any] = []

    func setShakeSensitivity(_ sensitivity: ShakeSensitivity) {
        detector = sensitivity.detector
    }

    func start() {
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged]
        // Global monitors see other apps' events; the local one sees Seashell's own.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }) {
            monitors.append(local)
        }
        Log.info(monitors.count == 2 ? "Watching drags for a shake" : "Couldn’t watch drags; shaking won’t open the floating shelf")
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            changeCountAtPress = dragPasteboard.changeCount
            shookThisDrag = false
            heldThisDrag = false
            cancelHold()
            detector?.reset()
        case .leftMouseDragged:
            guard dragPasteboard.changeCount != changeCountAtPress else { return }
            let point = NSEvent.mouseLocation
            watchForHold(at: point)
            if !shookThisDrag, detector?.add(x: point.x, at: event.timestamp) == true {
                shookThisDrag = true
                onShake?(point)
            }
        default:
            break
        }
    }

    /// The pointer may sit still at the edge, sending no events, so a timer
    /// decides; moving out of the zone cancels it.
    private func watchForHold(at point: NSPoint) {
        guard !heldThisDrag, Self.isInSpringLoadZone(point) else {
            cancelHold()
            return
        }
        guard holdTask == nil else { return }
        holdTask = Task { [weak self] in
            try? await Task.sleep(for: Self.holdDelay)
            guard let self, !Task.isCancelled else { return }
            self.holdTask = nil
            let now = NSEvent.mouseLocation
            guard NSEvent.pressedMouseButtons & 1 != 0, Self.isInSpringLoadZone(now) else { return }
            self.heldThisDrag = true
            self.onHoldAtTopEdge?(now)
        }
    }

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
    }

    private static func isInSpringLoadZone(_ point: NSPoint) -> Bool {
        guard let screen = NSScreen.containing(point) else { return false }
        return PanelGeometry.isInSpringLoadZone(point, screenFrame: screen.frame)
    }
}
