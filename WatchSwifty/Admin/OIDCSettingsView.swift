import SwiftUI
import WatchSwiftyClient
import WatchSwiftyCore

struct OIDCSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var store: OIDCSettingsStore?

    var body: some View {
        Group {
            if let store { OIDCContent(store: store) } else { ProgressView() }
        }
        .navigationTitle("Anmeldung über SSO")
        .task {
            if store == nil { store = OIDCSettingsStore(api: model.api, app: model) }
            await store?.load()
        }
    }
}

private struct OIDCContent: View {
    @Bindable var store: OIDCSettingsStore
    @State private var displayName = ""
    @State private var issuer = ""
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var baseURL = ""
    @State private var confirmDelete = false

    var body: some View {
        Form {
            if let settings = store.settings.value {
                if settings.unreadable {
                    Text("Die gespeicherten Einstellungen sind mit dem Server-Schlüssel nicht lesbar – SSO ist aus. Bitte neu eintragen.")
                        .foregroundStyle(.red)
                }
                Section {
                    TextField("Anzeigename (z. B. Authentik)", text: $displayName)
                    TextField("Issuer-URL", text: $issuer).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Client-ID", text: $clientID).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField(settings.hasClientSecret ? "Client-Secret (gespeichert)" : "Client-Secret", text: $clientSecret)
                    TextField("Adresse von WatchSwifty", text: $baseURL).keyboardType(.URL).textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Provider")
                } footer: {
                    if let redirect = settings.redirectUrl {
                        Text("Rücksprung-URL beim Provider: \(redirect)").textSelection(.enabled)
                    }
                }
                Section {
                    Button("Speichern") {
                        Task {
                            if await store.save(displayName: displayName, issuer: issuer, clientID: clientID,
                                                clientSecret: clientSecret, baseURL: baseURL) { clientSecret = "" }
                        }
                    }
                    .disabled(issuer.isEmpty || clientID.isEmpty || baseURL.isEmpty)
                    if settings.configured {
                        Button("Verbindung testen") { Task { await store.test() } }
                        Button("SSO-Einstellungen löschen", role: .destructive) { confirmDelete = true }
                    }
                }
                if settings.configured {
                    Section {
                        Toggle("Anmeldung mit Passwort erlauben",
                               isOn: Binding(get: { settings.passwordLoginStored ?? settings.passwordLogin },
                                             set: { value in Task { await store.setPasswordLogin(value) } }))
                    } footer: {
                        if settings.passwordLoginForced {
                            Text("Der Passwort-Login ist per PASSWORD_LOGIN=true erzwungen (Notschalter). Der Schalter gilt wieder, sobald er entfernt ist.")
                        }
                    }
                }
            } else if let error = store.settings.error {
                ErrorView(error: error) { await store.load() }
            }
        }
        .disabled(store.busy)
        .onChange(of: store.settings.value?.issuer, initial: true) { fill() }
        .confirmationDialog("SSO-Einstellungen löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { Task { await store.delete() } }
        }
        .alert("Das hat nicht geklappt", isPresented: Binding(get: { store.actionError != nil },
                                                                set: { if !$0 { store.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.actionError?.message ?? "")
        }
        .alert(store.notice ?? "", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private func fill() {
        guard let settings = store.settings.value else { return }
        displayName = settings.displayName ?? ""
        issuer = settings.issuer ?? ""
        clientID = settings.clientId ?? ""
        baseURL = settings.baseUrl ?? ""
    }
}
