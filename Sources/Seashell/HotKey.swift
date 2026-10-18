import Carbon.HIToolbox
import SeashellCore

/// A keyboard shortcut that works in every app, through Carbon's hot key API:
/// unlike watching the keyboard, it needs no Accessibility permission.
@MainActor
final class HotKey {
    private static let signature: OSType = 0x5353_484C  // "SSHL"
    private static var actions: [UInt32: @MainActor () -> Void] = [:]
    private static var handlerInstalled = false

    private let id: UInt32
    private var ref: EventHotKeyRef?

    init(id: UInt32) {
        self.id = id
    }

    /// Replaces any earlier shortcut. Nil turns it off.
    func set(_ key: (code: UInt32, modifiers: UInt32)?, action: @escaping @MainActor () -> Void) {
        clear()
        guard let key else { return }
        Self.installHandler()
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(key.code, key.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            Self.actions[id] = action
        } else {
            Log.error("Couldn’t set the keyboard shortcut (error \(status)); another app may be using it")
        }
    }

    func clear() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        Self.actions[id] = nil
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            DispatchQueue.main.async {
                MainActor.assumeIsolated { HotKey.actions[id]?() }
            }
            return noErr
        }, 1, &pressed, nil, nil)
    }
}
