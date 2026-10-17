import Foundation

/// NSFileCoordinator wrappers. Coordinated access lets iCloud (and Finder) see
/// Seashell's changes as orderly writes rather than surprises mid-sync.
enum Coordinated {
    static func read<T>(_ url: URL, _ body: (URL) throws -> T) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, any Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { url in
            result = Result { try body(url) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }

    static func write(_ url: URL, options: NSFileCoordinator.WritingOptions = [], _ body: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var bodyError: (any Error)?
        NSFileCoordinator().coordinate(writingItemAt: url, options: options, error: &coordinationError) { url in
            do { try body(url) } catch { bodyError = error }
        }
        if let coordinationError { throw coordinationError }
        if let bodyError { throw bodyError }
    }

    static func move(_ source: URL, to destination: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var moveError: (any Error)?
        coordinator.coordinate(writingItemAt: source, options: .forMoving,
                               writingItemAt: destination, options: .forReplacing,
                               error: &coordinationError) { source, destination in
            do {
                coordinator.item(at: source, willMoveTo: destination)
                try FileManager.default.moveItem(at: source, to: destination)
                coordinator.item(at: source, didMoveTo: destination)
            } catch {
                moveError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let moveError { throw moveError }
    }
}
