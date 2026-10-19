import Foundation
import os

/// Logs to the unified system log and to `~/Library/Logs/Seashell/Seashell.log`,
/// the file we read together when testing.
public enum Log {
    public static let fileURL = URL.libraryDirectory.appending(path: "Logs/Seashell/Seashell.log")

    private static let subsystem = "io.github.codexjdub.seashell"
    /// Only the app itself writes the file, so test runs don't fill it with noise.
    private static let writesFile = Bundle.main.bundleIdentifier == subsystem
    private static let logger = Logger(subsystem: subsystem, category: "app")
    private static let queue = DispatchQueue(label: "io.github.codexjdub.seashell.log")
    private static let timestamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .current)

    public static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        appendToFile(message)
    }

    public static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        appendToFile("ERROR " + message)
    }

    /// Once the file passes this size, launching keeps only its newest half,
    /// so it can't grow forever.
    static let sizeLimit = 1_000_000

    /// Called at launch, before anything is logged.
    public static func trimFile() {
        guard writesFile else { return }
        queue.async { trim(fileURL, limit: sizeLimit) }
    }

    /// Keeps the newest half of the file if it's over `limit` bytes, starting
    /// at a whole line.
    static func trim(_ url: URL, limit: Int) {
        guard let data = try? Data(contentsOf: url), data.count > limit else { return }
        var kept = data.suffix(limit / 2)
        if let newline = kept.firstIndex(of: UInt8(ascii: "\n")) { kept = kept[(newline + 1)...] }
        try? Data(kept).write(to: url, options: .atomic)
    }

    private static func appendToFile(_ message: String) {
        guard writesFile else { return }
        let line = Data("[\(Date.now.formatted(timestamp))] \(message)\n".utf8)
        queue.async {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: line)
            } else {
                try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? line.write(to: fileURL)
            }
        }
    }
}
