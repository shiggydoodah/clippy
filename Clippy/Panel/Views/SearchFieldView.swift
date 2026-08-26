import SwiftUI

struct SearchFieldView: View {
    @Bindable var model: PanelViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search clipboard", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($isFocused)
                .onAppear { isFocused = true }
                // Re-grab focus on every summon — the field must always be
                // ready to type into.
                .onChange(of: model.showCount) { isFocused = true }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
