import AppKit

/// Stateless mapping from raw pasteboard content to an `ItemKind`.
/// Takes plain values rather than an `NSPasteboard` so tests never need a
/// live pasteboard. Classification runs in a fixed order — first match wins.
nonisolated enum ItemClassifier {

    static func classify(types: Set<NSPasteboard.PasteboardType>, string: String?) -> ItemKind {
        if types.contains(.tiff) || types.contains(.png) { return .image }
        if types.contains(.fileURL) { return .file }

        guard let string else { return .text }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        if isLink(trimmed) { return .link }
        if isColour(trimmed) { return .colour }
        if looksLikeCode(trimmed) { return .code }
        return .text
    }

    // MARK: - Detection

    /// The whole (trimmed) string must be a single http(s) URL with a host:
    /// "see https://example.com for details" is text, "www.example.com" is text.
    private static func isLink(_ text: String) -> Bool {
        guard !text.isEmpty,
              !text.contains(where: \.isWhitespace),
              let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty
        else { return false }
        return true
    }

    /// #RGB, #RRGGBB or #RRGGBBAA — there is deliberately no 4-digit #RGBA form.
    private static func isColour(_ text: String) -> Bool {
        guard text.hasPrefix("#") else { return false }
        let digits = text.dropFirst()
        guard digits.count == 3 || digits.count == 6 || digits.count == 8 else { return false }
        return digits.allSatisfy(\.isHexDigit)
    }

    /// Deliberately narrow: false positives are unacceptable,
    /// false negatives are fine. Two independent signals must both fire:
    /// indentation structure AND a density of symbols that are rare in prose.
    /// A lone `const x = 1;` therefore classifies as text — accepted trade-off.
    private static let structuralSymbols = Set("{}();=<>[]")

    private static func looksLikeCode(_ text: String) -> Bool {
        if text.hasPrefix("#!") { return true }
        guard text.contains("\n") else { return false }

        let lines = text.components(separatedBy: "\n")
        let indentedLines = lines.count { $0.hasPrefix("\t") || $0.hasPrefix("  ") }

        let symbolCount = text.count { structuralSymbols.contains($0) }
        let density = Double(symbolCount) / Double(text.count)

        return indentedLines >= 2 && density >= 0.03
    }
}
