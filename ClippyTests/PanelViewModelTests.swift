import Foundation
import Testing
@testable import Clippy

/// Selection, tab, search, and commit-routing logic in the panel's view
/// model, driven against a real in-memory StorageService. The SwiftUI views
/// themselves are verified by running the app (CLAUDE.md).
@MainActor
struct PanelViewModelTests {

    // MARK: - Helpers

    private func textCapture(_ text: String) -> CapturedItem {
        CapturedItem(
            kind: .text,
            textContent: text,
            blobData: nil,
            blobFileExtension: nil,
            preview: text,
            byteSize: text.utf8.count,
            sourceAppID: nil,
            sourceAppName: nil
        )
    }

    /// A loaded view model over items saved oldest-first, so the panel shows
    /// the *reversed* order (most recently used first).
    private func makeModel(texts: [String]) async throws -> PanelViewModel {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        for (offset, text) in texts.enumerated() {
            _ = try await storage.save(
                textCapture(text),
                now: Date(timeIntervalSince1970: Double(offset + 1) * 1_000)
            )
        }
        let model = PanelViewModel(storage: storage)
        await model.load()
        return model
    }

    // MARK: - Loading

    @Test func loadShowsHistoryMostRecentFirst() async throws {
        let model = try await makeModel(texts: ["one", "two", "three"])
        #expect(model.visibleItems.map(\.preview) == ["three", "two", "one"])
        #expect(model.selectedItem?.preview == "three")
    }

    // MARK: - Selection

    @Test func moveSelectionClampsAtBothEnds() async throws {
        let model = try await makeModel(texts: ["a", "b", "c"])
        model.moveSelection(by: -1)
        #expect(model.selectedIndex == 0)
        model.moveSelection(by: 10)
        #expect(model.selectedIndex == 2)
    }

    @Test func moveSelectionOnEmptyListDoesNothing() async throws {
        let model = try await makeModel(texts: [])
        model.moveSelection(by: 1)
        #expect(model.selectedIndex == 0)
        #expect(model.selectedItem == nil)
    }

    @Test func selectIgnoresOutOfRangeIndex() async throws {
        let model = try await makeModel(texts: ["a", "b"])
        model.select(index: 5)
        #expect(model.selectedIndex == 0)
    }

    // MARK: - Search

    @Test func searchFiltersAndResetsSelection() async throws {
        let model = try await makeModel(texts: ["apple pie", "banana", "apple tart"])
        model.moveSelection(by: 2)
        model.searchText = "apple"
        #expect(model.selectedIndex == 0)
        #expect(model.visibleItems.map(\.preview) == ["apple tart", "apple pie"])
    }

    // MARK: - Tabs

    @Test func switchTabShowsFavouritesAndResetsSelection() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        _ = try await storage.save(textCapture("plain"), now: Date(timeIntervalSince1970: 1_000))
        _ = try await storage.save(textCapture("starred"), now: Date(timeIntervalSince1970: 2_000))
        let starred = try #require(try await storage.recentItems(limit: 10).first)
        _ = try await storage.toggleFavourite(id: starred.id)

        let model = PanelViewModel(storage: storage)
        await model.load()
        model.moveSelection(by: 1)

        model.switchTab()
        #expect(model.activeTab == .favourites)
        #expect(model.selectedIndex == 0)
        #expect(model.visibleItems.map(\.preview) == ["starred"])

        model.switchTab()
        #expect(model.activeTab == .history)
    }

    // MARK: - Commit routing

    @Test func commitSelectedPassesItemAndPasteFlag() async throws {
        let model = try await makeModel(texts: ["target"])
        var committed: (item: Item, paste: Bool)?
        model.onCommit = { committed = ($0, $1) }

        model.commitSelected(paste: true)
        #expect(committed?.item.preview == "target")
        #expect(committed?.paste == true)
    }

    @Test func commitAtDisplayIndexUsesTheVisibleOrdering() async throws {
        let model = try await makeModel(texts: ["old", "new"])
        var committed: Item?
        model.onCommit = { item, _ in committed = item }

        model.commitItem(atDisplayIndex: 1, paste: false)
        #expect(committed?.preview == "old")
    }

    @Test func commitAtOutOfRangeIndexDoesNothing() async throws {
        let model = try await makeModel(texts: ["only"])
        var commitCount = 0
        model.onCommit = { _, _ in commitCount += 1 }

        model.commitItem(atDisplayIndex: 5, paste: false)
        #expect(commitCount == 0)
    }

    // MARK: - Delete

    @Test func deleteRemovesTheItemImmediatelyAndClampsSelection() async throws {
        let model = try await makeModel(texts: ["a", "b"])
        model.moveSelection(by: 1) // select the last row
        let doomed = try #require(model.selectedItem)

        model.delete(doomed)
        // Optimistic removal: gone from the list before storage confirms.
        #expect(!model.visibleItems.contains(where: { $0.id == doomed.id }))
        #expect(model.selectedIndex == 0)
    }

    @Test func deletingAFavouriteFromHistoryKeepsItInFavourites() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        _ = try await storage.save(textCapture("plain"), now: Date(timeIntervalSince1970: 1_000))
        _ = try await storage.save(textCapture("starred"), now: Date(timeIntervalSince1970: 2_000))
        let starred = try #require(try await storage.recentItems(limit: 10).first)
        _ = try await storage.toggleFavourite(id: starred.id)

        let model = PanelViewModel(storage: storage)
        await model.load()
        let fav = try #require(model.selectedItem)
        #expect(fav.isFavourite)

        model.delete(fav)
        // Gone from History straight away, still in Favourites.
        #expect(model.visibleItems.map(\.preview) == ["plain"])
        #expect(model.favouriteItems.map(\.preview) == ["starred"])

        // …and once storage has caught up, a fresh load agrees.
        await model.commitDelete(fav, fromHistory: true)
        await model.load()
        #expect(model.visibleItems.map(\.preview) == ["plain"])
        model.switchTab()
        #expect(model.visibleItems.map(\.preview) == ["starred"])
    }

    @Test func deletingAFavouriteFromTheFavouritesTabDeletesIt() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        _ = try await storage.save(textCapture("starred"))
        let starred = try #require(try await storage.recentItems(limit: 10).first)
        _ = try await storage.toggleFavourite(id: starred.id)

        let model = PanelViewModel(storage: storage)
        await model.load()
        model.switchTab()
        let fav = try #require(model.selectedItem)

        model.delete(fav)
        #expect(model.visibleItems.isEmpty)
        #expect(model.favouriteItems.isEmpty)

        await model.commitDelete(fav, fromHistory: false)
        await model.load()
        #expect(model.favouriteItems.isEmpty)
        #expect(model.historyItems.isEmpty)
    }

    @Test func deletingANonFavouriteFromHistoryRemovesItForGood() async throws {
        let model = try await makeModel(texts: ["a", "b"])
        let doomed = try #require(model.selectedItem)

        await model.commitDelete(doomed, fromHistory: true)
        await model.load()

        #expect(model.visibleItems.map(\.preview) == ["a"])
    }

    // MARK: - Summon reset

    @Test func prepareForShowResetsSearchTabSelectionAndBumpsShowCount() async throws {
        let model = try await makeModel(texts: ["a", "b"])
        model.searchText = "zzz"
        model.switchTab()
        let showsBefore = model.showCount

        model.prepareForShow()
        #expect(model.searchText.isEmpty)
        #expect(model.activeTab == .history)
        #expect(model.selectedIndex == 0)
        #expect(model.showCount == showsBefore + 1)
    }
}
