import Foundation
import Testing
@testable import Clippy

/// The single-line preview builder: flattening, trimming, and the 200-char
/// cap. Also guards the bounded-work rule — a preview of a
/// multi-megabyte clip must never process the whole string.
struct ClipboardMonitorPreviewTests {

    @Test func shortStringIsUntouched() {
        #expect(ClipboardMonitor.preview(of: "hello world") == "hello world")
    }

    @Test func newlineVariantsFlattenToSingleSpaces() {
        // \r\n is one grapheme and must become one space, not two.
        #expect(ClipboardMonitor.preview(of: "a\nb\r\nc\u{2028}d") == "a b c d")
    }

    @Test func surroundingWhitespaceIsTrimmed() {
        #expect(ClipboardMonitor.preview(of: "  hello  \n") == "hello")
    }

    @Test func exactly200CharactersIsNotTruncated() {
        let text = String(repeating: "a", count: 200)
        #expect(ClipboardMonitor.preview(of: text) == text)
    }

    @Test func overlongStringIsCappedAt200WithEllipsis() {
        let preview = ClipboardMonitor.preview(of: String(repeating: "a", count: 300))
        #expect(preview.count == 200)
        #expect(preview == String(repeating: "a", count: 199) + "…")
    }

    @Test func megabyteClipProducesABoundedPreview() {
        let huge = String(repeating: "line of text\n", count: 100_000)
        let preview = ClipboardMonitor.preview(of: huge)
        #expect(preview.count == 200)
        #expect(preview.hasSuffix("…"))
        #expect(!preview.contains("\n"))
    }

    @Test func whitespaceOnlyStringPreviewsEmpty() {
        #expect(ClipboardMonitor.preview(of: "\n\n  \n").isEmpty)
    }
}
