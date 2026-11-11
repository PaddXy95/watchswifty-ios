import SwiftUI
import WatchSwiftyClient
import WatchSwiftyCore

struct SystemView: View {
    @Environment(AppModel.self) private var model
    @State private var store: SystemStore?

    var body: some View {
        Group {
            if let store { SystemContent(store: store) } else { ListSkeleton(rows: 5) }
        }
        .navigationTitle("System")
        .task {
            if store == nil { store = SystemStore(api: model.api, app: model) }
            await store?.load()
        }
    }
}

private struct SystemContent: View {
    @Bindable var store: SystemStore

    var body: some View {
        List {
            if let system = store.system.value {
                Section("Version") {
                    LabeledContent("Server", value: system.version.version)
                    if let commit = system.version.commit { LabeledContent("Commit", value: String(commit.prefix(7))) }
                }
                Section {
                    Toggle("Nach Updates suchen", isOn: Binding(get: { system.updateCheck.enabled },
                                                               set: { value in Task { await store.setUpdateCheck(value) } }))
                    if let latest = system.updateCheck.latestVersion {
                        LabeledContent("Neueste Version", value: latest)
                    }
                    if system.updateCheck.updateAvailable == true, let url = system.updateCheck.latestUrl.flatMap(URL.init(string:)) {
                        Link("Update verfügbar – Release ansehen", destination: url)
                    }
                    if let checked = system.updateCheck.checkedAt {
                        LabeledContent("Zuletzt geprüft", value: checked.formatted(date: .numeric, time: .shortened))
                    }
                    if let error = system.updateCheck.error { Text(error).foregroundStyle(.red) }
                    Button("Jetzt prüfen") { Task { await store.checkNow() } }
                } header: {
                    Text("Updates")
                }
            } else if let error = store.system.error {
                ErrorView(error: error) { await store.load() }
            } else {
                SkeletonRows(count: 5)
            }
            if let settings = store.notifications.value {
                NotificationSettingsSections(store: store, settings: settings)
            }
        }
        .disabled(store.busy)
        .refreshable { await store.load() }
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

/// System → Benachrichtigungen: time of the daily run (server time zone) and the KNot webhook address.
private struct NotificationSettingsSections: View {
    let store: SystemStore
    let settings: Components.Schemas.AdminNotificationSettings
    @State private var time = ClockTime(hour: 7, minute: 0)!
    @State private var webhookURL = ""
    @State private var confirmRemove = false

    private var changed: Bool {
        time.text != settings.dailyRunTime || webhookURL.trimmingCharacters(in: .whitespaces) != (settings.webhookUrl ?? "")
    }

    private var isUTC: Bool { ["UTC", "GMT", "Etc/UTC", "Etc/GMT"].contains(settings.timeZone) }

    var body: some View {
        Section {
            DatePicker("Täglicher Abgleich um", selection: Binding(get: { time.date(in: ClockTime.pickerCalendar) },
                                                                    set: { time = ClockTime($0, in: ClockTime.pickerCalendar) }),
                       displayedComponents: .hourAndMinute)
                .environment(\.calendar, ClockTime.pickerCalendar)
                .environment(\.timeZone, ClockTime.pickerCalendar.timeZone)
            LabeledContent("Zeitzone des Servers", value: settings.timeZone)
            LabeledContent("Letzter Durchgang", value: settings.lastRunAt.map(Self.format) ?? "noch keiner")
            LabeledContent("Nächster", value: Self.format(settings.nextRunAt))
        } header: {
            Text("Benachrichtigungen")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Wer Serien beobachtet, kann sich unter „Konto → Benachrichtigungen“ über neue Folgen informieren lassen – per E-Mail oder über einen Webhook. Geprüft wird einmal am Tag; dabei gleicht WatchSwifty auch die Serien mit TMDB ab.")
                if isUTC { Text("Der Server läuft in UTC – im Container TZ setzen, z. B. TZ=Europe/Berlin.") }
            }
        }
        Section {
            TextField("https://knot.example.lan/hook", text: $webhookURL)
                .keyboardType(.URL).textContentType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            if settings.webhookUrl != nil {
                Button("Webhook entfernen", role: .destructive) { confirmRemove = true }
                    .confirmationDialog("Webhook entfernen?", isPresented: $confirmRemove, titleVisibility: .visible) {
                        Button("Entfernen", role: .destructive) { Task { await store.removeWebhook() } }
                    } message: {
                        Text("Wer Benachrichtigungen per Webhook bekommt, erhält sie danach per E-Mail, sofern möglich.")
                    }
            }
        } header: {
            Text("Webhook-Adresse (KNot, optional)")
        } footer: {
            Text("[KNot](https://github.com/nexus421/KNot) leitet Webhooks als Mail weiter. Lege dort für jede Person ein eigenes Ziel mit ihrer Mail-Adresse an, erzeuge den Schlüssel mit „java -jar knot.jar key“ und gib ihn weiter – sie trägt ihn unter „Konto → Benachrichtigungen“ ein. Leer lassen schaltet den Webhook ab.")
        }
        Section {
            Button("Speichern") { Task { await store.saveNotifications(dailyRunTime: time, webhookURL: webhookURL) } }
                .disabled(!changed)
                .onChange(of: settings, initial: true) {
                    time = ClockTime(settings.dailyRunTime) ?? time
                    webhookURL = settings.webhookUrl ?? ""
                }
        }
    }

    private static func format(_ date: Date) -> String {
        date.formatted(date: .numeric, time: .shortened) + " Uhr"
    }
}
