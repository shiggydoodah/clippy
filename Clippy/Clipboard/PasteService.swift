import AppKit
import os

/// Writes the selected payload to the pasteboard, returns focus to the app
/// the user came from, and — when the user committed with ⌘↵ and the app is
/// trusted for Accessibility — synthesises ⌘V so the item lands directly in
/// that app. Every step degrades gracefully: without the permission the user
/// simply presses ⌘V themselves.
@MainActor
final class PasteService {

    private let logger = Logger(subsystem: "com.clip.app", category: "PasteService")
    private let pasteboard: NSPasteboard

    /// The pasteboard is injectable so tests can use a private named
    /// pasteboard instead of clobbering the user's real clipboard.
    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// Steps 3 and 4 of the §3.6 sequence — the caller performs step 1
    /// (write) and step 2 (hide the panel, which only PanelController can
    /// do) before calling this. `andPaste` is decided per keystroke: ↵
    /// copies only, ⌘↵ also pastes into the reactivated app.
    func completePaste(reactivating previousApp: NSRunningApplication?, andPaste paste: Bool) async {
        previousApp?.activate()

        guard paste else { return }
        guard Self.isAccessibilityTrusted else {
            // The contextual permission moment: the user just
            // asked for a direct paste, so now is the time to request
            // Accessibility. The item is already on the pasteboard, so ⌘V
            // still works while they decide. The system only shows the
            // dialog until the app appears in the Accessibility list, so
            // repeat calls are harmless.
            logger.log("⌘↵ without Accessibility permission — prompting, leaving the paste to the user")
            Self.promptForAccessibilityPermission()
            return
        }
        // The reactivated app needs a beat to accept key events before the
        // synthetic keystroke arrives; posting immediately drops the paste.
        try? await Task.sleep(for: .milliseconds(120))
        synthesisePasteKeystroke()
        logger.log("Synthesised paste into \(previousApp?.localizedName ?? "unknown app", privacy: .public)")
    }

    /// Writes the item's payload to the pasteboard. Our own monitor observes
    /// this write and dedupes it, refreshing lastUsedAt — floating the item
    /// to the top of history, as expected.
    func write(_ item: Item, blobData: Data?) {
        switch item.kind {
        case .image:
            guard let blobData else {
                logger.error("Missing blob for image item — nothing written")
                return
            }
            let type: NSPasteboard.PasteboardType =
                item.blobPath?.hasSuffix(".png") == true ? .png : .tiff
            pasteboard.clearContents()
            pasteboard.setData(blobData, forType: type)
        case .file:
            let urls = (item.textContent ?? "")
                .split(separator: "\n")
                .map { NSURL(fileURLWithPath: String($0)) }
            guard !urls.isEmpty else { return }
            pasteboard.clearContents()
            pasteboard.writeObjects(urls)
        case .text, .link, .colour, .code:
            pasteboard.clearContents()
            pasteboard.setString(item.textContent ?? "", forType: .string)
        }
    }

    // MARK: - Accessibility

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system's "grant Accessibility access" dialog. Called when
    /// the user commits with ⌘↵ without the permission, or from the button
    /// in General settings — never at launch.
    static func promptForAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Keystroke synthesis

    /// CGEvent speaks virtual key codes, not characters — 9 is kVK_ANSI_V on
    /// every keyboard layout's physical V position, which is what ⌘V checks.
    private func synthesisePasteKeystroke() {
        let vKey: CGKeyCode = 9
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else {
            logger.error("Could not create CGEvents for paste keystroke")
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
