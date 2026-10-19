import Foundation
import Testing
@testable import SeashellCore

struct LatestReleaseTests {
    private func release(_ tag: String) -> LatestRelease {
        LatestRelease(tag: tag, page: URL(string: "https://github.com/codexjdub/Seashell/releases/tag/\(tag)")!)
    }

    @Test func readsGitHubsAnswer() throws {
        let json = #"{"tag_name": "v0.1.1", "html_url": "https://github.com/codexjdub/Seashell/releases/tag/v0.1.1", "draft": false}"#
        let latest = try JSONDecoder().decode(LatestRelease.self, from: Data(json.utf8))
        #expect(latest.version == "0.1.1")
        #expect(latest.page.absoluteString.hasSuffix("/releases/tag/v0.1.1"))
    }

    @Test func comparesPartByPartAsNumbers() {
        #expect(release("v0.1.1").isNewer(than: "0.1.0"))
        #expect(release("v0.1.10").isNewer(than: "0.1.9"))
        #expect(release("v0.2").isNewer(than: "0.1.9"))
        #expect(release("1.0.0").isNewer(than: "0.9"))
    }

    @Test func sameOrOlderIsNotNewer() {
        #expect(!release("v0.1.0").isNewer(than: "0.1.0"))
        #expect(!release("v1.0").isNewer(than: "1.0.0"))
        #expect(!release("v0.1.0").isNewer(than: "0.1.1"))
    }

    @Test func oddVersionsAreNeverNewer() {
        #expect(!release("latest").isNewer(than: "0.1.0"))
        #expect(!release("v1.0-beta").isNewer(than: "0.1.0"))
        #expect(!release("v1.0").isNewer(than: "dev"))
    }
}
