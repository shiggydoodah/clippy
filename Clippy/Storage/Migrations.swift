import GRDB

/// Schema history. A registered migration must never be edited once it has
/// run on a real database — append a new one instead.
nonisolated enum Migrations {
    static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_createItem") { db in
            try db.create(table: "item") { t in
                t.primaryKey("id", .blob)
                t.column("kind", .text).notNull()
                // Unique: the dedupe lookup on every capture.
                t.column("contentHash", .text).notNull().unique()
                t.column("textContent", .text)
                t.column("blobPath", .text)
                t.column("preview", .text).notNull()
                t.column("byteSize", .integer).notNull()
                t.column("sourceAppID", .text)
                t.column("sourceAppName", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("lastUsedAt", .datetime).notNull()
                t.column("isFavourite", .boolean).notNull().defaults(to: false)
                t.column("favouriteRank", .integer)
            }
            // Retention pruning and default sort.
            try db.create(index: "item_on_createdAt", on: "item", columns: ["createdAt"])
            // Partial index: the Favourites tab reads a small subset.
            try db.create(
                index: "item_on_isFavourite",
                on: "item",
                columns: ["isFavourite"],
                condition: Column("isFavourite") == true
            )
        }

        migrator.registerMigration("v2_addFavouriteLabel") { db in
            // Custom display name for favourites — separate from
            // the content-derived preview, which stays untouched.
            try db.alter(table: "item") { t in
                t.add(column: "favouriteLabel", .text)
            }
        }

        return migrator
    }
}
