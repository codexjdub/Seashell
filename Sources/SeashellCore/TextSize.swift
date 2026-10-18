import Foundation

/// How big Seashell draws its text. Tiles, rows and the panel grow with it.
public enum TextSize: String, CaseIterable, Sendable {
    case small, medium, large, extraLarge

    public static let standard = TextSize.medium

    /// Relative to Small, which is the original size.
    public var scale: Double {
        switch self {
        case .small: 1.0
        case .medium: 1.15
        case .large: 1.3
        case .extraLarge: 1.5
        }
    }

    public var name: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        }
    }

    /// One step up, or the same at the largest.
    public var larger: TextSize {
        let all = Self.allCases
        return all[min(all.firstIndex(of: self)! + 1, all.count - 1)]
    }

    /// One step down, or the same at the smallest.
    public var smaller: TextSize {
        let all = Self.allCases
        return all[max(all.firstIndex(of: self)! - 1, 0)]
    }
}
