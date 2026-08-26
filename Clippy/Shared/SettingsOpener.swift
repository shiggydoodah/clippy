import AppKit
import SwiftUI

/// Opens the SwiftUI Settings scene from AppKit contexts (status menu,
/// panel keyboard map). A menu bar app is normally background (LSUIElement),
/// so it must activate itself for the window to come forward.
@MainActor
enum SettingsOpener {
    static func open() {
        NSApp.activate()
        // The legacy showSettingsWindow: selector is accepted but silently
        // ignored on macOS 14+ — SwiftUI replaced it with the openSettings
        // environment action. Calling it on a fresh EnvironmentValues works
        // because the default action routes to the app's Settings scene; no
        // view context is needed.
        EnvironmentValues().openSettings()
    }
}
