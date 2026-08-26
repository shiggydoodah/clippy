import Foundation
import os

/// Enforces the retention rules in order: max count, max age, orphaned blobs.
/// Favourites are exempt from every rule — enforced inside the storage
/// primitives themselves, not here, so no future caller can forget.
///
/// An actor so the timer loop and the after-capture trigger cannot run a
/// sweep concurrently; all real work happens inside the StorageService
/// actor anyway, far from the main thread.
actor RetentionEngine {

    /// Value snapshot so a run is consistent even if settings change
    /// mid-sweep, and so tests can inject policies directly.
    struct Policy {
        /// 0 = unlimited.
        var maxItems: Int
        /// 0 = keep forever.
        var maxAgeSeconds: Int

        static func current() -> Policy {
            Policy(maxItems: AppSettings.maxItems, maxAgeSeconds: AppSettings.maxAgeSeconds)
        }
    }

    private let logger = Logger(subsystem: "com.clip.app", category: "RetentionEngine")
    private let storage: StorageService?
    private var timerTask: Task<Void, Never>?

    init(storage: StorageService?) {
        self.storage = storage
    }

    /// Launch-time entry point: one immediate sweep, then every 5 minutes.
    func start() async {
        await run(reason: "launch")
        guard timerTask == nil else { return }
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                await self?.run(reason: "timer")
            }
        }
    }

    /// Called by the capture path after every stored item. Skips the orphan
    /// sweep: enumerating the whole blobs/ directory per copy is wasted I/O,
    /// and orphans (which only failed deletes create) are reclaimed by the
    /// launch and timer runs anyway.
    func runAfterCapture() async {
        await run(reason: "capture", sweepingOrphans: false)
    }

    func run(reason: String, policy: Policy? = nil, sweepingOrphans: Bool = true) async {
        guard let storage else { return }
        let policy = policy ?? Policy.current()
        do {
            var pruned = 0
            if policy.maxItems > 0 {
                pruned += try await storage.pruneHistory(toCount: policy.maxItems)
            }
            if policy.maxAgeSeconds > 0 {
                let cutoff = Date().addingTimeInterval(-TimeInterval(policy.maxAgeSeconds))
                pruned += try await storage.pruneHistory(olderThan: cutoff)
            }
            let orphans = sweepingOrphans ? try await storage.deleteOrphanedBlobs() : 0
            if pruned > 0 || orphans > 0 {
                logger.log("Retention (\(reason, privacy: .public)): pruned \(pruned) items, \(orphans) orphaned blobs")
            }
        } catch {
            logger.error("Retention sweep failed: \(String(describing: error), privacy: .public)")
        }
    }
}
