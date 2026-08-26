import Foundation

/// In-memory search over the loaded item list — deliberately not FTS5, which
/// would be overkill at this scale. Pure function so it is testable without
/// any UI.
nonisolated enum ItemSearchFilter {
    /// Case-insensitive substring match on preview, full text content,
    /// source app name, and the favourite's custom label. An empty (or
    /// whitespace-only) query matches everything.
    static func filter(_ items: [Item], query: String) -> [Item] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter { item in
            item.preview.localizedCaseInsensitiveContains(trimmed)
                || (item.textContent?.localizedCaseInsensitiveContains(trimmed) ?? false)
                || (item.sourceAppName?.localizedCaseInsensitiveContains(trimmed) ?? false)
                || (item.favouriteLabel?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }
}
