import Foundation

nonisolated enum StorageError: Error {
    /// The capture carried no hashable payload (empty text, no data).
    case emptyCapture
    /// A blob was expected at this relative path but could not be read.
    case blobNotFound(String)
    /// The item has no blob payload (its content is inline).
    case itemHasNoBlob
}
