import Foundation

/// The privacy & filter rules, applied to a classified capture just
/// before storage. Pure logic over a value snapshot of the settings, so every
/// rule is unit-testable without a pasteboard or UserDefaults.
///
/// Note: the concealed-type check is NOT here — it lives earlier in
/// ClipboardMonitor, is unconditional, and must stay that way.
nonisolated enum CaptureFilter {

    struct Rules {
        var ignorePasswordManagers = true
        /// 0 means no limit.
        var maxItemBytes = 0
        var excludedExtensions: [String] = []
        var excludedFolders: [String] = []
        var excludedApps: [String] = []

        /// Snapshot of the live settings, taken per capture.
        static func current() -> Rules {
            Rules(
                ignorePasswordManagers: AppSettings.ignorePasswordManagers,
                maxItemBytes: AppSettings.maxItemBytes,
                excludedExtensions: AppSettings.excludedExtensions,
                excludedFolders: AppSettings.excludedFolders,
                excludedApps: AppSettings.excludedApps
            )
        }
    }

    enum SkipReason: String {
        case excludedApp
        case passwordManager
        case tooLarge
        case excludedExtension
        case excludedFolder
    }

    /// Password managers that mark copies with concealed types are caught by
    /// the unconditional §7 gate; this list backstops the ones that do not,
    /// keyed by bundle identifier.
    static let knownPasswordManagerBundleIDs: Set<String> = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "org.keepassxc.keepassxc",
        "com.dashlane.Dashlane",
        "com.lastpass.LastPass",
        "com.mseven.msecure",
        "in.sinew.Enpass-Desktop",
    ]

    /// nil means "store it". The reason is for logging — content never
    /// appears in logs.
    static func skipReason(for capture: CapturedItem, rules: Rules) -> SkipReason? {
        if let appID = capture.sourceAppID {
            if rules.excludedApps.contains(where: { $0.caseInsensitiveCompare(appID) == .orderedSame }) {
                return .excludedApp
            }
            if rules.ignorePasswordManagers,
               knownPasswordManagerBundleIDs.contains(where: { $0.caseInsensitiveCompare(appID) == .orderedSame }) {
                return .passwordManager
            }
        }

        // Size applies to the payload we would store. File captures are path
        // references (byteSize is the path string), so they are effectively
        // exempt — a v1 limitation, accepted because references cost nothing
        // to store and checking a copied folder's true size is expensive.
        if rules.maxItemBytes > 0, capture.byteSize > rules.maxItemBytes {
            return .tooLarge
        }

        if capture.kind == .file {
            let paths = (capture.textContent ?? "").split(separator: "\n").map(String.init)
            if !rules.excludedExtensions.isEmpty {
                let excluded = Set(rules.excludedExtensions.map(Self.normalisedExtension))
                for path in paths {
                    let ext = (path as NSString).pathExtension.lowercased()
                    if !ext.isEmpty, excluded.contains(ext) {
                        return .excludedExtension
                    }
                }
            }
            for path in paths {
                for folder in rules.excludedFolders where isPath(path, inside: folder) {
                    return .excludedFolder
                }
            }
        }

        return nil
    }

    /// Accepts entries written as "pdf", ".pdf", or "PDF".
    private static func normalisedExtension(_ entry: String) -> String {
        entry.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }

    /// Component-boundary prefix match: /a/Secret excludes /a/Secret/f.txt
    /// but not /a/SecretStuff.txt.
    private static func isPath(_ path: String, inside folder: String) -> Bool {
        let folderComponents = (folder as NSString).expandingTildeInPath
            .split(separator: "/").map(String.init)
        let pathComponents = (path as NSString).expandingTildeInPath
            .split(separator: "/").map(String.init)
        guard !folderComponents.isEmpty, pathComponents.count > folderComponents.count else { return false }
        return Array(pathComponents.prefix(folderComponents.count)) == folderComponents
    }
}
