import SwiftUI

struct ItemRowView: View {
    let item: Item
    let shortcutNumber: Int?
    let isSelected: Bool
    var showsTimestamp = true

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: kindSymbol)
                .font(.system(size: 11))
                .frame(width: 18)
                .foregroundStyle(isSelected ? .primary : .secondary)
            Text(item.displayTitle)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if item.isFavourite {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.yellow)
            }
            if showsTimestamp {
                Text(item.lastUsedAt.compactRelativeDisplay)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            if let shortcutNumber {
                Text("⌘\(shortcutNumber)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.25) : .clear)
        )
        .contentShape(Rectangle())
    }

    private var kindSymbol: String {
        switch item.kind {
        case .text: "doc.text"
        case .link: "link"
        case .image: "photo"
        case .file: "doc"
        case .colour: "paintpalette"
        case .code: "chevron.left.forwardslash.chevron.right"
        }
    }
}
