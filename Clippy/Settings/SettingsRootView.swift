import SwiftUI

struct SettingsRootView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            HistorySettingsView()
                .tabItem { Label("History", systemImage: "clock") }
            PrivacySettingsView()
                .tabItem { Label("Privacy & Filters", systemImage: "hand.raised") }
            FavouritesSettingsView()
                .tabItem { Label("Favourites", systemImage: "star") }
            DangerZoneSettingsView()
                .tabItem { Label("Danger Zone", systemImage: "exclamationmark.triangle") }
        }
        .frame(width: 500)
    }
}
