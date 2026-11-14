import SwiftUI
import WatchSwiftyClient
import WatchSwiftyCore

struct UsersView: View {
    @Environment(AppModel.self) private var model
    @State private var store: AdminUsersStore?

    var body: some View {
        Group {
            if let store { UsersContent(store: store) } else { ListSkeleton(rows: 4) }
        }
        .navigationTitle("Benutzer")
        .task {
            if store == nil { store = AdminUsersStore(api: model.api, app: model) }
            await store?.load()
        }
    }
}

private struct UsersContent: View {
    @Bindable var store: AdminUsersStore
    @State private var creating = false
    @State private var passwordFor: Components.Schemas.UserSummary?
    @State private var deleting: Components.Schemas.UserSummary?
    @State private var confirming: ConfirmedAction?
    @State private var confirmPassword = ""

    var body: some View {
        if store.users.value == nil, store.users.error == nil {
            ListSkeleton(rows: 4)
        } else {
            userList
        }
    }

    private var userList: some View {
        List(store.users.value ?? [], id: \.id) { user in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(user.username).font(.headline)
                    if user.isAdmin { Text("Admin").font(.caption).foregroundStyle(.tint) }
                    if store.isSelf(user) { Text("Du").font(.caption).foregroundStyle(.secondary) }
                }
                let info = details(user)
                if !info.isEmpty { Text(info).font(.caption).foregroundStyle(.secondary) }
            }
            .contextMenu {
                if !store.isSelf(user) {
                    if user.invitePending {
                        Button("Einladung erneut senden", systemImage: "envelope") { Task { await store.resendInvite(id: user.id) } }
                    }
                    Button("Passwort setzen …", systemImage: "key") { passwordFor = user }
                    if !user.ssoLinked {
                        Button("SSO-Verknüpfungslink", systemImage: "link") { start(.ssoLink(user), asking: user.isAdmin) }
                    }
                    if user.isAdmin {
                        Button("Admin-Recht entziehen", systemImage: "crown") {
                            Task { await store.setAdmin(id: user.id, isAdmin: false) }
                        }
                    } else {
                        Button("Zum Admin machen", systemImage: "crown") { start(.grantAdmin(user), asking: true) }
                    }
                    Button("Löschen", systemImage: "trash", role: .destructive) { deleting = user }
                }
            }
            .swipeActions {
                if !store.isSelf(user) { Button("Löschen", role: .destructive) { deleting = user } }
            }
        }
        .disabled(store.busy)
        .refreshable { await store.load() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Benutzer anlegen", systemImage: "plus") { creating = true }
            }
        }
        .sheet(isPresented: $creating) { NewUserSheet(store: store) }
        .sheet(item: $passwordFor) { user in SetPasswordSheet(store: store, user: user) }
        .sheet(isPresented: Binding(get: { store.oneTimeLink != nil }, set: { if !$0 { store.dismissOneTimeLink() } })) {
            OneTimeLinkSheet(link: store.oneTimeLink ?? "")
        }
        .confirmationDialog("Benutzer löschen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { user in
            Button("Löschen", role: .destructive) { Task { await store.delete(id: user.id) } }
        } message: { user in
            Text("„\(user.username)“ und alle seine Daten werden gelöscht.")
        }
        .alert("Bestätige, dass du es bist", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
               presenting: confirming) { action in
            SecureField("Dein Passwort", text: $confirmPassword).textContentType(.password)
            Button("Bestätigen") {
                let password = confirmPassword
                Task { await run(action, currentPassword: password) }
            }
            .disabled(confirmPassword.isEmpty)
            Button("Abbrechen", role: .cancel) { store.confirmationNeeded = nil }
        } message: { action in
            Text(store.confirmationNeeded ?? action.prompt)
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

    /// Asks for the own password first when the change needs it and the account has one; otherwise runs it right
    /// away (the server then says what is missing).
    private func start(_ action: ConfirmedAction, asking: Bool) {
        if asking, store.confirmsWithPassword {
            ask(action)
        } else {
            Task { await run(action, currentPassword: nil) }
        }
    }

    private func run(_ action: ConfirmedAction, currentPassword: String?) async {
        switch action {
        case .grantAdmin(let user): await store.setAdmin(id: user.id, isAdmin: true, currentPassword: currentPassword)
        case .ssoLink(let user): await store.createSSOLink(id: user.id, currentPassword: currentPassword)
        }
        // Missing or wrong password: ask (again), with the server's message.
        if store.confirmationNeeded != nil { ask(action) }
    }

    private func ask(_ action: ConfirmedAction) {
        confirmPassword = ""
        confirming = action
    }

    private func details(_ user: Components.Schemas.UserSummary) -> String {
        [user.emailHint,
         user.invitePending ? "Einladung offen" : nil,
         user.ssoLinked ? "SSO" : nil,
         user.hasTMDBToken ? nil : "ohne TMDB-Token"]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

extension Components.Schemas.UserSummary: @retroactive Identifiable {}

/// A change from the list that needs the own current password (security confirmation).
private enum ConfirmedAction {
    case grantAdmin(Components.Schemas.UserSummary)
    case ssoLink(Components.Schemas.UserSummary)

    var prompt: String {
        switch self {
        case .grantAdmin(let user): "Admin-Rechte für „\(user.username)“ vergibst du mit deinem aktuellen Passwort."
        case .ssoLink(let user): "„\(user.username)“ ist Admin. Den Verknüpfungslink gibt es nur mit deinem aktuellen Passwort."
        }
    }
}

/// The own current password inside a sheet, for changes that grant or reach admin rights. Shows the server's
/// message after a missing or wrong password.
private struct ConfirmationSection: View {
    @Binding var password: String
    let hint: String
    let problem: String?

    var body: some View {
        Section {
            SecureField("Dein aktuelles Passwort", text: $password).textContentType(.password)
        } header: {
            Text("Bestätigung")
        } footer: {
            if let problem { Text(problem).foregroundStyle(.red) } else { Text(hint) }
        }
    }
}

private struct NewUserSheet: View {
    let store: AdminUsersStore
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var invite = true
    @State private var email = ""
    @State private var password = ""
    @State private var isAdmin = false
    @State private var currentPassword = ""

    /// An admin account needs the own password (or, without one, a confirmation in the browser).
    private var asksPassword: Bool { isAdmin && (store.confirmsWithPassword || store.confirmationNeeded != nil) }

    private var valid: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && (invite ? email.contains("@") : password.count >= 8)
            && (!asksPassword || !currentPassword.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Benutzername", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker("Zugang", selection: $invite) {
                    Text("Einladung per Mail").tag(true)
                    Text("Passwort festlegen").tag(false)
                }
                .pickerStyle(.segmented)
                if invite {
                    TextField("E-Mail-Adresse", text: $email)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                } else {
                    SecureField("Passwort (mind. 8 Zeichen)", text: $password).textContentType(.newPassword)
                }
                Toggle("Admin", isOn: $isAdmin)
                if asksPassword {
                    ConfirmationSection(password: $currentPassword,
                                        hint: "Admin-Rechte vergibst du mit deinem aktuellen Passwort.",
                                        problem: store.confirmationNeeded)
                }
            }
            .navigationTitle("Benutzer anlegen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") {
                        Task {
                            if await store.create(username: username.trimmingCharacters(in: .whitespaces),
                                                  password: invite ? nil : password,
                                                  email: invite ? email.trimmingCharacters(in: .whitespaces) : nil,
                                                  isAdmin: isAdmin, currentPassword: asksPassword ? currentPassword : nil) {
                                dismiss()
                            } else if store.confirmationNeeded != nil {
                                currentPassword = ""
                            }
                        }
                    }
                    .disabled(!valid)
                }
            }
        }
        .onDisappear { store.confirmationNeeded = nil }
    }
}

private struct SetPasswordSheet: View {
    let store: AdminUsersStore
    let user: Components.Schemas.UserSummary
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var currentPassword = ""

    /// Another admin's password needs the own one; also when the server asks for it (the list was out of date).
    private var asksPassword: Bool { (user.isAdmin && store.confirmsWithPassword) || store.confirmationNeeded != nil }

    var body: some View {
        NavigationStack {
            Form {
                SecureField("Neues Passwort (mind. 8 Zeichen)", text: $password).textContentType(.newPassword)
                if asksPassword {
                    ConfirmationSection(password: $currentPassword,
                                        hint: "„\(user.username)“ ist Admin. Bestätige mit deinem aktuellen Passwort.",
                                        problem: store.confirmationNeeded)
                }
            }
            .navigationTitle(user.username)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        Task {
                            if await store.resetPassword(id: user.id, password: password,
                                                         currentPassword: asksPassword ? currentPassword : nil) {
                                dismiss()
                            } else if store.confirmationNeeded != nil {
                                currentPassword = ""
                            }
                        }
                    }
                    .disabled(password.count < 8 || (asksPassword && currentPassword.isEmpty))
                }
            }
        }
        .presentationDetents([.medium])
        .onDisappear { store.confirmationNeeded = nil }
    }
}

/// A link that the server shows only once: copy or share it now.
struct OneTimeLinkSheet: View {
    let link: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(link).font(.callout.monospaced()).textSelection(.enabled)
                } footer: {
                    Text("Dieser Link wird nur jetzt angezeigt.")
                }
                Section {
                    Button("Kopieren", systemImage: "doc.on.doc") { UIPasteboard.general.string = link }
                    if let url = URL(string: link) { ShareLink("Teilen", item: url) }
                }
            }
            .navigationTitle("Verknüpfungslink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
    }
}
