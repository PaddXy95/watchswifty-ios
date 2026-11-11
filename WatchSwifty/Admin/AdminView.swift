import SwiftUI
import WatchSwiftyCore

/// „Verwaltung“ (admins only).
struct AdminView: View {
    var body: some View {
        List {
            NavigationLink(value: AdminDestination.users) { Label("Benutzer", systemImage: "person.2") }
            NavigationLink(value: AdminDestination.system) { Label("System", systemImage: "gearshape.2") }
            NavigationLink(value: AdminDestination.oidc) { Label("Anmeldung über SSO", systemImage: "person.badge.key") }
            NavigationLink(value: AdminDestination.mail) { Label("Mail", systemImage: "envelope") }
        }
        .navigationTitle("Verwaltung")
        .navigationDestination(for: AdminDestination.self) { destination in
            switch destination {
            case .users: UsersView()
            case .system: SystemView()
            case .oidc: OIDCSettingsView()
            case .mail: MailSettingsView()
            }
        }
    }
}

enum AdminDestination: Hashable {
    case users, system, oidc, mail
}
