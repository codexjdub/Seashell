import AppKit
import QuartzCore
import SeashellCore

/// The easter egg: 1 1 1 and Return in About Seashell shows the app icon at its
/// full 1024 pixels, floating in the middle of the screen. Zephyr's breath blows
/// in across it strand by strand, a ripple of pearly light runs up the shell
/// from the hinge to the rim, and the strands drift off, on a 4-second loop. A
/// click, Esc or any key puts it away. With Reduce Motion on, it's the still icon.
///
/// The pieces are Resources/EasterEgg, made by make-icon.sh from AppIcon.svg:
/// the icon without its strands, each strand, and the ribs above the hinge that
/// keep the light in. Everything here is in the drawing's 1024-wide units.
@MainActor
final class EasterEgg: NSObject, NSWindowDelegate {
    private static let size: CGFloat = 1024
    private static let loop: Double = 4
    private static let samples = 120
    /// Where the ribs meet, measured from the drawing's top.
    private static let hinge = CGPoint(x: 512, y: 724)
    private var window: NSPanel?

    /// Shows it in the middle of the screen `frame` is on (About's window).
    func show(over frame: NSRect?) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        guard let icon = Self.picture("icon") else {
            Log.error("Easter egg: its pictures are missing from the app")
            return
        }
        let screen = frame.flatMap { frame in NSScreen.screens.first { $0.frame.intersects(frame) } } ?? NSScreen.main
        // Its native 1024 pixels: half that in points on a Retina screen, smaller if the screen is.
        var side = Self.size / (screen?.backingScaleFactor ?? 2)
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: side, height: side)
        side = min(side, visible.width * 0.9, visible.height * 0.9)

        let panel = EggPanel(contentRect: NSRect(x: visible.midX - side / 2, y: visible.midY - side / 2, width: side, height: side),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false  // the icon has its own
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.onDismiss = { [weak self] in self?.close() }
        let view = EggView()
        view.onClick = { [weak self] in self?.close() }
        view.wantsLayer = true
        panel.contentView = view

        let art = CALayer()
        art.bounds = CGRect(x: 0, y: 0, width: Self.size, height: Self.size)
        art.position = CGPoint(x: side / 2, y: side / 2)
        art.transform = CATransform3DMakeScale(side / Self.size, side / Self.size, 1)
        view.layer?.addSublayer(art)
        art.addSublayer(Self.layer(showing: icon))
        let animated = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if animated, let ribs = Self.picture("ribs") {
            art.addSublayer(Self.ripple(inside: ribs))
        }
        for index in 0..<3 {
            guard let strand = Self.picture("strand-\(index + 1)") else { continue }
            art.addSublayer(animated ? Self.blowing(strand, index: index) : Self.layer(showing: strand))
        }

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            panel.animator().alphaValue = 1
        }
        window = panel
        Log.info("Easter egg shown")
    }

    func close() {
        guard let panel = window else { return }
        window = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in panel.orderOut(nil) }
        })
    }

    /// Clicking anywhere else puts it away too.
    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    // MARK: The pieces

    private static func picture(_ name: String) -> CGImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "EasterEgg"),
              let image = NSImage(contentsOf: url),
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }

    private static func layer(showing image: CGImage) -> CALayer {
        let layer = CALayer()
        layer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        layer.contents = image
        return layer
    }

    /// A strand that blows in from the left (each a little after the one above),
    /// holds, then drifts off up and to the right as it fades.
    private static func blowing(_ strand: CGImage, index: Int) -> CALayer {
        let layer = self.layer(showing: strand)
        let drift = loop - 1
        let reveal = sample { ease(($0 - 0.15 * Double(index)) / 0.7) }
        let leaving = sample { ease(($0 - drift - 0.1 * Double(index)) / 0.5) }

        // The strands sit in the top left; a box growing rightwards uncovers them.
        let cover = CALayer()
        cover.backgroundColor = NSColor.black.cgColor
        cover.anchorPoint = .zero
        cover.frame = CGRect(x: 100, y: size - 460, width: 0, height: 360)
        layer.mask = cover
        cover.add(repeating([keyframes("bounds.size.width", reveal.map { max(0.1, 260 * $0) })]), forKey: "reveal")

        layer.add(repeating([
            keyframes("opacity", leaving.map { 1 - $0 }),
            keyframes("transform.translation.x", leaving.map { 30 * $0 }),
            keyframes("transform.translation.y", leaving.map { 7.5 * $0 }),
        ]), forKey: "drift")
        return layer
    }

    /// A soft ring of pearly light (pink inside, white, mint outside) spreading
    /// from the hinge across the ribs to the rim, fading as it reaches the top.
    private static func ripple(inside ribs: CGImage) -> CALayer {
        let start = 0.4, length = 3.2, reach = 620.0, width = 160.0
        let radius = reach + width
        let shine = CAGradientLayer()
        shine.frame = CGRect(x: 0, y: 0, width: size, height: size)
        shine.type = .radial
        let centre = CGPoint(x: hinge.x / size, y: 1 - hinge.y / size)
        shine.startPoint = centre
        shine.endPoint = CGPoint(x: centre.x + radius / size, y: centre.y + radius / size)
        let pink = NSColor(srgbRed: 0xF9 / 255.0, green: 0xC9 / 255.0, blue: 0xD6 / 255.0, alpha: 1)
        let mint = NSColor(srgbRed: 0xBF / 255.0, green: 0xEB / 255.0, blue: 0xDD / 255.0, alpha: 1)
        shine.colors = [pink.withAlphaComponent(0), pink.withAlphaComponent(0), pink.withAlphaComponent(0.3),
                        NSColor.white.withAlphaComponent(0.85), mint.withAlphaComponent(0.3), mint.withAlphaComponent(0)].map(\.cgColor)
        let mask = layer(showing: ribs)
        shine.mask = mask

        let progress = sample { ($0 - start) / length }
        let rings = progress.map { p -> [NSNumber] in
            let r = ease(p) * reach
            return [0, r - width, r - width / 2, r, r + width / 2, r + width].map { NSNumber(value: min(1, max(0, $0 / radius))) }
        }
        let strength = progress.map { p in
            (0...1).contains(p) ? min(1, p / 0.15) * (1 - ease((p - 0.65) / 0.35)) : 0
        }
        shine.opacity = 0
        // Core Animation only animates the stops of a layer that already has some.
        shine.locations = rings[0]
        shine.add(repeating([keyframes("locations", rings), keyframes("opacity", strength)]), forKey: "ripple")
        return shine
    }

    // MARK: Timing

    private static func ease(_ x: Double) -> Double {
        0.5 - 0.5 * cos(Double.pi * min(1, max(0, x)))
    }

    /// `value` at evenly spaced moments through one loop, start to end.
    private static func sample<T>(_ value: (Double) -> T) -> [T] {
        (0...samples).map { value(loop * Double($0) / Double(samples)) }
    }

    private static func keyframes(_ keyPath: String, _ values: [Any]) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = (0...samples).map { NSNumber(value: Double($0) / Double(samples)) }
        animation.calculationMode = .linear
        return animation
    }

    private static func repeating(_ animations: [CAAnimation]) -> CAAnimationGroup {
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = loop
        group.repeatCount = .infinity
        return group
    }
}

/// The egg's borderless window: takes the keyboard so Esc or any key puts it away.
private final class EggPanel: NSPanel {
    var onDismiss: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        onDismiss?()
    }

    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        onDismiss?()
        return true
    }
}

/// A click anywhere on the egg puts it away; the first click counts even before
/// the window has the keyboard.
private final class EggView: NSView {
    var onClick: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
