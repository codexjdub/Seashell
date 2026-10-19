import Foundation
import Testing
@testable import SeashellCore

struct LogTests {
    private static func lines(_ count: Int) -> String {
        (1...count).map { "[2026-10-18] line \($0)\n" }.joined()
    }

    @Test func leavesASmallLogAlone() throws {
        let folder = TestFolder()
        let log = try folder.file("Seashell.log", Self.lines(10))
        Log.trim(log, limit: 1_000)
        #expect(try String(contentsOf: log, encoding: .utf8) == Self.lines(10))
    }

    @Test func keepsTheNewestHalfFromAWholeLine() throws {
        let folder = TestFolder()
        let log = try folder.file("Seashell.log", Self.lines(200))
        Log.trim(log, limit: 1_000)
        let kept = try String(contentsOf: log, encoding: .utf8)
        #expect(kept.utf8.count <= 500)
        #expect(kept.hasPrefix("[2026-10-18] line "))
        #expect(kept.hasSuffix("line 200\n"))
    }
}
