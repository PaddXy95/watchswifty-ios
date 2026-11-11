import SwiftUI
import WatchSwiftyCore

struct MoreView: View {
    var body: some View {
        List {
            Section {
                NavigationLink { StatsView() } label: { Label("Statistik", systemImage: "chart.bar") }
            }
            Section {
                NavigationLink { ServerSettingsView() } label: { Label("Server", systemImage: "server.rack") }
                NavigationLink { AboutView() } label: { Label("Über", systemImage: "info.circle") }
            }
        }
        .navigationTitle("Mehr")
    }
}
