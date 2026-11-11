import SwiftUI
import WatchSwiftyCore

/// „Verwaltung“ (admins only).
struct AdminView: View {
    var body: some View {
        List {
            NavigationLink { UsersView() } label: { Label("Benutzer", systemImage: "person.2") }
            NavigationLink { SystemView() } label: { Label("System", systemImage: "gearshape.2") }
            NavigationLink { OIDCSettingsView() } label: { Label("Anmeldung über SSO", systemImage: "person.badge.key") }
            NavigationLink { MailSettingsView() } label: { Label("Mail", systemImage: "envelope") }
        }
        .navigationTitle("Verwaltung")
    }
}
