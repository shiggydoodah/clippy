import AppKit
import Testing
@testable import Clippy

struct ThemeControllerTests {

    @Test func lightMapsToAqua() {
        #expect(ThemeController.appearanceName(for: "light") == .aqua)
    }

    @Test func darkMapsToDarkAqua() {
        #expect(ThemeController.appearanceName(for: "dark") == .darkAqua)
    }

    @Test func systemAndUnknownFollowTheSystem() {
        #expect(ThemeController.appearanceName(for: "system") == nil)
        #expect(ThemeController.appearanceName(for: "gibberish") == nil)
    }
}
