import AppKit

extension NSScreen {
    /// The screen under `point`, counting its top edge, where the pointer rests
    /// when pushed all the way up.
    static func containing(_ point: NSPoint) -> NSScreen? {
        screens.first { screen in
            let frame = screen.frame
            return point.x >= frame.minX && point.x < frame.maxX && point.y >= frame.minY && point.y <= frame.maxY
        }
    }

    static var underPointer: NSScreen? {
        containing(NSEvent.mouseLocation)
    }

    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
