import Foundation

/// Light or dark for Seashell's own windows, or whatever the Mac uses.
public enum Theme: String, CaseIterable, Sendable {
    case system, light, dark

    public static let standard = Theme.system

    public var name: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

/// Stashing anything bigger asks first: everything in Stash uploads to iCloud
/// and counts against its storage.
public enum LargeFileLimit: String, CaseIterable, Sendable {
    case mb500, gb1, gb5, never

    public static let standard = LargeFileLimit.gb1

    /// Nil: never ask.
    public var bytes: Int64? {
        switch self {
        case .mb500: 500_000_000
        case .gb1: 1_000_000_000
        case .gb5: 5_000_000_000
        case .never: nil
        }
    }

    public var name: String {
        switch self {
        case .mb500: "Over 500 MB"
        case .gb1: "Over 1 GB"
        case .gb5: "Over 5 GB"
        case .never: "Never"
        }
    }
}

/// How readily shaking the pointer during a drag shows the floating shelf.
public enum ShakeSensitivity: String, CaseIterable, Sendable {
    case off, gentle, normal, firm

    public static let standard = ShakeSensitivity.normal

    public var name: String {
        switch self {
        case .off: "Off"
        case .gentle: "Gentle"
        case .normal: "Normal"
        case .firm: "Firm"
        }
    }

    /// The detector to watch drags with; nil when shaking is off.
    public var detector: ShakeDetector? {
        var detector = ShakeDetector()
        switch self {
        case .off:
            return nil
        case .gentle:
            detector.reversalsNeeded = 2
            detector.minimumSwing = 15
        case .normal:
            break
        case .firm:
            detector.reversalsNeeded = 4
            detector.minimumSwing = 30
            // One more swing needs a little more time.
            detector.window = 0.8
        }
        return detector
    }
}

/// The keyboard shortcut that opens and closes the panel from any app.
public enum PanelShortcut: String, CaseIterable, Sendable {
    case controlOptionS, controlOptionCommandS, controlOptionZ, off

    public static let standard = PanelShortcut.controlOptionS

    public var name: String {
        switch self {
        case .controlOptionS: "⌃⌥S"
        case .controlOptionCommandS: "⌃⌥⌘S"
        case .controlOptionZ: "⌃⌥Z"
        case .off: "Off"
        }
    }

    /// The key (a `kVK_ANSI_*` code) and Carbon modifier flags; nil when off.
    public var key: (code: UInt32, modifiers: UInt32)? {
        let control: UInt32 = 0x1000, option: UInt32 = 0x0800, command: UInt32 = 0x0100  // controlKey, optionKey, cmdKey
        switch self {
        case .controlOptionS: return (1, control | option)  // kVK_ANSI_S
        case .controlOptionCommandS: return (1, control | option | command)
        case .controlOptionZ: return (6, control | option)  // kVK_ANSI_Z
        case .off: return nil
        }
    }

    /// The letter, for showing the shortcut in a menu.
    public var letter: String? {
        switch self {
        case .controlOptionS, .controlOptionCommandS: "s"
        case .controlOptionZ: "z"
        case .off: nil
        }
    }
}
