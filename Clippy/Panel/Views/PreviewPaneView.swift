import SwiftUI

struct PreviewPaneView: View {
    /// 2,000 characters fills the pane many times over; anything more only
    /// buys main-thread layout stalls (validated against 150KB–1MB clips).
    private static let textPreviewLimit = 2_000

    var model: PanelViewModel
    @State private var previewImage: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let item = model.selectedItem {
                Text(item.kind.rawValue.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)

                content(for: item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Divider()
                HStack {
                    Text(item.sourceAppName ?? "Unknown source")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: Int64(item.byteSize), countStyle: .file))
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            } else {
                Text("No selection")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // task(id:) cancels and restarts when the selection changes — the
        // image is fetched lazily, never at capture time.
        // Cached images are applied synchronously so revisiting an item does
        // not flash the spinner for a frame.
        .task(id: model.selectedItem?.id) {
            guard let item = model.selectedItem, item.kind == .image else {
                previewImage = nil
                return
            }
            if let cached = model.cachedPreviewImage(for: item) {
                previewImage = cached
                return
            }
            previewImage = nil
            previewImage = await model.previewImage(for: item)
        }
    }

    @ViewBuilder
    private func content(for item: Item) -> some View {
        switch item.kind {
        case .image:
            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(12)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .colour:
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hexString: item.textContent ?? "") ?? .clear)
                    .frame(width: 72, height: 72)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                Text(item.textContent ?? "")
                    .font(.system(size: 13, design: .monospaced))
            }
            .padding(12)
        case .text, .link, .file, .code:
            let preview = (item.textContent ?? item.preview).previewCapped(to: Self.textPreviewLimit)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(preview.text)
                        .font(.system(size: 12, design: item.kind == .code ? .monospaced : .default))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    if preview.isTruncated {
                        Text("Preview truncated — ↵ copies the full item")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
            }
        }
    }
}
