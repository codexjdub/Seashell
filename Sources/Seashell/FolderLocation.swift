import AppKit
import SeashellCore

/// Where Seashell keeps its folder of shelves and notes: Documents, where iCloud
/// syncs it, unless you choose another folder in Settings. A new folder takes
/// effect when Seashell starts again: it quits, and the next launch moves the
/// folder before anything reads it, so nothing still open saves into the old one.
@MainActor
enum FolderLocation {
    private static let parentKey = "folderParent"
    private static let moveFromKey = "folderMoveFrom"

    /// Settled at launch, then fixed until Seashell quits.
    private(set) static var folders = SeashellFolders.standard
    /// Whether iCloud syncs Seashell's folder, as of launch.
    private(set) static var isInICloud = true

    /// The folder that Seashell's folder is in: Documents unless you chose another.
    static var parent: URL {
        UserDefaults.standard.string(forKey: parentKey).map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? SeashellFolders.defaultParent
    }

    static var isInDocuments: Bool { UserDefaults.standard.string(forKey: parentKey) == nil }

    private static func setParent(_ url: URL) {
        if FolderMove.isSame(url, SeashellFolders.defaultParent) {
            UserDefaults.standard.removeObject(forKey: parentKey)
        } else {
            UserDefaults.standard.set(url.path(percentEncoded: false), forKey: parentKey)
        }
    }

    // MARK: At launch

    /// Seashell's folders, if nothing needs settling first: no move waiting and
    /// the folder there. Otherwise nil, for `settle` to do.
    static func foldersIfSettled() -> SeashellFolders? {
        guard UserDefaults.standard.string(forKey: moveFromKey) == nil, parentIsThere else { return nil }
        return settled()
    }

    /// Finishes a move chosen before the restart, then makes sure the folder is
    /// there: it may be on a disk that isn't connected. Nil if you chose to quit.
    static func settle() async -> SeashellFolders? {
        await finishMove()
        var hasWaited = false
        while !parentIsThere {
            // At login a disk can take a moment to appear.
            if !hasWaited {
                hasWaited = true
                if await appears(within: .seconds(5)) { break }
            }
            switch askAboutMissingFolder() {
            case .tryAgain: continue
            case .use(let parent): setParent(parent)
            case .quit: return nil
            }
        }
        return settled()
    }

    private static var parentIsThere: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: parent.path(percentEncoded: false), isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func appears(within limit: Duration) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(500))
            if parentIsThere { return true }
        }
        return false
    }

    private static func settled() -> SeashellFolders {
        folders = SeashellFolders.inside(parent)
        do {
            for folder in try folders.createMissing() {
                Log.info("Created \(folder.path(percentEncoded: false))")
            }
        } catch {
            Log.error("Could not create Seashell folders: \(error.localizedDescription)")
        }
        isInICloud = FileManager.default.isUbiquitousItem(at: folders.root)
        Log.info("Seashell’s folder: \(folders.root.path(percentEncoded: false)) (\(isInICloud ? "in iCloud" : "not in iCloud"))")
        return folders
    }

    /// The move you chose before the restart. If it can't happen, Seashell
    /// keeps using the old folder and says why.
    private static func finishMove() async {
        guard let sourcePath = UserDefaults.standard.string(forKey: moveFromKey) else { return }
        UserDefaults.standard.removeObject(forKey: moveFromKey)
        let source = URL(filePath: sourcePath, directoryHint: .isDirectory)
        let oldParent = source.deletingLastPathComponent()
        let plan: FolderMove.Plan
        do {
            plan = try FolderMove.plan(from: source, toParent: parent)
        } catch {
            setParent(oldParent)
            Alerts.showError("Couldn’t move Seashell’s folder", error)
            return
        }
        switch plan {
        case .nothing, .startNew:
            return
        case .useExisting(let existing):
            // One turned up there since you chose it (from another Mac, say).
            setParent(oldParent)
            Alerts.tell("Seashell’s folder didn’t move",
                        detail: "\(display(existing)) appeared before it could move there, so Seashell keeps using \(display(source)).")
        case .move(let from, let to):
            Log.info("Moving Seashell’s folder from \(from.path(percentEncoded: false)) to \(to.path(percentEncoded: false))")
            let progress = MoveProgress(to: to)
            let result = await Task.detached { Result { try FolderMove.move(from: from, to: to) } }.value
            progress.finish()
            switch result {
            case .success(nil):
                Log.info("Moved Seashell’s folder")
            case .success(let leftover?):
                Alerts.showError("Seashell’s folder moved, but some of it is still in \(display(from))", leftover)
            case .failure(let error):
                setParent(oldParent)
                Alerts.showError("Couldn’t move Seashell’s folder", error)
            }
        }
    }

    private enum MissingChoice {
        case tryAgain
        case use(URL)
        case quit
    }

    private static func askAboutMissingFolder() -> MissingChoice {
        Log.info("Seashell’s folder isn’t there: \(parent.path(percentEncoded: false))")
        let alert = NSAlert()
        alert.messageText = "Seashell’s folder isn’t there"
        alert.informativeText = "Seashell keeps your shelves and notes in \(display(SeashellFolders.root(in: parent))), which can’t be found. "
            + "If it’s on a disk that isn’t connected, connect it and click Try Again."
        for title in ["Try Again", "Choose…", "Use Documents", "Quit"] { alert.addButton(withTitle: title) }
        switch Alerts.run(alert) {
        case .alertFirstButtonReturn:
            return .tryAgain
        case .alertSecondButtonReturn:
            let panel = folderPanel()
            return panel.runModal() == .OK ? panel.url.map(MissingChoice.use) ?? .tryAgain : .tryAgain
        case .alertThirdButtonReturn:
            return .use(SeashellFolders.defaultParent)
        default:
            return .quit
        }
    }

    // MARK: Choosing another folder

    /// For choosing the folder to keep Seashell's folder in.
    static func folderPanel() -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = parent
        panel.prompt = "Choose"
        panel.message = "Choose where Seashell keeps your shelves and notes. They go in a folder named Seashell inside the one you choose."
        return panel
    }

    /// Moves Seashell's folder into `newParent`, or switches to a Seashell
    /// folder already there, after asking; then restarts.
    static func change(to newParent: URL) {
        let current = folders.root
        let plan: FolderMove.Plan
        do {
            plan = try FolderMove.plan(from: current, toParent: newParent)
        } catch {
            Alerts.showError("Seashell’s folder can’t go there", error)
            return
        }
        let place = name(of: newParent)
        switch plan {
        case .nothing:
            return
        case .useExisting(let existing):
            guard Alerts.confirm("Use the Seashell folder in “\(place)”?",
                                 detail: "Seashell restarts and shows the shelves and notes in \(display(existing)). "
                                     + "Those in \(display(current)) stay where they are.",
                                 confirm: "Use It and Restart") else { return }
            UserDefaults.standard.removeObject(forKey: moveFromKey)
        case .startNew(let fresh):
            guard Alerts.confirm("Start a new Seashell folder in “\(place)”?",
                                 detail: "Seashell restarts and keeps your shelves and notes in \(display(fresh)).",
                                 confirm: "Start It and Restart") else { return }
            UserDefaults.standard.removeObject(forKey: moveFromKey)
        case .move(let from, let to):
            let goesToICloud = FileManager.default.isUbiquitousItem(at: newParent)
            let leavesICloud = isInICloud && !goesToICloud
            if leavesICloud, !isAllDownloaded(from) { return }
            let iCloudNote = leavesICloud ? " iCloud won’t sync them there, so they’ll disappear from your other Macs."
                : !isInICloud && goesToICloud ? " iCloud will sync them to your other Macs." : ""
            guard Alerts.confirm("Move Seashell’s folder to “\(place)”?",
                                 detail: "Your shelves and notes move to \(display(to)), and Seashell restarts.\(iCloudNote)",
                                 confirm: "Move and Restart") else { return }
            UserDefaults.standard.set(from.path(percentEncoded: false), forKey: moveFromKey)
        }
        setParent(newParent)
        restart()
    }

    /// Leaving iCloud needs everything on this Mac first. Starts downloading
    /// what isn't and says so; true if it's all here.
    private static func isAllDownloaded(_ folder: URL) -> Bool {
        let missing = CloudStatus.itemsNotDownloaded(in: folder)
        guard !missing.isEmpty else { return true }
        for url in missing { try? CloudStatus.startDownloading(url) }
        Log.info("Folder move: \(missing.count) item(s) not on this Mac yet, downloading")
        Alerts.tell(missing.count == 1 ? "An item is only in iCloud" : "\(missing.count) items are only in iCloud",
                    detail: "Everything has to be on this Mac before Seashell’s folder can leave iCloud. "
                        + "It’s downloading now; choose the folder again once it’s done.")
        return false
    }

    /// Quits, then opens Seashell again once this copy has gone (a second copy
    /// would bow out).
    private static func restart() {
        Log.info("Restarting to use \(SeashellFolders.root(in: parent).path(percentEncoded: false))")
        let helper = Process()
        helper.executableURL = URL(filePath: "/bin/sh")
        helper.arguments = ["-c", "while /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$1\"",
                            "sh", Bundle.main.bundlePath]
        do {
            try helper.run()
        } catch {
            Alerts.showError("Open Seashell again to use its new folder", error)
        }
        NSApp.terminate(nil)
    }

    // MARK: Names

    /// How a folder reads in messages: `~/Documents/Seashell`, or
    /// `iCloud Drive/Projects/Seashell`.
    static func display(_ url: URL) -> String {
        var path = url.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        let iCloudDrive = NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs"
        if path == iCloudDrive || path.hasPrefix(iCloudDrive + "/") { return "iCloud Drive" + path.dropFirst(iCloudDrive.count) }
        return (path as NSString).abbreviatingWithTildeInPath
    }

    /// A folder's name as Finder shows it.
    static func name(of url: URL) -> String {
        var path = url.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return FileManager.default.displayName(atPath: path)
    }

    /// Where Main is, the way Finder's folders lead there.
    static var mainShelfInFinder: String {
        "\(name(of: parent)) ▸ \(SeashellFolders.folderName) ▸ Stash ▸ \(SeashellFolders.defaultShelfName)"
    }
}

/// "Moving your shelves and notes…" while a move across disks copies; shown
/// only if it takes more than a moment.
@MainActor
private final class MoveProgress {
    private var window: NSPanel?
    private var isFinished = false

    init(to destination: URL) {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            self?.show(destination)
        }
    }

    private func show(_ destination: URL) {
        guard !isFinished else { return }
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)
        let label = NSTextField(wrappingLabelWithString: "Moving your shelves and notes to \(FolderLocation.display(destination))…")
        label.preferredMaxLayoutWidth = 300
        let stack = NSStackView(views: [spinner, label])
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Seashell"
        panel.contentView = stack
        panel.setContentSize(stack.fittingSize)
        panel.center()
        NSApp.activate()
        panel.orderFrontRegardless()
        window = panel
    }

    func finish() {
        isFinished = true
        window?.orderOut(nil)
        window = nil
    }
}
