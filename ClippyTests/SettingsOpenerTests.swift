import AppKit
import Testing
@testable import Clippy

// Hosted in the running app, so the SwiftUI Settings scene is live and
// open() is exercised end-to-end — the same path the status menu uses.
@MainActor
struct SettingsOpenerTests {

    /// Regression: on macOS 14+ SwiftUI accepts the legacy
    /// showSettingsWindow: selector but silently does nothing, so open()
    /// must be verified by the window actually appearing.
    @Test func openPresentsAVisibleSettingsWindow() {
        SettingsOpener.open()
        // The scene materialises its window on a later runloop turn.
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))

        let settingsWindow = NSApp.windows.first {
            // The only titled non-panel window this app can show is Settings
            // (status items are borderless, the summon panel is an NSPanel).
            $0.isVisible && $0.styleMask.contains(.titled) && !($0 is NSPanel)
        }
        #expect(settingsWindow != nil, "Settings window did not appear")
        settingsWindow?.close()
    }
}
