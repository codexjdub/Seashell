import AppKit
import SeashellCore

/// The cat by the notes (Settings ▸ "Show a cat by your notes", off at first):
/// a grey tabby with white socks, lying like a loaf on the Notes header. It
/// keeps you company and reacts to what you do with notes:
///
/// - It watches: its eyes follow the pointer over the panel, and the text
///   cursor as you type. It blinks now and then.
/// - Typing twitches an ear, and now and then (`CatPace`) it bats a paw at
///   your line.
/// - A new note: it perks up with a hop. A to-do ticked: a paw pat and a
///   sparkle; ticking the last one gets happy eyes, hearts and a purr.
/// - Pinning a note: it sits up proud and gives a slow blink. Moving one to
///   the Trash: it swats, then looks away as if nothing happened.
/// - Read Aloud: ears up, its head tilting while it listens.
/// - Clicking it pets it.
/// - Left alone for a few minutes with the panel open, it dozes off; typing,
///   hovering over it or something arriving wakes it.
///
/// Drawn in code from the mock-up's shapes, on a 120 × 76 grid drawn with y
/// down and flipped to Core Animation's y up. Each part that moves (tail, body,
/// paw, head, ears, eyes) is its own layer, pivoting where it would. With
/// Reduce Motion it keeps its faces but doesn't move.
@MainActor
final class NotesCat: NSView {
    enum Reaction {
        case newNote
        case ticked(allDone: Bool)
        case pinned
        case trashed
    }

    /// As wide as this for each point of height.
    static let aspect = CatPen.grid.width / CatPen.grid.height
    /// Nothing happening for this long with the panel open: it dozes off.
    private static let dozeAfter: Duration = .seconds(180)

    /// Every cat there is (one, in the panel), for Read Aloud and arrivals.
    private static let all = NSHashTable<NotesCat>.weakObjects()
    /// Read Aloud is reading: the cat listens.
    static var isListening = false {
        didSet {
            guard isListening != oldValue else { return }
            all.allObjects.forEach { $0.listeningChanged() }
        }
    }

    /// Something new arrived on a shelf: a dozing cat wakes up.
    static func somethingArrived() {
        all.allObjects.forEach { $0.wake() }
    }

    private static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // MARK: Layers

    private let art = CALayer()
    private let whole = CatPen.part(pivot: CatPen.point(60, 76))
    private let tail = CatPen.part(pivot: CatPen.point(96, 52))
    private let body = CatPen.part(pivot: CatPen.point(61.5, 73.5))
    private let pawL = CatPen.part(pivot: CatPen.point(31, 76))
    private let pawR = CatPen.part(pivot: CatPen.point(52, 76.6))
    private let head = CatPen.part(pivot: CatPen.point(41, 51))
    private let earL = CatPen.part(pivot: CatPen.point(26, 22))
    private let earR = CatPen.part(pivot: CatPen.point(56, 22))
    private var openEyes: [CALayer] = []
    private var looks: [CALayer] = []
    private var happyEyes: [CAShapeLayer] = []
    private var shutEyes: [CAShapeLayer] = []
    private var blushes: [CAShapeLayer] = []
    private var smile = CAShapeLayer()
    private var flatMouth = CAShapeLayer()
    private var openMouth = CAShapeLayer()

    private enum Ink { case fur, tailLine, tailFur, stripe, sock, muzzle, earInside, eye, eyeLine, glint, nose, blush, mouthInside, whisker }
    private var inked: [(layer: CAShapeLayer, ink: Ink)] = []

    // MARK: State

    /// The panel is open (and the cat turned on).
    private var isShown = false
    private var isRunning: Bool { isShown && !isHiddenOrHasHiddenAncestor && window != nil }
    private var isAsleep = false
    private var isHappy = false
    private var isProud = false
    private var isSlowBlinking = false
    private var isInnocent = false
    private var isSayingMrrp = false
    /// Where the eyes look, in grid points from the middle.
    private var gaze = CGPoint.zero
    private var pace = CatPace()
    private var pending: [String: Task<Void, Never>] = [:]
    private var loops: [String: Task<Void, Never>] = [:]
    private weak var pointerHost: NSView?
    private var pointerArea: NSTrackingArea?
    private var hoverArea: NSTrackingArea?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        art.anchorPoint = .zero
        art.bounds = CGRect(origin: .zero, size: CatPen.grid)
        layer?.addSublayer(art)
        art.addSublayer(whole)
        draw()
        Self.all.add(self)
        recolor()
        updateFace()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Drawing

    private func draw() {
        // The tail, upright behind the body: an outline, then the fur.
        let tailPath = CatPen { $0.m(96, 52); $0.c(108, 47, 117, 35, 111, 22); $0.c(109, 18, 105, 18, 104, 21) }.path
        shape(tailPath, .tailLine, in: tail, width: 9.4)
        shape(tailPath, .tailFur, in: tail, width: 7)
        shape(CatPen {
            $0.m(16, 63); $0.c(16, 41, 38, 33, 64, 33); $0.c(90, 33, 107, 43, 107, 59)
            $0.c(107, 69, 97, 73.5, 83, 73.5); $0.l(28, 73.5); $0.c(20, 73.5, 16, 69, 16, 63); $0.z()
        }.path, .fur, in: body, width: 1.3)
        shape(CatPen {
            $0.m(70, 35); $0.q(75, 41, 72, 48); $0.m(82, 37); $0.q(87, 43, 84, 50); $0.m(93, 42); $0.q(97, 47, 95, 53)
        }.path, .stripe, in: body, width: 2)
        shape(CatPen { $0.ellipse(31, 71.5, 8, 4.6) }.path, .sock, in: pawL, width: 1.1)
        shape(CatPen { $0.ellipse(52, 72, 8, 4.6) }.path, .sock, in: pawR, width: 1.1)
        drawHead()
        // Front to back: the raised paw goes in front of the face.
        for part in [tail, body, pawL, head, pawR] { whole.addSublayer(part) }
    }

    /// The head, drawn around its middle at (41, 36).
    private func drawHead() {
        let at = (x: CGFloat(41), y: CGFloat(36))
        for (ear, side) in [(earL, CGFloat(-1)), (earR, CGFloat(1))] {
            shape(CatPen(at) { $0.m(25 * side, -7); $0.l(21.5 * side, -33); $0.l(5 * side, -21); $0.z() }.path, .fur, in: ear, width: 1.3)
            shape(CatPen(at) { $0.m(20.6 * side, -13); $0.l(19 * side, -27); $0.l(10.5 * side, -19.6); $0.z() }.path, .earInside, in: ear)
            head.addSublayer(ear)
        }
        shape(CatPen(at) {
            $0.m(-28, 3); $0.c(-28, -15, -15, -24, 0, -24); $0.c(15, -24, 28, -15, 28, 3)
            $0.c(28, 16, 16, 22, 0, 22); $0.c(-16, 22, -28, 16, -28, 3); $0.z()
        }.path, .fur, in: head, width: 1.3)
        shape(CatPen(at) { $0.m(-6.5, -21.5); $0.l(-5, -15.5); $0.m(0, -23); $0.l(0, -16.5); $0.m(6.5, -21.5); $0.l(5, -15.5) }.path,
              .stripe, in: head, width: 2)
        shape(CatPen(at) { $0.ellipse(0, 10.5, 11.5, 8.2) }.path, .muzzle, in: head)
        for side in [CGFloat(-1), 1] {
            blushes.append(shape(CatPen(at) { $0.ellipse(17.5 * side, 7.5, 4.4, 2.6) }.path, .blush, in: head))
        }
        for side in [CGFloat(-1), 1] {
            let center = (x: at.x + 11 * side, y: at.y - 1.5)
            let eye = CatPen.part(pivot: CatPen.point(center.x, center.y))
            let look = CALayer()
            look.frame = CGRect(origin: .zero, size: CatPen.grid)
            shape(CatPen(center) { $0.ellipse(0, 0, 5.4, 5.4) }.path, .eye, in: look)
            shape(CatPen(center) { $0.ellipse(-1.8, -2, 1.8, 1.8); $0.ellipse(1.9, 1.9, 0.8, 0.8) }.path, .glint, in: look)
            eye.addSublayer(look)
            head.addSublayer(eye)
            openEyes.append(eye)
            looks.append(look)
            happyEyes.append(shape(CatPen(center) { $0.m(-4.6, 1.6); $0.q(0, -4.2, 4.6, 1.6) }.path, .eyeLine, in: head, width: 2))
            shutEyes.append(shape(CatPen(center) { $0.m(-4.6, -0.6); $0.q(0, 3.6, 4.6, -0.6) }.path, .eyeLine, in: head, width: 2))
        }
        shape(CatPen(at) { $0.m(-2.8, 4.6); $0.q(0, 3.6, 2.8, 4.6); $0.q(1.3, 7.6, 0, 7.8); $0.q(-1.3, 7.6, -2.8, 4.6); $0.z() }.path,
              .nose, in: head)
        smile = shape(CatPen(at) { $0.m(0, 7.8); $0.q(-1.6, 10.8, -4.8, 10); $0.m(0, 7.8); $0.q(1.6, 10.8, 4.8, 10) }.path,
                      .eyeLine, in: head, width: 1.2)
        flatMouth = shape(CatPen(at) { $0.m(-3.6, 10.2); $0.l(3.6, 10.2) }.path, .eyeLine, in: head, width: 1.2)
        openMouth = shape(CatPen(at) { $0.ellipse(0, 11.4, 2.1, 2.4) }.path, .mouthInside, in: head)
        let whiskers = shape(CatPen(at) {
            $0.m(-13, 8.5); $0.l(-28, 6); $0.m(-13, 11); $0.l(-28, 12.6); $0.m(13, 8.5); $0.l(28, 6); $0.m(13, 11); $0.l(28, 12.6)
        }.path, .whisker, in: head, width: 0.8)
        whiskers.opacity = 0.8
    }

    @discardableResult
    private func shape(_ path: CGPath, _ ink: Ink, in parent: CALayer, width: CGFloat = 0) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.frame = CGRect(origin: .zero, size: CatPen.grid)
        layer.path = path
        layer.lineWidth = width
        layer.lineCap = .round
        layer.lineJoin = .round
        parent.addSublayer(layer)
        inked.append((layer, ink))
        return layer
    }

    /// Grey fur and white socks in both appearances, a touch darker in dark mode.
    private func recolor() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let fur = CatPen.color(dark ? 0x9C9EA6 : 0xA3A5AD)
        let line = CatPen.color(dark ? 0x5A5C63 : 0x6C6E76)
        let stripe = CatPen.color(dark ? 0x7C7E86 : 0x84868E)
        let sock = CatPen.color(dark ? 0xE6E6EA : 0xF4F4F6)
        let eye = CatPen.color(0x2A2A30)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (layer, ink) in inked {
            var fill: CGColor?
            var stroke: CGColor?
            switch ink {
            case .fur: fill = fur; stroke = line
            case .tailLine: stroke = line
            case .tailFur: stroke = fur
            case .stripe: stroke = stripe
            case .sock: fill = sock; stroke = line
            case .muzzle: fill = sock
            case .earInside: fill = CatPen.color(0xF2B3BD)
            case .eye: fill = eye
            case .eyeLine: stroke = eye
            case .glint: fill = CatPen.color(0xFFFFFF)
            case .nose: fill = CatPen.color(0xE8909E)
            case .blush: fill = CatPen.color(0xEF7891, alpha: 0.5)
            case .mouthInside: fill = CatPen.color(0xC45C6E)
            case .whisker: stroke = line
            }
            layer.fillColor = fill
            layer.strokeColor = stroke
        }
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        recolor()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for (layer, _) in inked { layer.contentsScale = scale }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let scale = min(bounds.width / CatPen.grid.width, bounds.height / CatPen.grid.height)
        art.position = CGPoint(x: (bounds.width - CatPen.grid.width * scale) / 2, y: 0)
        art.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        CATransaction.commit()
    }

    // MARK: Showing

    /// The panel opened.
    func shown() {
        isShown = true
        restart()
    }

    /// The panel closed: everything stops, and it's awake when it opens again.
    func hidden() {
        isShown = false
        stop()
    }

    override func viewDidHide() {
        super.viewDidHide()
        stop()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        restart()
    }

    private func restart() {
        guard isRunning else { return }
        restartDozing()
        updateLoops()
        updatePose(animated: false)
    }

    private func stop() {
        pending.values.forEach { $0.cancel() }
        pending.removeAll()
        isAsleep = false
        isHappy = false
        isProud = false
        isSlowBlinking = false
        isInnocent = false
        isSayingMrrp = false
        updateLoops()
        updateFace()
        updatePose(animated: false)
        for part in [whole, body, pawR, head, earL, earR] { part.removeAllAnimations() }
    }

    // MARK: Reactions

    func react(_ reaction: Reaction) {
        guard isRunning else { return }
        wake()
        switch reaction {
        case .newNote:
            hop()
            isSayingMrrp = true
            updateFace()
            after(0.7, "mrrp") { [weak self] in self?.isSayingMrrp = false; self?.updateFace() }
            pop(.bang)
        case .ticked(let allDone):
            if allDone {
                beHappy(for: 2.4, hearts: 3)
            } else {
                movePaw(.pat)
                pop(.spark)
            }
        case .pinned:
            isProud = true
            updatePose(animated: true)
            after(0.35, "slow blink") { [weak self] in
                self?.isSlowBlinking = true
                self?.updateFace()
                self?.after(0.7, "slow blink open") { [weak self] in self?.isSlowBlinking = false; self?.updateFace() }
            }
            after(1.5, "proud") { [weak self] in self?.isProud = false; self?.updatePose(animated: true) }
        case .trashed:
            movePaw(.swat)
            after(0.23, "innocent") { [weak self] in
                guard let self else { return }
                self.isInnocent = true
                self.updateFace()
                self.updatePose(animated: true)
                self.after(2.2, "innocent end") { [weak self] in
                    self?.isInnocent = false
                    self?.updateFace()
                    self?.updatePose(animated: true)
                }
            }
        }
    }

    /// A key typed in the note; `caret` is where the text cursor is on screen.
    func typed(caret: NSRect?) {
        guard isRunning else { return }
        wake()
        twitch()
        if let caret, caret.width.isFinite, caret != .zero { look(at: NSPoint(x: caret.midX, y: caret.midY)) }
        if pace.key(at: ProcessInfo.processInfo.systemUptime) { movePaw(.bat) }
    }

    private func pet() {
        guard isRunning else { return }
        guard !isAsleep else { return wake() }
        restartDozing()
        beHappy(for: 1.9, hearts: 2)
    }

    private func beHappy(for seconds: Double, hearts: Int) {
        isHappy = true
        updateFace()
        purr(for: seconds * 0.7)
        pop(.heart, count: hearts)
        after(0.3, "purr word") { [weak self] in self?.pop(.purr) }
        after(seconds, "happy") { [weak self] in self?.isHappy = false; self?.updateFace() }
    }

    private func wake() {
        guard isRunning else { return }
        if isAsleep {
            isAsleep = false
            updateFace()
            updatePose(animated: true)
            updateLoops()
            hop()
        }
        restartDozing()
    }

    private func restartDozing() {
        after(Self.dozeAfter.seconds, "doze") { [weak self] in self?.fallAsleep() }
    }

    private func fallAsleep() {
        guard isRunning else { return }
        isAsleep = true
        isHappy = false
        isProud = false
        isInnocent = false
        updateFace()
        updatePose(animated: true)
        updateLoops()
    }

    private func listeningChanged() {
        guard isRunning else { return }
        if Self.isListening { wake() }
        updatePose(animated: true)
        updateLoops()
    }

    // MARK: Faces and poses

    /// Which eyes and mouth show. Kept with Reduce Motion.
    private func updateFace() {
        let shut = isAsleep || isSlowBlinking
        let happy = isHappy && !shut
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        openEyes.forEach { $0.isHidden = shut || happy }
        happyEyes.forEach { $0.isHidden = !happy }
        shutEyes.forEach { $0.isHidden = !shut }
        blushes.forEach { $0.isHidden = !isHappy }
        openMouth.isHidden = !isSayingMrrp
        flatMouth.isHidden = isSayingMrrp || !isInnocent
        smile.isHidden = !openMouth.isHidden || !flatMouth.isHidden
        CATransaction.commit()
        updateGaze(animated: false)
    }

    /// Head and ears: asleep it rests its head, proud it sits up, innocent it
    /// looks away, listening its ears go up. Still with Reduce Motion.
    private func updatePose(animated: Bool) {
        var headPose = CATransform3DIdentity
        var earsUp = false
        if !Self.reduceMotion {
            if isAsleep {
                headPose = CATransform3DRotate(CATransform3DMakeTranslation(0, -4, 0), CatPen.radians(-5), 0, 0, 1)
            } else if isProud {
                headPose = CATransform3DScale(CATransform3DMakeTranslation(0, 4, 0), 1.05, 1.05, 1)
            } else if isInnocent {
                headPose = CATransform3DMakeRotation(CatPen.radians(-7), 0, 0, 1)
            }
            earsUp = Self.isListening && !isAsleep
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.25 : 0)
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.3, 0.7, 0.4, 1))
        head.transform = headPose
        earL.transform = earsUp ? CATransform3DScale(CATransform3DMakeRotation(CatPen.radians(6), 0, 0, 1), 1, 1.1, 1) : CATransform3DIdentity
        earR.transform = earsUp ? CATransform3DScale(CATransform3DMakeRotation(CatPen.radians(-6), 0, 0, 1), 1, 1.1, 1) : CATransform3DIdentity
        CATransaction.commit()
        updateGaze(animated: animated)
    }

    /// Looks toward `point` on screen, a couple of grid points at most.
    private func look(at point: NSPoint) {
        guard let window, let eye = openEyes.first else { return }
        let eyeInView = CGPoint(x: art.position.x + eye.position.x * art.affineTransform().a,
                                y: art.position.y + eye.position.y * art.affineTransform().d)
        let center = window.convertPoint(toScreen: convert(eyeInView, to: nil))
        let dx = point.x - center.x, dy = point.y - center.y
        let distance = max(hypot(dx, dy), 1)
        let reach = min(1, distance / 120)
        gaze = CGPoint(x: dx / distance * 2 * reach, y: dy / distance * 1.6 * reach)
        updateGaze(animated: true)
    }

    private func updateGaze(animated: Bool) {
        let offset = isInnocent ? CGPoint(x: 2.6, y: 1.4) : gaze
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        CATransaction.setDisableActions(!animated || Self.reduceMotion)
        looks.forEach { $0.transform = CATransform3DMakeTranslation(offset.x, offset.y, 0) }
        CATransaction.commit()
    }

    // MARK: Moves (none with Reduce Motion)

    private enum PawMove { case bat, pat, swat }

    private func movePaw(_ move: PawMove) {
        let times: [NSNumber], x: [CGFloat], y: [CGFloat], degrees: [CGFloat], duration: CFTimeInterval
        switch move {
        case .bat:
            (times, duration) = ([0, 0.45, 1], 0.45)
            (x, y, degrees) = ([0, 5, 0], [0, 11, 0], [0, 28, 0])
        case .pat:
            (times, duration) = ([0, 0.25, 0.45, 0.65, 0.85, 1], 0.6)
            (x, y, degrees) = ([0, 2, 3, 2, 3, 0], [0, 9, 0, 6, 0, 0], [0, 12, 0, 8, 0, 0])
        case .swat:
            (times, duration) = ([0, 0.3, 0.58, 1], 0.55)
            (x, y, degrees) = ([0, 4, -18, 0], [0, 10, 6, 0], [0, -22, 36, 0])
        }
        play([Self.keyframes("transform.translation.x", x, at: times),
              Self.keyframes("transform.translation.y", y, at: times),
              Self.keyframes("transform.rotation.z", degrees.map(CatPen.radians), at: times)],
             on: pawR, duration: duration, key: "paw")
    }

    private func hop() {
        play([Self.keyframes("transform.translation.y", [0, 8, 0, 2, 0], at: [0, 0.35, 0.62, 0.8, 1])],
             on: whole, duration: 0.55, key: "hop")
        let perk: [NSNumber] = [0, 0.2, 0.7, 1]
        play([Self.keyframes("transform.rotation.z", [0, 8, 8, 0].map(CatPen.radians), at: perk)], on: earL, duration: 0.55, key: "perk")
        play([Self.keyframes("transform.rotation.z", [0, -8, -8, 0].map(CatPen.radians), at: perk)], on: earR, duration: 0.55, key: "perk")
    }

    private func twitch() {
        play([Self.keyframes("transform.rotation.z", [0, 9, 0].map(CatPen.radians), at: [0, 0.4, 1])], on: earL, duration: 0.25, key: "twitch")
    }

    private func purr(for seconds: Double) {
        let purr = Self.keyframes("transform.translation.x", [0, 0.6, 0], at: [0, 0.5, 1])
        purr.duration = 0.12
        purr.repeatCount = Float(seconds / 0.12)
        play([purr], on: body, duration: 0.12, key: "purr", repeating: true)
    }

    private func blink() {
        guard !isAsleep, !isHappy, !isSlowBlinking else { return }
        for eye in openEyes {
            let blink = CAKeyframeAnimation(keyPath: "transform.scale.y")
            blink.values = [1, 0.1, 1]
            blink.keyTimes = [0, 0.5, 1]
            blink.duration = 0.13
            eye.add(blink, forKey: "blink")
        }
    }

    private func play(_ animations: [CAAnimation], on layer: CALayer, duration: CFTimeInterval, key: String, repeating: Bool = false) {
        guard isRunning, !Self.reduceMotion else { return }
        if repeating, let only = animations.first {
            layer.add(only, forKey: key)
            return
        }
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(group, forKey: key)
    }

    /// Added to wherever the part is.
    private static func keyframes(_ keyPath: String, _ values: [CGFloat], at times: [NSNumber]) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = times
        animation.isAdditive = true
        return animation
    }

    // MARK: Things that go on: the tail, breathing, listening, blinking

    private func updateLoops() {
        let running = isRunning
        let moving = running && !Self.reduceMotion
        swing(tail, key: "sway", on: moving && !isAsleep, from: 5, to: -6, duration: 1.8)
        swing(head, key: "tilt", on: moving && !isAsleep && Self.isListening, from: 11, to: -7, duration: 1.2)
        if moving && isAsleep {
            if body.animation(forKey: "breathe") == nil {
                let breath = CABasicAnimation(keyPath: "transform.scale.y")
                breath.fromValue = 0
                breath.toValue = 0.035
                breath.isAdditive = true
                breath.duration = 1.6
                breath.autoreverses = true
                breath.repeatCount = .infinity
                breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                body.add(breath, forKey: "breathe")
            }
        } else {
            body.removeAnimation(forKey: "breathe")
        }
        loop("blink", on: running && !isAsleep && !Self.reduceMotion, every: 2.6...5.8) { [weak self] in self?.blink() }
        loop("z", on: running && isAsleep, every: 1.3...1.3) { [weak self] in self?.pop(.z) }
        loop("note", on: running && Self.isListening && !isAsleep, every: 1.6...1.6) { [weak self] in self?.pop(.note) }
    }

    /// Back and forth between two angles, forever, while `on`.
    private func swing(_ layer: CALayer, key: String, on: Bool, from: CGFloat, to: CGFloat, duration: CFTimeInterval) {
        guard on else { return layer.removeAnimation(forKey: key) }
        guard layer.animation(forKey: key) == nil else { return }
        let swing = CABasicAnimation(keyPath: "transform.rotation.z")
        swing.fromValue = CatPen.radians(from)
        swing.toValue = CatPen.radians(to)
        swing.isAdditive = true
        swing.duration = duration
        swing.autoreverses = true
        swing.repeatCount = .infinity
        swing.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(swing, forKey: key)
    }

    private func loop(_ key: String, on: Bool, every seconds: ClosedRange<Double>, _ action: @escaping @MainActor () -> Void) {
        guard on else {
            loops[key]?.cancel()
            loops[key] = nil
            return
        }
        guard loops[key] == nil else { return }
        loops[key] = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: seconds)))
                guard !Task.isCancelled else { return }
                action()
            }
        }
    }

    /// Runs `action` after a while; a newer call with the same key replaces it.
    private func after(_ seconds: Double, _ key: String, _ action: @escaping @MainActor () -> Void) {
        pending[key]?.cancel()
        pending[key] = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            action()
        }
    }

    // MARK: Little things that float up

    private enum Glyph {
        case bang, heart, spark, z, note, purr

        var text: String {
            switch self {
            case .bang: "!"
            case .heart: "♥"
            case .spark: "✦"
            case .z: "z"
            case .note: "♪"
            case .purr: "prrr"
            }
        }

        var color: NSColor {
            switch self {
            case .bang: .controlAccentColor
            case .heart: NSColor(srgbRed: 0.937, green: 0.365, blue: 0.478, alpha: 1)
            case .spark: NSColor(srgbRed: 0.96, green: 0.71, blue: 0, alpha: 1)
            case .z, .note, .purr: .secondaryLabelColor
            }
        }

        var size: CGFloat { self == .purr ? 10 : self == .bang ? 15 : 12 }
    }

    /// Floats up beside its head and fades; with Reduce Motion it only fades.
    private func pop(_ glyph: Glyph, count: Int = 1) {
        guard isRunning, let host = layer else { return }
        let unit = bounds.height / CatPen.grid.height
        // Left of and above the head, over the header's empty space.
        let spots = [CGPoint(x: -6, y: 0.66), CGPoint(x: -18, y: 0.5), CGPoint(x: 6, y: 0.86)]
        var color = CGColor(gray: 0.5, alpha: 1)
        effectiveAppearance.performAsCurrentDrawingAppearance { color = glyph.color.cgColor }
        for index in 0..<count {
            let text = CATextLayer()
            let string = NSAttributedString(string: glyph.text, attributes: [
                .font: NSFont.systemFont(ofSize: glyph.size * unit * 76 / 42, weight: .bold),
                .foregroundColor: NSColor(cgColor: color) ?? .secondaryLabelColor,
            ])
            text.string = string
            text.alignmentMode = .center
            text.contentsScale = window?.backingScaleFactor ?? 2
            let size = string.size()
            text.bounds = CGRect(x: 0, y: 0, width: ceil(size.width) + 2, height: ceil(size.height))
            let spot = spots[index % spots.count]
            text.position = CGPoint(x: spot.x * unit * 76 / 42, y: bounds.height * spot.y)
            text.opacity = 0
            host.addSublayer(text)

            let duration: CFTimeInterval = glyph == .z ? 2.6 : 1.5
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 0]
            fade.keyTimes = [0, 0.15, 1]
            var animations: [CAAnimation] = [fade]
            if !Self.reduceMotion {
                animations.append(Self.keyframes("transform.translation.y", [-3, 0, 14 * unit * 76 / 42], at: [0, 0.15, 1]))
                animations.append(Self.keyframes("transform.scale", [-0.3, 0, 0.05], at: [0, 0.15, 1]))
            }
            let group = CAAnimationGroup()
            group.animations = animations
            group.duration = duration
            group.beginTime = CACurrentMediaTime() + Double(index) * 0.18
            group.fillMode = .backwards
            text.add(group, forKey: "pop")
            Task {
                try? await Task.sleep(for: .seconds(duration + Double(index) * 0.18 + 0.1))
                text.removeFromSuperlayer()
            }
        }
    }

    // MARK: The pointer and clicks

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let pointerArea { pointerHost?.removeTrackingArea(pointerArea) }
        pointerArea = nil
        // Its eyes follow the pointer anywhere over the panel.
        if let content = window?.contentView {
            let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
            content.addTrackingArea(area)
            pointerArea = area
            pointerHost = content
        }
        viewDidChangeBackingProperties()
        restart()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard isRunning, !isAsleep else { return }
        look(at: NSEvent.mouseLocation)
    }

    override func mouseEntered(with event: NSEvent) {
        guard isRunning else { return }
        if isAsleep { wake() } else { twitch() }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        pet()
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { isAsleep ? "Cat, asleep" : "Cat" }
    override func accessibilityHelp() -> String? { "Pet the cat" }
    override func accessibilityPerformPress() -> Bool {
        pet()
        return true
    }
}

/// Draws the cat's shapes from the mock-up's grid (120 × 76, y down) in Core
/// Animation's coordinates (y up), around an origin for parts drawn about
/// their own middle (the head at 41, 36).
struct CatPen {
    static let grid = CGSize(width: 120, height: 76)

    let path = CGMutablePath()
    private let origin: (x: CGFloat, y: CGFloat)

    init(_ origin: (x: CGFloat, y: CGFloat) = (0, 0), _ draw: (CatPen) -> Void) {
        self.origin = origin
        draw(self)
    }

    static func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x, y: grid.height - y)
    }

    private func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        Self.point(origin.x + x, origin.y + y)
    }

    func m(_ x: CGFloat, _ y: CGFloat) { path.move(to: at(x, y)) }
    func l(_ x: CGFloat, _ y: CGFloat) { path.addLine(to: at(x, y)) }
    func q(_ cx: CGFloat, _ cy: CGFloat, _ x: CGFloat, _ y: CGFloat) { path.addQuadCurve(to: at(x, y), control: at(cx, cy)) }
    func c(_ c1x: CGFloat, _ c1y: CGFloat, _ c2x: CGFloat, _ c2y: CGFloat, _ x: CGFloat, _ y: CGFloat) {
        path.addCurve(to: at(x, y), control1: at(c1x, c1y), control2: at(c2x, c2y))
    }
    func z() { path.closeSubpath() }
    func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) {
        let center = at(cx, cy)
        path.addEllipse(in: CGRect(x: center.x - rx, y: center.y - ry, width: 2 * rx, height: 2 * ry))
    }

    /// A layer the size of the grid that turns and moves about `pivot`, so
    /// shapes drawn on it stay at their grid points.
    static func part(pivot: CGPoint) -> CALayer {
        let layer = CALayer()
        layer.bounds = CGRect(origin: .zero, size: grid)
        layer.anchorPoint = CGPoint(x: pivot.x / grid.width, y: pivot.y / grid.height)
        layer.position = pivot
        return layer
    }

    static func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    static func radians(_ degrees: CGFloat) -> CGFloat { degrees * .pi / 180 }
}

private extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
