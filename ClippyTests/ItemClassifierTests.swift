import AppKit
import Testing
@testable import Clippy

struct ItemClassifierTests {

    private func classify(
        types: Set<NSPasteboard.PasteboardType> = [.string],
        string: String? = nil
    ) -> ItemKind {
        ItemClassifier.classify(types: types, string: string)
    }

    // MARK: - Image

    @Test func tiffDataIsImage() {
        #expect(classify(types: [.tiff]) == .image)
    }

    @Test func pngDataIsImage() {
        #expect(classify(types: [.png]) == .image)
    }

    @Test func imageOutranksFile() {
        // First match wins, and image sits above file.
        #expect(classify(types: [.png, .fileURL]) == .image)
    }

    // MARK: - File

    @Test func fileURLIsFile() {
        #expect(classify(types: [.fileURL], string: "file:///Users/me/doc.pdf") == .file)
    }

    // MARK: - Link

    @Test func httpsURLIsLink() {
        #expect(classify(string: "https://developer.apple.com/documentation") == .link)
    }

    @Test func httpURLIsLink() {
        #expect(classify(string: "http://example.com") == .link)
    }

    @Test func urlWithSurroundingWhitespaceIsLink() {
        #expect(classify(string: "  https://example.com/page\n") == .link)
    }

    @Test func nonHTTPSchemeIsText() {
        #expect(classify(string: "ftp://example.com/file") == .text)
    }

    @Test func schemeWithoutHostIsText() {
        #expect(classify(string: "https://") == .text)
    }

    @Test func bareDomainIsText() {
        #expect(classify(string: "www.example.com") == .text)
    }

    @Test func sentenceContainingURLIsText() {
        #expect(classify(string: "see https://example.com for details") == .text)
    }

    // MARK: - Colour

    @Test func threeDigitHexIsColour() {
        #expect(classify(string: "#fff") == .colour)
    }

    @Test func sixDigitHexIsColour() {
        #expect(classify(string: "#A1B2C3") == .colour)
    }

    @Test func eightDigitHexIsColour() {
        #expect(classify(string: "#a1b2c3ff") == .colour)
    }

    @Test func fourDigitHexIsText() {
        // #RGB / #RRGGBB / #RRGGBBAA only — no #RGBA form.
        #expect(classify(string: "#abcd") == .text)
    }

    @Test func nonHexCharactersAreText() {
        #expect(classify(string: "#ggg") == .text)
    }

    @Test func bareHashIsText() {
        #expect(classify(string: "#") == .text)
    }

    // MARK: - Code

    @Test func shebangIsCode() {
        #expect(classify(string: "#!/bin/bash\necho hello") == .code)
    }

    @Test func indentedBracedSnippetIsCode() {
        let swift = """
        func greet(name: String) -> String {
            let message = "Hello, \\(name)"
            return message
        }
        """
        #expect(classify(string: swift) == .code)
    }

    @Test func singleLineStatementIsText() {
        // Accepted false negative — single lines never classify as code.
        #expect(classify(string: "const x = 1;") == .text)
    }

    @Test func plainProseIsText() {
        let prose = """
        Dear team,
        here are the notes from Tuesday.
        We agreed to ship on Friday.
        """
        #expect(classify(string: prose) == .text)
    }

    @Test func proseWithParenthesesIsText() {
        let prose = """
        The meeting (moved from Monday) went well.
        Next steps (a) write up, (b) send round.
        """
        #expect(classify(string: prose) == .text)
    }

    @Test func indentedProseWithoutSymbolsIsText() {
        let poem = """
        The road goes ever on
          down from the door
          where it began
        """
        #expect(classify(string: poem) == .text)
    }

    // MARK: - Text fallback

    @Test func plainStringIsText() {
        #expect(classify(string: "hello world") == .text)
    }

    @Test func nilStringIsText() {
        #expect(classify(types: [NSPasteboard.PasteboardType("com.example.custom")], string: nil) == .text)
    }

    @Test func emptyStringIsText() {
        #expect(classify(string: "") == .text)
    }
}
