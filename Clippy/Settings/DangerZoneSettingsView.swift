import KeyboardShortcuts
import SwiftUI

/// Every destructive action confirms first — no exceptions.
struct DangerZoneSettingsView: View {
    @State private var confirmingClearHistory = false
    @State private var confirmingClearFavourites = false
    @State private var confirmingReset = false

    private var storage: StorageService? {
        (NSApp.delegate as? AppDelegate)?.storageService
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Clear history") {
                    Button("Clear History…", role: .destructive) {
                        confirmingClearHistory = true
                    }
                }
                Text("Removes every non-favourite item. Favourites are kept.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Color.clear.frame(height: 8)

            Section {
                LabeledContent("Clear favourites") {
                    Button("Clear Favourites…", role: .destructive) {
                        confirmingClearFavourites = true
                    }
                }
            }

            Color.clear.frame(height: 8)

            Section {
                LabeledContent("Reset settings") {
                    Button("Reset All Settings…", role: .destructive) {
                        confirmingReset = true
                    }
                }
                Text("Returns every setting to its default. Clipboard history is not touched.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .confirmationDialog(
            "Clear all history?",
            isPresented: $confirmingClearHistory,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                Task { try? await storage?.clearHistory() }
            }
        } message: {
            Text("Every non-favourite item will be deleted. This cannot be undone.")
        }
        .confirmationDialog(
            "Clear all favourites?",
            isPresented: $confirmingClearFavourites,
            titleVisibility: .visible
        ) {
            Button("Clear Favourites", role: .destructive) {
                Task { try? await storage?.clearFavourites() }
            }
        } message: {
            Text("Every favourite will be deleted, including renamed ones. This cannot be undone.")
        }
        .confirmationDialog(
            "Reset all settings?",
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button("Reset Settings", role: .destructive) {
                AppSettings.resetAll()
                // The summon hotkey lives in KeyboardShortcuts' own storage,
                // not AppSettings — reset it too so "all" means all.
                KeyboardShortcuts.reset(.summonPanel)
            }
        } message: {
            Text("All settings return to their defaults. History and favourites are not affected.")
        }
    }
}
