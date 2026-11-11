import SwiftUI
import WatchSwiftyCore

struct MoreView: View {
    @Environment(AppModel.self) private var model
    @State private var renewError: UserFacingError?

    var body: some View {
        List {
            if model.tokenExpiresSoon(), let token = model.token {
                Section {
                    Label("Verbindung läuft am \(token.expiresAt.formatted(date: .numeric, time: .omitted)) ab",
                          systemImage: "exclamationmark.circle")
                    Button("Jetzt erneuern") {
                        Task {
                            let store = AccountStore(api: model.api, app: model)
                            await store.renewConnection(using: ASWebAuthenticator())
                            renewError = store.actionError
                        }
                    }
                }
            }
            Section {
                NavigationLink(value: MoreDestination.stats) { Label("Statistik", systemImage: "chart.bar") }
                NavigationLink(value: MoreDestination.imports) { Label("Importe", systemImage: "square.and.arrow.down") }
                NavigationLink(value: MoreDestination.account) { Label("Konto", systemImage: "person.crop.circle") }
                if model.me?.isAdmin == true {
                    NavigationLink(value: MoreDestination.admin) { Label("Verwaltung", systemImage: "wrench.and.screwdriver") }
                }
            }
            Section {
                NavigationLink(value: MoreDestination.server) { Label("Server", systemImage: "server.rack") }
                NavigationLink(value: MoreDestination.about) { Label("Über", systemImage: "info.circle") }
            }
        }
        .navigationTitle("Mehr")
        .navigationDestination(for: MoreDestination.self) { destination in
            switch destination {
            case .stats: StatsView()
            case .imports: ImportsView()
            case .account: AccountView()
            case .admin: AdminView()
            case .server: ServerSettingsView()
            case .about: AboutView()
            }
        }
        .alert("Das hat nicht geklappt", isPresented: Binding(get: { renewError != nil }, set: { if !$0 { renewError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(renewError?.message ?? "")
        }
    }
}

/// Screens behind „Mehr“. Pushed by value like `Route`: a view-destination link in the same stack makes SwiftUI push
/// and pop in a loop once a value link follows it (`NavigationStyleTests`).
enum MoreDestination: Hashable {
    case stats, imports, account, admin, server, about
}
