import Foundation
import Testing
@testable import Clippy

struct ItemSearchFilterTests {

    private func item(
        preview: String,
        text: String? = nil,
        sourceApp: String? = nil,
        favouriteLabel: String? = nil
    ) -> Item {
        Item(
            id: UUID(),
            kind: .text,
            contentHash: UUID().uuidString,
            textContent: text ?? preview,
            blobPath: nil,
            preview: preview,
            byteSize: preview.utf8.count,
            sourceAppID: nil,
            sourceAppName: sourceApp,
            createdAt: Date(),
            lastUsedAt: Date(),
            isFavourite: favouriteLabel != nil,
            favouriteRank: nil,
            favouriteLabel: favouriteLabel,
            isHiddenFromHistory: false
        )
    }

    @Test func emptyQueryReturnsEverything() {
        let items = [item(preview: "one"), item(preview: "two")]
        #expect(ItemSearchFilter.filter(items, query: "").count == 2)
        #expect(ItemSearchFilter.filter(items, query: "   ").count == 2)
    }

    @Test func matchesPreviewCaseInsensitively() {
        let items = [item(preview: "Deploy Checklist"), item(preview: "groceries")]
        let result = ItemSearchFilter.filter(items, query: "deploy")
        #expect(result.map(\.preview) == ["Deploy Checklist"])
    }

    @Test func matchesFullTextContentBeyondTruncatedPreview() {
        let long = String(repeating: "a", count: 300) + " needle"
        let items = [item(preview: String(long.prefix(200)), text: long)]
        #expect(ItemSearchFilter.filter(items, query: "needle").count == 1)
    }

    @Test func matchesSourceAppName() {
        let items = [item(preview: "some snippet", sourceApp: "Safari")]
        #expect(ItemSearchFilter.filter(items, query: "safari").count == 1)
    }

    @Test func matchesFavouriteLabel() {
        let items = [
            item(preview: "https://linkedin.com/in/example", favouriteLabel: "LinkedIn Profile"),
            item(preview: "https://github.com/example"),
        ]
        let result = ItemSearchFilter.filter(items, query: "profile")
        #expect(result.map(\.preview) == ["https://linkedin.com/in/example"])
    }

    @Test func noMatchReturnsEmpty() {
        let items = [item(preview: "alpha"), item(preview: "beta")]
        #expect(ItemSearchFilter.filter(items, query: "zzz").isEmpty)
    }

    @Test func preservesInputOrder() {
        let items = [item(preview: "match 1"), item(preview: "other"), item(preview: "match 2")]
        let result = ItemSearchFilter.filter(items, query: "match")
        #expect(result.map(\.preview) == ["match 1", "match 2"])
    }
}
