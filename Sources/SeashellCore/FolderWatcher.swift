import CoreServices
import Foundation

/// Calls `onChange` on the main queue when anything under `folder` changes,
/// whether from Seashell, Finder, or iCloud bringing in another Mac's edits.
public final class FolderWatcher {
    private let onChange: @MainActor @Sendable () -> Void
    private var stream: FSEventStreamRef?

    public init(folder: URL, onChange: @escaping @MainActor @Sendable () -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let onChange = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue().onChange
            MainActor.assumeIsolated { onChange() }
        }
        guard let stream = FSEventStreamCreate(nil, callback, &context,
                                               [folder.path(percentEncoded: false)] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                               0.3, FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer))
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
