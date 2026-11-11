import SwiftUI
import WatchSwiftyCore

struct MoreView: View {
    var body: some View {
        List {
            Section {
                NavigationLink { ServerSettingsView() } label: { Label("Server", systemImage: "server.rack") }
                NavigationLink { AboutView() } label: { Label("Über", systemImage: "info.circle") }
            }
        }
        .navigationTitle("Mehr")
    }
}
