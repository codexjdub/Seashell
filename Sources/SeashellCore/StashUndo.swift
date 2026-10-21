import Foundation

/// One thing a drop, paste or move between shelves did to Stash, and so what
/// ⌘Z does to take it back.
public enum StashChange: Equatable, Sendable {
    /// A file or folder moved in from `from`: undo moves it back there, under its old name.
    case movedIn(URL, from: URL)
    /// Made or copied in (text, a link, a picture, a pasted copy, a file an app
    /// handed over): the original is still where it came from, so undo sends this
    /// one to the Trash.
    case added(URL)
    /// Moved from another shelf, where it was `from`: undo moves it back.
    case movedBetweenShelves(URL, from: URL)

    /// Where the item is now.
    public var item: URL {
        switch self {
        case .movedIn(let item, _), .added(let item), .movedBetweenShelves(let item, _): item
        }
    }
}

/// What ⌘Z can take back: the latest drops, pastes and moves between shelves,
/// one step each, newest last. Kept only while Seashell runs.
@MainActor
public final class StashUndoHistory {
    /// One drop's worth of changes. What a drop stashes is added as it lands,
    /// which for a big copy or a promised file (Photos, Mail) can be a while
    /// after the drop; until then the step is still landing.
    @MainActor
    public final class Step {
        public fileprivate(set) var changes: [StashChange] = []
        /// Pieces of the drop still on their way in.
        private var pending = 0
        private var waiting: [CheckedContinuation<Void, Never>] = []

        public var isLanding: Bool { pending > 0 }

        public func record(_ change: StashChange) {
            changes.append(change)
        }

        /// One more piece of the drop is on its way: files being moved in, a
        /// promised file, a picture being converted.
        public func expect() {
            pending += 1
        }

        /// One expected piece has landed, or given up.
        public func landed() {
            pending = max(0, pending - 1)
            guard pending == 0 else { return }
            let resumed = waiting
            waiting = []
            resumed.forEach { $0.resume() }
        }

        /// Returns once nothing more of the drop is on its way.
        public func untilLanded() async {
            guard isLanding else { return }
            await withCheckedContinuation { waiting.append($0) }
        }
    }

    public static let limit = 20
    private var steps: [Step] = []

    public init() {}

    /// Starts a step for a new drop; the oldest goes once there are more than `limit`.
    public func begin() -> Step {
        let step = Step()
        steps.append(step)
        if steps.count > Self.limit { steps.removeFirst(steps.count - Self.limit) }
        return step
    }

    /// Takes out the newest step that changed anything or is still landing
    /// (wait for it with `untilLanded()`). Steps that finished without changing
    /// anything (a drop that was declined) are skipped.
    public func popLatest() -> Step? {
        while let step = steps.popLast() {
            if !step.changes.isEmpty || step.isLanding { return step }
        }
        return nil
    }
}
