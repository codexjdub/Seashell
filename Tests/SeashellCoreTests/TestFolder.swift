import Foundation
@testable import SeashellCore

/// A throwaway folder for one test, deleted afterwards. Tests never touch the
/// real Documents or the real Trash.
final class TestFolder {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "SeashellTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    init() {
        // If this fails, the test's first file write fails with a clear error.
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// Creates (if needed) and returns a subfolder.
    func folder(_ path: String) throws -> URL {
        let url = root.appending(path: path, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    func file(_ path: String, _ contents: String = "contents") throws -> URL {
        let url = root.appending(path: path, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        return url
    }

    /// A FileMover whose "Trash" is a folder inside this test folder.
    func mover(simulateOtherVolume: Bool = false) throws -> FileMover {
        let trash = try folder("Trash")
        return FileMover(trash: { url in
            try FileManager.default.moveItem(at: url, to: trash.appending(path: url.lastPathComponent))
        }, simulateOtherVolume: simulateOtherVolume)
    }

    func names(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []).sorted()
    }
}

func exists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
}

func text(_ url: URL) throws -> String {
    try String(contentsOf: url, encoding: .utf8)
}
