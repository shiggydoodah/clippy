import Foundation

/// Typed access to the app's UserDefaults-backed settings. Named `AppSettings`
/// rather than the more obvious `Settings` because that collides with
/// SwiftUI's `Settings` scene (used in ClipApp.swift).
///
/// Keys are exposed so the SwiftUI settings panes can bind the same storage
/// via @AppStorage — one source of truth, two access styles.
nonisolated enum AppSettings {

    enum Keys {
        static let historyEnabled = "historyEnabled"
        static let maxItems = "maxItems"
        static let maxAgeSeconds = "maxAgeSeconds"
        static let persistAcrossRestart = "persistAcrossRestart"
        static let ignorePasswordManagers = "ignorePasswordManagers"
        static let maxItemBytes = "maxItemBytes"
        static let excludedExtensions = "excludedExtensions"
        static let excludedFolders = "excludedFolders"
        static let excludedApps = "excludedApps"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let theme = "theme"

        static let all = [
            historyEnabled, maxItems, maxAgeSeconds, persistAcrossRestart,
            ignorePasswordManagers, maxItemBytes,
            excludedExtensions, excludedFolders, excludedApps, showMenuBarIcon,
            theme,
        ]
    }

    private static var defaults: UserDefaults { .standard }

    /// Call once at launch, before anything reads a setting. `register`
    /// supplies fallbacks without writing them, so "Reset all settings"
    /// (removing the keys) lands back on these values.
    static func registerDefaults() {
        defaults.register(defaults: [
            Keys.historyEnabled: true,
            Keys.maxItems: 500,
            Keys.maxAgeSeconds: 0,          // forever
            Keys.persistAcrossRestart: true,
            Keys.ignorePasswordManagers: true,
            Keys.maxItemBytes: 10_000_000,  // 10MB
            Keys.showMenuBarIcon: true,
            Keys.theme: "system",
        ])
    }

    /// Master capture toggle — when off, the monitor stores nothing.
    static var historyEnabled: Bool {
        get { defaults.bool(forKey: Keys.historyEnabled) }
        set { defaults.set(newValue, forKey: Keys.historyEnabled) }
    }

    /// Retention: maximum non-favourite items. 0 means unlimited.
    static var maxItems: Int {
        get { defaults.integer(forKey: Keys.maxItems) }
        set { defaults.set(newValue, forKey: Keys.maxItems) }
    }

    /// Retention: maximum age in seconds. 0 means keep forever.
    static var maxAgeSeconds: Int {
        get { defaults.integer(forKey: Keys.maxAgeSeconds) }
        set { defaults.set(newValue, forKey: Keys.maxAgeSeconds) }
    }

    /// Off = ephemeral history. Read once at launch to pick the
    /// storage mode; toggling takes effect at the next launch.
    static var persistAcrossRestart: Bool {
        get { defaults.bool(forKey: Keys.persistAcrossRestart) }
        set { defaults.set(newValue, forKey: Keys.persistAcrossRestart) }
    }

    /// Skips captures sourced from known password manager apps. This is an
    /// extra layer on top of the concealed-type check, which is unconditional
    /// (CLAUDE.md hard rule) and NOT controlled by this setting.
    static var ignorePasswordManagers: Bool {
        get { defaults.bool(forKey: Keys.ignorePasswordManagers) }
        set { defaults.set(newValue, forKey: Keys.ignorePasswordManagers) }
    }

    /// Capture filter: skip payloads larger than this. 0 means no limit.
    static var maxItemBytes: Int {
        get { defaults.integer(forKey: Keys.maxItemBytes) }
        set { defaults.set(newValue, forKey: Keys.maxItemBytes) }
    }

    static var excludedExtensions: [String] {
        get { defaults.stringArray(forKey: Keys.excludedExtensions) ?? [] }
        set { defaults.set(newValue, forKey: Keys.excludedExtensions) }
    }

    static var excludedFolders: [String] {
        get { defaults.stringArray(forKey: Keys.excludedFolders) ?? [] }
        set { defaults.set(newValue, forKey: Keys.excludedFolders) }
    }

    static var excludedApps: [String] {
        get { defaults.stringArray(forKey: Keys.excludedApps) ?? [] }
        set { defaults.set(newValue, forKey: Keys.excludedApps) }
    }

    static var showMenuBarIcon: Bool {
        get { defaults.bool(forKey: Keys.showMenuBarIcon) }
        set { defaults.set(newValue, forKey: Keys.showMenuBarIcon) }
    }

    /// "system" | "light" | "dark".
    static var theme: String {
        get { defaults.string(forKey: Keys.theme) ?? "system" }
        set { defaults.set(newValue, forKey: Keys.theme) }
    }

    /// Danger zone: removes every stored key, landing back on the
    /// registered defaults above.
    static func resetAll() {
        for key in Keys.all {
            defaults.removeObject(forKey: key)
        }
    }
}
