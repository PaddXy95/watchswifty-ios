import SwiftUI
import WatchSwiftyClient
import WatchSwiftyCore

/// Konto → Benachrichtigungen: three switches, the channel, the KNot key and a test message (as in the web).
struct NotificationSections: View {
    let store: AccountStore
    let prefs: Components.Schemas.NotificationPrefs
    let editKey: () -> Void
    @State private var removingKey = false
    @State private var password = ""

    var body: some View {
        Section {
            Toggle("Sobald eine neue Folge bekannt wird", isOn: binding(\.announced))
            Toggle("3 Tage vor der Ausstrahlung", isOn: binding(\.soon))
            Toggle("Am Tag der Ausstrahlung", isOn: binding(\.today))
            channel
            if let active = prefs.activeChannel {
                Button {
                    Task { await store.sendTestNotification() }
                } label: {
                    LabeledContent("Testnachricht senden", value: "per \(active.displayName)")
                }
            }
        } header: {
            Text("Benachrichtigungen")
        } footer: {
            Text("Neue Folgen beobachteter Serien. Geprüft wird täglich um \(prefs.dailyRunTime) Uhr; alles Neue kommt in einer Nachricht. Der Hinweis auf neu verbundene Geräte geht immer über denselben Weg.")
        }
        if prefs.webhookConfigured {
            Section {
                LabeledContent("Status", value: prefs.hasWebhookKey ? "Gespeichert" : "Nicht hinterlegt")
                Button(prefs.hasWebhookKey ? "Schlüssel ändern" : "Schlüssel eintragen", action: editKey)
                if prefs.hasWebhookKey {
                    Button("Schlüssel entfernen", role: .destructive) {
                        if store.webhookKeyNeedsPassword {
                            password = ""
                            removingKey = true
                        } else {
                            Task { _ = await store.deleteWebhookKey(currentPassword: "") }
                        }
                    }
                    .alert("Schlüssel entfernen?", isPresented: $removingKey) {
                        SecureField("Aktuelles Passwort", text: $password).textContentType(.password)
                        Button("Entfernen", role: .destructive) {
                            let password = password
                            Task { _ = await store.deleteWebhookKey(currentPassword: password) }
                        }
                        Button("Abbrechen", role: .cancel) {}
                    } message: {
                        Text("Zum Entfernen brauchst du dein aktuelles Passwort.")
                    }
                }
            } header: {
                Text("Webhook-Schlüssel (KNot)")
            } footer: {
                Text("Den Schlüssel bekommst du vom Admin. Er wird nach dem Speichern nicht mehr angezeigt.")
            }
        }
    }

    @ViewBuilder private var channel: some View {
        if prefs.availableChannels.count > 1 {
            Picker("Senden per", selection: Binding(get: { prefs.activeChannel ?? prefs.channel },
                                                    set: { value in Task { await store.updateNotifications { $0.channel = value } } })) {
                ForEach(prefs.availableChannels, id: \.self) { Text($0.displayName).tag($0) }
            }
        } else if let only = prefs.availableChannels.first {
            LabeledContent("Senden per", value: only.displayName)
        } else {
            Text("Noch kein Versandweg: hinterlege eine Mail-Adresse oder einen Webhook-Schlüssel – oder der Admin hat den Versand noch nicht eingerichtet.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<Components.Schemas.NotificationPrefsUpdate, Bool> & Sendable) -> Binding<Bool> {
        Binding(get: { prefs.update[keyPath: keyPath] },
                set: { value in Task { await store.updateNotifications { $0[keyPath: keyPath] = value } } })
    }
}

/// Stores the KNot key; on servers before 0.5.0 accounts with a password confirm with it.
struct WebhookKeySheet: View {
    let store: AccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Webhook-Schlüssel", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } footer: {
                    Text("Den Schlüssel bekommst du vom Admin. Er wird nach dem Speichern nicht mehr angezeigt.")
                }
                if store.webhookKeyNeedsPassword {
                    SecureField("Aktuelles Passwort", text: $password).textContentType(.password)
                }
            }
            .navigationTitle("Webhook-Schlüssel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        Task { if await store.setWebhookKey(key, currentPassword: password) { dismiss() } }
                    }
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || (store.webhookKeyNeedsPassword && password.isEmpty) || store.busy)
                }
            }
        }
    }
}
