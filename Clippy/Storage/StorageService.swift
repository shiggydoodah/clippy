import CryptoKit
import Foundation
import GRDB
import os

/// Owns the SQLite database and the blob store. An actor so every caller —
/// the clipboard monitor's queue, the panel, the settings window — goes through
/// one serialised access path with no hand-rolled locking; the serial order
/// also makes the check-then-insert dedupe race-free.
actor StorageService {

    enum Mode {
        /// clip.sqlite and blobs/ under this directory.
        case persistent(directory: URL)
        /// History is fully in-memory and discarded on quit.
        /// Favourites are the exception: they are mirrored into a persistent
        /// vault (clip.sqlite + blobs/ at `vaultDirectory`) so they survive
        /// restart. A nil vault keeps absolutely everything in memory.
        case ephemeral(vaultDirectory: URL?)
    }

    /// The on-disk home for favourites while the main store is in-memory.
    private struct FavouritesVault {
        let dbQueue: DatabaseQueue
        let blobStore: BlobStore
    }

    enum SaveOutcome: Equatable, Sendable {
        case inserted
        /// Same contentHash already stored — lastUsedAt refreshed instead,
        /// which floats the item back to the top of the history.
        case deduplicated
    }

    private let dbQueue: DatabaseQueue
    private let blobStore: BlobStore
    /// Non-nil only in ephemeral mode with a vault directory.
    private let vault: FavouritesVault?
    /// Hashes mid-save: the actor is reentrant at `save`'s awaited insert,
    /// so an orphan sweep can interleave between the blob write and the row
    /// landing — these blobs are not orphans and must not be swept.
    private var hashesBeingSaved: Set<String> = []
    private let logger = Logger(subsystem: "com.clip.app", category: "StorageService")

    /// ~/Library/Application Support/Clip/
    static func defaultDirectory() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Clip", isDirectory: true)
    }

    init(mode: Mode) throws {
        switch mode {
        case .persistent(let directory):
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            dbQueue = try DatabaseQueue(path: directory.appendingPathComponent("clip.sqlite").path)
            blobStore = BlobStore(rootURL: directory.appendingPathComponent("blobs", isDirectory: true))
            vault = nil
        case .ephemeral(let vaultDirectory):
            dbQueue = try DatabaseQueue()
            blobStore = BlobStore(rootURL: nil)
            if let vaultDirectory {
                try FileManager.default.createDirectory(at: vaultDirectory, withIntermediateDirectories: true)
                vault = FavouritesVault(
                    dbQueue: try DatabaseQueue(path: vaultDirectory.appendingPathComponent("clip.sqlite").path),
                    blobStore: BlobStore(rootURL: vaultDirectory.appendingPathComponent("blobs", isDirectory: true))
                )
            } else {
                vault = nil
            }
        }
        try Migrations.migrator().migrate(dbQueue)
        if let vault {
            try Migrations.migrator().migrate(vault.dbQueue)
            try Self.loadVault(vault, into: dbQueue, logger: logger)
        }
    }

    /// Ephemeral startup: favourites come back from the vault; any history
    /// rows left over from a previously-persistent clip.sqlite are pruned —
    /// the user turned persistence off, so persisted history must go.
    private static func loadVault(
        _ vault: FavouritesVault,
        into dbQueue: DatabaseQueue,
        logger: Logger
    ) throws {
        let favourites = try vault.dbQueue.write { db -> [Item] in
            let stale = try Item.filter(Item.Columns.isFavourite == false).fetchCount(db)
            if stale > 0 {
                try Item.filter(Item.Columns.isFavourite == false).deleteAll(db)
                logger.log("Pruned \(stale) persisted history rows on ephemeral startup")
            }
            return try Item.fetchAll(db)
        }
        try dbQueue.write { db in
            for item in favourites {
                try item.insert(db)
            }
        }
        if !favourites.isEmpty {
            logger.log("Restored \(favourites.count) favourites from the vault")
        }
    }

    // MARK: - Capture path

    /// Stores a capture, deduplicating by SHA-256 of the payload. Errors
    /// propagate — the capture path must never fail silently (CLAUDE.md).
    /// `now` is injectable so tests can pin timestamps.
    func save(_ capture: CapturedItem, now: Date = Date()) async throws -> SaveOutcome {
        let payload = capture.blobData ?? Data((capture.textContent ?? "").utf8)
        guard !payload.isEmpty else { throw StorageError.emptyCapture }
        let hash = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()

        // Refresh-if-exists first, so a re-copy never rewrites its blob.
        // Copying the content again is a fresh history event, so it also
        // undoes a previous "remove from history" — otherwise the user would
        // copy something and watch it not appear.
        let refreshedCount = try await dbQueue.write { db in
            try Item
                .filter(Item.Columns.contentHash == hash)
                .updateAll(
                    db,
                    Item.Columns.lastUsedAt.set(to: now),
                    Item.Columns.isHiddenFromHistory.set(to: false)
                )
        }
        if refreshedCount > 0 {
            // A favourite's vault copy tracks lastUsedAt too, so its
            // ordering fallback stays truthful across restarts.
            if let vault {
                _ = try? await vault.dbQueue.write { db in
                    try Item
                        .filter(Item.Columns.contentHash == hash)
                        .updateAll(
                            db,
                            Item.Columns.lastUsedAt.set(to: now),
                            Item.Columns.isHiddenFromHistory.set(to: false)
                        )
                }
            }
            logger.log("Deduplicated \(capture.kind.rawValue, privacy: .public) capture")
            return .deduplicated
        }

        hashesBeingSaved.insert(hash)
        defer { hashesBeingSaved.remove(hash) }

        var blobPath: String?
        if let data = capture.blobData {
            blobPath = try blobStore.write(
                data,
                contentHash: hash,
                fileExtension: capture.blobFileExtension ?? "bin"
            )
        }

        let item = Item(
            id: UUID(),
            kind: capture.kind,
            contentHash: hash,
            textContent: capture.textContent,
            blobPath: blobPath,
            preview: capture.preview,
            byteSize: capture.byteSize,
            sourceAppID: capture.sourceAppID,
            sourceAppName: capture.sourceAppName,
            createdAt: now,
            lastUsedAt: now,
            isFavourite: false,
            favouriteRank: nil,
            favouriteLabel: nil,
            isHiddenFromHistory: false
        )
        try await dbQueue.write { db in try item.insert(db) }
        logger.log("Stored \(capture.kind.rawValue, privacy: .public) item, \(capture.byteSize) bytes")
        return .inserted
    }

    // MARK: - Mutations

    /// The History tab's delete. A favourite only drops out of history —
    /// the row and its blob stay, because a favourite is removed from the
    /// Favourites tab and nowhere else. Anything else is a real delete.
    /// The rule lives here rather than at the call site so no future caller
    /// can delete a favourite out from under the user by accident.
    func removeFromHistory(id: UUID) async throws {
        let hidden = try await dbQueue.write { db -> Item? in
            guard var item = try Item.fetchOne(db, key: id), item.isFavourite else { return nil }
            item.isHiddenFromHistory = true
            try item.update(db)
            return item
        }
        guard let hidden else {
            try await deleteItem(id: id)
            return
        }
        copyToVault(hidden)
    }

    /// Removes an item and its blob file (if any). The blob delete is
    /// best-effort: a leftover file is invisible to the user and the orphan
    /// sweep in RetentionEngine reclaims it, so a failure here is
    /// logged rather than thrown.
    func deleteItem(id: UUID) async throws {
        let deleted = try await dbQueue.write { db -> Item? in
            guard let item = try Item.fetchOne(db, key: id) else { return nil }
            try item.delete(db)
            return item
        }
        if let path = deleted?.blobPath {
            do {
                try blobStore.delete(relativePath: path)
            } catch {
                logger.error("Blob left behind after item delete: \(String(describing: error), privacy: .public)")
            }
        }
        if let deleted, deleted.isFavourite {
            removeFromVault(deleted)
        }
    }

    /// Flips the favourite flag. A newly favourited item goes to the end of
    /// the favourites ordering (max rank + 1); unfavouriting clears the rank
    /// and puts the item back in history.
    ///
    /// One special case: unfavouriting something the user had already deleted
    /// from history leaves it in neither list, so the row goes. Restoring it
    /// to history instead would resurrect content the user deleted.
    /// The returned item describes the toggle that happened; check
    /// `isHiddenFromHistory` on it to tell whether the row survived.
    @discardableResult
    func toggleFavourite(id: UUID) async throws -> Item? {
        let toggled = try await dbQueue.write { db -> Item? in
            guard var item = try Item.fetchOne(db, key: id) else { return nil }
            item.isFavourite.toggle()
            if item.isFavourite {
                let maxRank = try Int.fetchOne(
                    db,
                    Item.select(max(Item.Columns.favouriteRank), as: Int?.self)
                ) ?? nil
                item.favouriteRank = (maxRank ?? 0) + 1
            } else {
                item.favouriteRank = nil
            }
            try item.update(db)
            return item
        }
        guard let toggled else { return nil }
        if toggled.isFavourite {
            copyToVault(toggled)
        } else if toggled.isHiddenFromHistory {
            // deleteItem only clears the vault for rows that are still
            // favourites, and this one no longer is — clear it here, or the
            // vault would hand it back as a favourite on the next launch.
            removeFromVault(toggled)
            try await deleteItem(id: toggled.id)
        } else {
            removeFromVault(toggled)
        }
        return toggled
    }

    /// Sets or clears a favourite's display label. Whitespace-only input
    /// clears, so "rename to nothing" behaves like removing the rename.
    @discardableResult
    func renameFavourite(id: UUID, label: String?) async throws -> Item? {
        let cleaned = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalLabel = (cleaned?.isEmpty ?? true) ? nil : cleaned
        let renamed = try await dbQueue.write { db -> Item? in
            guard var item = try Item.fetchOne(db, key: id) else { return nil }
            item.favouriteLabel = finalLabel
            try item.update(db)
            return item
        }
        if let renamed, renamed.isFavourite {
            copyToVault(renamed)
        }
        return renamed
    }

    /// Moves a favourite up (negative delta) or down (positive) in the
    /// manual ordering. Ranks are renumbered 1…n on every move — with at
    /// most dozens of favourites, simplicity beats a clever gap scheme.
    func moveFavourite(id: UUID, delta: Int) async throws {
        let reordered = try await dbQueue.write { db -> [Item] in
            var favourites = try Item
                .filter(Item.Columns.isFavourite == true)
                .order(Item.Columns.favouriteRank.ascNullsLast, Item.Columns.lastUsedAt.desc)
                .fetchAll(db)
            guard let index = favourites.firstIndex(where: { $0.id == id }) else { return [] }
            let target = min(max(index + delta, 0), favourites.count - 1)
            guard target != index else { return [] }
            let moved = favourites.remove(at: index)
            favourites.insert(moved, at: target)
            var changed: [Item] = []
            for (offset, var item) in favourites.enumerated() where item.favouriteRank != offset + 1 {
                item.favouriteRank = offset + 1
                try item.update(db)
                changed.append(item)
            }
            return changed
        }
        for item in reordered {
            copyToVault(item)
        }
    }

    /// Danger-zone "Clear history": removes everything except favourites,
    /// which are exempt from every destructive sweep (CLAUDE.md hard rule).
    func clearHistory() async throws {
        let victims = try await dbQueue.write { db -> [Item] in
            let doomed = try Item.filter(Item.Columns.isFavourite == false).fetchAll(db)
            try Item.filter(Item.Columns.isFavourite == false).deleteAll(db)
            return doomed
        }
        for path in victims.compactMap(\.blobPath) {
            do {
                try blobStore.delete(relativePath: path)
            } catch {
                logger.error("Blob left behind after clear: \(String(describing: error), privacy: .public)")
            }
        }
        logger.log("Cleared history: \(victims.count) items removed, favourites kept")
    }

    /// Danger-zone "Clear favourites": the inverse of clearHistory. The only
    /// place favourites may be bulk-deleted — and only ever explicitly.
    func clearFavourites() async throws {
        let victims = try await dbQueue.write { db -> [Item] in
            let doomed = try Item.filter(Item.Columns.isFavourite == true).fetchAll(db)
            try Item.filter(Item.Columns.isFavourite == true).deleteAll(db)
            return doomed
        }
        for item in victims {
            if let path = item.blobPath {
                try? blobStore.delete(relativePath: path)
            }
            removeFromVault(item)
        }
        logger.log("Cleared favourites: \(victims.count) removed")
    }

    /// Settings drag-reorder: assigns ranks 1…n following the given order.
    /// IDs not currently favourited are ignored.
    func setFavouriteOrder(ids: [UUID]) async throws {
        let changed = try await dbQueue.write { db -> [Item] in
            var changed: [Item] = []
            for (offset, id) in ids.enumerated() {
                guard var item = try Item.fetchOne(db, key: id), item.isFavourite else { continue }
                if item.favouriteRank != offset + 1 {
                    item.favouriteRank = offset + 1
                    try item.update(db)
                    changed.append(item)
                }
            }
            return changed
        }
        for item in changed {
            copyToVault(item)
        }
    }

    // MARK: - Retention primitives (favourites always exempt)

    /// Rule 1: cap the number of non-favourite items, deleting the least
    /// recently used beyond the limit. Favourites are exempt and do not
    /// count against the limit. Returns how many were removed.
    func pruneHistory(toCount limit: Int) async throws -> Int {
        let victims = try await dbQueue.write { db -> [Item] in
            // This runs after every capture — fetch only the rows beyond the
            // limit, not the entire history with its full text content.
            let history = Item.filter(Item.Columns.isFavourite == false)
            let total = try history.fetchCount(db)
            guard total > limit else { return [] }
            let doomed = try history
                .order(Item.Columns.lastUsedAt.desc)
                .limit(total - limit, offset: limit)
                .fetchAll(db)
            for item in doomed {
                try item.delete(db)
            }
            return doomed
        }
        deleteBlobs(of: victims)
        return victims.count
    }

    /// Rule 2: delete non-favourites not used since the cutoff. lastUsedAt
    /// rather than createdAt, so an item the user keeps re-copying is never
    /// pruned out from under them.
    func pruneHistory(olderThan cutoff: Date) async throws -> Int {
        let victims = try await dbQueue.write { db -> [Item] in
            let doomed = try Item
                .filter(Item.Columns.isFavourite == false)
                .filter(Item.Columns.lastUsedAt < cutoff)
                .fetchAll(db)
            for item in doomed {
                try item.delete(db)
            }
            return doomed
        }
        deleteBlobs(of: victims)
        return victims.count
    }

    /// Rule 3: remove blob files with no corresponding row — the safety net
    /// for every "row deleted but blob delete failed" path. Sweeps the vault
    /// store too in ephemeral mode.
    func deleteOrphanedBlobs() async throws -> Int {
        let liveHashes = Set(try await dbQueue.read { db in
            try String.fetchAll(db, Item.select(Item.Columns.contentHash, as: String.self))
        })
        var removed = 0
        removed += sweepOrphans(in: blobStore, liveHashes: liveHashes)
        if let vault {
            let vaultHashes = Set(try await vault.dbQueue.read { db in
                try String.fetchAll(db, Item.select(Item.Columns.contentHash, as: String.self))
            })
            removed += sweepOrphans(in: vault.blobStore, liveHashes: vaultHashes)
        }
        return removed
    }

    private func sweepOrphans(in store: BlobStore, liveHashes: Set<String>) -> Int {
        var removed = 0
        for path in store.allRelativePaths() {
            // blobs/<prefix>/<hash>.<ext> — the hash is the filename stem.
            let hash = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            guard !liveHashes.contains(hash), !hashesBeingSaved.contains(hash) else { continue }
            do {
                try store.delete(relativePath: path)
                removed += 1
            } catch {
                logger.error("Orphaned blob not removed: \(String(describing: error), privacy: .public)")
            }
        }
        return removed
    }

    private func deleteBlobs(of items: [Item]) {
        for path in items.compactMap(\.blobPath) {
            do {
                try blobStore.delete(relativePath: path)
            } catch {
                logger.error("Blob left behind after prune: \(String(describing: error), privacy: .public)")
            }
        }
    }

    // MARK: - Favourites vault

    /// Inserts or refreshes the vault copy of a favourite, including its
    /// blob payload. Vault failures are logged, never fatal — the favourite
    /// still exists in the live store; it just would not survive a restart.
    private func copyToVault(_ item: Item) {
        guard let vault else { return }
        do {
            if let path = item.blobPath {
                let data = try blobData(for: item)
                let ext = (path as NSString).pathExtension
                _ = try vault.blobStore.write(data, contentHash: item.contentHash, fileExtension: ext.isEmpty ? "bin" : ext)
            }
            try vault.dbQueue.write { db in try item.save(db) }
        } catch {
            logger.error("Favourite not mirrored to vault: \(String(describing: error), privacy: .public)")
        }
    }

    private func removeFromVault(_ item: Item) {
        guard let vault else { return }
        do {
            _ = try vault.dbQueue.write { db in try Item.deleteOne(db, key: item.id) }
            if let path = item.blobPath {
                try? vault.blobStore.delete(relativePath: path)
            }
        } catch {
            logger.error("Favourite not removed from vault: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Queries

    /// Most recently used first — the history list's default ordering.
    /// Favourites the user deleted from history are left out; they live on
    /// in favouriteItems().
    func recentItems(limit: Int) async throws -> [Item] {
        try await dbQueue.read { db in
            try Item
                .filter(Item.Columns.isHiddenFromHistory == false)
                .order(Item.Columns.lastUsedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Manual rank order first, then recency for any unranked stragglers.
    func favouriteItems() async throws -> [Item] {
        try await dbQueue.read { db in
            try Item
                .filter(Item.Columns.isFavourite == true)
                .order(Item.Columns.favouriteRank.ascNullsLast, Item.Columns.lastUsedAt.desc)
                .fetchAll(db)
        }
    }

    func itemCount() async throws -> Int {
        try await dbQueue.read { db in
            try Item.fetchCount(db)
        }
    }

    /// Payload for an item whose content lives in the blob store. In
    /// ephemeral mode a favourite restored from the vault has its blob on
    /// disk, not in the in-memory store — hence the fallback.
    func blobData(for item: Item) throws -> Data {
        guard let path = item.blobPath else { throw StorageError.itemHasNoBlob }
        do {
            return try blobStore.read(relativePath: path)
        } catch {
            guard let vault else { throw error }
            return try vault.blobStore.read(relativePath: path)
        }
    }
}
