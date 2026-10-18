import Foundation

/// Files promised in a drag are written by the app they come from, after the
/// drop. Older promises (Chrome and other Chromium browsers use them) report the
/// file before anything is written, so wait until it has content that has
/// stopped changing.
public enum PromisedFile {
    /// True once `url` has content whose size has held for `settle`; false if
    /// that doesn't happen within `timeout`.
    public static func waitUntilWritten(_ url: URL, settle: Duration = .milliseconds(500),
                                        timeout: Duration = .seconds(15), poll: Duration = .milliseconds(100)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        var lastSize: Int64 = -1
        var stableSince = clock.now
        while clock.now < deadline {
            // A fresh URL each time: a URL caches the size it read first.
            let size = (try? FileSize.of(URL(fileURLWithPath: url.path(percentEncoded: false)))) ?? 0
            if size != lastSize {
                lastSize = size
                stableSince = clock.now
            } else if size > 0, clock.now - stableSince >= settle {
                return true
            }
            try? await Task.sleep(for: poll)
        }
        return false
    }
}
