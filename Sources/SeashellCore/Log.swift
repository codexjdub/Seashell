import Foundation
import os

/// Logs to the unified system log and to `~/Library/Logs/Seashell/Seashell.log`,
/// the file we read together when testing.
public enum Log {
    public static let fileURL = URL.libraryDirectory.appending(path: "Logs/Seashell/Seashell.log")

    private static let logger = Logger(subsystem: "io.github.codexjdub.seashell", category: "app")
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

    private static func appendToFile(_ message: String) {
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
