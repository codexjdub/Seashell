import AppKit
import SeashellCore

/// "Check for Updates…" in the menu bar menu: asks GitHub for the newest
/// release when you choose it, and offers its page if it's newer than this copy.
@MainActor
enum UpdateChecker {
    private static var isChecking = false

    static func check() {
        guard !isChecking else { return }
        isChecking = true
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        Log.info("Checking for updates (this is \(current))")
        Task {
            defer { isChecking = false }
            do {
                let latest = try await fetchLatest()
                Log.info("Newest release on GitHub: \(latest.version)")
                if latest.isNewer(than: current) {
                    if Alerts.confirm("Seashell \(latest.version) is available",
                                      detail: "You have \(current). Its page on GitHub has the download.",
                                      confirm: "Open the Download Page") {
                        NSWorkspace.shared.open(latest.page)
                    }
                } else {
                    Alerts.tell("Seashell is up to date", detail: latest.version == current
                        ? "\(current) is the newest version."
                        : "You have \(current); the newest release is \(latest.version).")
                }
            } catch {
                Alerts.showError("Couldn’t check for updates", error)
            }
        }
    }

    private static func fetchLatest() async throws -> LatestRelease {
        var request = URLRequest(url: LatestRelease.apiURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateCheckError.status(status) }
        return try JSONDecoder().decode(LatestRelease.self, from: data)
    }
}

private enum UpdateCheckError: LocalizedError {
    case status(Int)

    var errorDescription: String? {
        switch self {
        case .status(let code): "GitHub answered with status \(code). Try again later."
        }
    }
}
