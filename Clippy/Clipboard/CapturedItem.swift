import Foundation

/// A classified pasteboard capture, ready to hand to StorageService.
/// A plain value type so it can cross from the monitor's queue into the
/// storage actor without any shared state.
nonisolated struct CapturedItem: Sendable {
    let kind: ItemKind
    /// Inline content for text-like kinds and file paths; nil for images.
    let textContent: String?
    /// Binary payload destined for the blob store (images).
    let blobData: Data?
    let blobFileExtension: String?
    /// Display string, truncated to 200 characters.
    let preview: String
    let byteSize: Int
    let sourceAppID: String?
    let sourceAppName: String?
}
