import AppKit
import SeashellCore

/// Watches scrolling with the pointer at the top edge of any screen and reports
/// pull-down and push-up gestures, with the screen they happened on.
@MainActor
final class EdgeScrollWatcher {
    var onGesture: ((EdgeScrollDetector.Gesture, NSScreen) -> Void)?

    private var detector = EdgeScrollDetector()
    private var monitors: [Any] = []

    func start() {
        // Global for scrolls over other apps and the menu bar; local for scrolls over Seashell's own windows.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }) {
            monitors.append(local)
        }
        Log.info(monitors.count == 2 ? "Watching the top edge for a pull down" : "Couldn’t watch scrolling; pulling down won’t open the panel")
    }

    private func handle(_ event: NSEvent) {
        // Momentum keeps scrolling after the fingers lift; only the gesture itself counts.
        guard event.momentumPhase.isEmpty else { return }
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.containing(point), PanelGeometry.isAtTopEdge(point, screenFrame: screen.frame) else {
            detector.reset()
            return
        }
        let downward = EdgeScrollDetector.downward(deltaY: event.scrollingDeltaY,
                                                   invertedFromDevice: event.isDirectionInvertedFromDevice)
        if let gesture = detector.add(downward: downward, precise: event.hasPreciseScrollingDeltas, at: event.timestamp) {
            onGesture?(gesture, screen)
        }
    }
}
