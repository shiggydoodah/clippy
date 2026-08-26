import SwiftUI

struct FooterBarView: View {
    var model: PanelViewModel

    var body: some View {
        HStack(spacing: 14) {
            hint("↵", "copy")
            hint("⌘↵", "paste")
            hint("⌘1–9", "quick copy")
            hint("⌘⌫", "delete")
            hint("⌘F", "favourite")
            hint("⌘⇧V", "open")
            if model.activeTab == .favourites {
                hint("⌘↑↓", "reorder")
            }
            Spacer()
            hint("esc", "dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key).font(.system(size: 10, weight: .medium))
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}
