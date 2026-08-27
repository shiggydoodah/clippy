import Foundation
import Testing
@testable import Clippy

struct StorageServiceTests {

    // MARK: - Helpers

    private func textCapture(_ text: String, kind: ItemKind = .text) -> CapturedItem {
        CapturedItem(
            kind: kind,
            textContent: text,
            blobData: nil,
            blobFileExtension: nil,
            preview: String(text.prefix(200)),
            byteSize: text.utf8.count,
            sourceAppID: "com.example.test",
            sourceAppName: "Test"
        )
    }

    private func imageCapture(_ data: Data) -> CapturedItem {
        CapturedItem(
            kind: .image,
            textContent: nil,
            blobData: data,
            blobFileExtension: "png",
            preview: "Image",
            byteSize: data.count,
            sourceAppID: "com.example.test",
            sourceAppName: "Test"
        )
    }

    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipTests-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: - Dedupe by hash

    @Test func savingNewContentInserts() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        let outcome = try await storage.save(textCapture("hello"))
        #expect(outcome == .inserted)
        #expect(try await storage.itemCount() == 1)
    }

    @Test func recopyingSameContentDoesNotDuplicate() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        let first = Date(timeIntervalSince1970: 1_000)
        let second = Date(timeIntervalSince1970: 2_000)

        _ = try await storage.save(textCapture("same content"), now: first)
        let outcome = try await storage.save(textCapture("same content"), now: second)

        #expect(outcome == .deduplicated)
        #expect(try await storage.itemCount() == 1)

        let item = try #require(try await storage.recentItems(limit: 10).first)
        #expect(item.createdAt == first)
        #expect(item.lastUsedAt == second)
    }

    @Test func differentContentInsertsSeparateRows() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        _ = try await storage.save(textCapture("one"))
        _ = try await storage.save(textCapture("two"))
        #expect(try await storage.itemCount() == 2)
    }

    @Test func dedupedItemSortsToTheTop() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        _ = try await storage.save(textCapture("older"), now: Date(timeIntervalSince1970: 1_000))
        _ = try await storage.save(textCapture("newer"), now: Date(timeIntervalSince1970: 2_000))
        _ = try await storage.save(textCapture("older"), now: Date(timeIntervalSince1970: 3_000))

        let items = try await storage.recentItems(limit: 10)
        #expect(items.map(\.textContent) == ["older", "newer"])
    }

    @Test func emptyCaptureThrows() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        await #expect(throws: StorageError.self) {
            _ = try await storage.save(self.textCapture(""))
        }
        #expect(try await storage.itemCount() == 0)
    }

    // MARK: - Blob write/read

    @Test func imagePayloadRoundTripsThroughBlobStore() async throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try StorageService(mode: .persistent(directory: directory))

        let data = Data((0..<512).map { UInt8($0 % 251) })
        _ = try await storage.save(imageCapture(data))

        let item = try #require(try await storage.recentItems(limit: 1).first)
        #expect(item.kind == .image)
        #expect(item.blobPath != nil)
        #expect(try await storage.blobData(for: item) == data)

        // The blob really is a file on disk under blobs/.
        let blobURL = directory
            .appendingPathComponent("blobs")
            .appendingPathComponent(item.blobPath ?? "")
        #expect(FileManager.default.fileExists(atPath: blobURL.path))
    }

    @Test func inlineItemHasNoBlob() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        _ = try await storage.save(textCapture("inline"))
        let item = try #require(try await storage.recentItems(limit: 1).first)
        #expect(item.blobPath == nil)
        await #expect(throws: StorageError.self) {
            _ = try await storage.blobData(for: item)
        }
    }

    // MARK: - Persistence across relaunch

    @Test func dataSurvivesReopen() async throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try StorageService(mode: .persistent(directory: directory))
        _ = try await first.save(textCapture("persist me", kind: .link))

        // A second service on the same directory stands in for a relaunch.
        let second = try StorageService(mode: .persistent(directory: directory))
        let items = try await second.recentItems(limit: 10)
        #expect(items.count == 1)
        #expect(items.first?.textContent == "persist me")
        #expect(items.first?.kind == .link)

        // And the re-copy still dedupes against the reopened store.
        let outcome = try await second.save(textCapture("persist me", kind: .link))
        #expect(outcome == .deduplicated)
    }

    // MARK: - Ephemeral mode

    @Test func ephemeralModeRoundTripsInMemory() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        let data = Data("fake image bytes".utf8)
        _ = try await storage.save(imageCapture(data))

        let item = try #require(try await storage.recentItems(limit: 1).first)
        // Blob round-trips without a blobs/ directory ever being created —
        // the store is backed by memory, not disk.
        #expect(try await storage.blobData(for: item) == data)
    }

    @Test func ephemeralModeWritesNothingInsideAppSupport() async throws {
        // The ephemeral service is never given a directory, so the only way
        // it could touch disk is by reaching for the default location itself.
        // Snapshot the default directory's state around a save to prove it
        // does not.
        let defaultDirectory = try StorageService.defaultDirectory()
        let before = (try? FileManager.default.contentsOfDirectory(atPath: defaultDirectory.path)) ?? []

        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        _ = try await storage.save(textCapture("never on disk"))
        _ = try await storage.save(imageCapture(Data("bytes".utf8)))

        let after = (try? FileManager.default.contentsOfDirectory(atPath: defaultDirectory.path)) ?? []
        #expect(before == after)
    }
}

// MARK: - Fetching, search and blob round-trips

extension StorageServiceTests {

    @Test func deleteItemRemovesRow() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        _ = try await storage.save(textCapture("delete me"))
        let item = try #require(try await storage.recentItems(limit: 1).first)

        try await storage.deleteItem(id: item.id)
        #expect(try await storage.itemCount() == 0)
    }

    @Test func deleteItemRemovesBlobFile() async throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try StorageService(mode: .persistent(directory: directory))

        _ = try await storage.save(imageCapture(Data("blob payload".utf8)))
        let item = try #require(try await storage.recentItems(limit: 1).first)
        let blobURL = directory
            .appendingPathComponent("blobs")
            .appendingPathComponent(item.blobPath ?? "")
        #expect(FileManager.default.fileExists(atPath: blobURL.path))

        try await storage.deleteItem(id: item.id)
        #expect(!FileManager.default.fileExists(atPath: blobURL.path))
    }

    @Test func deleteUnknownIDIsANoOp() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        _ = try await storage.save(textCapture("survivor"))
        try await storage.deleteItem(id: UUID())
        #expect(try await storage.itemCount() == 1)
    }

    @Test func toggleFavouriteFlipsFlagAndAssignsRank() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        _ = try await storage.save(textCapture("fav me"))
        let item = try #require(try await storage.recentItems(limit: 1).first)

        let favourited = try #require(try await storage.toggleFavourite(id: item.id))
        #expect(favourited.isFavourite)
        #expect(favourited.favouriteRank == 1)

        let unfavourited = try #require(try await storage.toggleFavourite(id: item.id))
        #expect(!unfavourited.isFavourite)
        #expect(unfavourited.favouriteRank == nil)
    }

    @Test func newFavouritesRankAfterExistingOnes() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        _ = try await storage.save(textCapture("first"), now: Date(timeIntervalSince1970: 1_000))
        _ = try await storage.save(textCapture("second"), now: Date(timeIntervalSince1970: 2_000))
        let items = try await storage.recentItems(limit: 10)
        let first = try #require(items.first { $0.textContent == "first" })
        let second = try #require(items.first { $0.textContent == "second" })

        _ = try await storage.toggleFavourite(id: first.id)
        _ = try await storage.toggleFavourite(id: second.id)

        let favourites = try await storage.favouriteItems()
        #expect(favourites.map(\.textContent) == ["first", "second"])
        #expect(favourites.map(\.favouriteRank) == [1, 2])
    }

    @Test func favouriteItemsExcludesNonFavourites() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        _ = try await storage.save(textCapture("plain"))
        _ = try await storage.save(textCapture("starred"))
        let starred = try #require(try await storage.recentItems(limit: 10).first { $0.textContent == "starred" })
        _ = try await storage.toggleFavourite(id: starred.id)

        let favourites = try await storage.favouriteItems()
        #expect(favourites.map(\.textContent) == ["starred"])
    }
}

// MARK: - Favourites

extension StorageServiceTests {

    private func favouritedItem(_ storage: StorageService, text: String) async throws -> Item {
        _ = try await storage.save(textCapture(text))
        let item = try #require(try await storage.recentItems(limit: 100).first { $0.textContent == text })
        return try #require(try await storage.toggleFavourite(id: item.id))
    }

    @Test func renameSetsAndClearsLabel() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        let fav = try await favouritedItem(storage, text: "content")

        let renamed = try #require(try await storage.renameFavourite(id: fav.id, label: "My snippet"))
        #expect(renamed.favouriteLabel == "My snippet")
        #expect(renamed.displayTitle == "My snippet")

        let cleared = try #require(try await storage.renameFavourite(id: fav.id, label: "   "))
        #expect(cleared.favouriteLabel == nil)
        #expect(cleared.displayTitle == "content")
    }

    @Test func moveFavouriteReordersAndRenumbers() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        _ = try await favouritedItem(storage, text: "a")
        _ = try await favouritedItem(storage, text: "b")
        let c = try await favouritedItem(storage, text: "c")

        try await storage.moveFavourite(id: c.id, delta: -2)
        let favourites = try await storage.favouriteItems()
        #expect(favourites.map(\.textContent) == ["c", "a", "b"])
        #expect(favourites.map(\.favouriteRank) == [1, 2, 3])
    }

    @Test func moveFavouriteClampsAtEdges() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        let a = try await favouritedItem(storage, text: "a")
        _ = try await favouritedItem(storage, text: "b")

        try await storage.moveFavourite(id: a.id, delta: -1) // already first
        #expect(try await storage.favouriteItems().map(\.textContent) == ["a", "b"])
        try await storage.moveFavourite(id: a.id, delta: 5)  // clamps to last
        #expect(try await storage.favouriteItems().map(\.textContent) == ["b", "a"])
    }

    @Test func clearHistoryKeepsFavouritesAndTheirBlobs() async throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try StorageService(mode: .persistent(directory: directory))

        _ = try await storage.save(textCapture("doomed text"))
        _ = try await storage.save(imageCapture(Data("doomed image".utf8)))
        _ = try await storage.save(imageCapture(Data("kept image".utf8)))
        let keptImage = try #require(try await storage.recentItems(limit: 10).first)
        _ = try await storage.toggleFavourite(id: keptImage.id)

        try await storage.clearHistory()

        let remaining = try await storage.recentItems(limit: 10)
        #expect(remaining.map(\.id) == [keptImage.id])
        // The favourite's blob survives; the doomed image's blob is gone.
        #expect(try await storage.blobData(for: keptImage) == Data("kept image".utf8))
        let blobsRoot = directory.appendingPathComponent("blobs")
        let files = FileManager.default.enumerator(at: blobsRoot, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { !$0.hasDirectoryPath } ?? []
        #expect(files.count == 1)
    }

    // MARK: - Ephemeral favourites vault

    @Test func favouritesSurviveEphemeralRestart() async throws {
        let vaultDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: vaultDir) }

        let first = try StorageService(mode: .ephemeral(vaultDirectory: vaultDir))
        _ = try await first.save(textCapture("ephemeral history"))
        let fav = try await favouritedItem(first, text: "keep me forever")
        _ = try await first.renameFavourite(id: fav.id, label: "The One")

        // A fresh service on the same vault stands in for an app relaunch.
        let second = try StorageService(mode: .ephemeral(vaultDirectory: vaultDir))
        let items = try await second.recentItems(limit: 10)
        #expect(items.map(\.textContent) == ["keep me forever"])
        #expect(items.first?.isFavourite == true)
        #expect(items.first?.favouriteLabel == "The One")
        // History rows must not have survived.
        #expect(try await second.itemCount() == 1)
    }

    @Test func favouriteImageBlobSurvivesEphemeralRestart() async throws {
        let vaultDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: vaultDir) }
        let payload = Data("favourite pixels".utf8)

        let first = try StorageService(mode: .ephemeral(vaultDirectory: vaultDir))
        _ = try await first.save(imageCapture(payload))
        let image = try #require(try await first.recentItems(limit: 1).first)
        _ = try await first.toggleFavourite(id: image.id)

        let second = try StorageService(mode: .ephemeral(vaultDirectory: vaultDir))
        let restored = try #require(try await second.recentItems(limit: 1).first)
        #expect(try await second.blobData(for: restored) == payload)
    }

    @Test func unfavouritingRemovesFromVault() async throws {
        let vaultDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: vaultDir) }

        let first = try StorageService(mode: .ephemeral(vaultDirectory: vaultDir))
        let fav = try await favouritedItem(first, text: "briefly loved")
        _ = try await first.toggleFavourite(id: fav.id) // un-favourite

        let second = try StorageService(mode: .ephemeral(vaultDirectory: vaultDir))
        #expect(try await second.itemCount() == 0)
    }

    @Test func ephemeralVaultPrunesStalePersistedHistory() async throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // A previously persistent store with history and one favourite…
        let persistent = try StorageService(mode: .persistent(directory: directory))
        _ = try await persistent.save(textCapture("old history"))
        _ = try await favouritedItem(persistent, text: "old favourite")

        // …reopened ephemeral (user turned persistence off): only the
        // favourite may remain on disk or in memory.
        let ephemeral = try StorageService(mode: .ephemeral(vaultDirectory: directory))
        let items = try await ephemeral.recentItems(limit: 10)
        #expect(items.map(\.textContent) == ["old favourite"])

        let onDisk = try StorageService(mode: .persistent(directory: directory))
        let diskItems = try await onDisk.recentItems(limit: 10)
        #expect(diskItems.map(\.textContent) == ["old favourite"])
    }
}

// MARK: - clearFavourites and explicit ordering

extension StorageServiceTests {

    @Test func clearFavouritesRemovesOnlyFavourites() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        _ = try await storage.save(textCapture("history item"))
        _ = try await favouritedItem(storage, text: "favourite item")

        try await storage.clearFavourites()

        let remaining = try await storage.recentItems(limit: 10)
        #expect(remaining.map(\.textContent) == ["history item"])
    }

    @Test func clearFavouritesEmptiesTheVault() async throws {
        let vaultDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: vaultDir) }

        let first = try StorageService(mode: .ephemeral(vaultDirectory: vaultDir))
        _ = try await favouritedItem(first, text: "vaulted")
        try await first.clearFavourites()

        let second = try StorageService(mode: .ephemeral(vaultDirectory: vaultDir))
        #expect(try await second.itemCount() == 0)
    }

    @Test func setFavouriteOrderIgnoresNonFavouriteIDs() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        let fav = try await favouritedItem(storage, text: "fav")
        _ = try await storage.save(textCapture("plain"))
        let plain = try #require(try await storage.recentItems(limit: 10).first { $0.textContent == "plain" })

        // A stale drag payload could include a non-favourite — it must be
        // skipped, not silently promoted to a favourite.
        try await storage.setFavouriteOrder(ids: [plain.id, fav.id])

        #expect(try await storage.favouriteItems().map(\.textContent) == ["fav"])
        let reloaded = try #require(try await storage.recentItems(limit: 10).first { $0.textContent == "plain" })
        #expect(!reloaded.isFavourite)
    }

    @Test func setFavouriteOrderAppliesGivenSequence() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        let a = try await favouritedItem(storage, text: "a")
        let b = try await favouritedItem(storage, text: "b")
        let c = try await favouritedItem(storage, text: "c")

        try await storage.setFavouriteOrder(ids: [c.id, a.id, b.id])
        let favourites = try await storage.favouriteItems()
        #expect(favourites.map(\.textContent) == ["c", "a", "b"])
        #expect(favourites.map(\.favouriteRank) == [1, 2, 3])
    }
}

// MARK: - Removing from history (the History tab's delete)

extension StorageServiceTests {

    @Test func removeFromHistoryKeepsAFavouriteOutOfHistoryOnly() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        _ = try await storage.save(textCapture("plain"), now: Date(timeIntervalSince1970: 1_000))
        let fav = try await favouritedItem(storage, text: "kept")

        try await storage.removeFromHistory(id: fav.id)

        #expect(try await storage.recentItems(limit: 10).map(\.textContent) == ["plain"])
        #expect(try await storage.favouriteItems().map(\.textContent) == ["kept"])
        #expect(try await storage.itemCount() == 2)
        let reloaded = try #require(try await storage.favouriteItems().first)
        #expect(reloaded.isHiddenFromHistory)
        #expect(reloaded.isFavourite)
    }

    @Test func removeFromHistoryKeepsAFavouriteRename() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        let fav = try await favouritedItem(storage, text: "content")
        _ = try await storage.renameFavourite(id: fav.id, label: "My snippet")

        try await storage.removeFromHistory(id: fav.id)

        let kept = try #require(try await storage.favouriteItems().first)
        #expect(kept.displayTitle == "My snippet")
        #expect(kept.favouriteRank == 1)
    }

    @Test func removeFromHistoryKeepsAFavouriteBlob() async throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try StorageService(mode: .persistent(directory: directory))
        let payload = Data("favourite pixels".utf8)

        _ = try await storage.save(imageCapture(payload))
        let image = try #require(try await storage.recentItems(limit: 1).first)
        _ = try await storage.toggleFavourite(id: image.id)

        try await storage.removeFromHistory(id: image.id)

        let blobURL = directory
            .appendingPathComponent("blobs")
            .appendingPathComponent(image.blobPath ?? "")
        #expect(FileManager.default.fileExists(atPath: blobURL.path))
        let kept = try #require(try await storage.favouriteItems().first)
        #expect(try await storage.blobData(for: kept) == payload)
    }

    @Test func removeFromHistoryDeletesANonFavourite() async throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try StorageService(mode: .persistent(directory: directory))

        _ = try await storage.save(imageCapture(Data("doomed".utf8)))
        let item = try #require(try await storage.recentItems(limit: 1).first)
        let blobURL = directory
            .appendingPathComponent("blobs")
            .appendingPathComponent(item.blobPath ?? "")

        try await storage.removeFromHistory(id: item.id)

        #expect(try await storage.itemCount() == 0)
        #expect(!FileManager.default.fileExists(atPath: blobURL.path))
    }

    @Test func removeFromHistoryOnAnUnknownIDIsANoOp() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        _ = try await storage.save(textCapture("survivor"))
        try await storage.removeFromHistory(id: UUID())
        #expect(try await storage.itemCount() == 1)
    }

    @Test func deletingAFavouriteOutrightStillRemovesItEverywhere() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        let fav = try await favouritedItem(storage, text: "goodbye")
        try await storage.removeFromHistory(id: fav.id)

        // The Favourites tab's delete: the one route that really deletes it.
        try await storage.deleteItem(id: fav.id)

        #expect(try await storage.favouriteItems().isEmpty)
        #expect(try await storage.itemCount() == 0)
    }

    @Test func recopyingContentBringsItBackIntoHistory() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        let fav = try await favouritedItem(storage, text: "recopied")
        try await storage.removeFromHistory(id: fav.id)
        #expect(try await storage.recentItems(limit: 10).isEmpty)

        let outcome = try await storage.save(textCapture("recopied"), now: Date(timeIntervalSince1970: 9_000))

        #expect(outcome == .deduplicated)
        #expect(try await storage.recentItems(limit: 10).map(\.textContent) == ["recopied"])
        #expect(try await storage.favouriteItems().map(\.textContent) == ["recopied"])
        #expect(try await storage.itemCount() == 1)
    }

    @Test func unfavouritingAnItemRemovedFromHistoryDeletesIt() async throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try StorageService(mode: .persistent(directory: directory))

        _ = try await storage.save(imageCapture(Data("orphan to be".utf8)))
        let image = try #require(try await storage.recentItems(limit: 1).first)
        _ = try await storage.toggleFavourite(id: image.id)
        try await storage.removeFromHistory(id: image.id)

        // It is in neither list now, so the row and its blob go with it —
        // the alternative would resurrect content the user deleted.
        _ = try await storage.toggleFavourite(id: image.id)

        #expect(try await storage.itemCount() == 0)
        let blobURL = directory
            .appendingPathComponent("blobs")
            .appendingPathComponent(image.blobPath ?? "")
        #expect(!FileManager.default.fileExists(atPath: blobURL.path))
    }

    @Test func unfavouritingAnItemStillInHistoryKeepsIt() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        let fav = try await favouritedItem(storage, text: "back to plain")

        _ = try await storage.toggleFavourite(id: fav.id)

        #expect(try await storage.recentItems(limit: 10).map(\.textContent) == ["back to plain"])
        #expect(try await storage.favouriteItems().isEmpty)
    }

    @Test func clearHistoryLeavesAFavouriteRemovedFromHistoryAlone() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        _ = try await storage.save(textCapture("doomed"))
        let fav = try await favouritedItem(storage, text: "hidden favourite")
        try await storage.removeFromHistory(id: fav.id)

        try await storage.clearHistory()

        #expect(try await storage.recentItems(limit: 10).isEmpty)
        #expect(try await storage.favouriteItems().map(\.textContent) == ["hidden favourite"])
    }

    @Test func clearFavouritesRemovesOneTakenOutOfHistory() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        let fav = try await favouritedItem(storage, text: "hidden favourite")
        try await storage.removeFromHistory(id: fav.id)

        try await storage.clearFavourites()

        #expect(try await storage.itemCount() == 0)
    }

    @Test func removalFromHistorySurvivesEphemeralRestart() async throws {
        let vaultDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: vaultDir) }

        let first = try StorageService(mode: .ephemeral(vaultDirectory: vaultDir))
        let fav = try await favouritedItem(first, text: "vaulted but hidden")
        try await first.removeFromHistory(id: fav.id)

        let second = try StorageService(mode: .ephemeral(vaultDirectory: vaultDir))
        #expect(try await second.favouriteItems().map(\.textContent) == ["vaulted but hidden"])
        #expect(try await second.recentItems(limit: 10).isEmpty)
    }

    @Test func unfavouritingAnItemRemovedFromHistoryEmptiesTheVault() async throws {
        let vaultDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: vaultDir) }

        let first = try StorageService(mode: .ephemeral(vaultDirectory: vaultDir))
        let fav = try await favouritedItem(first, text: "briefly loved")
        try await first.removeFromHistory(id: fav.id)
        _ = try await first.toggleFavourite(id: fav.id)

        let second = try StorageService(mode: .ephemeral(vaultDirectory: vaultDir))
        #expect(try await second.itemCount() == 0)
    }
}
