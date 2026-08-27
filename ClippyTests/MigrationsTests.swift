import Foundation
import GRDB
import Testing
@testable import Clippy

/// Upgrade paths for real, already-populated databases — the one thing the
/// other tests cannot cover, because they always start from an empty file
/// and run every migration in one go.
struct MigrationsTests {

    private func makeTempDatabase() throws -> (DatabaseQueue, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipMigrations-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("clip.sqlite")
        return (try DatabaseQueue(path: url.path), directory)
    }

    @Test func existingRowsUpgradeToTheHiddenFromHistoryColumn() throws {
        let (dbQueue, directory) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }

        // A database as an installed copy of the app left it, before this
        // change existed.
        try Migrations.migrator().migrate(dbQueue, upTo: "v2_addFavouriteLabel")
        let id = UUID()
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO item
                (id, kind, contentHash, textContent, blobPath, preview, byteSize,
                 sourceAppID, sourceAppName, createdAt, lastUsedAt, isFavourite,
                 favouriteRank, favouriteLabel)
                VALUES (?, 'text', 'deadbeef', 'old row', NULL, 'old row', 7,
                        NULL, NULL, '2026-01-01 00:00:00.000', '2026-01-01 00:00:00.000', 1,
                        1, 'Kept')
                """,
                arguments: [id.uuidString]
            )
        }

        try Migrations.migrator().migrate(dbQueue)

        let items = try dbQueue.read { db in try Item.fetchAll(db) }
        #expect(items.count == 1)
        let item = try #require(items.first)
        // Everything the user had is intact, and the new column defaults to
        // "still in history" — nothing disappears on upgrade.
        #expect(item.textContent == "old row")
        #expect(item.isFavourite)
        #expect(item.favouriteLabel == "Kept")
        #expect(!item.isHiddenFromHistory)
    }
}
