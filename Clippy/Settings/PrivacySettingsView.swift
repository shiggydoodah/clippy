import SwiftUI

struct PrivacySettingsView: View {
    @AppStorage(AppSettings.Keys.ignorePasswordManagers) private var ignorePasswordManagers = true
    @AppStorage(AppSettings.Keys.maxItemBytes) private var maxItemBytes = 10_000_000

    var body: some View {
        Form {
            Section {
                Toggle("Ignore password managers", isOn: $ignorePasswordManagers)
                Text("Copies marked confidential by any app are always skipped, regardless of this setting.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Color.clear.frame(height: 8)

            Section {
                Picker("Skip items larger than:", selection: $maxItemBytes) {
                    Text("1 MB").tag(1_000_000)
                    Text("5 MB").tag(5_000_000)
                    Text("10 MB").tag(10_000_000)
                    Text("50 MB").tag(50_000_000)
                    Text("No limit").tag(0)
                }
            }

            Color.clear.frame(height: 8)

            Section {
                EditableListView(
                    title: "Excluded file extensions",
                    placeholder: "pdf",
                    get: { AppSettings.excludedExtensions },
                    set: { AppSettings.excludedExtensions = $0 }
                )
            }

            Color.clear.frame(height: 8)

            Section {
                EditableListView(
                    title: "Excluded folders",
                    placeholder: "/Users/you/Secrets",
                    get: { AppSettings.excludedFolders },
                    set: { AppSettings.excludedFolders = $0 }
                )
            }

            Color.clear.frame(height: 8)

            Section {
                EditableListView(
                    title: "Excluded apps (bundle identifiers)",
                    placeholder: "com.example.app",
                    get: { AppSettings.excludedApps },
                    set: { AppSettings.excludedApps = $0 }
                )
            }
        }
        .padding(16)
    }
}
