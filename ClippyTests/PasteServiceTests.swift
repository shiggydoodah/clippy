import AppKit
import Testing
@testable import Clippy

/// Tests the pasteboard-write half of PasteService on a private named
/// pasteboard — the reactivation and CGEvent half needs a human (and
/// Accessibility permission) and is on the manual checklist.
@MainActor
struct PasteServiceTests {

    private func makeItem(
        kind: ItemKind,
        textContent: String? = nil,
        blobPath: String? = nil
    ) -> Item {
        Item(
            id: UUID(),
            kind: kind,
            contentHash: UUID().uuidString,
            textContent: textContent,
            blobPath: blobPath,
            preview: textContent ?? "preview",
            byteSize: 0,
            sourceAppID: nil,
            sourceAppName: nil,
            createdAt: Date(),
            lastUsedAt: Date(),
            isFavourite: false,
            favouriteRank: nil,
            favouriteLabel: nil
        )
    }

    private func makeScratchPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("com.clip.app.tests.\(UUID().uuidString)"))
    }

    @Test func writesTextInline() {
        let pasteboard = makeScratchPasteboard()
        defer { pasteboard.releaseGlobally() }
        let service = PasteService(pasteboard: pasteboard)

        service.write(makeItem(kind: .text, textContent: "hello paste"), blobData: nil)
        #expect(pasteboard.string(forType: .string) == "hello paste")
    }

    @Test func writesLinkAsString() {
        let pasteboard = makeScratchPasteboard()
        defer { pasteboard.releaseGlobally() }
        let service = PasteService(pasteboard: pasteboard)

        service.write(makeItem(kind: .link, textContent: "https://example.com"), blobData: nil)
        #expect(pasteboard.string(forType: .string) == "https://example.com")
    }

    @Test func writesImageBlobAsPNG() {
        let pasteboard = makeScratchPasteboard()
        defer { pasteboard.releaseGlobally() }
        let service = PasteService(pasteboard: pasteboard)
        let payload = Data([0x89, 0x50, 0x4E, 0x47])

        service.write(makeItem(kind: .image, blobPath: "ab/abcd.png"), blobData: payload)
        #expect(pasteboard.data(forType: .png) == payload)
    }

    @Test func imageWithMissingBlobWritesNothing() {
        let pasteboard = makeScratchPasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("previous contents", forType: .string)
        let service = PasteService(pasteboard: pasteboard)

        service.write(makeItem(kind: .image, blobPath: "ab/abcd.png"), blobData: nil)
        // A failed write must not clear what the user already had.
        #expect(pasteboard.string(forType: .string) == "previous contents")
    }

    @Test func writesFilePathsAsFileURLs() {
        let pasteboard = makeScratchPasteboard()
        defer { pasteboard.releaseGlobally() }
        let service = PasteService(pasteboard: pasteboard)

        service.write(makeItem(kind: .file, textContent: "/tmp/a.txt\n/tmp/b.txt"), blobData: nil)
        let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]
        #expect(urls?.map(\.path) == ["/tmp/a.txt", "/tmp/b.txt"])
    }
}
