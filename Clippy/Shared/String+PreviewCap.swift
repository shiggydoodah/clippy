import Foundation

nonisolated extension String {
    /// Bounded prefix for the preview pane. A history item can legally be
    /// megabytes of text (the capture size threshold defaults to 10MB), and
    /// laying that out in a Text view stalls the main thread for hundreds of
    /// milliseconds per selection change. Cost here is O(limit), never
    /// O(count) — do not replace the index walk with `count` or `prefix`
    /// comparisons that scan the whole string.
    func previewCapped(to limit: Int) -> (text: String, isTruncated: Bool) {
        guard let end = index(startIndex, offsetBy: limit, limitedBy: endIndex),
              end < endIndex
        else { return (self, false) }
        return (String(self[..<end]), true)
    }
}
