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
                NavigationLink { StatsView() } label: { Label("Statistik", systemImage: "chart.bar") }
                NavigationLink { AccountView() } label: { Label("Konto", systemImage: "person.crop.circle") }
            }
            Section {
                NavigationLink { ServerSettingsView() } label: { Label("Server", systemImage: "server.rack") }
                NavigationLink { AboutView() } label: { Label("Über", systemImage: "info.circle") }
            }
        }
        .navigationTitle("Mehr")
        .alert("Das hat nicht geklappt", isPresented: Binding(get: { renewError != nil }, set: { if !$0 { renewError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(renewError?.message ?? "")
        }
    }
}
