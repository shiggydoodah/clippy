import AppKit
import os

/// Applies the General settings theme app-wide. Setting
/// NSApp.appearance covers every window — panel and settings alike;
/// nil means follow the system.
@MainActor
final class ThemeController {

    init() {
        apply()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(defaultsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    /// Pure mapping, testable without AppKit state.
    nonisolated static func appearanceName(for theme: String) -> NSAppearance.Name? {
        switch theme {
        case "light": .aqua
        case "dark": .darkAqua
        default: nil // system
        }
    }

    private func apply() {
        NSApp.appearance = Self.appearanceName(for: AppSettings.theme).flatMap(NSAppearance.init(named:))
    }

    /// Defaults notifications arrive on the writing thread — hop to main
    /// before touching NSApp.
    @objc nonisolated private func defaultsChanged() {
        Task { @MainActor in
            self.apply()
        }
    }
}
