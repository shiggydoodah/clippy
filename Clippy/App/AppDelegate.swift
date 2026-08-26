import AppKit
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.clip.app", category: "AppDelegate")

    // Held strongly here — nothing else keeps these alive.
    private var statusItemController: StatusItemController?
    /// Read (not mutated) by the Settings window via NSApp.delegate.
    private(set) var storageService: StorageService?
    private var clipboardMonitor: ClipboardMonitor?
    private var panelController: PanelController?
    private var hotkeyManager: HotkeyManager?
    private var retentionEngine: RetentionEngine?
    private var themeController: ThemeController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.registerDefaults()
        themeController = ThemeController()
        statusItemController = StatusItemController()

        // Opening the database and running migrations takes a few
        // milliseconds — acceptable on the main thread once at launch.
        // Everything after this point runs on background queues.
        do {
            let directory = try StorageService.defaultDirectory()
            // "Remember history after restart" is read once here; toggling
            // it mid-session applies at the next launch.
            let mode: StorageService.Mode = AppSettings.persistAcrossRestart
                ? .persistent(directory: directory)
                : .ephemeral(vaultDirectory: directory)
            storageService = try StorageService(mode: mode)
        } catch {
            // The app stays up, but captures cannot be stored — make the
            // failure loud rather than silently dropping history.
            logger.fault("Storage unavailable, captures will be dropped: \(String(describing: error), privacy: .public)")
        }

        let retention = RetentionEngine(storage: storageService)
        retentionEngine = retention

        let monitor = ClipboardMonitor(storage: storageService)
        clipboardMonitor = monitor
        monitor.onItemStored = {
            Task { await retention.runAfterCapture() }
        }
        monitor.start()

        let panel = PanelController(storage: storageService)
        panelController = panel
        hotkeyManager = HotkeyManager(panelController: panel)

        Task { await retention.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor?.stop()
    }
}
