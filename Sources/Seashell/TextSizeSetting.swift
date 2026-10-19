import AppKit
import Observation
import SeashellCore

/// The text size chosen in Settings or with ⌘+ / ⌘− / ⌘0, remembered
/// on this Mac. Views read it inside `observeChanges`, so they update at once.
@MainActor @Observable
final class TextSizeSetting {
    static let shared = TextSizeSetting()
    private static let key = "textSize"

    var size: TextSize {
        didSet {
            UserDefaults.standard.set(size.rawValue, forKey: Self.key)
            Log.info("Text size: \(size.name)")
        }
    }

    private init() {
        size = UserDefaults.standard.string(forKey: Self.key).flatMap(TextSize.init(rawValue:)) ?? .standard
    }
}

/// Sizes in points at the current text size. Every size in Seashell's views is
/// written at Small (the original) and scaled through here.
@MainActor
enum UIScale {
    static var factor: CGFloat { CGFloat(TextSizeSetting.shared.size.scale) }

    static func pt(_ base: CGFloat) -> CGFloat {
        (base * factor).rounded()
    }

    static func font(_ base: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: pt(base), weight: weight)
    }
}
