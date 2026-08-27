import SwiftUI

/// The Favourites pane: drag to reorder, rename inline, remove.
/// Talks to the same StorageService the rest of the app uses, reached
/// through the app delegate (the Settings scene is created by SwiftUI, so
/// it cannot be constructor-injected like the panel).
struct FavouritesSettingsView: View {
    @State private var favourites: [Item] = []
    @State private var labels: [UUID: String] = [:]

    private var storage: StorageService? {
        (NSApp.delegate as? AppDelegate)?.storageService
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if favourites.isEmpty {
                Text("No favourites yet — select an item in the panel and press ⌘F.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Drag to reorder — the order drives the ⌘1–9 slots in the Favourites tab.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                List {
                    ForEach(Array(favourites.enumerated()), id: \.element.id) { index, item in
                        HStack {
                            // Only the first nine favourites get a ⌘ slot;
                            // later rows keep the column width for alignment.
                            Text("⌘\(index + 1)")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .opacity(index < 9 ? 1 : 0)
                            TextField(item.preview, text: labelBinding(for: item))
                                .textFieldStyle(.plain)
                                .onSubmit { commitRename(item) }
                            Spacer()
                            Button {
                                unfavourite(item)
                            } label: {
                                Image(systemName: "star.slash")
                            }
                            .buttonStyle(.borderless)
                            .help(unfavouriteHelp(for: item))
                        }
                    }
                    .onMove(perform: move)
                }
            }
        }
        .padding(16)
        .frame(minHeight: 300)
        .task { await reload() }
    }

    /// An item the user deleted from history has nowhere to fall back to,
    /// so unfavouriting it removes it for good — say which one it will be.
    private func unfavouriteHelp(for item: Item) -> String {
        item.isHiddenFromHistory
            ? "Remove from favourites (deletes it — it is no longer in history)"
            : "Remove from favourites (keeps the item in history)"
    }

    private func labelBinding(for item: Item) -> Binding<String> {
        Binding(
            get: { labels[item.id] ?? item.favouriteLabel ?? "" },
            set: { labels[item.id] = $0 }
        )
    }

    private func commitRename(_ item: Item) {
        guard let storage, let label = labels[item.id] else { return }
        Task {
            _ = try? await storage.renameFavourite(id: item.id, label: label)
            await reload()
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        favourites.move(fromOffsets: source, toOffset: destination)
        guard let storage else { return }
        let ids = favourites.map(\.id)
        Task {
            try? await storage.setFavouriteOrder(ids: ids)
            await reload()
        }
    }

    private func unfavourite(_ item: Item) {
        guard let storage else { return }
        Task {
            _ = try? await storage.toggleFavourite(id: item.id)
            await reload()
        }
    }

    private func reload() async {
        guard let storage else { return }
        favourites = (try? await storage.favouriteItems()) ?? []
        labels = [:]
    }
}
