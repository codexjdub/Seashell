import AppKit
import SeashellCore

// The helper AppDelegate starts to set up Copy Text's model: it does that and quits.
if CommandLine.arguments.contains(TextRecognition.warmUpArgument) {
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        await TextRecognition.warmUp()
        done.signal()
    }
    done.wait()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Menu bar app: no Dock icon, even when run outside the bundle (LSUIElement covers the bundle).
app.setActivationPolicy(.accessory)
app.run()
