import AppKit
import SeashellCore

/// Turns a drop (files, promised files, links, images, text) into Stash items.
/// Shared by every drop target that stashes: the menu bar icon now, the panel
/// and floating shelf later.
@MainActor
final class StashDropper {
    static let acceptedTypes: [NSPasteboard.PasteboardType] =
        [.fileURL, .URL, .png, .tiff, .string]
        + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }

    private static let urlTitleType = NSPasteboard.PasteboardType("public.url-name")

    private let mover: FileMover
    private let promiseQueue = OperationQueue()

    init(mover: FileMover) {
        self.mover = mover
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
        let pasteboard = info.draggingPasteboard
        // One object per dragged item, in order of preference.
        let classes: [AnyClass] = [NSFilePromiseReceiver.self, NSURL.self, NSImage.self, NSString.self]
        guard let objects = pasteboard.readObjects(forClasses: classes, options: nil), !objects.isEmpty else {
            Log.info("Drop had nothing Seashell can stash: \(pasteboard.types?.map(\.rawValue) ?? [])")
            return false
        }

        var files: [URL] = []
        for object in objects {
            switch object {
            case let receiver as NSFilePromiseReceiver:
                receive(receiver, into: shelf)
            case let url as URL where url.isFileURL:
                files.append(url)
            case let url as URL:
                run("link") { try $0.stash(link: url, title: pasteboard.string(forType: Self.urlTitleType), into: shelf) }
            case let image as NSImage:
                guard let data = image.tiffRepresentation else { continue }
                run("image") { try $0.stash(imageData: data, into: shelf) }
            case let text as String:
                run("text") { try $0.stash(text: text, into: shelf) }
            default:
                continue
            }
        }
        if !files.isEmpty {
            Task { await stash(files, into: shelf, rememberOrigin: true) }
        }
        return true
    }

    /// Moves files in one by one, off the main thread, asking first about ones
    /// over the limit in Settings.
    private func stash(_ files: [URL], into shelf: URL, rememberOrigin: Bool) async {
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
                _ = try await Task.detached { try mover.stash(file, into: shelf, rememberOrigin: rememberOrigin) }.value
            } catch {
                report("Couldn’t stash “\(file.lastPathComponent)”", error)
            }
        }
    }

    /// Apps such as Photos and Mail hand over a file only when it's dropped. It is
    /// written to a temporary folder on the same disk, then moved into the shelf.
    private func receive(_ receiver: NSFilePromiseReceiver, into shelf: URL) {
        let incoming = URL.temporaryDirectory.appending(path: "Seashell-Incoming/\(UUID().uuidString)", directoryHint: .isDirectory)
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
                if let error {
                    self.report("Couldn’t receive “\(file.lastPathComponent)”", error)
                    return
                }
                await self.stash([file], into: shelf, rememberOrigin: false)
            }
        }
    }

    private func run(_ what: String, _ body: (FileMover) throws -> Void) {
        do {
            try body(mover)
        } catch {
            report("Couldn’t stash the \(what)", error)
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
