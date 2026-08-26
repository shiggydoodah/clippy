import AppKit
import SwiftUI
import os

/// Owns the panel window: configuration, positioning, show/hide, and the
/// keyboard/mouse event routing that SwiftUI cannot do from inside a
/// nonactivating panel.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {

    /// Single source of truth for the panel's dimensions — PanelRootView
    /// sizes its SwiftUI tree from this too.
    static let panelSize = NSSize(width: 680, height: 420)

    private let logger = Logger(subsystem: "com.clip.app", category: "PanelController")
    private let panel: SummonPanel
    private let viewModel: PanelViewModel
    private let storage: StorageService?
    private let pasteService = PasteService()
    private var keyMonitor: Any?
    private var clickOutsideMonitor: Any?
    /// Frontmost app recorded just before the panel appears — PasteService
    /// returns focus (and the paste) to it.
    private(set) var previousApp: NSRunningApplication?

    init(storage: StorageService?) {
        self.storage = storage
        viewModel = PanelViewModel(storage: storage)
        panel = SummonPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            // .nonactivatingPanel is the whole reason this is an NSPanel: the
            // panel takes key input without activating the app underneath.
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        super.init()
        viewModel.dismiss = { [weak self] in self?.hide() }
        viewModel.onCommit = { [weak self] item, paste in self?.commit(item, paste: paste) }
        viewModel.onRenameRequest = { [weak self] item in self?.presentRenameSheet(for: item) }
        configurePanel()
        logger.log("Panel ready")
    }

    private func configurePanel() {
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        for button: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = false
        // Deactivation is handled via windowDidResignKey instead, because the
        // app underneath never deactivates in the first place.
        panel.hidesOnDeactivate = false
        // The panel is created once and shown many times; releasing it on
        // close would leave a dangling reference.
        panel.isReleasedWhenClosed = false
        // Summon must feel instant (<100ms to first paint).
        panel.animationBehavior = .none
        panel.isFloatingPanel = true
        panel.delegate = self
        let hostingView = NSHostingView(rootView: PanelRootView(model: viewModel))
        // The title bar is hidden but .titled + .fullSizeContentView still
        // reports it as a top safe-area inset, shoving the content ~28pt down.
        hostingView.safeAreaRegions = []
        panel.contentView = hostingView
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        viewModel.prepareForShow()
        position()
        // With .nonactivatingPanel this grants the panel key status without
        // activating Clip — the previous app keeps the menu bar.
        // A short fade-in reads as polish without delaying key readiness;
        // hide stays instant because paste-back timing depends on it.
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        installEventMonitors()
    }

    func hide() {
        removeEventMonitors()
        // A click outside can hide the panel while the rename sheet is still
        // attached; ordering out underneath it would strand the sheet on
        // screen. Ending it as a cancel runs the completion handler normally.
        if let sheet = panel.attachedSheet {
            panel.endSheet(sheet, returnCode: .cancel)
        }
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    /// Centred horizontally, top edge one third down the active screen —
    /// Spotlight-like. NSScreen.main is the screen with
    /// keyboard focus, i.e. where the user is working right now.
    private func position() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - Self.panelSize.width / 2,
            // AppKit's y axis grows upward, so "one third down from the top"
            // is maxY minus a third of the height, minus the panel height.
            y: visible.maxY - visible.height / 3 - Self.panelSize.height
        )
        panel.setFrameOrigin(origin)
    }

    /// Commit sequence: fetch any blob first (the write needs it), then
    /// write → hide → reactivate → optional synthetic ⌘V, all inside
    /// PasteService apart from the hide, which only this controller can do.
    private func commit(_ item: Item, paste: Bool) {
        let previousApp = previousApp
        Task {
            var blobData: Data?
            if item.kind == .image {
                blobData = try? await storage?.blobData(for: item)
            }
            pasteService.write(item, blobData: blobData)
            hide()
            await pasteService.completePaste(reactivating: previousApp, andPaste: paste)
        }
    }

    // MARK: - Event routing

    /// A local key monitor is the one reliable way to run the full keyboard
    /// map while a SwiftUI TextField keeps focus. Events we handle return nil
    /// (swallowed); everything else falls through to the search field, so
    /// typing filters without any focus juggling.
    private func installEventMonitors() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            // While the rename sheet is up the sheet owns the keyboard:
            // Return must press its default button and esc must cancel it,
            // not commit/hide the panel underneath.
            guard self.panel.attachedSheet == nil else { return event }
            return self.handleKeyDown(event) ? nil : event
        }
        // Global monitors only see events destined for *other* apps, which is
        // exactly the "clicked outside" signal. Mouse monitors need no
        // Accessibility permission (key monitors would).
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.hide()
        }
    }

    private func removeEventMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let clickOutsideMonitor { NSEvent.removeMonitor(clickOutsideMonitor) }
        keyMonitor = nil
        clickOutsideMonitor = nil
    }

    /// The full keyboard map. Returns true if the event was handled.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch event.keyCode {
        case 53: // esc
            hide()
            return true
        case 125: // down arrow; with ⌘ in Favourites, reorder instead
            if modifiers == .command {
                viewModel.moveFavouriteSelected(by: 1)
            } else {
                viewModel.moveSelection(by: 1)
            }
            return true
        case 126: // up arrow
            if modifiers == .command {
                viewModel.moveFavouriteSelected(by: -1)
            } else {
                viewModel.moveSelection(by: -1)
            }
            return true
        case 36: // return copies; ⌘return also pastes into the previous app
            viewModel.commitSelected(paste: modifiers == .command)
            return true
        case 48: // tab — switches History/Favourites, never moves focus
            viewModel.switchTab()
            return true
        case 51 where modifiers == .command: // ⌘⌫
            viewModel.deleteSelected()
            return true
        default:
            break
        }

        guard let characters = event.charactersIgnoringModifiers?.lowercased() else { return false }

        if modifiers == .command {
            if let digit = Int(characters), (1...9).contains(digit) {
                viewModel.commitItem(atDisplayIndex: digit - 1, paste: false)
                return true
            }
            if characters == "f" {
                viewModel.toggleFavouriteSelected()
                return true
            }
            if characters == "," {
                // The only guaranteed route to Settings when the menu bar
                // icon is hidden.
                hide()
                SettingsOpener.open()
                return true
            }
        }
        if modifiers == [.command, .shift], characters == "v" {
            viewModel.openSelected()
            return true
        }
        return false
    }

    // MARK: - Rename sheet

    /// NSAlert as a sheet on the panel (never runModal — that would activate
    /// the app, which the nonactivating panel exists to avoid).
    private func presentRenameSheet(for item: Item) {
        let alert = NSAlert()
        alert.messageText = "Rename Favourite"
        alert.informativeText = "Shown in place of the content preview. Leave empty to go back to the preview."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = item.favouriteLabel ?? ""
        field.placeholderString = item.preview
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: panel) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let label = field.stringValue
            Task {
                do {
                    try await self.storage?.renameFavourite(id: item.id, label: label)
                } catch {
                    self.logger.error("Rename failed: \(String(describing: error), privacy: .public)")
                }
                self.viewModel.reload()
            }
        }
    }

    // MARK: - NSWindowDelegate

    /// Losing key status means the user clicked into another window — the
    /// panel should get out of the way.
    /// Exception: key status moving to our own attached sheet (rename).
    func windowDidResignKey(_ notification: Notification) {
        guard panel.attachedSheet == nil else { return }
        hide()
    }
}
