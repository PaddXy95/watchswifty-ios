import SwiftUI
import WatchSwiftyClient
import WatchSwiftyCore

struct SystemView: View {
    @Environment(AppModel.self) private var model
    @State private var store: SystemStore?

    var body: some View {
        Group {
            if let store { SystemContent(store: store) } else { ProgressView() }
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
    }
}
