import AppKit
import SeashellCore

/// The app icon's shell pressed onto the right edge of Seashell's panels like a
/// seal: the pull-down panel, the grab shelf, the drop shelf and tear-off
/// shelves. It's the icon without its tile (Seal.png, made by make-icon.sh),
/// which would glare on a dark panel. About a third of it sticks out past the
/// edge. Sizes are at Small text, scaled.
@MainActor
enum Seal {
    static let size: CGFloat = 42
    /// The icon's frame past the panel's right edge; the artwork leaves a margin
    /// inside its frame, so about a third of what you see is outside.
    static let overhang: CGFloat = 15
    /// Room the window keeps past the panel's right edge for it.
    static let sideRoom: CGFloat = PanelGeometry.sideColumn
    /// It sits a fifth of the way down the right edge, on the panel and the shelves alike.
    static let shelfPosition: CGFloat = 0.2

    /// The shell and strands, or the app icon if the picture is missing.
    static var picture: NSImage {
        NSImage(named: "Seal") ?? NSApp.applicationIconImage
    }

    /// Clickable, for the panel, the grab shelf and tear-off shelves.
    static func button(target: AnyObject, action: Selector, toolTip: String) -> SealView {
        SealView(target: target, action: action, toolTip: toolTip)
    }

    /// Just the picture, for the drop shelf (it can't be clicked mid-drag).
    static func image() -> SealView {
        SealView(target: nil, action: nil, toolTip: nil)
    }

    /// Where its center sits below a shelf's top: a fifth of the way down, but
    /// never so high that it would stick out above a short shelf, or reach
    /// into the top `clearing` points (a title bar with a close button).
    static func centerOffset(inHeight height: CGFloat, clearing: CGFloat = 0) -> CGFloat {
        max(height * shelfPosition, clearing + UIScale.pt(size) / 2 + 2)
    }
}

/// The shell on a panel's edge, which reacts to what happens on its shelf:
/// it catches a drop, leans toward a drag from another app, shakes its head
/// when ⌘Z has nothing to take back, holds a pearl while something new has
/// arrived (StashStore's arrivals), and breathes while Read Aloud reads. Only the shell moves as a whole, never its
/// wind curls on their own: those belong to the easter egg. With Reduce Motion
/// on it stays still; the pearl still shows.
@MainActor
final class SealView: NSView {
    enum Reaction {
        /// Something landed on the shelf: a squash and a bounce.
        case catchDrop
        /// Nothing to undo: side to side, with the beep.
        case shake
    }

    /// Every shell there is, for reactions and the pearl.
    private static let all = NSHashTable<SealView>.weakObjects()
    /// Something new has arrived: every shell holds a pearl.
    static var showsPearl = false {
        didSet {
            guard showsPearl != oldValue else { return }
            all.allObjects.forEach { $0.updatePearl(animated: true) }
        }
    }
    /// Read Aloud is reading: every shell breathes.
    static var isBreathing = false {
        didSet {
            guard isBreathing != oldValue else { return }
            all.allObjects.forEach { $0.updateBreathing() }
        }
    }
    private static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Where the shell's ribs meet, as a fraction of its frame from the bottom
    /// left: it pivots there, and the pearl sits just below. The shell is right
    /// of the picture's middle (the wind curls take the left): measured in
    /// Seal.png, its every row is centered at 0.547.
    private static let hinge = CGPoint(x: 0.547, y: 0.293)

    private let shell = CALayer()
    /// The pearl's shadow; its face is a sublayer, clipped round.
    private let pearl = CALayer()
    private let pearlFace = CAGradientLayer()
    private weak var target: AnyObject?
    private let action: Selector?
    private var isLeaning = false

    init(target: AnyObject?, action: Selector?, toolTip: String?) {
        self.target = target
        self.action = action
        super.init(frame: .zero)
        self.toolTip = toolTip
        wantsLayer = true
        shell.contentsGravity = .resizeAspect
        layer?.addSublayer(shell)

        pearlFace.type = .radial
        // A highlight up and to the left, darkening to the rim.
        pearlFace.startPoint = CGPoint(x: 0.35, y: 0.7)
        pearlFace.endPoint = CGPoint(x: 1.05, y: 1.4)
        pearlFace.colors = [NSColor.white, NSColor(srgbRed: 0.965, green: 0.933, blue: 0.949, alpha: 1),
                            NSColor(srgbRed: 0.89, green: 0.827, blue: 0.867, alpha: 1),
                            NSColor(srgbRed: 0.788, green: 0.71, blue: 0.769, alpha: 1)].map(\.cgColor)
        pearlFace.locations = [0, 0.18, 0.55, 1]
        pearlFace.masksToBounds = true
        pearl.addSublayer(pearlFace)
        pearl.shadowColor = NSColor.black.cgColor
        pearl.shadowOpacity = 0.35
        pearl.shadowRadius = 1
        pearl.shadowOffset = CGSize(width: 0, height: -1)
        shell.addSublayer(pearl)

        Self.all.add(self)
        updatePicture()
        updatePearl(animated: false)
        updateBreathing()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shell.anchorPoint = Self.hinge
        shell.bounds = CGRect(origin: .zero, size: bounds.size)
        shell.position = CGPoint(x: bounds.width * Self.hinge.x, y: bounds.height * Self.hinge.y)
        // Nestled just below the hinge, about a quarter of the shell across.
        let side = (bounds.width * 0.28).rounded()
        pearl.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        pearl.position = CGPoint(x: bounds.width * Self.hinge.x, y: bounds.height * 0.22)
        pearl.shadowPath = CGPath(ellipseIn: pearl.bounds, transform: nil)
        pearlFace.frame = pearl.bounds
        pearlFace.cornerRadius = side / 2
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateBreathing()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updatePicture()
    }

    /// The picture at this screen's resolution.
    private func updatePicture() {
        let scale = window?.backingScaleFactor ?? 2
        let picture = Seal.picture
        shell.contentsScale = picture.recommendedLayerContentsScale(scale)
        shell.contents = picture.layerContents(forContentsScale: shell.contentsScale)
        pearlFace.contentsScale = scale
        pearl.contentsScale = scale
    }

    // MARK: Clicking

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        action != nil
    }

    override func mouseDown(with event: NSEvent) {
        guard action != nil else { return super.mouseDown(with: event) }
        setPressed(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard action != nil else { return super.mouseDragged(with: event) }
        setPressed(bounds.contains(convert(event.locationInWindow, from: nil)))
    }

    override func mouseUp(with event: NSEvent) {
        guard action != nil else { return super.mouseUp(with: event) }
        setPressed(false)
        if bounds.contains(convert(event.locationInWindow, from: nil)) { perform() }
    }

    /// Dimmed while pressed, as a picture button is.
    private func setPressed(_ pressed: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shell.opacity = pressed ? 0.7 : 1
        CATransaction.commit()
    }

    private func perform() {
        guard let action else { return }
        NSApp.sendAction(action, to: target, from: self)
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { action == nil ? .image : .button }
    override func accessibilityLabel() -> String? {
        let name = toolTip ?? "Seashell"
        return Self.showsPearl ? "\(name), something new has arrived" : name
    }
    override func accessibilityPerformPress() -> Bool {
        guard action != nil else { return false }
        perform()
        return true
    }

    // MARK: Reactions

    /// The shells in `window` (where a drop landed, or ⌘Z was pressed) react.
    static func react(_ reaction: Reaction, in window: NSWindow?) {
        guard let window else { return }
        all.allObjects.filter { $0.window === window }.forEach { $0.play(reaction) }
    }

    private func play(_ reaction: Reaction) {
        guard !Self.reduceMotion, window?.isVisible == true else { return }
        let animations: [CAKeyframeAnimation]
        let duration: CFTimeInterval
        switch reaction {
        case .catchDrop:
            settle()
            duration = 0.36
            animations = [Self.keyframes("transform.scale.x", [0, 0.16, -0.07, 0], at: [0, 0.3, 0.6, 1]),
                          Self.keyframes("transform.scale.y", [0, -0.16, 0.07, 0], at: [0, 0.3, 0.6, 1])]
        case .shake:
            duration = 0.42
            let unit = bounds.width / Seal.size  // points at Small text
            let times: [NSNumber] = [0, 0.15, 0.35, 0.55, 0.75, 1]
            animations = [Self.keyframes("transform.translation.x", [0, -5, 5, -4, 3, 0].map { $0 * unit }, at: times),
                          Self.keyframes("transform.rotation.z", [0, 4, -4, 3, -2, 0].map { $0 * .pi / 180 }, at: times)]
        }
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0.7, 0.4, 1)
        shell.add(group, forKey: "reaction")
    }

    /// Added to wherever the shell is (upright, or leaning).
    private static func keyframes(_ keyPath: String, _ values: [CGFloat], at times: [NSNumber]) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = times
        animation.isAdditive = true
        return animation
    }

    // MARK: Leaning toward a drag

    private static var dragEndCheck: Task<Void, Never>?

    /// A drag from another app is at `point` (screen coordinates): shells in
    /// the window under it lean toward it, the rest settle.
    static func dragMoved(to point: NSPoint) {
        for seal in all.allObjects {
            if let window = seal.window, window.isVisible, window.frame.contains(point) {
                seal.lean(toward: point)
            } else {
                seal.settle()
            }
        }
        watchForDragEnd()
    }

    /// The drag's last events can go to the app it came from, so once the
    /// button is up (checked every 0.3 s while it's held), every shell settles.
    private static func watchForDragEnd() {
        dragEndCheck?.cancel()
        dragEndCheck = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            if NSEvent.pressedMouseButtons & 1 == 0 {
                all.allObjects.forEach { $0.settle() }
            } else {
                watchForDragEnd()
            }
        }
    }

    /// Tipped in toward the pointer (always to its left), 6° give or take 4
    /// as it's higher or lower.
    private func lean(toward point: NSPoint) {
        guard !Self.reduceMotion, let window else { return }
        let center = window.convertPoint(toScreen: convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil))
        let degrees = 6 + max(-4, min(4, (point.y - center.y) / 30))
        let lean = CATransform3DRotate(CATransform3DMakeTranslation(-3 * bounds.width / Seal.size, 0, 0), degrees * .pi / 180, 0, 0, 1)
        isLeaning = true
        animate { shell.transform = lean }
    }

    private func settle() {
        guard isLeaning else { return }
        isLeaning = false
        animate { shell.transform = CATransform3DIdentity }
    }

    private func animate(_ change: () -> Void) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.3, 0.7, 0.4, 1))
        change()
        CATransaction.commit()
    }

    // MARK: Breathing while Read Aloud reads

    /// Slowly a little larger and back, about every two and a half seconds,
    /// from the hinge; added to whatever else it's doing.
    private func updateBreathing() {
        guard Self.isBreathing, !Self.reduceMotion else {
            shell.removeAnimation(forKey: "breathing")
            return
        }
        guard shell.animation(forKey: "breathing") == nil else { return }
        let breath = CABasicAnimation(keyPath: "transform.scale")
        breath.fromValue = 0
        breath.toValue = 0.07
        breath.isAdditive = true
        breath.duration = 1.25
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shell.add(breath, forKey: "breathing")
    }

    // MARK: The pearl

    private func updatePearl(animated: Bool) {
        let show = Self.showsPearl
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pearl.isHidden = !show
        CATransaction.commit()
        guard show, animated, !Self.reduceMotion, window?.isVisible == true else { return }
        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 0
        pop.toValue = 1
        pop.damping = 9
        pop.stiffness = 260
        pop.duration = pop.settlingDuration
        pearl.add(pop, forKey: "pop")
    }
}
