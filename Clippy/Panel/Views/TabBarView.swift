import SwiftUI

struct TabBarView: View {
    var model: PanelViewModel

    var body: some View {
        HStack(spacing: 12) {
            tab("History", count: model.historyItems.count, tab: .history)
            tab("Favourites", count: model.favouriteItems.count, tab: .favourites)
            Spacer()
            Text("⇥ switch")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func tab(_ title: String, count: Int, tab: PanelViewModel.Tab) -> some View {
        let isActive = model.activeTab == tab
        return Text("\(title) \(count)")
            .font(.system(size: 12, weight: isActive ? .semibold : .regular))
            .foregroundStyle(isActive ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isActive ? Color.secondary.opacity(0.15) : .clear)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if !isActive { model.switchTab() }
            }
    }
}
