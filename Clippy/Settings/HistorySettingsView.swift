import SwiftUI

struct HistorySettingsView: View {
    @AppStorage(AppSettings.Keys.historyEnabled) private var historyEnabled = true
    @AppStorage(AppSettings.Keys.maxItems) private var maxItems = 500
    @AppStorage(AppSettings.Keys.maxAgeSeconds) private var maxAgeSeconds = 0
    @AppStorage(AppSettings.Keys.persistAcrossRestart) private var persistAcrossRestart = true

    var body: some View {
        Form {
            Section {
                Toggle("Enable clipboard history", isOn: $historyEnabled)
            }

            Color.clear.frame(height: 8)

            Section {
                Picker("Maximum items:", selection: $maxItems) {
                    Text("50").tag(50)
                    Text("100").tag(100)
                    Text("500").tag(500)
                    Text("1000").tag(1000)
                    Text("Unlimited").tag(0)
                }
            }

            Color.clear.frame(height: 8)

            Section {
                Picker("Keep history for:", selection: $maxAgeSeconds) {
                    Text("1 hour").tag(3600)
                    Text("8 hours").tag(28_800)
                    Text("24 hours").tag(86_400)
                    Text("7 days").tag(604_800)
                    Text("30 days").tag(2_592_000)
                    Text("Forever").tag(0)
                }
            }

            Color.clear.frame(height: 8)

            Section {
                Toggle("Remember history after restart", isOn: $persistAcrossRestart)
                Text("Takes effect the next time Clippy starts. When off, history lives only in memory — favourites are always kept.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }
}
