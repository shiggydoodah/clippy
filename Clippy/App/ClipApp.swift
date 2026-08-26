import SwiftUI

@main
struct ClipApp: App {
    // SwiftUI owns the app lifecycle, but everything real (status item,
    // clipboard monitoring) is AppKit, driven from the delegate. The adaptor
    // is the bridge: SwiftUI instantiates this delegate and forwards the
    // NSApplication lifecycle callbacks to it.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The only SwiftUI scene: a standard Settings window,
        // opened via SettingsOpener from the status menu or the panel's ⌘,.
        Settings {
            SettingsRootView()
        }
    }
}
