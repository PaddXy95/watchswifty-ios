import SwiftUI
import WatchSwiftyClient
import WatchSwiftyCore

struct MailSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var store: MailSettingsStore?

    var body: some View {
        Group {
            if let store { MailContent(store: store) } else { ProgressView() }
        }
        .navigationTitle("Mail")
        .task {
            if store == nil { store = MailSettingsStore(api: model.api, app: model) }
            await store?.load()
        }
    }
}

private struct MailContent: View {
    @Bindable var store: MailSettingsStore
    @State private var form = MailForm()
    @State private var testAddress = ""
    @State private var confirmDelete = false

    var body: some View {
        Form {
            if let settings = store.settings.value {
                if settings.unreadable {
                    Text("Die gespeicherten Einstellungen sind nicht lesbar – bitte neu eintragen.").foregroundStyle(.red)
                }
                Section("SMTP-Server") {
                    TextField("Host", text: $form.host).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Port", text: $form.port).keyboardType(.numberPad)
                    Picker("Verschlüsselung", selection: $form.encryption) {
                        Text("STARTTLS").tag(Components.Schemas.MailEncryption.starttls)
                        Text("SSL/TLS").tag(Components.Schemas.MailEncryption.ssl)
                        Text("Keine").tag(Components.Schemas.MailEncryption.plain)
                    }
                    TextField("Benutzername", text: $form.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField(settings.hasPassword ? "Passwort (gespeichert)" : "Passwort", text: $form.password)
                    TextField("CA-Datei (optional)", text: $form.caFile).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section("Absender") {
                    TextField("Adresse", text: $form.fromAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    TextField("Name (optional)", text: $form.fromName)
                    TextField("Adresse von WatchSwifty", text: $form.baseURL).keyboardType(.URL).textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Button("Speichern") { Task { if await store.save(form) { form.password = "" } } }
                        .disabled(form.host.isEmpty || form.fromAddress.isEmpty || form.baseURL.isEmpty)
                    if settings.configured {
                        Button("Mail-Einstellungen löschen", role: .destructive) { confirmDelete = true }
                    }
                }
                if settings.configured {
                    Section("Testmail") {
                        TextField("Empfänger", text: $testAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                        Button("Testmail senden") { Task { await store.sendTest(to: testAddress) } }
                            .disabled(!testAddress.contains("@"))
                    }
                }
            } else if let error = store.settings.error {
                ErrorView(error: error) { await store.load() }
            }
        }
        .disabled(store.busy)
        .onChange(of: store.settings.value?.host, initial: true) {
            if let settings = store.settings.value { form = MailForm(settings) }
        }
        .confirmationDialog("Mail-Einstellungen löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
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
}
