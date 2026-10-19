import Foundation

/// The newest release on GitHub, for "Check for Updates…". Seashell asks only
/// when you choose that, never in the background.
public struct LatestRelease: Decodable, Equatable, Sendable {
    /// GitHub's answer for the newest release that isn't a draft or pre-release.
    public static let apiURL = URL(string: "https://api.github.com/repos/codexjdub/Seashell/releases/latest")!

    public let tag: String
    /// The release's page, where the zip is.
    public let page: URL

    enum CodingKeys: String, CodingKey {
        case tag = "tag_name"
        case page = "html_url"
    }

    public init(tag: String, page: URL) {
        self.tag = tag
        self.page = page
    }

    /// The version in the tag: "v0.1.1" → "0.1.1".
    public var version: String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// Compared part by part as numbers: 0.1.10 is newer than 0.1.9, and 1.0
    /// is the same as 1.0.0. A version that isn't numbers is never newer.
    public func isNewer(than current: String) -> Bool {
        guard let latest = Self.parts(version), let current = Self.parts(current) else { return false }
        for index in 0..<max(latest.count, current.count) {
            let a = index < latest.count ? latest[index] : 0
            let b = index < current.count ? current[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func parts(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return nil }
        return parts.compactMap { $0 }
    }
}
