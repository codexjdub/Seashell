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
        /// Those waiting for it to land, by number.
        private var waiting: [Int: CheckedContinuation<Bool, Never>] = [:]
        private var nextWaiter = 0
        /// The history it's in, to go back to if more lands after it was taken back.
        fileprivate weak var history: StashUndoHistory?
        private var isTakenBack = false

        public var isLanding: Bool { pending > 0 }

        /// A piece that lands after the step was taken back (it gave up
        /// waiting, or more came than expected) puts the step back in the
        /// history, so the next ⌘Z takes that back too.
        public func record(_ change: StashChange) {
            changes.append(change)
            if isTakenBack {
                isTakenBack = false
                history?.add(self)
            }
        }

        /// Its changes, for ⌘Z to undo; they're forgotten here.
        public func takeBack() -> [StashChange] {
            defer { changes = [] }
            isTakenBack = true
            return changes
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
            let resumed = waiting.values
            waiting = [:]
            resumed.forEach { $0.resume(returning: true) }
        }

        /// True once nothing more of the drop is on its way; false if `limit`
        /// passes first (a promised file whose app never hands it over, say).
        public func untilLanded(within limit: Duration) async -> Bool {
            guard isLanding else { return true }
            let id = nextWaiter
            nextWaiter += 1
            let timer = Task { [weak self] in
                try? await Task.sleep(for: limit)
                guard !Task.isCancelled else { return }
                self?.waiting.removeValue(forKey: id)?.resume(returning: false)
            }
            defer { timer.cancel() }
            return await withCheckedContinuation { waiting[id] = $0 }
        }
    }

    public static let limit = 20
    private var steps: [Step] = []

    public init() {}

    /// Starts a step for a new drop.
    public func begin() -> Step {
        let step = Step()
        step.history = self
        add(step)
        return step
    }

    /// The newest step now; the oldest goes once there are more than `limit`.
    fileprivate func add(_ step: Step) {
        steps.append(step)
        if steps.count > Self.limit { steps.removeFirst(steps.count - Self.limit) }
    }

    /// Takes out the newest step that changed anything or is still landing
    /// (wait for it with `untilLanded(within:)`). Steps that finished without changing
    /// anything (a drop that was declined) are skipped.
    public func popLatest() -> Step? {
        while let step = steps.popLast() {
            if !step.changes.isEmpty || step.isLanding { return step }
        }
        return nil
    }
}
