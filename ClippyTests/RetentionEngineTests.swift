import Foundation
import Testing
@testable import Clippy

/// Every retention rule plus the favourite exemption, driven through
/// RetentionEngine.run with injected policies (no UserDefaults involved).
struct RetentionEngineTests {

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

    private func imageCapture(_ data: Data) -> CapturedItem {
        CapturedItem(
            kind: .image,
            textContent: nil,
            blobData: data,
            blobFileExtension: "png",
            preview: "Image",
            byteSize: data.count,
            sourceAppID: nil,
            sourceAppName: nil
        )
    }

    // MARK: - Rule 1: max item count

    @Test func maxCountPrunesOldestBeyondLimit() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        for i in 1...5 {
            _ = try await storage.save(textCapture("item \(i)"), now: Date(timeIntervalSince1970: Double(i) * 1_000))
        }

        let engine = RetentionEngine(storage: storage)
        await engine.run(reason: "test", policy: .init(maxItems: 3, maxAgeSeconds: 0))

        let remaining = try await storage.recentItems(limit: 10)
        #expect(remaining.map(\.textContent) == ["item 5", "item 4", "item 3"])
    }

    @Test func maxCountZeroMeansUnlimited() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        for i in 1...5 {
            _ = try await storage.save(textCapture("item \(i)"))
        }
        let engine = RetentionEngine(storage: storage)
        await engine.run(reason: "test", policy: .init(maxItems: 0, maxAgeSeconds: 0))
        #expect(try await storage.itemCount() == 5)
    }

    @Test func favouritesAreExemptFromMaxCount() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        for i in 1...4 {
            _ = try await storage.save(textCapture("item \(i)"), now: Date(timeIntervalSince1970: Double(i) * 1_000))
        }
        // Favourite the OLDEST item — precisely the one count-pruning would kill.
        let oldest = try #require(try await storage.recentItems(limit: 10).last)
        _ = try await storage.toggleFavourite(id: oldest.id)

        let engine = RetentionEngine(storage: storage)
        await engine.run(reason: "test", policy: .init(maxItems: 2, maxAgeSeconds: 0))

        let remaining = try await storage.recentItems(limit: 10)
        // 2 newest non-favourites + the exempt favourite, which also does
        // not consume a history slot.
        #expect(Set(remaining.compactMap(\.textContent)) == ["item 1", "item 3", "item 4"])
    }

    // MARK: - Rule 2: max age

    @Test func maxAgePrunesItemsNotUsedSinceCutoff() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        let now = Date()
        _ = try await storage.save(textCapture("ancient"), now: now.addingTimeInterval(-10_000))
        _ = try await storage.save(textCapture("fresh"), now: now)

        let engine = RetentionEngine(storage: storage)
        await engine.run(reason: "test", policy: .init(maxItems: 0, maxAgeSeconds: 3_600))

        #expect(try await storage.recentItems(limit: 10).map(\.textContent) == ["fresh"])
    }

    @Test func recentlyReusedItemSurvivesAgePruning() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        let now = Date()
        // Created long ago but re-copied just now: lastUsedAt is fresh.
        _ = try await storage.save(textCapture("old but loved"), now: now.addingTimeInterval(-100_000))
        _ = try await storage.save(textCapture("old but loved"), now: now)

        let engine = RetentionEngine(storage: storage)
        await engine.run(reason: "test", policy: .init(maxItems: 0, maxAgeSeconds: 3_600))

        #expect(try await storage.itemCount() == 1)
    }

    @Test func favouritesAreExemptFromMaxAge() async throws {
        let storage = try StorageService(mode: .ephemeral(vaultDirectory: nil))
        let now = Date()
        _ = try await storage.save(textCapture("ancient favourite"), now: now.addingTimeInterval(-1_000_000))
        let fav = try #require(try await storage.recentItems(limit: 1).first)
        _ = try await storage.toggleFavourite(id: fav.id)

        let engine = RetentionEngine(storage: storage)
        await engine.run(reason: "test", policy: .init(maxItems: 0, maxAgeSeconds: 60))

        #expect(try await storage.itemCount() == 1)
    }

    // MARK: - Rule 3: orphaned blobs

    @Test func orphanedBlobsAreSwept() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipRetention-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try StorageService(mode: .persistent(directory: directory))

        _ = try await storage.save(imageCapture(Data("live image".utf8)))

        // Plant an orphan by hand where a crashed delete would leave one.
        let orphanDir = directory.appendingPathComponent("blobs/zz")
        try FileManager.default.createDirectory(at: orphanDir, withIntermediateDirectories: true)
        let orphanURL = orphanDir.appendingPathComponent("zzzz1111.png")
        try Data("orphan".utf8).write(to: orphanURL)

        let engine = RetentionEngine(storage: storage)
        await engine.run(reason: "test", policy: .init(maxItems: 0, maxAgeSeconds: 0))

        #expect(!FileManager.default.fileExists(atPath: orphanURL.path))
        // The live item's blob is untouched.
        let live = try #require(try await storage.recentItems(limit: 1).first)
        #expect(try await storage.blobData(for: live) == Data("live image".utf8))
    }

    @Test func captureTriggeredRunsSkipTheOrphanSweep() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipRetention-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try StorageService(mode: .persistent(directory: directory))

        let orphanDir = directory.appendingPathComponent("blobs/zz")
        try FileManager.default.createDirectory(at: orphanDir, withIntermediateDirectories: true)
        let orphanURL = orphanDir.appendingPathComponent("zzzz1111.png")
        try Data("orphan".utf8).write(to: orphanURL)

        let engine = RetentionEngine(storage: storage)
        // The per-capture run leaves orphans alone (no blobs/ traversal per
        // copy); the launch/timer run reclaims them.
        await engine.run(reason: "capture", policy: .init(maxItems: 0, maxAgeSeconds: 0), sweepingOrphans: false)
        #expect(FileManager.default.fileExists(atPath: orphanURL.path))

        await engine.run(reason: "timer", policy: .init(maxItems: 0, maxAgeSeconds: 0))
        #expect(!FileManager.default.fileExists(atPath: orphanURL.path))
    }

    @Test func prunedImageItemsLoseTheirBlobs() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipRetention-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try StorageService(mode: .persistent(directory: directory))

        _ = try await storage.save(imageCapture(Data("doomed".utf8)), now: Date(timeIntervalSince1970: 1_000))
        _ = try await storage.save(textCapture("newer 1"), now: Date(timeIntervalSince1970: 2_000))
        _ = try await storage.save(textCapture("newer 2"), now: Date(timeIntervalSince1970: 3_000))

        let engine = RetentionEngine(storage: storage)
        await engine.run(reason: "test", policy: .init(maxItems: 2, maxAgeSeconds: 0))

        let blobsRoot = directory.appendingPathComponent("blobs")
        let files = FileManager.default.enumerator(at: blobsRoot, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { !$0.hasDirectoryPath } ?? []
        #expect(files.isEmpty)
    }
}
