import Foundation
import Testing
@testable import SeashellCore

struct FileNamingTests {
    let folder = TestFolder()

    @Test func freeNameIsKept() throws {
        let url = FileNaming.uniqueDestination(for: "report.pdf", in: folder.root, isDirectory: false)
        #expect(url.lastPathComponent == "report.pdf")
    }

    @Test func clashesCountUpLikeFinder() throws {
        try folder.file("report.pdf")
        #expect(FileNaming.uniqueDestination(for: "report.pdf", in: folder.root, isDirectory: false).lastPathComponent == "report 2.pdf")
        try folder.file("report 2.pdf")
        #expect(FileNaming.uniqueDestination(for: "report.pdf", in: folder.root, isDirectory: false).lastPathComponent == "report 3.pdf")
    }

    @Test func numberedCopyCountsOnFromItsNumber() throws {
        try folder.file("report.pdf")
        try folder.file("report 2.pdf")
        #expect(FileNaming.uniqueDestination(for: "report 2.pdf", in: folder.root, isDirectory: false).lastPathComponent == "report 3.pdf")
    }

    @Test func clashIgnoresCase() throws {
        try folder.file("Report.pdf")
        #expect(FileNaming.uniqueDestination(for: "report.pdf", in: folder.root, isDirectory: false).lastPathComponent == "report 2.pdf")
    }

    @Test func noExtensionAndFolders() throws {
        try folder.file("Makefile")
        _ = try folder.folder("Photos.2026")
        #expect(FileNaming.uniqueDestination(for: "Makefile", in: folder.root, isDirectory: false).lastPathComponent == "Makefile 2")
        #expect(FileNaming.uniqueDestination(for: "Photos.2026", in: folder.root, isDirectory: true).lastPathComponent == "Photos.2026 2")
    }

    @Test func snippetUsesFirstSixWords() {
        let name = FileNaming.snippetName(for: "Recently, I lived for a few years in India", date: .now)
        #expect(name == "Recently, I lived for a few.txt")
    }

    @Test func snippetStaysWithinFortyCharacters() {
        let name = FileNaming.snippetName(for: "Extraordinarily comprehensive internationalization documentation", date: .now)
        #expect(name == "Extraordinarily comprehensive.txt")
        let oneLongWord = FileNaming.snippetName(for: String(repeating: "a", count: 60), date: .now)
        #expect(oneLongWord == String(repeating: "a", count: 40) + ".txt")
    }

    @Test func snippetSpansLinesAndDropsUnsafeCharacters() {
        #expect(FileNaming.snippetName(for: "  ..hidden/path:here\nnext line", date: .now) == "hidden-path-here next line.txt")
    }

    @Test func emptySnippetFallsBackToDate() throws {
        let date = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 9, minute: 42)))
        #expect(FileNaming.snippetName(for: " \n\t ", date: date) == "Snippet 2026-10-17 0942.txt")
    }

    @Test func linkNames() throws {
        let url = try #require(URL(string: "https://example.com/page"))
        #expect(FileNaming.linkName(for: url, title: "Example: Domain") == "Example- Domain.webloc")
        #expect(FileNaming.linkName(for: url, title: nil) == "example.com.webloc")
        #expect(FileNaming.linkName(for: url, title: "   ") == "example.com.webloc")
    }

    @Test func nameEndingInANumberKeepsIt() throws {
        try folder.file("Budget 2024.xlsx")
        #expect(FileNaming.uniqueDestination(for: "Budget 2024.xlsx", in: folder.root, isDirectory: false).lastPathComponent
                == "Budget 2024 2.xlsx")
        try folder.file("IMG.jpg")
        try folder.file("IMG 0001.jpg")
        #expect(FileNaming.uniqueDestination(for: "IMG 0001.jpg", in: folder.root, isDirectory: false).lastPathComponent
                == "IMG 0001 2.jpg", "a leading zero is part of the name, not a count")
    }

    @Test func numberedCopies() {
        #expect(FileNaming.isNumberedCopy("report 2.pdf", of: "report.pdf"))
        #expect(FileNaming.isNumberedCopy("Report 12.PDF", of: "report.pdf"))
        #expect(FileNaming.isNumberedCopy("Makefile 3", of: "Makefile"))
        #expect(!FileNaming.isNumberedCopy("report.pdf", of: "report.pdf"))
        #expect(!FileNaming.isNumberedCopy("report 1.pdf", of: "report.pdf"))
        #expect(!FileNaming.isNumberedCopy("report 02.pdf", of: "report.pdf"))
        #expect(!FileNaming.isNumberedCopy("report 2a.pdf", of: "report.pdf"))
        #expect(!FileNaming.isNumberedCopy("reports 2.pdf", of: "report.pdf"))
    }
}
