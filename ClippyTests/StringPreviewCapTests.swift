import Foundation
import Testing
@testable import Clippy

/// Regression coverage for the preview pane's bounded-text rule: rendering a
/// full multi-megabyte clip in the preview stalled selection cycling, so the
/// pane must only ever receive a capped prefix.
struct StringPreviewCapTests {

    @Test func shortStringIsUntouched() {
        let result = "hello".previewCapped(to: 10)
        #expect(result.text == "hello")
        #expect(!result.isTruncated)
    }

    @Test func exactLimitIsNotTruncated() {
        let result = "12345".previewCapped(to: 5)
        #expect(result.text == "12345")
        #expect(!result.isTruncated)
    }

    @Test func longStringIsCappedAtLimit() {
        let result = String(repeating: "a", count: 100).previewCapped(to: 5)
        #expect(result.text == "aaaaa")
        #expect(result.isTruncated)
    }

    @Test func emptyStringIsNotTruncated() {
        let result = "".previewCapped(to: 5)
        #expect(result.text.isEmpty)
        #expect(!result.isTruncated)
    }

    @Test func capCountsCharactersNotBytes() {
        // Four graphemes, far more than 4 UTF-8 bytes — the cap must not
        // split a character or misreport truncation for multi-byte content.
        let flags = "🇬🇧🇫🇷🇩🇪🇪🇸"
        let result = flags.previewCapped(to: 4)
        #expect(result.text == flags)
        #expect(!result.isTruncated)

        let capped = flags.previewCapped(to: 2)
        #expect(capped.text == "🇬🇧🇫🇷")
        #expect(capped.isTruncated)
    }
}
