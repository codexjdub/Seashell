import AppKit
import QuickLookThumbnailing
import SeashellCore

/// The grid of items in a shelf. Handles the keyboard (Space, ⌘⌫, ⌘O, ⌘A),
/// double-click, and selecting what was right-clicked. What those actions do is
/// up to the controller.
@MainActor
final class StashGridView: NSCollectionView {
    var onOpen: (() -> Void)?
    var onDelete: (() -> Void)?
    var onTogglePreview: (() -> Void)?
    var onCopy: (() -> Void)?
    var onPaste: (() -> Void)?
    var contextMenu: (() -> NSMenu?)?

    // ⌘C and ⌘V arrive here as the standard copy: and paste: actions.
    @objc func copy(_ sender: Any?) { onCopy?() }
    @objc func paste(_ sender: Any?) { onPaste?() }

    override var acceptsFirstResponder: Bool { true }

    /// The grab shelf is never the key window: the first click must start a drag.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        switch (event.keyCode, modifiers) {
        case (49, []): onTogglePreview?()          // Space
        case (51, [.command]): onDelete?()         // ⌘⌫
        case (31, [.command]): onOpen?()           // ⌘O
        default: super.keyDown(with: event)        // ⌘A and arrows are handled by NSCollectionView
        }
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2, indexPathForItem(at: convert(event.locationInWindow, from: nil)) != nil {
            onOpen?()
        }
    }

    /// Right-clicking an item that isn't selected selects just that item first, like Finder.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let indexPath = indexPathForItem(at: convert(event.locationInWindow, from: nil)) else { return nil }
        if !selectionIndexPaths.contains(indexPath) {
            deselectAll(nil)
            selectItems(at: [indexPath], scrollPosition: [])
        }
        return contextMenu?()
    }
}

/// One item in the grid. Files and folders show a thumbnail and their name.
/// Text shows as a note card with its first lines; a link as a card with its
/// title and site. A cloud badge marks items that are only in iCloud.
@MainActor
final class StashItemCell: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("StashItemCell")
    // Sizes at the current text size (see UIScale).
    static var iconSize: CGFloat { UIScale.pt(56) }
    static var tileSize: NSSize { NSSize(width: UIScale.pt(92), height: UIScale.pt(104)) }

    // Files and folders
    private let icon = NSImageView()
    // Labels let the mouse through: AppKit makes wrapping labels selectable, and a
    // selectable label would start a text selection instead of dragging the item.
    private let name = PassThroughLabel(wrappingLabelWithString: "")
    // Text
    private let noteCard = CardView(color: NoteTint.color, fill: NoteTint.fill, border: NoteTint.border)
    private let noteText = PassThroughLabel(wrappingLabelWithString: "")
    // Links
    private let linkCard = CardView(color: LinkTint.card, fill: LinkTint.fill, border: LinkTint.border)
    private let linkSymbol = NSImageView()
    private let linkTitle = PassThroughLabel(wrappingLabelWithString: "")
    private let linkSite = PassThroughLabel(labelWithString: "")

    private let cloudBadge = NSImageView()
    private var shownURL: URL?
    private var iconWidth: NSLayoutConstraint?
    private var iconHeight: NSLayoutConstraint?

    override func loadView() {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 8

        icon.imageScaling = .scaleProportionallyUpOrDown
        name.alignment = .center
        // Truncating line-break modes turn wrapping off in AppKit, so wrap by
        // word and let the last visible line end in "…".
        name.maximumNumberOfLines = 2
        name.lineBreakMode = .byWordWrapping
        name.cell?.truncatesLastVisibleLine = true

        noteText.textColor = .labelColor
        noteText.maximumNumberOfLines = 5  // what fits in one tile at 13 pt
        noteText.lineBreakMode = .byWordWrapping
        noteText.cell?.truncatesLastVisibleLine = true

        linkSymbol.image = NSImage(systemSymbolName: "link", accessibilityDescription: "Link")
        linkSymbol.contentTintColor = LinkTint.symbol
        linkTitle.alignment = .center
        linkTitle.maximumNumberOfLines = 2  // at this size, 3 lines would push the site off the card
        linkTitle.lineBreakMode = .byWordWrapping
        linkTitle.cell?.truncatesLastVisibleLine = true
        linkSite.textColor = .secondaryLabelColor
        linkSite.alignment = .center
        linkSite.lineBreakMode = .byTruncatingMiddle

        cloudBadge.image = NSImage(systemSymbolName: "icloud.and.arrow.down", accessibilityDescription: "In iCloud only")
        cloudBadge.contentTintColor = .secondaryLabelColor

        Self.add([noteText], to: noteCard)
        Self.add([linkSymbol, linkTitle, linkSite], to: linkCard)
        Self.add([icon, name, noteCard, linkCard, cloudBadge], to: view)
        let iconWidth = icon.widthAnchor.constraint(equalToConstant: Self.iconSize)
        let iconHeight = icon.heightAnchor.constraint(equalToConstant: Self.iconSize)
        self.iconWidth = iconWidth
        self.iconHeight = iconHeight
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            icon.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconWidth,
            iconHeight,
            name.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 4),
            name.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            name.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),

            // Cards fill the tile, inset so the selection highlight shows around them.
            noteCard.topAnchor.constraint(equalTo: view.topAnchor, constant: 5),
            noteCard.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -5),
            noteCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 5),
            noteCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -5),
            noteText.topAnchor.constraint(equalTo: noteCard.topAnchor, constant: 6),
            noteText.leadingAnchor.constraint(equalTo: noteCard.leadingAnchor, constant: 6),
            noteText.trailingAnchor.constraint(equalTo: noteCard.trailingAnchor, constant: -6),
            noteText.bottomAnchor.constraint(lessThanOrEqualTo: noteCard.bottomAnchor, constant: -6),

            linkCard.topAnchor.constraint(equalTo: view.topAnchor, constant: 5),
            linkCard.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -5),
            linkCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 5),
            linkCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -5),
            linkSymbol.topAnchor.constraint(equalTo: linkCard.topAnchor, constant: 10),
            linkSymbol.centerXAnchor.constraint(equalTo: linkCard.centerXAnchor),
            linkTitle.topAnchor.constraint(equalTo: linkSymbol.bottomAnchor, constant: 6),
            linkTitle.leadingAnchor.constraint(equalTo: linkCard.leadingAnchor, constant: 5),
            linkTitle.trailingAnchor.constraint(equalTo: linkCard.trailingAnchor, constant: -5),
            linkSite.topAnchor.constraint(greaterThanOrEqualTo: linkTitle.bottomAnchor, constant: 2),
            linkSite.bottomAnchor.constraint(equalTo: linkCard.bottomAnchor, constant: -6),
            linkSite.leadingAnchor.constraint(equalTo: linkCard.leadingAnchor, constant: 4),
            linkSite.trailingAnchor.constraint(equalTo: linkCard.trailingAnchor, constant: -4),

            cloudBadge.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            cloudBadge.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            cloudBadge.widthAnchor.constraint(equalToConstant: 16),
            cloudBadge.heightAnchor.constraint(equalToConstant: 16),
        ])
        self.view = view
        imageView = icon
        textField = name
    }

    override var isSelected: Bool {
        didSet {
            view.layer?.backgroundColor = isSelected ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.35).cgColor : nil
        }
    }

    /// Fonts and sizes for the current text size; tiles are reconfigured when it changes.
    private func applyTextSize() {
        let tile = Self.tileSize
        iconWidth?.constant = Self.iconSize
        iconHeight?.constant = Self.iconSize
        name.font = UIScale.font(12)
        name.preferredMaxLayoutWidth = tile.width - 8
        noteText.font = UIScale.font(13)  // same as the note editor
        noteText.preferredMaxLayoutWidth = tile.width - 22  // card inset 10, padding 12
        linkSymbol.symbolConfiguration = .init(pointSize: UIScale.pt(18), weight: .medium)
        linkTitle.font = UIScale.font(14, weight: .semibold)
        linkTitle.preferredMaxLayoutWidth = tile.width - 20
        linkSite.font = UIScale.font(13)
    }

    func configure(with item: StashItem, thumbnails: ThumbnailLoader) {
        applyTextSize()
        shownURL = item.url
        let cloudOnly = item.cloud == .cloudOnly
        cloudBadge.isHidden = !cloudOnly
        let title = item.url.deletingPathExtension().lastPathComponent

        switch item.kind {
        case .text:
            show(.text)
            // Read in the background (file coordination can wait on iCloud); the
            // title stands in until then.
            let showText: @MainActor @Sendable (String?) -> Void = { [weak self] preview in
                guard let self, self.shownURL == item.url else { return }
                self.noteText.stringValue = preview.map { String($0.prefix(400)) } ?? title
                self.view.toolTip = preview ?? (cloudOnly ? "\(title) (in iCloud)" : title)
            }
            showText(thumbnails.cachedText(for: item))
            thumbnails.loadText(item, completion: showText)
        case .link:
            show(.link)
            linkTitle.stringValue = title
            let showLink: @MainActor @Sendable (URL?) -> Void = { [weak self] link in
                guard let self, self.shownURL == item.url else { return }
                self.linkSite.stringValue = link?.host(percentEncoded: false)?.replacingOccurrences(of: "www.", with: "") ?? ""
                self.view.toolTip = link?.absoluteString ?? title
            }
            showLink(thumbnails.cachedLink(for: item))
            thumbnails.loadLink(item, completion: showLink)
        case .file, .folder:
            show(.file)
            name.stringValue = item.name
            view.toolTip = item.name
            icon.image = thumbnails.cached(for: item.url) ?? NSWorkspace.shared.icon(forFile: item.url.path(percentEncoded: false))
            thumbnails.load(item.url, size: Self.iconSize, scale: view.window?.backingScaleFactor ?? 2) { [weak self] image in
                guard let self, self.shownURL == item.url else { return }
                self.icon.image = image
            }
        }
    }

    private func show(_ kind: StashItem.Kind) {
        icon.isHidden = kind == .text || kind == .link
        if icon.isHidden { icon.image = nil }  // a reused tile may still hold another file's thumbnail
        name.isHidden = icon.isHidden
        noteCard.isHidden = kind != .text
        linkCard.isHidden = kind != .link
    }

    /// What a drag shows. macOS builds it from the icon and name by default;
    /// text and links show their card instead.
    override var draggingImageComponents: [NSDraggingImageComponent] {
        let card: NSView? = !noteCard.isHidden ? noteCard : (!linkCard.isHidden ? linkCard : nil)
        guard let card, let rep = card.bitmapImageRepForCachingDisplay(in: card.bounds) else {
            return super.draggingImageComponents
        }
        card.cacheDisplay(in: card.bounds, to: rep)
        let image = NSImage(size: card.bounds.size)
        image.addRepresentation(rep)
        let component = NSDraggingImageComponent(key: .icon)
        component.contents = image
        component.frame = card.frame
        return [component]
    }

    private static func add(_ subviews: [NSView], to parent: NSView) {
        for subview in subviews {
            subview.translatesAutoresizingMaskIntoConstraints = false
            parent.addSubview(subview)
        }
    }
}

/// The faint yellow notes are drawn in, alike on Stash's note cards and the
/// Notes card. Opacities of `color`, washed over the card underneath; Light
/// Mode needs a little more to show.
@MainActor
enum NoteTint {
    static let color = NSColor.systemYellow
    static let fill = Opacity(light: 0.10, dark: 0.06)
    static let border = Opacity(light: 0.30, dark: 0.22)
    /// The selected note in the Notes list.
    static let selection = Opacity(light: 0.22, dark: 0.16)
}

/// Link cards are neutral, with only the link symbol in blue: a blue card
/// would look selected.
@MainActor
enum LinkTint {
    static let card = NSColor.labelColor
    static let fill = Opacity(light: 0.04, dark: 0.06)
    static let border = Opacity(light: 0.14, dark: 0.18)
    static let symbol = NSColor.systemBlue
}

/// An opacity that can differ between Light and Dark Mode.
struct Opacity {
    let light: CGFloat
    let dark: CGFloat

    init(light: CGFloat, dark: CGFloat) {
        self.light = light
        self.dark = dark
    }

    init(_ both: CGFloat) {
        self.init(light: both, dark: both)
    }

    func value(in appearance: NSAppearance) -> CGFloat {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
    }
}

/// A rounded, tinted card. Drawn rather than layer-styled, so it can be
/// captured for a drag image and follows light and dark mode.
final class CardView: NSView {
    private let color: NSColor
    private let fill: Opacity
    private let border: Opacity

    init(color: NSColor, fill: Opacity = Opacity(0.18), border: Opacity = Opacity(0.45)) {
        self.color = color
        self.fill = fill
        self.border = border
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Clicks and drags go to the tile underneath, which the grid handles.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        color.withAlphaComponent(fill.value(in: effectiveAppearance)).setFill()
        path.fill()
        color.withAlphaComponent(border.value(in: effectiveAppearance)).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

/// What tiles show that has to be read from disk: Quick Look thumbnails, and
/// the text or address of text and link items. Loaded in the background and
/// cached per file and modification date.
@MainActor
final class ThumbnailLoader {
    private let cache = NSCache<NSString, NSImage>()
    private let texts = NSCache<NSString, NSString>()
    private let links = NSCache<NSString, NSURL>()

    func cachedText(for item: StashItem) -> String? {
        texts.object(forKey: key(for: item) as NSString) as String?
    }

    /// Nil if it can't be read (too big, not text, or only in iCloud).
    func loadText(_ item: StashItem, completion: @escaping @MainActor (String?) -> Void) {
        let key = key(for: item)
        if texts.object(forKey: key as NSString) != nil { return }
        let url = item.url
        Task { [weak self] in
            let preview = await Task.detached { ItemContent.preview(of: url, maxCharacters: 1000) }.value
            if let preview { self?.texts.setObject(preview as NSString, forKey: key as NSString) }
            completion(preview)
        }
    }

    func cachedLink(for item: StashItem) -> URL? {
        links.object(forKey: key(for: item) as NSString) as URL?
    }

    func loadLink(_ item: StashItem, completion: @escaping @MainActor (URL?) -> Void) {
        let key = key(for: item)
        if links.object(forKey: key as NSString) != nil { return }
        let url = item.url
        Task { [weak self] in
            let link = await Task.detached { ItemContent.link(of: url) }.value
            if let link { self?.links.setObject(link as NSURL, forKey: key as NSString) }
            completion(link)
        }
    }

    private func key(for item: StashItem) -> String {
        "\(item.url.path(percentEncoded: false))|\(item.modified?.timeIntervalSince1970 ?? 0)"
    }

    func cached(for url: URL) -> NSImage? {
        cache.object(forKey: key(for: url) as NSString)
    }

    func load(_ url: URL, size: CGFloat, scale: CGFloat, completion: @escaping @MainActor (NSImage) -> Void) {
        let key = key(for: url)
        if cache.object(forKey: key as NSString) != nil { return }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size),
                                                   scale: scale, representationTypes: .all)
        // Called on a background queue; @Sendable keeps Swift from treating it as main-thread-only.
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { @Sendable [weak self] representation, _ in
            guard let cgImage = representation?.cgImage else { return }
            let image = NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
            Task { @MainActor in
                self?.cache.setObject(image, forKey: key as NSString)
                completion(image)
            }
        }
    }

    private func key(for url: URL) -> String {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        return "\(url.path(percentEncoded: false))|\(modified)"
    }
}
