import AppKit

// NSObject subclass because NSMenuItem's target/action mechanism is
// Objective-C message dispatch — a plain Swift class can't receive it.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        statusItem.button?.image = NSImage(
            systemSymbolName: "paperclip",
            accessibilityDescription: "Clip"
        )
        statusItem.menu = makeMenu()
        refreshAppearance()

        // The Settings window writes showMenuBarIcon; there is no direct
        // reference back here, so observe the defaults instead.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(defaultsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    /// UserDefaults posts this on whichever thread wrote the change —
    /// NSStatusItem throws when touched off main, so hop explicitly.
    @objc nonisolated private func defaultsChanged() {
        Task { @MainActor in
            self.refreshAppearance()
        }
    }

    /// Paused state reads as the dimmed icon: appearsDisabled keeps the same
    /// glyph while making it unmistakably inactive.
    private func refreshAppearance() {
        statusItem.isVisible = AppSettings.showMenuBarIcon
        let paused = !AppSettings.historyEnabled
        statusItem.button?.appearsDisabled = paused
        statusItem.button?.toolTip = paused ? "Clip — history paused" : "Clip"
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let pauseItem = NSMenuItem(
            title: "Pause History",
            action: #selector(togglePause(_:)),
            keyEquivalent: ""
        )
        pauseItem.target = self
        menu.addItem(pauseItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Clip",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        menu.addItem(quitItem)

        return menu
    }

    @objc private func togglePause(_ sender: NSMenuItem) {
        // Same switch as Settings' "Enable clipboard history" — pausing here
        // and disabling there are one thing.
        AppSettings.historyEnabled.toggle()
    }

    @objc private func openSettings(_ sender: NSMenuItem) {
        SettingsOpener.open()
    }

}

extension StatusItemController: NSMenuDelegate {
    /// Checkmarks are refreshed on open rather than kept in sync — the
    /// setting can change from other places (the Settings window).
    func menuWillOpen(_ menu: NSMenu) {
        for item in menu.items {
            if item.action == #selector(togglePause(_:)) {
                item.state = AppSettings.historyEnabled ? .off : .on
            }
        }
    }
}
