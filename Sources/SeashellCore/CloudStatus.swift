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

    /// What in `folder` isn't fully on this Mac: only in iCloud, or still
    /// downloading. Moving the folder out of iCloud needs all of it here first.
    public static func itemsNotDownloaded(in folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsDownloadingKey]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { [.cloudOnly, .downloading].contains(state(of: $0)) }
    }
}
