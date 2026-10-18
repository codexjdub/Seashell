import Foundation
import Testing
@testable import SeashellCore

struct PromisedFileTests {
    let folder = TestFolder()

    @Test func finishedFileIsReadyOnceItSettles() async throws {
        let file = try folder.file("photo.jpg", "already here")
        #expect(await PromisedFile.waitUntilWritten(file, settle: .milliseconds(100), timeout: .seconds(2), poll: .milliseconds(20)))
    }

    @Test func waitsForAnAppThatWritesLate() async throws {
        // Like Chrome: the file is reported empty, and the picture arrives a moment later.
        let file = try folder.file("screenshot.png", "")
        Task.detached {
            try? await Task.sleep(for: .milliseconds(300))
            try? Data(repeating: 7, count: 5_000).write(to: file)
        }
        #expect(await PromisedFile.waitUntilWritten(file, settle: .milliseconds(150), timeout: .seconds(3), poll: .milliseconds(20)))
        #expect(try FileSize.of(URL(fileURLWithPath: file.path(percentEncoded: false))) == 5_000)
    }

    @Test func givesUpOnAFileThatStaysEmpty() async throws {
        let file = try folder.file("never.png", "")
        #expect(await !PromisedFile.waitUntilWritten(file, settle: .milliseconds(50), timeout: .milliseconds(300), poll: .milliseconds(20)))
    }

    @Test func givesUpOnAMissingFile() async {
        let file = folder.root.appending(path: "missing.png")
        #expect(await !PromisedFile.waitUntilWritten(file, settle: .milliseconds(50), timeout: .milliseconds(300), poll: .milliseconds(20)))
    }
}
