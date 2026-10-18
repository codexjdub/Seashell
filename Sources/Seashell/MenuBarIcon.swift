import AppKit

/// The menu bar icon: a scallop drawn in lines with Zephyr's three wind strands
/// across its edge, echoing the app icon. A template image, so macOS tints it
/// for light and dark menu bars, drawn in code so it stays sharp at any scale.
@MainActor
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            NSColor.black.set()
            stroke(outline, width: 1.15)
            stroke(ribs, width: 0.85)
            // A gap around the wind, so it reads in front of the shell.
            context.setBlendMode(.clear)
            for (d, width) in strands { stroke(d, width: width + 1.3) }
            context.setBlendMode(.normal)
            for (d, width) in strands { stroke(d, width: width) }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Seashell"
        return image
    }()

    // Shapes in an 18 × 18 box, y growing downward, from the icon's design
    // (the same scallop geometry as the app icon, simplified to seven lobes).
    private static let outline = """
        M8.20 16.60 Q7.80 15.90 7.80 15.20 L9.30 14.80 Q6.60 14.60 5.80 13.20 C4.90 13.20 3.90 10.20 4.70 9.80 \
        C4.00 9.20 5.00 6.30 5.90 6.30 C5.50 5.50 8.10 3.70 8.80 4.20 C9.00 3.30 12.20 3.30 12.40 4.20 \
        C13.10 3.70 15.70 5.50 15.30 6.30 C16.20 6.30 17.20 9.20 16.50 9.80 C17.30 10.20 16.30 13.20 15.40 13.20 \
        Q14.60 14.60 11.90 14.80 L13.40 15.20 Q13.40 15.90 13.00 16.60 Q10.60 17.00 8.20 16.60 Z
        """
    private static let ribs = """
        M8.90 13.51 L4.94 9.76 M9.23 12.52 L6.04 6.47 M10.08 11.91 L8.86 4.44 \
        M11.12 11.91 L12.34 4.44 M11.97 12.52 L15.16 6.47 M12.30 13.51 L16.26 9.76
        """
    /// Top to bottom: a curl, a hook, a short stroke, each a little thinner.
    private static let strands: [(String, CGFloat)] = [
        ("M1.90 5.20 C3.40 4.10 4.60 5.20 5.90 4.40 C6.90 3.80 6.80 2.20 5.70 2.10 C4.80 2.00 4.60 3.10 5.20 3.50", 1.05),
        ("M2.20 7.90 C3.60 7.20 4.60 7.90 5.70 7.40 C6.30 7.10 6.30 6.30 5.70 6.30", 0.85),
        ("M2.50 10.50 C3.60 10.00 4.40 10.40 5.20 10.10", 0.7),
    ]

    private static func stroke(_ d: String, width: CGFloat) {
        let path = path(d)
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    /// Reads the absolute M, L, Q, C and Z commands of SVG path data.
    private static func path(_ d: String) -> NSBezierPath {
        let path = NSBezierPath()
        var command: Character = "M"
        var numbers: [CGFloat] = []
        func flush() {
            let p = stride(from: 0, to: numbers.count - 1, by: 2).map { NSPoint(x: numbers[$0], y: numbers[$0 + 1]) }
            switch command {
            case "M": if let first = p.first { path.move(to: first) }; p.dropFirst().forEach { path.line(to: $0) }
            case "L": p.forEach { path.line(to: $0) }
            case "Q": stride(from: 0, to: p.count - 1, by: 2).forEach { path.curve(to: p[$0 + 1], controlPoint: p[$0]) }
            case "C": stride(from: 0, to: p.count - 2, by: 3).forEach {
                path.curve(to: p[$0 + 2], controlPoint1: p[$0], controlPoint2: p[$0 + 1])
            }
            default: break
            }
            numbers = []
        }
        // Tokens are numbers, each possibly led by a command letter ("M8.20").
        for token in d.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
            var number = token
            if let letter = token.first, letter.isLetter {
                flush()
                command = letter
                if letter == "Z" { path.close() }
                number = token.dropFirst()
            }
            if let value = Double(number) { numbers.append(CGFloat(value)) }
        }
        flush()
        return path
    }
}
