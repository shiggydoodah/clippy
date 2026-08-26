import Foundation

/// Content-addressed payload storage: `blobs/<hash-prefix>/<hash>.<ext>`.
/// With a nil root the store is purely in-memory — ephemeral mode must never
/// touch disk.
///
/// Deliberately not Sendable: owned by the StorageService actor, which
/// serialises all access. Nothing else may hold a reference.
nonisolated final class BlobStore {
    private let rootURL: URL?
    private var memoryStore: [String: Data] = [:]

    init(rootURL: URL?) {
        self.rootURL = rootURL
    }

    /// Writes the payload and returns the relative path it lives under.
    /// The two-character prefix directory keeps any one folder from
    /// accumulating thousands of entries.
    func write(_ data: Data, contentHash: String, fileExtension: String) throws -> String {
        let relativePath = "\(contentHash.prefix(2))/\(contentHash).\(fileExtension)"
        guard let rootURL else {
            memoryStore[relativePath] = data
            return relativePath
        }
        let fileURL = rootURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Default user-only permissions are inherited — never loosened.
        try data.write(to: fileURL, options: .atomic)
        return relativePath
    }

    /// Every stored blob's relative path — the orphan sweep compares these
    /// against live contentHashes.
    func allRelativePaths() -> [String] {
        guard let rootURL else { return Array(memoryStore.keys) }
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [] }
        var paths: [String] = []
        for case let url as URL in enumerator where url.hasDirectoryPath == false {
            let prefixDir = url.deletingLastPathComponent().lastPathComponent
            paths.append("\(prefixDir)/\(url.lastPathComponent)")
        }
        return paths
    }

    func delete(relativePath: String) throws {
        guard let rootURL else {
            memoryStore[relativePath] = nil
            return
        }
        try FileManager.default.removeItem(at: rootURL.appendingPathComponent(relativePath))
    }

    func read(relativePath: String) throws -> Data {
        guard let rootURL else {
            guard let data = memoryStore[relativePath] else {
                throw StorageError.blobNotFound(relativePath)
            }
            return data
        }
        let fileURL = rootURL.appendingPathComponent(relativePath)
        guard let data = FileManager.default.contents(atPath: fileURL.path) else {
            throw StorageError.blobNotFound(relativePath)
        }
        return data
    }
}
