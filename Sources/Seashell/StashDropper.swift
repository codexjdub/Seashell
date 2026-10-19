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
    /// source such as TextEdit would delete the dragged text on `move`.
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

    /// Stashes everything in the drop into `shelf`. Returns false if nothing was usable.
    func accept(_ info: any NSDraggingInfo, into shelf: URL) -> Bool {
        accept(info.draggingPasteboard, into: shelf, copyingFiles: false)
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
        let step = history.begin()

        var files: [URL] = []
        for object in objects {
            switch object {
            case let receiver as NSFilePromiseReceiver:
                receive(receiver, into: shelf, fallback: fallback ?? PromiseFallback(pasteboard), step: step)
            case let url as URL where url.isFileURL:
                files.append(url)
            case let url as URL:
                run("link", step) { try $0.stash(link: url, title: pasteboard.string(forType: Self.urlTitleType), into: shelf) }
            case let image as NSImage:
                // A lone picture's PNG goes in as it is, rather than through a
                // full-size TIFF; anything else is converted in the background.
                let png = objects.count == 1 ? pasteboard.data(forType: .png) : nil
                guard let data = png ?? image.tiffRepresentation else { continue }
                runInBackground("image", step) { try $0.stash(imageData: data, into: shelf) }
            case let text as String:
                run("text", step) { try $0.stash(text: text, into: shelf) }
            default:
                continue
            }
        }
        if !files.isEmpty {
            Task { await stash(files, into: shelf, rememberOrigin: true, copying: copyingFiles, step: step) }
        }
        return true
    }

    /// Moves files in one by one, off the main thread, asking first about ones
    /// over the limit in Settings.
    private func stash(_ files: [URL], into shelf: URL, rememberOrigin: Bool, copying: Bool = false,
                       step: StashUndoHistory.Step) async {
        let mover = self.mover
        for file in files {
            if let limit = AppSettings.shared.largeFileLimit.bytes {
                let size = await Task.detached { (try? FileSize.of(file)) ?? 0 }.value
                if size > limit, !confirmLarge(file, size: size) {
                    Log.info("Skipped \(file.lastPathComponent) (\(size) bytes): declined")
                    if !rememberOrigin { try? FileManager.default.removeItem(at: file) }
                    continue
                }
            }
            do {
                let stashed = try await Task.detached {
                    copying ? try mover.stashCopy(file, into: shelf) : try mover.stash(file, into: shelf, rememberOrigin: rememberOrigin)
                }.value
                // A file from a folder goes back there on undo; a copy, or a file
                // an app wrote somewhere temporary, goes to the Trash.
                if stashed != file {
                    step.record(copying || !rememberOrigin ? .added(stashed) : .movedIn(stashed, from: file))
                }
            } catch {
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
        // Runs on promiseQueue. Marked @Sendable so Swift doesn't treat it as
        // main-thread-only (it's written inside a main-actor method) and stop the app.
        receiver.receivePromisedFiles(atDestination: incoming, options: [:], operationQueue: promiseQueue) { @Sendable file, error in
            Task { @MainActor in
                defer { Self.cleanUp(file, in: incoming) }
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
        Task {
            do {
                step.record(.added(try await Task.detached { try body(mover) }.value))
            } catch {
                report("Couldn’t stash the \(what)", error)
            }
        }
    }

    /// ⌘Z: takes back the latest drop, paste or move between shelves, whichever
    /// shelf it went to. False if there was nothing left to take back.
    func undoLast() async -> Bool {
        guard let changes = history.popLatest() else { return false }
        // Items since moved, renamed or trashed are left alone.
        let present = changes.filter { FileManager.default.fileExists(atPath: $0.item.path(percentEncoded: false)) }
        Log.info("Undo: \(present.count) of \(changes.count) \(changes.count == 1 ? "item" : "items") from the last drop")
        guard !present.isEmpty else { return false }
        let mover = self.mover
        for change in present.reversed() {
            do {
                _ = try await Task.detached { try mover.undo(change) }.value
            } catch {
                report("Couldn’t undo “\(change.item.lastPathComponent)”", error)
            }
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
