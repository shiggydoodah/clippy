import QuartzCore
import SwiftUI

struct ItemListView: View {
    var model: PanelViewModel
    /// Monotonic timestamp of the last selection move — see scrollToSelection.
    @State private var lastSelectionMove: CFTimeInterval = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.visibleItems.enumerated()), id: \.element.id) { index, item in
                        ItemRowView(
                            item: item,
                            shortcutNumber: index < 9 ? index + 1 : nil,
                            isSelected: index == model.selectedIndex,
                            // Favourites are curated, not chronological — the
                            // capture timestamp is noise there.
                            showsTimestamp: model.activeTab == .history
                        )
                        .onTapGesture { model.select(index: index) }
                        .contextMenu {
                            // The only mouse route to a commit — every other
                            // path to the clipboard is a keystroke.
                            Button("Copy") { model.commit(item, paste: false) }
                            Divider()
                            Button(item.isFavourite ? "Remove from Favourites" : "Add to Favourites") {
                                model.toggleFavourite(item)
                            }
                            if item.isFavourite {
                                Button("Rename…") { model.requestRename(item) }
                            }
                            Divider()
                            Button("Delete", role: .destructive) { model.delete(item) }
                        }
                    }
                }
                .padding(6)
            }
            .onChange(of: model.selectedIndex) { scrollToSelection(proxy) }
            // Re-summons and tab switches reset the selection without
            // necessarily changing selectedIndex — snap the viewport back too.
            .onChange(of: model.showCount) { scrollToSelection(proxy) }
            .onChange(of: model.activeTab) { scrollToSelection(proxy) }
            .overlay {
                if model.visibleItems.isEmpty {
                    emptyState
                }
            }
        }
    }

    /// The "animated selection scroll" polish, but only for deliberate
    /// presses. Key-repeat arrives every ~30ms — far faster than a 0.12s
    /// scroll animation can finish. Animating every step lets the viewport
    /// fall behind the selection until the highlighted row is off-screen and
    /// the list looks frozen, so rapid moves jump instantly instead.
    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        guard let id = model.selectedItem?.id else { return }
        let now = CACurrentMediaTime()
        defer { lastSelectionMove = now }
        if now - lastSelectionMove < 0.25 {
            proxy.scrollTo(id)
        } else {
            withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: emptySymbol)
                .font(.system(size: 28))
                .foregroundStyle(.quaternary)
            Text(emptyTitle)
                .foregroundStyle(.secondary)
            Text(emptyHint)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
        .padding()
    }

    private var emptySymbol: String {
        if !model.searchText.isEmpty { return "magnifyingglass" }
        return model.activeTab == .favourites ? "star" : "clipboard"
    }

    private var emptyTitle: String {
        if !model.searchText.isEmpty { return "No matches" }
        return model.activeTab == .favourites ? "No favourites yet" : "History is empty"
    }

    private var emptyHint: String {
        if !model.searchText.isEmpty { return "Try a different search" }
        return model.activeTab == .favourites
            ? "Select an item and press ⌘F to keep it here"
            : "Copy something and it will appear here"
    }
}
