import Foundation
import Testing
@testable import Clippy

struct CaptureFilterTests {

    private func capture(
        kind: ItemKind = .text,
        text: String? = "hello",
        byteSize: Int = 5,
        sourceAppID: String? = "com.apple.Safari"
    ) -> CapturedItem {
        CapturedItem(
            kind: kind,
            textContent: text,
            blobData: nil,
            blobFileExtension: nil,
            preview: text ?? "",
            byteSize: byteSize,
            sourceAppID: sourceAppID,
            sourceAppName: nil
        )
    }

    // MARK: - Excluded apps

    @Test func excludedAppIsSkipped() {
        var rules = CaptureFilter.Rules()
        rules.excludedApps = ["com.apple.Safari"]
        #expect(CaptureFilter.skipReason(for: capture(), rules: rules) == .excludedApp)
    }

    @Test func excludedAppMatchIsCaseInsensitive() {
        var rules = CaptureFilter.Rules()
        rules.excludedApps = ["COM.APPLE.SAFARI"]
        #expect(CaptureFilter.skipReason(for: capture(), rules: rules) == .excludedApp)
    }

    @Test func nonExcludedAppPasses() {
        var rules = CaptureFilter.Rules()
        rules.excludedApps = ["com.example.other"]
        #expect(CaptureFilter.skipReason(for: capture(), rules: rules) == nil)
    }

    // MARK: - Password managers

    @Test func passwordManagerSkippedWhenEnabled() {
        let rules = CaptureFilter.Rules() // ignorePasswordManagers defaults true
        let pw = capture(sourceAppID: "com.1password.1password")
        #expect(CaptureFilter.skipReason(for: pw, rules: rules) == .passwordManager)
    }

    @Test func passwordManagerAllowedWhenDisabled() {
        var rules = CaptureFilter.Rules()
        rules.ignorePasswordManagers = false
        let pw = capture(sourceAppID: "com.1password.1password")
        #expect(CaptureFilter.skipReason(for: pw, rules: rules) == nil)
    }

    // MARK: - Size threshold

    @Test func oversizedPayloadIsSkipped() {
        var rules = CaptureFilter.Rules()
        rules.maxItemBytes = 100
        #expect(CaptureFilter.skipReason(for: capture(byteSize: 101), rules: rules) == .tooLarge)
        #expect(CaptureFilter.skipReason(for: capture(byteSize: 100), rules: rules) == nil)
    }

    @Test func zeroThresholdMeansNoLimit() {
        var rules = CaptureFilter.Rules()
        rules.maxItemBytes = 0
        #expect(CaptureFilter.skipReason(for: capture(byteSize: 500_000_000), rules: rules) == nil)
    }

    // MARK: - Excluded extensions (file captures)

    private func fileCapture(paths: [String]) -> CapturedItem {
        capture(kind: .file, text: paths.joined(separator: "\n"), byteSize: 10)
    }

    @Test func excludedExtensionIsSkipped() {
        var rules = CaptureFilter.Rules()
        rules.excludedExtensions = ["pdf"]
        #expect(CaptureFilter.skipReason(for: fileCapture(paths: ["/tmp/doc.pdf"]), rules: rules) == .excludedExtension)
    }

    @Test func extensionEntriesAcceptDotAndAnyCase() {
        var rules = CaptureFilter.Rules()
        rules.excludedExtensions = [".PDF"]
        #expect(CaptureFilter.skipReason(for: fileCapture(paths: ["/tmp/doc.pdf"]), rules: rules) == .excludedExtension)
        #expect(CaptureFilter.skipReason(for: fileCapture(paths: ["/tmp/DOC.PDF"]), rules: rules) == .excludedExtension)
    }

    @Test func anyFileInMultiSelectionTriggersSkip() {
        var rules = CaptureFilter.Rules()
        rules.excludedExtensions = ["key"]
        let mixed = fileCapture(paths: ["/tmp/fine.txt", "/tmp/secret.key"])
        #expect(CaptureFilter.skipReason(for: mixed, rules: rules) == .excludedExtension)
    }

    @Test func extensionRuleIgnoresNonFileKinds() {
        var rules = CaptureFilter.Rules()
        rules.excludedExtensions = ["pdf"]
        let text = capture(text: "see report.pdf for details", byteSize: 10)
        #expect(CaptureFilter.skipReason(for: text, rules: rules) == nil)
    }

    // MARK: - Excluded folders (file captures)

    @Test func fileInsideExcludedFolderIsSkipped() {
        var rules = CaptureFilter.Rules()
        rules.excludedFolders = ["/Users/me/Secrets"]
        #expect(CaptureFilter.skipReason(for: fileCapture(paths: ["/Users/me/Secrets/plan.txt"]), rules: rules) == .excludedFolder)
        #expect(CaptureFilter.skipReason(for: fileCapture(paths: ["/Users/me/Secrets/deep/nested.txt"]), rules: rules) == .excludedFolder)
    }

    @Test func folderMatchRespectsComponentBoundaries() {
        var rules = CaptureFilter.Rules()
        rules.excludedFolders = ["/Users/me/Secrets"]
        // Sibling with a shared prefix must NOT match.
        #expect(CaptureFilter.skipReason(for: fileCapture(paths: ["/Users/me/SecretsBackup/file.txt"]), rules: rules) == nil)
        // The folder itself (no children) is not "inside" the folder.
        #expect(CaptureFilter.skipReason(for: fileCapture(paths: ["/Users/me/Secrets"]), rules: rules) == nil)
    }

    @Test func fileOutsideExcludedFolderPasses() {
        var rules = CaptureFilter.Rules()
        rules.excludedFolders = ["/Users/me/Secrets"]
        #expect(CaptureFilter.skipReason(for: fileCapture(paths: ["/Users/me/Public/file.txt"]), rules: rules) == nil)
    }

    @Test func excludedFolderEntriesExpandTilde() {
        // Users naturally type "~/Secrets" in the settings list — it must
        // match the absolute paths the pasteboard delivers.
        var rules = CaptureFilter.Rules()
        rules.excludedFolders = ["~/ClipTestSecrets"]
        let path = NSHomeDirectory() + "/ClipTestSecrets/file.txt"
        #expect(CaptureFilter.skipReason(for: fileCapture(paths: [path]), rules: rules) == .excludedFolder)
    }

    // MARK: - Clean pass

    @Test func unremarkableCapturePassesAllRules() {
        var rules = CaptureFilter.Rules()
        rules.maxItemBytes = 1_000_000
        rules.excludedExtensions = ["key"]
        rules.excludedFolders = ["/Users/me/Secrets"]
        rules.excludedApps = ["com.example.excluded"]
        #expect(CaptureFilter.skipReason(for: capture(), rules: rules) == nil)
    }
}
