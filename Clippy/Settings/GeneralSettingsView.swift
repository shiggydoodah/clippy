import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(AppSettings.Keys.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(AppSettings.Keys.theme) private var theme = "system"
    @State private var accessibilityGranted = PasteService.isAccessibilityTrusted
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginNeedsApproval = SMAppService.mainApp.status == .requiresApproval

    var body: some View {
        // One Section per option, with an explicit clear row between them —
        // a Settings-scene Form has no row-spacing knob, so the invisible
        // fixed-height rows are what space the option groups apart. Hint
        // captions stay inside the section of the control they explain.
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { applyLaunchAtLogin() }
                if launchAtLoginNeedsApproval {
                    Text("Waiting for approval — allow Clippy in System Settings → General → Login Items.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Color.clear.frame(height: 8)

            Section {
                KeyboardShortcuts.Recorder("Summon panel:", name: .summonPanel)
            }

            Color.clear.frame(height: 8)

            Section {
                Picker("Theme:", selection: $theme) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
            }

            Color.clear.frame(height: 8)

            // Direct paste is a keystroke (⌘↵), not a setting — the only
            // thing this pane manages is the Accessibility permission it
            // depends on.
            Section {
                if accessibilityGranted {
                    Text("In the panel, ↩ copies the selected item and ⌘↩ pastes it straight into the active app.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Grant Accessibility Access…") {
                        PasteService.promptForAccessibilityPermission()
                        accessibilityGranted = PasteService.isAccessibilityTrusted
                    }
                    Text("Direct paste (⌘↩ in the panel) needs Accessibility permission to paste straight into the active app. Until it is granted, ⌘↩ copies like ↩ and you press ⌘V yourself. Grant it here or in System Settings → Privacy & Security → Accessibility.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Color.clear.frame(height: 8)

            Section {
                Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
                if !showMenuBarIcon {
                    Text("With the icon hidden, open Settings by summoning the panel and pressing ⌘,")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .onAppear {
            accessibilityGranted = PasteService.isAccessibilityTrusted
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchAtLoginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
        }
    }

    /// SMAppService is the system framework for this — no package required.
    /// On failure the toggle reverts so the UI never lies about the state.
    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        launchAtLoginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }
}
