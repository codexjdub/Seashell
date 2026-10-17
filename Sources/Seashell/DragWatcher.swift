import AppKit
import SeashellCore

/// Watches mouse drags in every app and calls `onShake` once per drag when the
/// pointer is shaken while something is actually being dragged. Dragging a
/// window or selecting text doesn't count: those leave the drag pasteboard alone.
@MainActor
final class DragWatcher {
    var onShake: ((NSPoint) -> Void)?

    private var detector = ShakeDetector()
    private let dragPasteboard = NSPasteboard(name: .drag)
    private var changeCountAtPress = 0
    private var shookThisDrag = false
    private var monitors: [Any] = []

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
            detector.reset()
        case .leftMouseDragged:
            guard !shookThisDrag, dragPasteboard.changeCount != changeCountAtPress else { return }
            let point = NSEvent.mouseLocation
            if detector.add(x: point.x, at: event.timestamp) {
                shookThisDrag = true
                onShake?(point)
            }
        default:
            break
        }
    }
}
