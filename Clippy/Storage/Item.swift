import Foundation
import GRDB

/// One clipboard history entry — the app's core data model.
/// Codable does double duty: GRDB derives the database mapping from it.
nonisolated struct Item: Identifiable, Codable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "item"

    let id: UUID
    var kind: ItemKind
    var contentHash: String
    var textContent: String?
    var blobPath: String?
    var preview: String
    var byteSize: Int
    var sourceAppID: String?
    var sourceAppName: String?
    var createdAt: Date
    var lastUsedAt: Date
    var isFavourite: Bool
    var favouriteRank: Int?
    /// User-chosen display name for a favourite; nil falls back to preview.
    var favouriteLabel: String?

    /// What list rows display: the favourite's custom label when set,
    /// otherwise the content preview.
    var displayTitle: String {
        if let favouriteLabel, !favouriteLabel.isEmpty { return favouriteLabel }
        return preview
    }

    /// Typed column references for query building — keeps raw strings out
    /// of call sites and in sync with the Codable keys.
    nonisolated enum Columns {
        static let contentHash = Column(CodingKeys.contentHash)
        static let createdAt = Column(CodingKeys.createdAt)
        static let lastUsedAt = Column(CodingKeys.lastUsedAt)
        static let isFavourite = Column(CodingKeys.isFavourite)
        static let favouriteRank = Column(CodingKeys.favouriteRank)
    }
}
