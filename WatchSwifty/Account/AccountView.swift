import SwiftUI
import WatchSwiftyClient
import WatchSwiftyCore

struct AccountView: View {
    @Environment(AppModel.self) private var model
    @State private var store: AccountStore?

    var body: some View {
        Group {
            if let store { AccountContent(store: store) } else { ListSkeleton() }
        }
        .navigationTitle("Konto")
        .task {
            if store == nil { store = AccountStore(api: model.api, app: model) }
            await store?.load()
        }
    }
}

private struct AccountContent: View {
    @Bindable var store: AccountStore
    @Environment(\.openURL) private var openURL
    @State private var sheet: AccountSheet?

    var body: some View {
        List {
            if let me = store.me {
                Section {
                    LabeledContent("Benutzername", value: me.username)
                    if me.ssoLinked { Label("Mit SSO verknüpft", systemImage: "person.badge.key") }
                }
                if store.canChangePassword {
                    Section { Button("Passwort ändern") { sheet = .password } }
                }
                Section("E-Mail") {
                    LabeledContent("Adresse", value: me.email ?? "Keine")
                    Button(me.email == nil ? "Hinzufügen" : "Ändern") { sheet = .email }
                }
                Section {
                    LabeledContent("Status", value: tmdbState(me.tmdbToken))
                    Button(me.tmdbToken.state == .none ? "Token eintragen" : "Token ändern") { sheet = .tmdb }
                    if me.tmdbToken.state != .none {
                        Button("Token entfernen", role: .destructive) { Task { await store.deleteTMDBToken() } }
                    }
                } header: {
                    Text("TMDB-Token")
                } footer: {
                    Text("Dein eigener TMDB-Lesezugriffstoken für Suche und Titeldaten.")
                }
            }
            if let prefs = store.notifications.value {
                NotificationSections(store: store, prefs: prefs) { sheet = .webhookKey }
            }
            Section {
                NavigationLink("Geräte", value: AccountDestination.devices)
                NavigationLink("Beobachtete Serien", value: AccountDestination.followed)
            }
            if let url = store.webAccountURL {
                Section {
                    Button("Token für Skripte erstellen") { openURL(url) }
                    if store.me?.ssoLinked == false { Button("Mit SSO verknüpfen") { openURL(url) } }
                } header: {
                    Text("Im Browser")
                } footer: {
                    Text("Diese Schritte laufen über die Weboberfläche, weil sie eine Anmeldung im Browser brauchen.")
                }
            }
        }
        .disabled(store.busy)
        .refreshable { await store.load() }
        .navigationDestination(for: AccountDestination.self) { destination in
            switch destination {
            case .devices: DevicesView(store: store)
            case .followed: FollowedView(store: store)
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .password: PasswordSheet(store: store)
            case .email: EmailSheet(store: store)
            case .tmdb: TMDBTokenSheet(store: store, onSaved: {})
            case .webhookKey: WebhookKeySheet(store: store)
            }
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

    private func tmdbState(_ state: Components.Schemas.TMDBTokenState) -> String {
        switch state.state {
        case .none: "Nicht hinterlegt"
        case .stored: "Hinterlegt \(state.suffix ?? "")"
        case .unreadable: "Nicht lesbar – bitte neu eintragen"
        }
    }
}

enum AccountDestination: Hashable {
    case devices, followed
}

private enum AccountSheet: Identifiable {
    case password, email, tmdb, webhookKey
    var id: Self { self }
}

private struct PasswordSheet: View {
    let store: AccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var repeated = ""

    private var problem: String? {
        if new.count < 8 { return "Mindestens 8 Zeichen." }
        if new != repeated { return "Die Passwörter stimmen nicht überein." }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                SecureField("Aktuelles Passwort", text: $current).textContentType(.password)
                Section {
                    SecureField("Neues Passwort", text: $new).textContentType(.newPassword)
                    SecureField("Wiederholen", text: $repeated).textContentType(.newPassword)
                } footer: {
                    if !new.isEmpty, let problem { Text(problem) }
                }
            }
            .navigationTitle("Passwort ändern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        Task { if await store.changePassword(current: current, new: new) { dismiss() } }
                    }
                    .disabled(current.isEmpty || problem != nil)
                }
            }
        }
    }
}

private struct EmailSheet: View {
    let store: AccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("E-Mail-Adresse", text: $email)
                        .keyboardType(.emailAddress).textContentType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } footer: {
                    Text("Leer lassen, um die Adresse zu entfernen.")
                }
                SecureField("Aktuelles Passwort", text: $password).textContentType(.password)
            }
            .navigationTitle("E-Mail")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { email = store.me?.email ?? "" }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        Task { if await store.setEmail(email.trimmingCharacters(in: .whitespaces), currentPassword: password) { dismiss() } }
                    }
                }
            }
        }
    }
}

struct TMDBTokenSheet: View {
    let store: AccountStore
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("API-Lesezugriffstoken", text: $token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } footer: {
                    Text("Zu finden in deinem TMDB-Konto unter Einstellungen → API. Der Server prüft ihn bei TMDB.")
                }
            }
            .navigationTitle("TMDB-Token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        Task {
                            if await store.setTMDBToken(token.trimmingCharacters(in: .whitespacesAndNewlines)) {
                                onSaved()
                                dismiss()
                            }
                        }
                    }
                    .disabled(token.isEmpty || store.busy)
                }
            }
        }
    }
}

private struct DevicesView: View {
    let store: AccountStore
    @State private var revoking: Components.Schemas.Device?

    var body: some View {
        List(store.devices.value ?? [], id: \.id) { device in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(device.name)
                    if store.isCurrent(device) { Text("Dieses Gerät").font(.caption).foregroundStyle(.tint) }
                }
                Text([device.kind == .manual ? "manuell erstellt" : nil,
                      "seit \(device.createdAt.formatted(date: .numeric, time: .omitted))",
                      device.lastUsedAt.map { "zuletzt \($0.formatted(date: .numeric, time: .omitted))" }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .swipeActions { Button("Abmelden", role: .destructive) { revoking = device } }
        }
        .navigationTitle("Geräte")
        .confirmationDialog("Gerät abmelden?", isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }),
                            titleVisibility: .visible, presenting: revoking) { device in
            Button("Abmelden", role: .destructive) { Task { await store.revokeDevice(id: device.id) } }
        } message: { device in
            Text(store.isCurrent(device) ? "Das ist dieses Gerät – danach ist eine neue Anmeldung nötig." : device.name)
        }
    }
}

private struct FollowedView: View {
    let store: AccountStore

    var body: some View {
        List(store.followed.value ?? [], id: \.tmdbId) { series in
            NavigationLink(series.name, value: Route.series(series.tmdbId))
        }
        .overlay {
            if store.followed.value?.isEmpty == true {
                ContentUnavailableView("Keine beobachteten Serien", systemImage: "bell.slash")
            }
        }
        .navigationTitle("Beobachtete Serien")
    }
}
