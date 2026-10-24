import AppKit
import SeashellCore

/// Turns a drop (files, promised files, links, images, text) into Stash items.
/// Shared by every drop target that stashes (the menu bar icon, the panel, the
/// floating shelf and tear-off shelves) and by Paste.
@MainActor
final class StashDropper {
    static let acceptedTypes: [NSPasteboard.PasteboardType] =
        [.fileURL, .URL, .png, .tiff, .string]
        + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }

    private static let urlTitleType = NSPasteboard.PasteboardType("public.url-name")

    /// What ⌘Z takes back: each drop or paste is a step, as are moves between
    /// shelves (recorded by the shelf tabs).
    let history = StashUndoHistory()
    private var isUndoing = false
    private let mover: FileMover
    private let promiseQueue = OperationQueue()
    /// Where promised files land before they move into a shelf.
    private static let incomingRoot = URL.temporaryDirectory.appending(path: "Seashell-Incoming", directoryHint: .isDirectory)

    init(mover: FileMover) {
        self.mover = mover
        // Nothing is on its way in at launch: whatever is here was left behind.
        try? FileManager.default.removeItem(at: Self.incomingRoot)
    }

    /// Answer `move` only for files: Finder leaves the moving to us. A text
    /// source such as TextEdit would delete the dragged text on `move`. Files
    /// whose drag doesn't allow moving (⌥ held, or an app that only lets them be
    /// copied) are a `copy`, and copied in.
    /// Items dragged out of Seashell's own grid are already stashed: refused here
    /// (moving them between shelves is the shelf tabs' job).
    static func operation(for info: any NSDraggingInfo) -> NSDragOperation {
        if info.draggingSource is StashGridView { return [] }
        let offered = info.draggingSourceOperationMask
        let hasFiles = info.draggingPasteboard.canReadObject(forClasses: [NSURL.self],
                                                             options: [.urlReadingFileURLsOnly: true])
        if hasFiles, offered.contains(.move) { return .move }
        if offered.contains(.copy) { return .copy }
        return offered.contains(.generic) ? .generic : []
    }

    /// Stashes everything in the drop into `shelf`: files move in, or are copied
    /// in when the drop is a copy (see `operation(for:)`), so they go as the
    /// pointer's badge says. Returns false if nothing was usable.
    /// The shell in the window it landed in catches it.
    func accept(_ info: any NSDraggingInfo, into shelf: URL) -> Bool {
        let accepted = accept(info.draggingPasteboard, into: shelf, copyingFiles: Self.operation(for: info) == .copy)
        if accepted { SealView.react(.catchDrop, in: info.draggingDestinationWindow) }
        return accepted
    }

    /// "Stash in Seashell" in the Services menu: like a drop of the selection.
    func stash(_ pasteboard: NSPasteboard, into shelf: URL) -> Bool {
        accept(pasteboard, into: shelf, copyingFiles: false)
    }

    /// ⌘V into a shelf: like a drop, except files are copied in and the
    /// originals stay, as pasting does everywhere.
    func paste(into shelf: URL) -> Bool {
        Log.info("Pasting into \(shelf.lastPathComponent)")
        return accept(NSPasteboard.general, into: shelf, copyingFiles: true)
    }

    private func accept(_ pasteboard: NSPasteboard, into shelf: URL, copyingFiles: Bool) -> Bool {
        // One object per item, in order of preference.
        let classes: [AnyClass] = [NSFilePromiseReceiver.self, NSURL.self, NSImage.self, NSString.self]
        guard let objects = pasteboard.readObjects(forClasses: classes, options: nil), !objects.isEmpty else {
            Log.info("Nothing Seashell can stash: \(pasteboard.types?.map(\.rawValue) ?? [])")
            return false
        }

        // Read now: the drag's pasteboard is gone by the time a slow promise gives up.
        let fallback = objects.contains { $0 is NSFilePromiseReceiver } ? PromiseFallback(pasteboard) : nil
        let titles = Self.linkTitles(on: pasteboard)
        let links = objects.filter { ($0 as? URL)?.isFileURL == false }.count
        // Each object is its pasteboard item's when every item gave one.
        let items = pasteboard.pasteboardItems ?? []
        let ownItems = items.count == objects.count
        let step = history.begin()

        var files: [URL] = []
        for (index, object) in objects.enumerated() {
            switch object {
            case let receiver as NSFilePromiseReceiver:
                receive(receiver, into: shelf, fallback: fallback ?? PromiseFallback(pasteboard), step: step)
            case let url as URL where url.isFileURL:
                files.append(url)
            case let url as URL:
                // Its own title, or a lone link's from the drag as a whole.
                let title = titles[url.absoluteString] ?? (links == 1 ? pasteboard.string(forType: Self.urlTitleType) : nil)
                run("link", step) { try $0.stash(link: url, title: title, into: shelf) }
            case let image as NSImage:
                // The picture's own data, converted in the background: making a
                // full-size TIFF of it here would hold everything up (a photo
                // takes a tenth of a second and tens of MB).
                let own = ownItems ? Self.imageData(on: items[index]) : nil
                let lone = objects.count == 1 ? pasteboard.data(forType: .png) : nil
                guard let data = own ?? lone ?? image.tiffRepresentation else { continue }
                runInBackground("image", step) { try $0.stash(imageData: data, into: shelf) }
            case let text as String:
                run("text", step) { try $0.stash(text: text, into: shelf) }
            default:
                continue
            }
        }
        if !files.isEmpty {
            step.expect()
            Task {
                await stash(files, into: shelf, rememberOrigin: true, copying: copyingFiles, step: step)
                step.landed()
            }
        }
        return true
    }

    /// A picture's data as its pasteboard item holds it, PNG or TIFF first:
    /// anything ImageIO can read.
    private static func imageData(on item: NSPasteboardItem) -> Data? {
        let types = [NSPasteboard.PasteboardType.png, .tiff] + item.types
        return types.lazy
            .filter { item.types.contains($0) && ImageConversion.readableTypes.contains($0.rawValue) }
            .compactMap { item.data(forType: $0) }
            .first
    }

    /// Each link's title, by its address: browsers put both on the link's own
    /// pasteboard item. The address is spelled as the dropped URL spells it
    /// (“Zürich” comes in as “Z%C3%BCrich”), so they match.
    private static func linkTitles(on pasteboard: NSPasteboard) -> [String: String] {
        var titles: [String: String] = [:]
        for item in pasteboard.pasteboardItems ?? [] {
            if let address = item.string(forType: .URL), let title = item.string(forType: urlTitleType) {
                titles[URL(string: address)?.absoluteString ?? address] = title
            }
        }
        return titles
    }

    /// Moves files in, off the main thread, after asking about any over the
    /// limit in Settings; the shelf's manifest is written once for them all.
    private func stash(_ files: [URL], into shelf: URL, rememberOrigin: Bool, copying: Bool = false,
                       step: StashUndoHistory.Step) async {
        let mover = self.mover
        var accepted: [URL] = []
        // Sizes taken for asking, so moving from another disk needn't walk a folder again.
        var measured: [URL: FileSize.Measurement] = [:]
        for file in files {
            if let limit = AppSettings.shared.largeFileLimit.bytes {
                let size = await Task.detached { try? FileSize.measure(file) }.value
                measured[file] = size
                let bytes = size?.bytes ?? 0
                if bytes > limit, !confirmLarge(file, size: bytes) {
                    Log.info("Skipped \(file.lastPathComponent) (\(bytes) bytes): declined")
                    if !rememberOrigin { try? FileManager.default.removeItem(at: file) }
                    continue
                }
            }
            accepted.append(file)
        }
        guard !accepted.isEmpty else { return }
        let sources = accepted
        let sizes = measured
        let results = await Task.detached {
            copying ? mover.stashCopies(sources, into: shelf) : mover.stash(sources, into: shelf, rememberOrigin: rememberOrigin, measured: sizes)
        }.value
        for (file, result) in zip(sources, results) {
            switch result {
            case .success(let stashed):
                // A file from a folder goes back there on undo; a copy, or a file
                // an app wrote somewhere temporary, goes to the Trash.
                if stashed != file {
                    step.record(copying || !rememberOrigin ? .added(stashed) : .movedIn(stashed, from: file))
                }
            case .failure(let error):
                report("Couldn’t stash “\(file.lastPathComponent)”", error)
            }
        }
    }

    /// Apps such as Photos, Mail and web browsers hand over a file only when it's
    /// dropped. It is written to a temporary folder on the same disk, then moved
    /// into the shelf.
    private func receive(_ receiver: NSFilePromiseReceiver, into shelf: URL, fallback: PromiseFallback,
                         step: StashUndoHistory.Step) {
        let incoming = Self.incomingRoot.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
        } catch {
            report("Couldn’t receive the dropped file", error)
            return
        }
        // The reader below is called once for each promised file.
        for _ in 0..<max(1, receiver.fileNames.count) { step.expect() }
        // Runs on promiseQueue. Marked @Sendable so Swift doesn't treat it as
        // main-thread-only (it's written inside a main-actor method) and stop the app.
        receiver.receivePromisedFiles(atDestination: incoming, options: [:], operationQueue: promiseQueue) { @Sendable file, error in
            Task { @MainActor in
                defer {
                    Self.cleanUp(file, in: incoming)
                    step.landed()
                }
                if let error {
                    self.report("Couldn’t receive “\(file.lastPathComponent)”", error)
                    return
                }
                await self.finishPromise(file, into: shelf, fallback: fallback, step: step)
            }
        }
    }

    /// Stashes a promised file once its app has finished writing it. If it never
    /// does (it stays empty), the picture's web address or data from the same
    /// drag stands in. An empty file is never stashed.
    private func finishPromise(_ file: URL, into shelf: URL, fallback: PromiseFallback,
                               step: StashUndoHistory.Step) async {
        let name = file.lastPathComponent
        let started = ContinuousClock.now
        if await PromisedFile.waitUntilWritten(file) {
            let waited = ContinuousClock.now - started
            Log.info("Promised \(name) arrived after \(waited.formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1))))")
            await stash([file], into: shelf, rememberOrigin: false, step: step)
            return
        }
        Log.info("Promised \(name) was still empty after 15 s")
        try? FileManager.default.removeItem(at: file)
        if let address = fallback.webAddress, let data = await Self.downloadImage(address) {
            do {
                try data.write(to: file)
                Log.info("Downloaded \(name) from \(address.host() ?? "the web") instead")
                await stash([file], into: shelf, rememberOrigin: false, step: step)
                return
            } catch {
                Log.error("Couldn’t save the downloaded \(name): \(error.localizedDescription)")
            }
        }
        if let data = fallback.imageData {
            Log.info("Saved the dragged picture data instead of \(name)")
            runInBackground("picture", step) { try $0.stash(imageData: data, into: shelf) }
            return
        }
        report("Couldn’t get “\(name)”", DropError.neverWritten)
    }

    /// The picture at `address`, if it's a picture: dragging a linked image can
    /// carry the link's page instead.
    private static func downloadImage(_ address: URL) async -> Data? {
        guard address.scheme == "https" else { return nil }
        let request = URLRequest(url: address, timeoutInterval: 15)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              response.mimeType?.hasPrefix("image/") == true, !data.isEmpty
        else { return nil }
        return data
    }

    /// Runs something that makes a new item, which undo sends to the Trash.
    private func run(_ what: String, _ step: StashUndoHistory.Step, _ body: (FileMover) throws -> URL) {
        do {
            step.record(.added(try body(mover)))
        } catch {
            report("Couldn’t stash the \(what)", error)
        }
    }

    /// Like `run`, off the main thread: converting a big picture takes a moment.
    private func runInBackground(_ what: String, _ step: StashUndoHistory.Step,
                                 _ body: @escaping @Sendable (FileMover) throws -> URL) {
        let mover = self.mover
        step.expect()
        Task {
            defer { step.landed() }
            do {
                step.record(.added(try await Task.detached { try body(mover) }.value))
            } catch {
                report("Couldn’t stash the \(what)", error)
            }
        }
    }

    /// How long ⌘Z waits for a drop still landing before taking back what has.
    private static let landingWait = Duration.seconds(60)

    /// ⌘Z: takes back the latest drop, paste or move between shelves, whichever
    /// shelf it went to. One still landing (a big copy, a promised file) is taken
    /// back once it has landed, or after a minute what has (the rest, landing
    /// later, is the next ⌘Z's). False if there was nothing left to take back,
    /// or an earlier ⌘Z is still waiting.
    func undoLast() async -> Bool {
        guard !isUndoing, let step = history.popLatest() else { return false }
        isUndoing = true
        defer { isUndoing = false }
        if step.isLanding {
            Log.info("Undo: waiting for the last drop to land")
            if !(await step.untilLanded(within: Self.landingWait)) {
                Log.info("Undo: the drop hasn’t finished landing after \(Self.landingWait); taking back what has")
            }
        }
        let changes = step.takeBack()
        // Items since moved, renamed or trashed are left alone.
        let present = changes.filter { FileManager.default.fileExists(atPath: $0.item.path(percentEncoded: false)) }
        Log.info("Undo: \(present.count) of \(changes.count) \(changes.count == 1 ? "item" : "items") from the last drop")
        guard !present.isEmpty else { return false }
        let mover = self.mover
        let newestFirst = Array(present.reversed())
        let results = await Task.detached { mover.undo(newestFirst) }.value
        for (change, result) in zip(newestFirst, results) {
            if case .failure(let error) = result { report("Couldn’t undo “\(change.item.lastPathComponent)”", error) }
        }
        return true
    }

    /// Once a promised file has moved into a shelf (or couldn't), what's left of
    /// it goes, and its folder too once empty.
    private static func cleanUp(_ file: URL, in folder: URL) {
        try? FileManager.default.removeItem(at: file)
        if (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)))?.isEmpty == true {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private func confirmLarge(_ file: URL, size: Int64) -> Bool {
        Alerts.confirm("Stash “\(file.lastPathComponent)”?",
                       detail: "It’s \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)). "
                           + "Everything in Stash uploads to iCloud and counts against your iCloud storage.",
                       confirm: "Stash")
    }

    private func report(_ message: String, _ error: any Error) {
        Alerts.showError(message, error)
    }
}

/// What else a drag with a promised file carried, in case the promise is never kept.
struct PromiseFallback: Sendable {
    let imageData: Data?
    let webAddress: URL?

    @MainActor
    init(_ pasteboard: NSPasteboard) {
        imageData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        webAddress = urls.first { !$0.isFileURL }
    }
}

private enum DropError: LocalizedError {
    case neverWritten

    var errorDescription: String? {
        "The app it came from never finished handing it over, and the drag had no picture to use instead."
    }
}
