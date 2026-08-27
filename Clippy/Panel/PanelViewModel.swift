import AppKit
import ImageIO
import Observation
import os

/// State and actions for the panel's SwiftUI tree. @Observable (macOS 14+)
/// rather than ObservableObject: views track exactly the properties they
/// read, and the view model can be passed around as a plain reference.
@MainActor
@Observable
final class PanelViewModel {

    enum Tab {
        case history
        case favourites
    }

    @ObservationIgnored private let logger = Logger(subsystem: "com.clip.app", category: "PanelViewModel")
    @ObservationIgnored private let storage: StorageService?
    /// Thumbnails are decoded on first display and cached.
    /// NSCache evicts under memory pressure, which is exactly the behaviour
    /// we want for decoded images.
    @ObservationIgnored private let imageCache = NSCache<NSString, NSImage>()

    /// Injected by PanelController — the view model cannot know how the
    /// window is hidden.
    @ObservationIgnored var dismiss: () -> Void = {}
    /// Injected by PanelController, which owns the paste flow (it holds the
    /// panel window and the previously frontmost app). The Bool is "also
    /// paste into the previous app" — true for ⌘↵, false for plain ↵.
    @ObservationIgnored var onCommit: (_ item: Item, _ paste: Bool) -> Void = { _, _ in }
    /// Injected by PanelController — rename needs an AppKit sheet on the panel.
    @ObservationIgnored var onRenameRequest: (Item) -> Void = { _ in }

    private(set) var historyItems: [Item] = []
    private(set) var favouriteItems: [Item] = []
    private(set) var selectedIndex = 0
    private(set) var activeTab: Tab = .history
    /// Bumped on every summon; the search field watches it to re-grab focus.
    private(set) var showCount = 0
    var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            selectedIndex = 0
            refreshVisibleItems()
        }
    }

    /// Stored rather than computed: several views read this on every render,
    /// and the search filter scans full text content — recompute once per
    /// state change, not once per access.
    private(set) var visibleItems: [Item] = []

    init(storage: StorageService?) {
        self.storage = storage
        // Preview images are pane-sized (≤1200px) but still megabytes each
        // once decoded; bound the cache so browsing image history cannot
        // hold RAM hostage.
        imageCache.countLimit = 12
        imageCache.totalCostLimit = 64 * 1024 * 1024
    }

    // MARK: - Derived state

    private func refreshVisibleItems() {
        let base = activeTab == .history ? historyItems : favouriteItems
        visibleItems = ItemSearchFilter.filter(base, query: searchText)
    }

    var selectedItem: Item? {
        let items = visibleItems
        guard items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }

    // MARK: - Lifecycle

    func prepareForShow() {
        searchText = ""
        activeTab = .history
        selectedIndex = 0
        refreshVisibleItems()
        showCount += 1
        reload()
    }

    /// How many history rows the panel holds in memory for search — the
    /// filter runs over exactly this window, never as a database query.
    private static let historyWindow = 1000

    func reload() {
        Task { await load() }
    }

    /// Awaitable so tests can load deterministically; the app goes through
    /// reload(), which is safe to call from any synchronous UI path.
    func load() async {
        guard let storage else { return }
        do {
            historyItems = try await storage.recentItems(limit: Self.historyWindow)
            favouriteItems = try await storage.favouriteItems()
            refreshVisibleItems()
            clampSelection()
        } catch {
            logger.error("Failed to load items: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Selection

    func moveSelection(by delta: Int) {
        let count = visibleItems.count
        guard count > 0 else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), count - 1)
    }

    func select(index: Int) {
        guard visibleItems.indices.contains(index) else { return }
        selectedIndex = index
    }

    /// ⌘↑/⌘↓ — manual reorder, only meaningful on the Favourites tab and
    /// only while not searching (a filtered list has no stable positions).
    func moveFavouriteSelected(by delta: Int) {
        guard activeTab == .favourites,
              searchText.isEmpty,
              let item = selectedItem,
              let storage
        else { return }
        Task {
            do {
                try await storage.moveFavourite(id: item.id, delta: delta)
                favouriteItems = try await storage.favouriteItems()
                refreshVisibleItems()
                if let newIndex = favouriteItems.firstIndex(where: { $0.id == item.id }) {
                    selectedIndex = newIndex
                }
            } catch {
                logger.error("Reorder failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func requestRename(_ item: Item) {
        guard item.isFavourite else { return }
        onRenameRequest(item)
    }

    func toggleFavourite(_ item: Item) {
        guard let storage else { return }
        Task {
            do {
                try await storage.toggleFavourite(id: item.id)
                await load()
            } catch {
                logger.error("Failed to toggle favourite: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// ⌘⌫ and the row context menu. Which list the user is looking at
    /// decides how far the delete reaches: from History a favourite only
    /// leaves the history list, because favourites are removed from the
    /// Favourites tab and nowhere else. From Favourites it is a real delete.
    func delete(_ item: Item) {
        let fromHistory = activeTab == .history
        let keepsFavourite = fromHistory && item.isFavourite
        historyItems.removeAll { $0.id == item.id }
        if !keepsFavourite {
            favouriteItems.removeAll { $0.id == item.id }
        }
        refreshVisibleItems()
        clampSelection()
        Task { await commitDelete(item, fromHistory: fromHistory) }
    }

    /// The storage half of delete(_:) — the list is updated first so the row
    /// disappears on the same frame as the keystroke. Awaitable so tests can
    /// drive it deterministically; the app goes through delete(_:).
    func commitDelete(_ item: Item, fromHistory: Bool) async {
        guard let storage else { return }
        do {
            if fromHistory {
                try await storage.removeFromHistory(id: item.id)
            } else {
                try await storage.deleteItem(id: item.id)
            }
        } catch {
            logger.error("Failed to delete item: \(String(describing: error), privacy: .public)")
            reload()
        }
    }

    func switchTab() {
        activeTab = activeTab == .history ? .favourites : .history
        selectedIndex = 0
        refreshVisibleItems()
    }

    private func clampSelection() {
        let count = visibleItems.count
        selectedIndex = count == 0 ? 0 : min(selectedIndex, count - 1)
    }

    // MARK: - Actions

    /// Every commit route — keyboard, ⌘1–9, and the row context menu —
    /// funnels through here.
    func commit(_ item: Item, paste: Bool) {
        onCommit(item, paste)
    }

    func commitSelected(paste: Bool) {
        guard let item = selectedItem else { return }
        commit(item, paste: paste)
    }

    func commitItem(atDisplayIndex index: Int, paste: Bool) {
        let items = visibleItems
        guard items.indices.contains(index) else { return }
        commit(items[index], paste: paste)
    }

    func deleteSelected() {
        guard let item = selectedItem else { return }
        delete(item)
    }

    func toggleFavouriteSelected() {
        guard let item = selectedItem else { return }
        toggleFavourite(item)
    }

    /// ⌘⇧V — links open in the default browser, files reveal in Finder.
    /// Other kinds have no sensible "open" and do nothing.
    func openSelected() {
        guard let item = selectedItem else { return }
        switch item.kind {
        case .link:
            guard let text = item.textContent, let url = URL(string: text) else { return }
            NSWorkspace.shared.open(url)
            dismiss()
        case .file:
            let urls = (item.textContent ?? "")
                .split(separator: "\n")
                .map { URL(fileURLWithPath: String($0)) }
            guard !urls.isEmpty else { return }
            NSWorkspace.shared.activateFileViewerSelecting(urls)
            dismiss()
        case .text, .image, .colour, .code:
            break
        }
    }

    // MARK: - Previews

    /// Synchronous cache peek so the preview pane can show a cached image on
    /// the same frame the selection changes, without a spinner flash.
    func cachedPreviewImage(for item: Item) -> NSImage? {
        imageCache.object(forKey: item.contentHash as NSString)
    }

    func previewImage(for item: Item) async -> NSImage? {
        guard item.kind == .image, let storage else { return nil }
        let key = item.contentHash as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        guard let data = try? await storage.blobData(for: item),
              let image = await Self.decodeDownsampled(data)
        else { return nil }
        let cost = Int(image.size.width * image.size.height) * 4
        imageCache.setObject(image, forKey: key, cost: cost)
        return image
    }

    /// nonisolated async, so it runs on the concurrent pool: NSImage(data:)
    /// defers PNG/JPEG decode to first *draw*, which lands the whole decode
    /// on the main thread mid-render. ImageIO's thumbnail API decodes here,
    /// off the main actor, and downsamples to pane scale — a 10MB screenshot
    /// never becomes a 40MB bitmap.
    nonisolated private static func decodeDownsampled(_ data: Data) async -> NSImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_200,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options)
        else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
