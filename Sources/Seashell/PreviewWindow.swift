import AppKit
import Quartz
import SeashellCore

/// Seashell's own preview window, below the pull-down panel. It uses the same
/// Quick Look view as Finder, but unlike the system Quick Look window it never
/// needs Seashell to be the active app: the panel keeps the keyboard, so Space,
/// Esc and the arrows always reach Seashell.
@MainActor
final class PreviewWindow {
    private(set) var isShowing = false
    private lazy var window = makeWindow()
    private lazy var previewView: QLPreviewView? = QLPreviewView(frame: .zero, style: .normal)
    private let title = NSTextField(labelWithString: "")

    func show(_ url: URL, below panelFrame: NSRect, in visibleFrame: NSRect, level: NSWindow.Level) {
        window.level = NSWindow.Level(rawValue: level.rawValue + 1)
        title.font = UIScale.font(12, weight: .semibold)
        window.setFrame(PanelGeometry.previewFrame(below: panelFrame, in: visibleFrame), display: false)
        update(url)
        window.orderFront(nil)
        isShowing = true
    }

    /// Follows the selection while open.
    func update(_ url: URL) {
        title.stringValue = url.lastPathComponent
        previewView?.previewItem = url as NSURL
    }

    func hide() {
        guard isShowing else { return }
        isShowing = false
        window.orderOut(nil)
        previewView?.previewItem = nil
    }

    private func makeWindow() -> NSPanel {
        // Never key: the pull-down panel keeps the keyboard.
        let window = NSPanel(contentRect: NSRect(origin: .zero, size: PanelGeometry.previewMaxSize),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 16
        background.layer?.masksToBounds = true

        title.textColor = .secondaryLabelColor
        title.lineBreakMode = .byTruncatingMiddle
        title.alignment = .center

        var subviews: [NSView] = [title]
        if let previewView {
            previewView.shouldCloseWithWindow = false
            subviews.append(previewView)
        } else {
            Log.error("Couldn’t create a Quick Look view; previews will be blank")
        }
        for subview in subviews {
            subview.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(subview)
        }
        var constraints = [
            title.topAnchor.constraint(equalTo: background.topAnchor, constant: 10),
            title.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -16),
        ]
        if let previewView {
            constraints += [
                previewView.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
                previewView.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 10),
                previewView.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -10),
                previewView.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -10),
            ]
        }
        NSLayoutConstraint.activate(constraints)
        window.contentView = background
        return window
    }
}
