import Foundation

/// Where the SwiftUI Settings scene finds the storage service.
///
/// The panel, the clipboard monitor and the retention engine are all
/// constructor-injected by AppDelegate. The Settings scene cannot be:
/// SwiftUI builds it from ClipApp's `Settings { }` and gives its views no
/// injection point. They used to reach the service through
/// `NSApp.delegate as? AppDelegate`, which never succeeds — SwiftUI's
/// delegate adaptor puts its own forwarding object in `NSApp.delegate`, not
/// our delegate — so every storage-backed control in Settings silently did
/// nothing. A registry set once at launch is the boring way to bridge that.
@MainActor
enum AppServices {
    private(set) static var storage: StorageService?

    static func register(storage: StorageService?) {
        Self.storage = storage
    }
}
