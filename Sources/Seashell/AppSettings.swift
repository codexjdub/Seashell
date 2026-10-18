import AppKit
import Observation
import ServiceManagement
import SeashellCore

/// The choices in the Settings window, remembered on this Mac. Views and
/// watchers read them inside `observeChanges`, so changes apply at once.
/// Text size lives in `TextSizeSetting`, launch at login in `LoginItem`.
@MainActor @Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Key {
        static let theme = "theme"
        static let largeFileLimit = "largeFileLimit"
        static let shakeSensitivity = "shakeSensitivity"
        static let opensOnPullDown = "opensOnPullDown"
        static let shakeIgnoredApps = "shakeIgnoredApps"
        static let panelShortcut = "panelShortcut"
    }

    var theme: Theme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Key.theme)
            Log.info("Theme: \(theme.name)")
        }
    }

    /// Asks before stashing anything bigger.
    var largeFileLimit: LargeFileLimit {
        didSet {
            UserDefaults.standard.set(largeFileLimit.rawValue, forKey: Key.largeFileLimit)
            Log.info("Ask before stashing: \(largeFileLimit.name)")
        }
    }

    var shakeSensitivity: ShakeSensitivity {
        didSet {
            UserDefaults.standard.set(shakeSensitivity.rawValue, forKey: Key.shakeSensitivity)
            Log.info("Shake to show the shelf: \(shakeSensitivity.name)")
        }
    }

    /// Pulling down at the top edge opens the panel. Pushing up still closes it.
    var opensOnPullDown: Bool {
        didSet {
            UserDefaults.standard.set(opensOnPullDown, forKey: Key.opensOnPullDown)
            Log.info(opensOnPullDown ? "Pull down at the top edge: on" : "Pull down at the top edge: off")
        }
    }

    /// Opens and closes the panel from any app.
    var panelShortcut: PanelShortcut {
        didSet {
            UserDefaults.standard.set(panelShortcut.rawValue, forKey: Key.panelShortcut)
            Log.info("Keyboard shortcut: \(panelShortcut.name)")
        }
    }

    /// Apps (bundle IDs) in which shakes are ignored, for both the drop shelf and
    /// the grab shelf: drawing apps and games move the pointer fast on purpose.
    var shakeIgnoredApps: [String] {
        didSet {
            UserDefaults.standard.set(shakeIgnoredApps, forKey: Key.shakeIgnoredApps)
            Log.info("Shakes ignored in: \(shakeIgnoredApps.isEmpty ? "no apps" : shakeIgnoredApps.joined(separator: ", "))")
        }
    }

    func setShakesIgnored(_ ignored: Bool, in bundleID: String) {
        var apps = shakeIgnoredApps.filter { $0 != bundleID }
        if ignored { apps.append(bundleID) }
        shakeIgnoredApps = apps
    }

    /// False while one of those apps is in front.
    func allowsShake() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier,
              shakeIgnoredApps.contains(id) else { return true }
        Log.info("Shake ignored: \(app.localizedName ?? id) is in front")
        return false
    }

    private init() {
        theme = Self.load(Key.theme) ?? .standard
        largeFileLimit = Self.load(Key.largeFileLimit) ?? .standard
        shakeSensitivity = Self.load(Key.shakeSensitivity) ?? .standard
        opensOnPullDown = UserDefaults.standard.object(forKey: Key.opensOnPullDown) as? Bool ?? true
        shakeIgnoredApps = UserDefaults.standard.stringArray(forKey: Key.shakeIgnoredApps) ?? []
        panelShortcut = Self.load(Key.panelShortcut) ?? .standard
    }

    private static func load<Value: RawRepresentable>(_ key: String) -> Value? where Value.RawValue == String {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        return Value(rawValue: raw)
    }
}

extension Theme {
    /// Nil follows the Mac.
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Opening Seashell when you log in. macOS keeps track of it (and lists it in
/// System Settings → General → Login Items), so nothing is stored here.
@MainActor
enum LoginItem {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    /// Turned on, but waiting for you to allow it in System Settings.
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func set(_ on: Bool) throws {
        if on {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        Log.info("Launch at login: \(on ? "on" : "off") (status \(SMAppService.mainApp.status.rawValue))")
    }

    /// System Settings → General → Login Items, where you allow it.
    static func openSystemSettings() {
        Log.info("Opening Login Items in System Settings to allow Seashell")
        SMAppService.openSystemSettingsLoginItems()
    }
}
