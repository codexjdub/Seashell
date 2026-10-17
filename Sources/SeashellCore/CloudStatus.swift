import Foundation

public enum CloudState: Sendable, Equatable {
    /// Not in iCloud Drive at all.
    case local
    /// In iCloud and on this Mac.
    case downloaded
    /// In iCloud only ("Optimize Mac Storage" removed the local copy).
    case cloudOnly
    case downloading
}

public enum CloudStatus {
    public static func state(of url: URL) -> CloudState {
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsDownloadingKey]
        guard let values = try? url.resourceValues(forKeys: keys), values.isUbiquitousItem == true else { return .local }
        if values.ubiquitousItemIsDownloading == true { return .downloading }
        switch values.ubiquitousItemDownloadingStatus {
        case .current?, .downloaded?: return .downloaded
        default: return .cloudOnly
        }
    }

    /// Starts bringing a cloud-only item down to this Mac.
    public static func startDownloading(_ url: URL) throws {
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
    }
}
