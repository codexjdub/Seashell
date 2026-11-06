import AppKit
import SeashellCore

/// The cat by the notes (Settings ▸ "Show a cat by your notes", off at first):
/// a grey tabby with white socks, lying like a loaf on the Notes header. It
/// keeps you company and reacts to what you do:
///
/// - It watches: its eyes follow the pointer over the panel, and the text
///   cursor as you type. It blinks now and then.
/// - Typing twitches an ear, and now and then (`CatPace`) it bats a paw at
///   your line.
/// - A new note: it hops into a note-shaped box for a moment. A to-do ticked:
///   a paw pat and a sparkle; ticking the last one gets happy eyes, hearts and
///   a purr.
/// - Pinning a note: it sits up proud and gives a slow blink. Moving one to
///   the Trash: it swats, then looks away as if nothing happened.
/// - Read Aloud: ears up, its head tilting while it listens.
/// - Clicking it pets it; a few pets in a row (`PetStreak`) and it kneads.
/// - Shelves: it nods at something dropped onto a shelf in the panel, waves a
///   paw at something dragged out of one, watches a file dragged over the
///   panel from another app and pounces as it comes near (`CatPounce`), and
///   puffs up when a big batch arrives (`ArrivalBurst`).
/// - Left alone, it grooms or plays with a pencil once (`CatIdle`); after a
///   few minutes it rests its chin on its paws, dozes off and tucks its tail
///   round. Typing, hovering over it or something arriving wakes it, with a
///   yawn and a stretch.
/// - A Santa hat in December, a pumpkin in October (`CatHat`).
///
/// Drawn in code from the mock-up's shapes, on a 120 × 76 grid drawn with y
/// down and flipped to Core Animation's y up. Each part that moves (tail, body,
/// paws, head, ears, eyes) is its own layer, pivoting where it would. With
/// Reduce Motion it keeps its faces but doesn't move, and has no idle moves.
@MainActor
final class NotesCat: NSView {
    enum Reaction {
        case newNote
        case ticked(allDone: Bool)
        case pinned
        case trashed
        /// Something dropped onto a shelf in the panel.
        case shelfDrop
        /// Something dragged out of a shelf.
        case dragOut
    }

    /// As wide as this for each point of height.
    static let aspect = CatPen.grid.width / CatPen.grid.height

    /// Every cat there is (one, in the panel), for Read Aloud, arrivals and drags.
    private static let all = NSHashTable<NotesCat>.weakObjects()
    /// Read Aloud is reading: the cat listens.
    static var isListening = false {
        didSet {
            guard isListening != oldValue else { return }
            all.allObjects.forEach { $0.listeningChanged() }
        }
    }

    private static var arrivals = 0
    /// How many things have arrived on the shelves since the panel was last
    /// open: more wakes a dozing cat; a big batch at once puffs it up.
    static func arrivalsChanged(to count: Int) {
        defer { arrivals = count }
        guard count > arrivals else { return }
        let big = ArrivalBurst.isBig(from: arrivals, to: count)
        all.allObjects.forEach { big ? $0.puffUp() : $0.wake() }
    }

    /// A drag from another app moved to `point` on screen.
    static func dragMoved(to point: NSPoint) {
        all.allObjects.forEach { $0.dragMoved(to: point) }
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
    /// The right paw held up to the face, for grooming.
    private let groomPaw = CatPen.part(pivot: CatPen.point(52, 62))
    /// Both paws under the chin, for resting it on them.
    private let pawsFront = CatPen.part(pivot: CatPen.point(41, 70))
    private let box = CatPen.part(pivot: CatPen.point(60, 77))
    private let pencil = CatPen.part(pivot: CatPen.point(4, 72))
    private let pumpkin = CatPen.part(pivot: CatPen.point(9, 76))
    private let santa = CALayer()
    private var tailShapes: [CAShapeLayer] = []
    private var fuzz = CAShapeLayer()
    private var openEyes: [CALayer] = []
    private var looks: [CALayer] = []
    private var happyEyes: [CAShapeLayer] = []
    private var shutEyes: [CAShapeLayer] = []
    private var lids: [CAShapeLayer] = []
    private var blushes: [CAShapeLayer] = []
    private var smile = CAShapeLayer()
    private var flatMouth = CAShapeLayer()
    private var openMouth = CAShapeLayer()
    private let yawnMouth = CALayer()
    private var tongue = CAShapeLayer()

    /// The tail upright (as it sits), lying on the ledge behind, and tucked
    /// round behind the body with its tip by the front paw. Same number of
    /// points each, so one turns into the next.
    private static let tailUp = CatPen { $0.m(96, 52); $0.c(108, 47, 117, 35, 111, 22); $0.c(109, 18, 105, 18, 104, 21) }.path
    private static let tailDown = CatPen { $0.m(99, 68); $0.c(110, 73, 122, 75.5, 131, 74); $0.c(135, 73.3, 138, 72, 138.5, 69.5) }.path
    private static let tailTucked = CatPen { $0.m(99, 68); $0.c(111, 74, 96, 70, 72, 69); $0.c(40, 68, 3, 73, 7, 57.5) }.path

    private enum Ink {
        case fur, tailLine, tailFur, stripe, sock, muzzle, earInside, eye, eyeLine, glint, nose, blush, mouthInside, whisker
        case fuzz, toe, yawnInside, tongue, hatRed, hatTrim, boxFace, boxFlap, boxFold, boxLine
        case pencilWood, pencilTip, pencilLead, pencilBand, pencilRubber, pumpkin, pumpkinStem
    }
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
    private var isYawning = false
    private var isStretching = false
    private var isGrooming = false
    private var isLicking = false
    private var isDrowsy = false
    private var isChinDown = false
    private var isPuffed = false
    private var isHunting = false
    private var isBoxed = false
    /// Looking straight at you, after knocking the pencil off.
    private var isStaring = false
    /// Where the eyes look, in grid points from the middle.
    private var gaze = CGPoint.zero
    private var pace = CatPace()
    private var petStreak = PetStreak()
    private var pounce = CatPounce()
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
        resetProps()
        updateFace()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Drawing

    private func draw() {
        // The tail, upright behind the body: an outline, then the fur.
        tailShapes = [shape(Self.tailUp, .tailLine, in: tail, width: 9.4), shape(Self.tailUp, .tailFur, in: tail, width: 7)]
        let bodyPath = CatPen {
            $0.m(16, 63); $0.c(16, 41, 38, 33, 64, 33); $0.c(90, 33, 107, 43, 107, 59)
            $0.c(107, 69, 97, 73.5, 83, 73.5); $0.l(28, 73.5); $0.c(20, 73.5, 16, 69, 16, 63); $0.z()
        }.path
        // Puffed up, a dashed outline round the body reads as fur on end.
        fuzz = shape(bodyPath, .fuzz, in: body, width: 5)
        fuzz.lineDashPattern = [1.6, 1.5]
        fuzz.lineCap = .butt
        shape(bodyPath, .fur, in: body, width: 1.3)
        shape(CatPen {
            $0.m(70, 35); $0.q(75, 41, 72, 48); $0.m(82, 37); $0.q(87, 43, 84, 50); $0.m(93, 42); $0.q(97, 47, 95, 53)
        }.path, .stripe, in: body, width: 2)
        shape(CatPen { $0.ellipse(31, 71.5, 8, 4.6) }.path, .sock, in: pawL, width: 1.1)
        shape(CatPen { $0.ellipse(52, 72, 8, 4.6) }.path, .sock, in: pawR, width: 1.1)
        drawPumpkin()
        drawPencil()
        drawHead()
        shape(CatPen { $0.ellipse(52, 62, 7.6, 4.8, turn: -30) }.path, .sock, in: groomPaw, width: 1.1)
        shape(CatPen { $0.m(47.6, 60.2); $0.l(49.2, 62.4); $0.m(50.6, 58.6); $0.l(52.2, 60.8) }.path, .toe, in: groomPaw, width: 0.9)
        shape(CatPen { $0.ellipse(33, 69.5, 7.6, 4.4); $0.ellipse(49, 69.8, 7.6, 4.4) }.path, .sock, in: pawsFront, width: 1.1)
        // Front to back: the raised paw goes in front of the face.
        for part in [tail, body, pumpkin, pencil, pawL, head, pawR, groomPaw, pawsFront] { whole.addSublayer(part) }
        drawBox()
        art.addSublayer(box)
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
            // Sleepy: an eyelid most of the way down, its edge curving down.
            lids.append(shape(CatPen(center) {
                $0.m(-6.3, 0.8); $0.c(-6.6, -3.5, -3.6, -6.4, 0, -6.4); $0.c(3.6, -6.4, 6.6, -3.5, 6.3, 0.8); $0.q(0, 4.2, -6.3, 0.8); $0.z()
            }.path, .fur, in: head, width: 1))
        }
        shape(CatPen(at) { $0.m(-2.8, 4.6); $0.q(0, 3.6, 2.8, 4.6); $0.q(1.3, 7.6, 0, 7.8); $0.q(-1.3, 7.6, -2.8, 4.6); $0.z() }.path,
              .nose, in: head)
        smile = shape(CatPen(at) { $0.m(0, 7.8); $0.q(-1.6, 10.8, -4.8, 10); $0.m(0, 7.8); $0.q(1.6, 10.8, 4.8, 10) }.path,
                      .eyeLine, in: head, width: 1.2)
        flatMouth = shape(CatPen(at) { $0.m(-3.6, 10.2); $0.l(3.6, 10.2) }.path, .eyeLine, in: head, width: 1.2)
        openMouth = shape(CatPen(at) { $0.ellipse(0, 11.4, 2.1, 2.4) }.path, .mouthInside, in: head)
        yawnMouth.frame = CGRect(origin: .zero, size: CatPen.grid)
        shape(CatPen(at) { $0.ellipse(0, 12.6, 5.2, 6.6) }.path, .yawnInside, in: yawnMouth)
        shape(CatPen(at) { $0.ellipse(0, 16.2, 3.4, 2.6) }.path, .tongue, in: yawnMouth)
        head.addSublayer(yawnMouth)
        // Licking: the tongue pokes out towards the raised paw.
        tongue = shape(CatPen(at) { $0.m(0.4, 9.4); $0.q(0.6, 14.6, 3.6, 14.4); $0.q(6.2, 13.8, 3.8, 9.2); $0.z() }.path, .tongue, in: head)
        let whiskers = shape(CatPen(at) {
            $0.m(-13, 8.5); $0.l(-28, 6); $0.m(-13, 11); $0.l(-28, 12.6); $0.m(13, 8.5); $0.l(28, 6); $0.m(13, 11); $0.l(28, 12.6)
        }.path, .whisker, in: head, width: 0.8)
        whiskers.opacity = 0.8
        // A Santa hat, tipped over the right ear.
        santa.frame = CGRect(origin: .zero, size: CatPen.grid)
        let hat = (x: at.x + 4, y: at.y - 21)
        shape(CatPen(hat, turn: 13) { $0.m(-13, 0); $0.c(-9, -9, -1, -20, 10, -25); $0.c(8, -17, 9, -8, 13, 0); $0.z() }.path,
              .hatRed, in: santa, width: 1)
        shape(CatPen(hat, turn: 13) { $0.roundedRect(-15, -3.5, 30, 7, radius: 3.5); $0.ellipse(10, -25, 4.2, 4.2) }.path,
              .hatTrim, in: santa, width: 0.8)
        head.addSublayer(santa)
    }

    /// A pencil lying on the header in front of the left paw, for knocking off.
    private func drawPencil() {
        let at = (x: CGFloat(4), y: CGFloat(71.8))
        shape(CatPen(at) { $0.m(0, -3.2); $0.l(-7.5, 0); $0.l(0, 3.2); $0.z() }.path, .pencilTip, in: pencil, width: 0.8)
        shape(CatPen(at) { $0.m(-5.4, -0.9); $0.l(-7.5, 0); $0.l(-5.4, 0.9); $0.z() }.path, .pencilLead, in: pencil)
        shape(CatPen(at) { $0.m(0, -3.2); $0.l(24, -3.2); $0.l(24, 3.2); $0.l(0, 3.2); $0.z() }.path, .pencilWood, in: pencil, width: 0.8)
        shape(CatPen(at) { $0.m(24, -3.2); $0.l(26.6, -3.2); $0.l(26.6, 3.2); $0.l(24, 3.2); $0.z() }.path, .pencilBand, in: pencil)
        shape(CatPen(at) {
            $0.m(26.6, -3.2); $0.l(29.6, -3.2); $0.q(31.4, -3.2, 31.4, 0); $0.q(31.4, 3.2, 29.6, 3.2); $0.l(26.6, 3.2); $0.z()
        }.path, .pencilRubber, in: pencil, width: 0.8)
    }

    /// A small pumpkin beside its front paws, for October.
    private func drawPumpkin() {
        let at = (x: CGFloat(9), y: CGFloat(66.4))
        for (x, rx, ry) in [(CGFloat(-5.5), CGFloat(6.6), CGFloat(8.6)), (5.5, 6.6, 8.6), (0, 6.4, 9.2)] {
            shape(CatPen(at) { $0.ellipse(x, 0, rx, ry) }.path, .pumpkin, in: pumpkin, width: 1)
        }
        shape(CatPen(at) { $0.m(0, -8.6); $0.c(0, -11.5, 1.5, -13.5, 3.8, -13.8) }.path, .pumpkinStem, in: pumpkin, width: 2.4)
    }

    /// An open note-yellow box with its flaps up, for a new note.
    private func drawBox() {
        shape(CatPen {
            $0.m(12, 52); $0.l(1, 41); $0.l(14, 38.5); $0.l(22, 52); $0.z()
            $0.m(108, 52); $0.l(119, 41); $0.l(106, 38.5); $0.l(98, 52); $0.z()
        }.path, .boxFlap, in: box, width: 1.2)
        shape(CatPen { $0.m(12, 52); $0.l(108, 52); $0.l(108, 77); $0.l(12, 77); $0.z() }.path, .boxFace, in: box, width: 1.2)
        shape(CatPen { $0.m(22, 61); $0.l(98, 61); $0.m(22, 67.5); $0.l(98, 67.5) }.path, .boxLine, in: box, width: 1)
        shape(CatPen { $0.m(96, 77); $0.l(108, 65); $0.l(108, 77); $0.z() }.path, .boxFold, in: box, width: 1)
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
        let boxEdge = CatPen.color(0xB48E24)
        let pencilEdge = CatPen.color(0xB98A12)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (layer, ink) in inked {
            var fill: CGColor?
            var stroke: CGColor?
            switch ink {
            case .fur: fill = fur; stroke = line
            case .tailLine, .fuzz, .whisker, .toe: stroke = line
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
            case .yawnInside: fill = CatPen.color(0x8C3445)
            case .tongue: fill = CatPen.color(0xEF8FA0)
            case .hatRed: fill = CatPen.color(0xD9363E); stroke = CatPen.color(0x8F1D24)
            case .hatTrim: fill = CatPen.color(0xFBFBFB); stroke = CatPen.color(0xC9C9CF)
            case .boxFace: fill = CatPen.color(0xF7E7A6); stroke = boxEdge
            case .boxFlap: fill = CatPen.color(0xEAD58A); stroke = boxEdge
            case .boxFold: fill = CatPen.color(0xE3CB78); stroke = boxEdge
            case .boxLine: stroke = CatPen.color(0x967014, alpha: 0.45)
            case .pencilWood: fill = CatPen.color(0xF6C343); stroke = pencilEdge
            case .pencilTip: fill = CatPen.color(0xEDD2A6); stroke = pencilEdge
            case .pencilLead: fill = CatPen.color(0x3A3A3F)
            case .pencilBand: fill = CatPen.color(0xC7C9CF)
            case .pencilRubber: fill = CatPen.color(0xF19AA8); stroke = CatPen.color(0xC06878)
            case .pumpkin: fill = CatPen.color(0xF08A24); stroke = CatPen.color(0xB4561A)
            case .pumpkinStem: stroke = CatPen.color(0x5B8C3A)
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
        let hat = CatHat.on(.now)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        santa.isHidden = hat != .santa
        pumpkin.isHidden = hat != .pumpkin
        CATransaction.commit()
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
        isYawning = false
        isStretching = false
        isGrooming = false
        isLicking = false
        isDrowsy = false
        isChinDown = false
        isPuffed = false
        isHunting = false
        isBoxed = false
        isStaring = false
        pounce.ended()
        updateLoops()
        resetProps()
        updateFace()
        updatePose(animated: false)
        for part in [whole, body, pawL, pawR, head, earL, earR, tail, pencil, box, groomPaw] { part.removeAllAnimations() }
        tailShapes.forEach { $0.removeAllAnimations() }
    }

    /// The things that come and go, put away: box, pencil, raised paw, tail up.
    private func resetProps() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        box.opacity = 0
        box.transform = CATransform3DMakeScale(1, 0.3, 1)
        pencil.opacity = 0
        pencil.transform = CATransform3DIdentity
        groomPaw.opacity = 0
        groomPaw.transform = CATransform3DIdentity
        pawL.opacity = 1
        pawR.opacity = 1
        pawsFront.opacity = 0
        fuzz.opacity = 0
        setTail(puffed: false)
        tailShapes.forEach { $0.path = Self.tailUp }
        CATransaction.commit()
    }

    // MARK: Reactions

    func react(_ reaction: Reaction) {
        guard isRunning else { return }
        stopIdleMove()
        wake(yawning: false)
        switch reaction {
        case .newNote:
            hopIntoBox()
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
        case .shelfDrop:
            nod()
        case .dragOut:
            movePaw(.wave)
        }
    }

    /// A key typed in the note; `caret` is where the text cursor is on screen.
    func typed(caret: NSRect?) {
        guard isRunning else { return }
        stopIdleMove()
        wake()
        twitch()
        if let caret, caret.width.isFinite, caret != .zero { look(at: NSPoint(x: caret.midX, y: caret.midY)) }
        if pace.key(at: ProcessInfo.processInfo.systemUptime) { movePaw(.bat) }
    }

    private func pet() {
        guard isRunning else { return }
        guard !isAsleep else { return wake() }
        stopIdleMove()
        stopDozing()
        restartDozing()
        if petStreak.pet(at: ProcessInfo.processInfo.systemUptime) {
            knead()
        } else {
            beHappy(for: 1.9, hearts: 2)
        }
    }

    private func beHappy(for seconds: Double, hearts: Int) {
        isHappy = true
        updateFace()
        purr(for: seconds * 0.7)
        pop(.heart, count: hearts)
        after(0.3, "purr word") { [weak self] in self?.pop(.purr) }
        after(seconds, "happy") { [weak self] in self?.isHappy = false; self?.updateFace() }
    }

    /// Wakes it if it's asleep or dozing off. Woken gently (typing, hovering,
    /// petting, an arrival) it yawns and stretches; woken by something you
    /// did with a note or shelf it just gets up.
    private func wake(yawning: Bool = true) {
        guard isRunning else { return }
        stopDozing()
        if isAsleep {
            isAsleep = false
            moveTail(through: [Self.tailDown, Self.tailUp], duration: 0.9)
            updateLoops()
            if yawning {
                yawnAndStretch()
            } else {
                updateFace()
                updatePose(animated: true)
                hop()
            }
        }
        restartDozing()
    }

    /// Something happened: it dozes off after a while of nothing more, and
    /// somewhere along the way does one idle move.
    private func restartDozing() {
        after(CatIdle.dozeAfter, "doze") { [weak self] in self?.dozeOff() }
        after(CatIdle.moment(), "idle") { [weak self] in self?.idleMove() }
    }

    /// Chin on paws, eyelids drooping, then asleep.
    private func dozeOff() {
        run("doze") { cat in
            guard !cat.isAsleep else { return }
            cat.stopIdleMove()
            cat.isChinDown = true
            cat.setChinPaws(true)
            cat.updatePose(animated: true, duration: 0.8)
            guard await cat.pause(0.7) else { return }
            cat.isDrowsy = true
            cat.updateFace()
            guard await cat.pause(1.2) else { return }
            cat.isDrowsy = false
            cat.isChinDown = false
            cat.setChinPaws(false)
            cat.fallAsleep()
        }
    }

    /// Stops dozing off, if it had started to.
    private func stopDozing() {
        guard isChinDown || isDrowsy else { return }
        pending["doze"]?.cancel()
        isChinDown = false
        isDrowsy = false
        setChinPaws(false)
        updateFace()
        updatePose(animated: true)
    }

    private func setChinPaws(_ on: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        CATransaction.setDisableActions(Self.reduceMotion)
        pawsFront.opacity = on ? 1 : 0
        pawL.opacity = on ? 0 : 1
        pawR.opacity = on || isGrooming ? 0 : 1
        CATransaction.commit()
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
        // Its tail down onto the ledge, then round behind it until the tip curls up by its front paw.
        moveTail(through: [Self.tailDown, Self.tailTucked], duration: 1.65)
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
        let shut = isAsleep || isSlowBlinking || isYawning || isGrooming
        let happy = isHappy && !shut
        let mouthBusy = isYawning || isLicking
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        openEyes.forEach { $0.isHidden = shut || happy }
        happyEyes.forEach { $0.isHidden = !happy }
        shutEyes.forEach { $0.isHidden = !shut }
        lids.forEach { $0.isHidden = !isDrowsy || shut }
        blushes.forEach { $0.isHidden = !isHappy }
        let wide: CGFloat = isPuffed || isHunting ? 1.18 : 1
        openEyes.forEach { $0.transform = CATransform3DMakeScale(wide, wide, 1) }
        yawnMouth.isHidden = !isYawning
        tongue.isHidden = !isLicking || isYawning
        openMouth.isHidden = !isSayingMrrp || mouthBusy
        flatMouth.isHidden = !(isInnocent || isStaring) || isSayingMrrp || mouthBusy
        smile.isHidden = !openMouth.isHidden || !flatMouth.isHidden || mouthBusy
        CATransaction.commit()
        updateGaze(animated: false)
    }

    /// Head, ears, body and paws for what it's doing. Still with Reduce Motion.
    private func updatePose(animated: Bool, duration: CFTimeInterval = 0.25) {
        var headPose = CATransform3DIdentity
        var wholePose = CATransform3DIdentity
        var bodyPose = CATransform3DIdentity
        var pawShift: CGFloat = 0
        var earTurn: CGFloat = 0  // degrees, outward
        var earsUp = false
        if !Self.reduceMotion {
            if isAsleep {
                headPose = Self.pose(y: -4, degrees: -5)
                earTurn = 9
            } else if isChinDown {
                headPose = Self.pose(y: -7, degrees: -3)
                earTurn = 9
            } else if isGrooming {
                headPose = Self.pose(x: 3, y: -6, degrees: -10)
            } else if isStretching {
                headPose = Self.pose(x: -3, y: 2, degrees: 9)
            } else if isHunting {
                headPose = Self.pose(y: -3)
                earTurn = -6
            } else if isProud {
                headPose = CATransform3DScale(CATransform3DMakeTranslation(0, 4, 0), 1.05, 1.05, 1)
            } else if isInnocent {
                headPose = CATransform3DMakeRotation(CatPen.radians(-7), 0, 0, 1)
            }
            if isYawning { earTurn = 14 }
            if isPuffed { earTurn = 24 }
            earsUp = Self.isListening && !isAsleep && earTurn == 0
            if isStretching {
                pawShift = -11
                bodyPose = CATransform3DScale(CATransform3DMakeTranslation(-2.3, 0, 0), 1.05, 1, 1)
            }
            if isPuffed {
                wholePose = CATransform3DMakeScale(1.08, 1.08, 1)
            } else if isBoxed {
                wholePose = CATransform3DMakeTranslation(0, -7, 0)
            }
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? duration : 0)
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.3, 0.7, 0.4, 1))
        head.transform = headPose
        whole.transform = wholePose
        body.transform = bodyPose
        pawL.transform = CATransform3DMakeTranslation(pawShift, 0, 0)
        pawR.transform = CATransform3DMakeTranslation(pawShift, 0, 0)
        if earsUp {
            earL.transform = CATransform3DScale(CATransform3DMakeRotation(CatPen.radians(6), 0, 0, 1), 1, 1.1, 1)
            earR.transform = CATransform3DScale(CATransform3DMakeRotation(CatPen.radians(-6), 0, 0, 1), 1, 1.1, 1)
        } else {
            earL.transform = CATransform3DMakeRotation(CatPen.radians(earTurn), 0, 0, 1)
            earR.transform = CATransform3DMakeRotation(CatPen.radians(-earTurn), 0, 0, 1)
        }
        CATransaction.commit()
        updateGaze(animated: animated)
    }

    /// Moved by `x`, `y` (grid points, y up) and turned `degrees` (counterclockwise).
    private static func pose(x: CGFloat = 0, y: CGFloat = 0, degrees: CGFloat = 0) -> CATransform3D {
        CATransform3DRotate(CATransform3DMakeTranslation(x, y, 0), CatPen.radians(degrees), 0, 0, 1)
    }

    /// Looks toward `point` on screen, a couple of grid points at most.
    private func look(at point: NSPoint) {
        guard let center = onScreen(eyes: true) else { return }
        let dx = point.x - center.x, dy = point.y - center.y
        let distance = max(hypot(dx, dy), 1)
        let reach = min(1, distance / 120)
        gaze = CGPoint(x: dx / distance * 2 * reach, y: dy / distance * 1.6 * reach)
        updateGaze(animated: true)
    }

    /// Where its eyes (or the middle of its head) are on screen.
    private func onScreen(eyes: Bool) -> NSPoint? {
        guard let window, let eye = openEyes.first else { return nil }
        let grid = eyes ? eye.position : CatPen.point(41, 40)
        let inView = CGPoint(x: art.position.x + grid.x * art.affineTransform().a,
                             y: art.position.y + grid.y * art.affineTransform().d)
        return window.convertPoint(toScreen: convert(inView, to: nil))
    }

    private func updateGaze(animated: Bool) {
        let offset = isInnocent ? CGPoint(x: 2.6, y: 1.4) : isStaring ? .zero : isDrowsy ? CGPoint(x: 0, y: -1) : gaze
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        CATransaction.setDisableActions(!animated || Self.reduceMotion)
        looks.forEach { $0.transform = CATransform3DMakeTranslation(offset.x, offset.y, 0) }
        CATransaction.commit()
    }

    /// The tail through `paths` in turn, ending on the last; straight there with Reduce Motion.
    private func moveTail(through paths: [CGPath], duration: CFTimeInterval) {
        guard let last = paths.last else { return }
        for layer in tailShapes {
            if isRunning, !Self.reduceMotion, let from = layer.presentation()?.path ?? layer.path {
                let move = CAKeyframeAnimation(keyPath: "path")
                move.values = [from] + paths
                if paths.count == 2 { move.keyTimes = [0, 0.4, 1] }
                move.duration = duration
                move.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: paths.count)
                layer.add(move, forKey: "tail shape")
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.path = last
            CATransaction.commit()
        }
    }

    /// A bottle-brush tail when puffed up.
    private func setTail(puffed: Bool) {
        guard tailShapes.count == 2 else { return }
        tailShapes[0].lineWidth = puffed ? 18 : 9.4
        tailShapes[0].lineDashPattern = puffed ? [1.8, 1.5] : nil
        tailShapes[0].lineCap = puffed ? .butt : .round
        tailShapes[1].lineWidth = puffed ? 12 : 7
    }

    // MARK: Moves (none with Reduce Motion)

    private enum PawMove { case bat, pat, swat, wave }

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
        case .wave:
            // Up, a little wave side to side, and down: bye-bye.
            (times, duration) = ([0, 0.2, 0.38, 0.56, 0.74, 1], 1.1)
            (x, y, degrees) = ([0, 3, 3, 3, 3, 0], [0, 12, 12, 12, 12, 0], [0, 18, 38, 14, 36, 0])
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

    /// A couple of nods, with happy eyes: that'll do.
    private func nod() {
        play([Self.keyframes("transform.translation.y", [0, -3, 0, -2.5, 0], at: [0, 0.25, 0.5, 0.75, 1])],
             on: head, duration: 0.7, key: "nod")
        isHappy = true
        updateFace()
        after(0.9, "happy") { [weak self] in self?.isHappy = false; self?.updateFace() }
    }

    private func purr(for seconds: Double) {
        let purr = Self.keyframes("transform.translation.x", [0, 0.6, 0], at: [0, 0.5, 1])
        purr.duration = 0.12
        purr.repeatCount = Float(seconds / 0.12)
        play([purr], on: body, duration: 0.12, key: "purr", repeating: true)
    }

    private func blink() {
        guard !isAsleep, !isHappy, !isSlowBlinking, !isYawning, !isGrooming else { return }
        for eye in openEyes {
            let blink = CAKeyframeAnimation(keyPath: "transform.scale.y")
            blink.values = [1, 0.1, 1]
            blink.keyTimes = [0, 0.5, 1]
            blink.duration = 0.13
            eye.add(blink, forKey: "blink")
        }
    }

    /// Woken up: a big yawn with its ears back, front paws sliding out.
    private func yawnAndStretch() {
        run("yawn") { cat in
            cat.isYawning = true
            cat.isStretching = true
            cat.updateFace()
            cat.updatePose(animated: true, duration: 0.5)
            guard await cat.pause(1.3) else { return }
            cat.isYawning = false
            cat.updateFace()
            cat.updatePose(animated: true)
            guard await cat.pause(0.15) else { return }
            cat.isStretching = false
            cat.updatePose(animated: true, duration: 0.45)
            guard await cat.pause(0.6) else { return }
            cat.blink()
        }
    }

    /// Petted again and again: left paw, right paw, purring with happy eyes.
    private func knead() {
        run("knead") { cat in
            cat.isHappy = true
            cat.updateFace()
            cat.purr(for: 2)
            cat.pop(.purr)
            for step in 0..<6 {
                cat.play([Self.keyframes("transform.translation.y", [0, 4, 4, 0], at: [0, 0.3, 0.7, 1])],
                         on: step.isMultiple(of: 2) ? cat.pawL : cat.pawR, duration: 0.3, key: "knead")
                if step == 1 || step == 4 { cat.pop(.heart) }
                guard await cat.pause(0.32) else { return }
            }
            guard await cat.pause(0.3) else { return }
            cat.isHappy = false
            cat.updateFace()
        }
    }

    /// A big batch arrived: a startled hop, fur and tail on end, then it settles.
    private func puffUp() {
        guard isRunning else { return }
        stopIdleMove()
        wake(yawning: false)
        run("puff") { cat in
            cat.isPuffed = true
            cat.isSayingMrrp = true
            cat.updateFace()
            cat.updatePose(animated: true, duration: 0.2)
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.2)
            CATransaction.setDisableActions(Self.reduceMotion)
            cat.fuzz.opacity = 1
            cat.setTail(puffed: true)
            CATransaction.commit()
            cat.hop()
            cat.pop(.bang)
            guard await cat.pause(1.1) else { return }
            cat.isPuffed = false
            cat.isSayingMrrp = false
            cat.updateFace()
            cat.updatePose(animated: true, duration: 0.5)
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.5)
            CATransaction.setDisableActions(Self.reduceMotion)
            cat.fuzz.opacity = 0
            cat.setTail(puffed: false)
            CATransaction.commit()
            guard await cat.pause(0.6) else { return }
            cat.blink()
        }
    }

    /// A new note: it hops into a note-shaped box for a moment, pleased.
    private func hopIntoBox() {
        run("box") { cat in
            cat.isBoxed = true
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.3)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.3, 1.4, 0.5, 1))
            CATransaction.setDisableActions(Self.reduceMotion)
            cat.box.opacity = 1
            cat.box.transform = CATransform3DIdentity
            cat.boxPaws(hidden: true)
            CATransaction.commit()
            cat.updatePose(animated: true, duration: 0.3)
            cat.hop()
            guard await cat.pause(0.4) else { return }
            cat.isHappy = true
            cat.updateFace()
            cat.pop(.note)
            guard await cat.pause(1.6) else { return }
            cat.isHappy = false
            cat.updateFace()
            guard await cat.pause(0.3) else { return }
            cat.isBoxed = false
            cat.updatePose(animated: true, duration: 0.3)
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.25)
            CATransaction.setDisableActions(Self.reduceMotion)
            cat.box.opacity = 0
            cat.box.transform = CATransform3DMakeScale(1, 0.3, 1)
            cat.boxPaws(hidden: false)
            CATransaction.commit()
        }
    }

    /// In the box its paws are inside it, out of sight.
    private func boxPaws(hidden: Bool) {
        pawL.opacity = hidden || isChinDown ? 0 : 1
        pawR.opacity = hidden || isChinDown || isGrooming ? 0 : 1
    }

    // MARK: Idle moves: once in a quiet spell

    private func idleMove() {
        guard isRunning, !Self.reduceMotion, !isAsleep, !isChinDown, !isHunting, !isBoxed, !isPuffed, !isYawning else { return }
        Bool.random() ? groom() : playWithPencil()
    }

    /// A paw up a little, its head down to it, a few licks.
    private func groom() {
        run("idle move") { cat in
            cat.isGrooming = true
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            cat.groomPaw.transform = CATransform3DMakeTranslation(0, -9, 0)
            CATransaction.commit()
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.25)
            cat.groomPaw.opacity = 1
            cat.groomPaw.transform = CATransform3DIdentity
            cat.pawR.opacity = 0
            CATransaction.commit()
            cat.updateFace()
            cat.updatePose(animated: true, duration: 0.35)
            guard await cat.pause(0.45) else { return }
            for lick in 0..<4 {
                if lick == 3 { guard await cat.pause(0.15) else { return } }
                cat.lick(true)
                guard await cat.pause(0.19) else { return }
                cat.lick(false)
                guard await cat.pause(0.17) else { return }
            }
            guard await cat.pause(0.2) else { return }
            cat.endGrooming()
            guard await cat.pause(0.35) else { return }
            cat.blink()
        }
    }

    private func lick(_ on: Bool) {
        isLicking = on
        updateFace()
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        groomPaw.transform = on ? CATransform3DMakeTranslation(-0.6, 1.8, 0) : CATransform3DIdentity
        CATransaction.commit()
    }

    private func endGrooming() {
        isGrooming = false
        isLicking = false
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        groomPaw.opacity = 0
        groomPaw.transform = CATransform3DMakeTranslation(0, -9, 0)
        pawR.opacity = isChinDown ? 0 : 1
        CATransaction.commit()
        updateFace()
        updatePose(animated: true, duration: 0.35)
    }

    /// Pats a pencil along the header until it falls off, then looks at you.
    private func playWithPencil() {
        run("idle move") { cat in
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            cat.pencil.transform = CATransform3DIdentity
            CATransaction.commit()
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.3)
            cat.pencil.opacity = 1
            CATransaction.commit()
            cat.gaze = CGPoint(x: -1.8, y: -1)
            cat.updateGaze(animated: true)
            guard await cat.pause(0.5) else { return }
            for push in 1...3 {
                cat.play([Self.keyframes("transform.translation.x", [0, -4, 0], at: [0, 0.5, 1]),
                          Self.keyframes("transform.translation.y", [0, 8, 0], at: [0, 0.5, 1])],
                         on: cat.pawL, duration: 0.3, key: "pat")
                guard await cat.pause(0.15) else { return }
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.22)
                cat.pencil.transform = CATransform3DMakeTranslation(CGFloat(-8 * push), 0, 0)
                CATransaction.commit()
                guard await cat.pause(0.45) else { return }
            }
            // Over the edge it goes.
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.6)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeIn))
            cat.pencil.transform = CATransform3DRotate(CATransform3DMakeTranslation(-30, -34, 0), CatPen.radians(80), 0, 0, 1)
            cat.pencil.opacity = 0
            CATransaction.commit()
            guard await cat.pause(0.7) else { return }
            cat.gaze = .zero
            cat.isStaring = true
            cat.updateFace()
            guard await cat.pause(0.7) else { return }
            cat.isSlowBlinking = true
            cat.updateFace()
            guard await cat.pause(0.5) else { return }
            cat.isSlowBlinking = false
            cat.updateFace()
            guard await cat.pause(0.7) else { return }
            cat.isStaring = false
            cat.updateFace()
        }
    }

    /// Something else happened: an idle move in progress stops and tidies up.
    private func stopIdleMove() {
        pending["idle move"]?.cancel()
        pending["idle move"] = nil
        if isGrooming || isLicking { endGrooming() }
        if pencil.opacity > 0 || isStaring {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.2)
            pencil.opacity = 0
            CATransaction.commit()
            isStaring = false
            isSlowBlinking = false
            updateFace()
        }
    }

    // MARK: Watching a drag

    private func dragMoved(to point: NSPoint) {
        guard isRunning, let window, window.frame.contains(point) else { return }
        guard !isAsleep else { return wake(yawning: false) }
        stopIdleMove()
        stopDozing()
        restartDozing()
        if !isHunting {
            isHunting = true
            updateFace()
            updatePose(animated: true)
            updateLoops()
        }
        look(at: point)
        if let middle = onScreen(eyes: false),
           pounce.moved(distance: hypot(point.x - middle.x, point.y - middle.y), reach: bounds.height * 1.6) {
            hop()
            movePaw(.bat)
        }
        after(0.45, "hunt end") { [weak self] in self?.endHunt() }
    }

    private func endHunt() {
        pounce.ended()
        guard isHunting else { return }
        isHunting = false
        updateFace()
        updatePose(animated: true)
        updateLoops()
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
        // Watching a drag: its back end wiggles, ready to pounce.
        for part in [body, tail] { shuffle(part, on: moving && isHunting) }
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

    /// A quick little side-to-side, forever, while `on`.
    private func shuffle(_ layer: CALayer, on: Bool) {
        guard on else { return layer.removeAnimation(forKey: "wiggle") }
        guard layer.animation(forKey: "wiggle") == nil else { return }
        let wiggle = CABasicAnimation(keyPath: "transform.translation.x")
        wiggle.fromValue = -1.3
        wiggle.toValue = 1.3
        wiggle.isAdditive = true
        wiggle.duration = 0.15
        wiggle.autoreverses = true
        wiggle.repeatCount = .infinity
        layer.add(wiggle, forKey: "wiggle")
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

    /// Runs a move made of steps; a newer one with the same key replaces it,
    /// and closing the panel stops it.
    private func run(_ key: String, _ steps: @escaping @MainActor (NotesCat) async -> Void) {
        pending[key]?.cancel()
        pending[key] = Task { await steps(self) }
    }

    /// Waits between steps of a move; false if the move should stop.
    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled && isRunning
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
        guard isRunning, !isAsleep, !isStaring else { return }
        look(at: NSEvent.mouseLocation)
    }

    override func mouseEntered(with event: NSEvent) {
        guard isRunning else { return }
        if isAsleep {
            wake()
        } else {
            twitch()
            stopDozing()
            restartDozing()
        }
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
/// their own middle (the head at 41, 36), turned `turn` degrees clockwise
/// about it.
struct CatPen {
    static let grid = CGSize(width: 120, height: 76)

    let path = CGMutablePath()
    private let origin: (x: CGFloat, y: CGFloat)
    private let turn: CGFloat

    init(_ origin: (x: CGFloat, y: CGFloat) = (0, 0), turn: CGFloat = 0, _ draw: (CatPen) -> Void) {
        self.origin = origin
        self.turn = turn
        draw(self)
    }

    static func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x, y: grid.height - y)
    }

    private func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        let angle = Self.radians(turn)
        return Self.point(origin.x + x * cos(angle) - y * sin(angle), origin.y + x * sin(angle) + y * cos(angle))
    }

    func m(_ x: CGFloat, _ y: CGFloat) { path.move(to: at(x, y)) }
    func l(_ x: CGFloat, _ y: CGFloat) { path.addLine(to: at(x, y)) }
    func q(_ cx: CGFloat, _ cy: CGFloat, _ x: CGFloat, _ y: CGFloat) { path.addQuadCurve(to: at(x, y), control: at(cx, cy)) }
    func c(_ c1x: CGFloat, _ c1y: CGFloat, _ c2x: CGFloat, _ c2y: CGFloat, _ x: CGFloat, _ y: CGFloat) {
        path.addCurve(to: at(x, y), control1: at(c1x, c1y), control2: at(c2x, c2y))
    }
    func z() { path.closeSubpath() }

    /// An ellipse, itself turned `turn` degrees clockwise.
    func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, turn: CGFloat = 0) {
        let center = at(cx, cy)
        let transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: -Self.radians(self.turn + turn))
        path.addEllipse(in: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry), transform: transform)
    }

    /// A rectangle with rounded corners, from its top left corner.
    func roundedRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, radius: CGFloat) {
        let center = at(x + width / 2, y + height / 2)
        let transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: -Self.radians(turn))
        path.addRoundedRect(in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height),
                            cornerWidth: radius, cornerHeight: radius, transform: transform)
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
