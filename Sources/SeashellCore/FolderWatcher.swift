import CoreServices
import Foundation

/// Calls `onChange` on the main queue when anything under `folder` changes,
/// whether from Seashell, Finder, or iCloud bringing in another Mac's edits.
/// It's told which folders changed, or nil when macOS can't say (it dropped
/// events, say) and anything under `folder` may have.
public final class FolderWatcher {
    private let onChange: @MainActor @Sendable (_ changed: [URL]?) -> Void
    private var stream: FSEventStreamRef?

    /// Events that mean macOS lost track of what changed, so everything has to be looked at.
    private static let lostTrack = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
        | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagEventIdsWrapped | kFSEventStreamEventFlagRootChanged
        | kFSEventStreamEventFlagMount | kFSEventStreamEventFlagUnmount)

    public init(folder: URL, onChange: @escaping @MainActor @Sendable (_ changed: [URL]?) -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let onChange = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue().onChange
            // With kFSEventStreamCreateFlagUseCFTypes, the paths are a CFArray of CFStrings.
            let list = unsafeBitCast(paths, to: NSArray.self) as? [String]
            let lost = (0..<count).contains { flags[$0] & FolderWatcher.lostTrack != 0 }
            let changed = lost ? nil : list?.map { URL(filePath: $0, directoryHint: .isDirectory) }
            MainActor.assumeIsolated { onChange(changed) }
        }
        let flags = kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes
        guard let stream = FSEventStreamCreate(nil, callback, &context,
                                               [folder.path(percentEncoded: false)] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                               0.3, FSEventStreamCreateFlags(flags))
        else {
            Log.error("Couldn’t watch \(folder.path(percentEncoded: false))")
            return
        }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
