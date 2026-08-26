import AppKit
import KeyboardShortcuts
import os

extension KeyboardShortcuts.Name {
    /// Default ⌥Space — a global hotkey needs at least one
    /// modifier, so plain Space is not registrable.
    static let summonPanel = Self("summonPanel", default: .init(.space, modifiers: [.option]))
}

/// Thin wrapper around KeyboardShortcuts registration. The recorder UI for
/// changing the shortcut lives in General settings; the default applies
/// until the user records something else.
@MainActor
final class HotkeyManager {
    private let logger = Logger(subsystem: "com.clip.app", category: "HotkeyManager")

    init(panelController: PanelController) {
        KeyboardShortcuts.onKeyDown(for: .summonPanel) { [weak panelController] in
            panelController?.toggle()
        }
        logger.log("Global hotkey registered")
    }
}
