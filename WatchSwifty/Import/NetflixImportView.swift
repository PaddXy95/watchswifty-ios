import SwiftUI
import UniformTypeIdentifiers
import WatchSwiftyClient
import WatchSwiftyCore

struct NetflixImportView: View {
    @Environment(AppModel.self) private var model
    @State private var store: NetflixImportStore?

    var body: some View {
        Group {
            if let store { NetflixImportContent(store: store) } else { ListSkeleton() }
        }
        .navigationTitle("Netflix-Verlauf")
        .onAppear { if store == nil { store = NetflixImportStore(api: model.api, app: model) } }
    }
}

private struct NetflixImportContent: View {
    @Bindable var store: NetflixImportStore
    @State private var picking = false
    @State private var pollRound = 0
    @State private var changing: MappingTarget?
    @State private var assigning: Components.Schemas.UnmatchedRow?

    var body: some View {
        List {
            Section {
                Button("CSV-Datei auswählen …", systemImage: "doc.badge.plus") { picking = true }
                if let summary = store.lastUpload {
                    Text("\(summary.new) neu · \(summary.known) schon bekannt · \(summary.skipped) übersprungen")
                        .font(.callout)
                }
            } header: {
                Text("Hochladen")
            } footer: {
                Text("Bei Netflix unter Konto → Profil → Wiedergabeaktivität → „Alle herunterladen“ (höchstens 10 MB).")
            }
            if let state = store.state.value {
                progress(state.progress)
                if !state.review.isEmpty { reviewSection(state.review) }
                if !state.unmatched.isEmpty { unmatchedSection(state.unmatched, total: state.unmatchedTotal) }
                mappingsSection(state.mappings)
            } else if let error = store.state.error {
                ErrorView(error: error) { await store.load() }
            } else {
                Section { SkeletonRows(count: 4) }
            }
        }
        .disabled(store.busy)
        .refreshable { await store.load() }
        .task(id: pollRound) { await store.pollWhileRunning() }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            guard case .success(let url) = result else { return }
            Task { if await store.upload(fileURL: url) { pollRound += 1 } }
        }
        .sheet(item: $changing) { target in
            MappingSearchSheet(store: store, target: target)
        }
        .sheet(item: $assigning) { row in
            RowAssignSheet(store: store, row: row)
        }
        .alert("Das hat nicht geklappt", isPresented: Binding(get: { store.actionError != nil },
                                                                set: { if !$0 { store.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.actionError?.message ?? "")
        }
    }

    @ViewBuilder private func progress(_ progress: Components.Schemas.ImportProgress) -> some View {
        Section("Stand") {
            if progress.running {
                HStack {
                    ProgressView()
                    Text("Ordne noch \(progress.pendingRows) Zeilen zu …")
                }
            } else {
                LabeledContent("Offene Zeilen", value: "\(progress.pendingRows)")
            }
            LabeledContent("Zu prüfen", value: "\(progress.waitingForReview)")
            if let error = progress.lastError {
                Text(error).foregroundStyle(.red)
                Button("Erneut versuchen") { Task { await store.retry(); pollRound += 1 } }
            }
        }
    }

    private func reviewSection(_ reviews: [Components.Schemas.MappingReview]) -> some View {
        Section("Zu prüfen") {
            ForEach(reviews, id: \.id) { review in
                VStack(alignment: .leading, spacing: 6) {
                    Text(review.netflixName).font(.headline)
                    Text([review.rowCount == 1 ? "1 Zeile" : "\(review.rowCount) Zeilen",
                          Day.watchedRange(first: review.firstDay, last: review.lastDay)].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                    if let rows = review.rows, !rows.isEmpty {
                        DisclosureGroup("Zeilen anzeigen") {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                    Text("\(row.rawTitle) · \(Day.display(row.day))")
                                }
                                if review.rowCount > rows.count {
                                    Text("… und \(review.rowCount - rows.count) weitere").foregroundStyle(.secondary)
                                }
                            }
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.callout)
                    }
                    ForEach(review.candidates, id: \.tmdbId) { candidate in
                        Button {
                            Task {
                                await store.accept(mappingID: review.id, kind: .init(rawValue: candidate.kind.rawValue) ?? .tv,
                                                   tmdbID: candidate.tmdbId)
                            }
                        } label: {
                            Label(candidate.name + (candidate.year.map { " (\($0))" } ?? ""), systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                    HStack {
                        Button("Anderen Titel …") {
                            changing = MappingTarget(id: review.id, name: review.netflixName, accept: true)
                        }
                        Spacer()
                        Button("Ignorieren", role: .destructive) { Task { await store.ignore(mappingID: review.id) } }
                    }
                    .buttonStyle(.borderless)
                    .font(.callout)
                }
            }
        }
    }

    private func unmatchedSection(_ rows: [Components.Schemas.UnmatchedRow], total: Int) -> some View {
        Section {
            ForEach(rows, id: \.id) { row in
                VStack(alignment: .leading) {
                    Text(row.rawTitle)
                    Text(Day.display(row.day)).font(.caption).foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button("Ignorieren", role: .destructive) { Task { await store.ignore(rowID: row.id) } }
                    if row.canAssign { Button("Zuordnen") { assigning = row }.tint(.blue) }
                }
            }
        } header: {
            Text("Nicht zugeordnet (\(total))")
        }
    }

    private func mappingsSection(_ mappings: [Components.Schemas.Mapping]) -> some View {
        Section {
            Picker("Zuordnungen", selection: Binding(get: { store.mappingFilter },
                                                     set: { value in Task { await store.setMappingFilter(value) } })) {
                ForEach(NetflixImportStore.MappingFilter.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            ForEach(mappings, id: \.id) { mapping in
                VStack(alignment: .leading) {
                    Text(mapping.netflixName)
                    Text([mapping.title?.name, mapping.status.label].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .contextMenu {
                    Button("Ändern …", systemImage: "pencil") {
                        changing = MappingTarget(id: mapping.id, name: mapping.netflixName, accept: false)
                    }
                    Button("Ignorieren", systemImage: "eye.slash") { Task { await store.ignore(mappingID: mapping.id) } }
                    Button("Zurücksetzen", systemImage: "arrow.uturn.backward") { Task { await store.reset(mappingID: mapping.id) } }
                }
            }
        } header: {
            Text("Zuordnungen")
        }
    }
}

struct MappingTarget: Identifiable {
    let id: String
    let name: String
    /// Review entry (accept) or existing mapping (change).
    let accept: Bool
}

private struct MappingSearchSheet: View {
    let store: NetflixImportStore
    let target: MappingTarget
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Components.Schemas.SearchResult] = []

    var body: some View {
        NavigationStack {
            List(results, id: \.tmdbId) { result in
                Button {
                    Task {
                        let kind = Components.Schemas.MappingDecision.kindPayload(rawValue: result.kind.rawValue) ?? .tv
                        if target.accept { await store.accept(mappingID: target.id, kind: kind, tmdbID: result.tmdbId) }
                        else { await store.change(mappingID: target.id, kind: kind, tmdbID: result.tmdbId) }
                        dismiss()
                    }
                } label: {
                    VStack(alignment: .leading) {
                        Text(result.name)
                        Text([result.kind == .tv ? "Serie" : "Film", result.year.map(String.init)].compactMap { $0 }
                            .joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .onSubmit(of: .search) { Task { results = await store.searchCandidates(mappingID: target.id, query: query) } }
            .navigationTitle(target.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
            .task {
                query = target.name
                results = await store.searchCandidates(mappingID: target.id, query: query)
            }
        }
    }
}

private struct RowAssignSheet: View {
    let store: NetflixImportStore
    let row: Components.Schemas.UnmatchedRow
    @Environment(\.dismiss) private var dismiss
    @State private var options: [Components.Schemas.EpisodeOption] = []

    var body: some View {
        NavigationStack {
            List(options, id: \.episodeId) { option in
                Button("\(option.code) · \(option.name)") {
                    Task { await store.assign(rowID: row.id, episodeID: option.episodeId); dismiss() }
                }
            }
            .navigationTitle(row.rawTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
            .task { options = await store.rowOptions(rowID: row.id) }
        }
    }
}

extension Components.Schemas.UnmatchedRow: @retroactive Identifiable {}
