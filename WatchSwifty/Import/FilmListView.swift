import SwiftUI
import UniformTypeIdentifiers
import WatchSwiftyClient
import WatchSwiftyCore

struct FilmListView: View {
    @Environment(AppModel.self) private var model
    @State private var store: FilmListStore?

    var body: some View {
        Group {
            if let store { FilmListContent(store: store) } else { ProgressView() }
        }
        .navigationTitle("Filmliste")
        .onAppear { if store == nil { store = FilmListStore(api: model.api, app: model) } }
    }
}

private struct FilmListContent: View {
    @Bindable var store: FilmListStore
    @State private var picking = false
    @State private var pollRound = 0
    @State private var searching: Components.Schemas.FilmEntry?

    var body: some View {
        List {
            Section {
                Button("CSV-Datei auswählen …", systemImage: "doc.badge.plus") { picking = true }
                if let count = store.lastUploadCount { Text("\(count) Filme hochgeladen").font(.callout) }
            } header: {
                Text("Hochladen")
            } footer: {
                Text("Eine Liste deiner Filme als CSV (höchstens 2 MB), z. B. ein Export aus Letterboxd.")
            }
            if let list = store.list.value {
                Section("Stand") {
                    if list.counts.pending > 0 {
                        HStack { ProgressView(); Text("\(list.counts.pending) Filme werden gesucht …") }
                    }
                    LabeledContent("Importiert", value: "\(list.counts.imported)")
                    LabeledContent("Zu prüfen", value: "\(list.counts.review)")
                    LabeledContent("Nicht gefunden", value: "\(list.counts.notFound)")
                    LabeledContent("Übersprungen", value: "\(list.counts.skipped)")
                    if let error = list.error {
                        Text(error).foregroundStyle(.red)
                        Button("Erneut versuchen") { Task { await store.retry(); pollRound += 1 } }
                    }
                }
                let open = list.entries.filter { $0.status == .review || $0.status == .notFound }
                if !open.isEmpty {
                    Section("Zu entscheiden") {
                        ForEach(open, id: \.id) { entry in entryRow(entry) }
                    }
                }
            } else if let error = store.list.error {
                ErrorView(error: error) { await store.load() }
            }
        }
        .disabled(store.busy)
        .refreshable { await store.load() }
        .task(id: pollRound) { await store.pollWhilePending() }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            guard case .success(let url) = result else { return }
            Task { if await store.upload(fileURL: url) { pollRound += 1 } }
        }
        .sheet(item: $searching) { entry in FilmSearchSheet(store: store, entry: entry) }
        .alert("Das hat nicht geklappt", isPresented: Binding(get: { store.actionError != nil },
                                                                set: { if !$0 { store.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.actionError?.message ?? "")
        }
    }

    private func entryRow(_ entry: Components.Schemas.FilmEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.title + (entry.year.map { " (\($0))" } ?? "")).font(.headline)
            if let error = entry.error { Text(error).font(.caption).foregroundStyle(.red) }
            ForEach(entry.candidates, id: \.tmdbId) { candidate in
                Button {
                    Task { await store.accept(entryID: entry.id, tmdbID: candidate.tmdbId) }
                } label: {
                    Label(candidate.name + (candidate.year.map { " (\($0))" } ?? ""), systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderless)
            }
            HStack {
                Button("Anders suchen …") { searching = entry }
                Spacer()
                Button("Überspringen", role: .destructive) { Task { await store.skip(entryID: entry.id) } }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
    }
}

private struct FilmSearchSheet: View {
    let store: FilmListStore
    let entry: Components.Schemas.FilmEntry
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Titel und Jahr", text: $query)
                    .onSubmit(search)
            }
            .navigationTitle(entry.title)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { query = entry.title + (entry.year.map { " \($0)" } ?? "") }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Suchen", action: search) }
            }
        }
        .presentationDetents([.medium])
    }

    private func search() {
        Task { await store.search(entryID: entry.id, query: query); dismiss() }
    }
}

extension Components.Schemas.FilmEntry: @retroactive Identifiable {}
