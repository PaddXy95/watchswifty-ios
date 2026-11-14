import SwiftUI
import WatchSwiftyClient
import WatchSwiftyCore

/// Series page: header, seasons with episodes, every change the web offers.
struct SeriesView: View {
    let tmdbID: Int
    @Environment(AppModel.self) private var model
    @State private var store: SeriesStore?

    var body: some View {
        Group {
            if let store { SeriesContent(store: store) } else { DetailSkeleton() }
        }
        .task {
            if store == nil { store = SeriesStore(tmdbID: tmdbID, api: model.api, app: model) }
            await store?.load()
        }
    }
}

private struct SeriesContent: View {
    @Bindable var store: SeriesStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selected: EpisodeTarget?
    @State private var expanded: Set<Int>?
    @State private var bulk: BulkTarget?
    @State private var feedback = 0

    var body: some View {
        Group {
            if let detail = store.detail.value {
                list(detail)
            } else if let error = store.detail.error {
                ErrorView(error: error) { await store.load() }
            } else {
                DetailSkeleton()
            }
        }
        .navigationTitle(store.detail.value?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if let detail = store.detail.value { menu(detail) } }
        .refreshable { await store.load() }
        .staleBanner(store.detail.value == nil ? nil : store.detail.error) { await store.load() }
        .onAppear { Task { await store.reloadIfStale() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.load() } } }
        .onChange(of: store.detail.value?.tmdbId, initial: true) {
            if expanded == nil, let detail = store.detail.value { expanded = SeriesStore.initiallyExpanded(detail) }
        }
        .sheet(item: $selected) { target in
            EpisodeSheet(store: store, target: target) { feedback += 1 }
        }
        .sheet(item: $bulk) { target in
            BulkWatchSheet(target: target) { service in
                Task {
                    switch target.scope {
                    case .season(let number): await store.markSeason(number, service: service, rewatch: target.rewatch)
                    case .series: await store.markAll(service: service, rewatch: target.rewatch)
                    }
                    feedback += 1
                }
            }
        }
        .alert("Das hat nicht geklappt", isPresented: errorShown) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.actionError?.message ?? "")
        }
        .sensoryFeedback(.success, trigger: feedback)
    }

    private var errorShown: Binding<Bool> {
        Binding(get: { store.actionError != nil }, set: { if !$0 { store.actionError = nil } })
    }

    private func isExpanded(_ season: Int) -> Binding<Bool> {
        Binding(get: { expanded?.contains(season) ?? false },
                set: { open in withAnimation { if open { expanded?.insert(season) } else { expanded?.remove(season) } } })
    }

    private func list(_ detail: Components.Schemas.SeriesDetail) -> some View {
        List {
            if let next = detail.next {
                Section {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Als Nächstes").font(.caption).foregroundStyle(.secondary)
                            Text("S\(next.season)E\(next.number) · \(next.name)").font(.headline).lineLimit(2)
                                .id(next.episodeId)
                                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .move(edge: .top).combined(with: .opacity)))
                        }
                        .clipped()
                        .animation(.snappy(duration: 0.4), value: next.episodeId)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { selected = EpisodeTarget(season: next.season, number: next.number) }
                        Button("Gesehen") {
                            Task {
                                await store.markNext()
                                if store.actionError == nil { feedback += 1 }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                }
            }
            Section {
                TitleHeader(posterPath: detail.posterPath, title: detail.name,
                            subtitle: [detail.year.map(String.init), detail.status].compactMap { $0 }.joined(separator: " · "),
                            genres: detail.genres, overview: detail.overview)
                RatingControl(rating: detail.rating) { rating in Task { await store.setRating(rating) } }
                LinksRow(links: detail.links)
            }
            Section("Kommentar") {
                CommentField(placeholder: "Was hältst du von der Serie?", saved: detail.comment) { text in
                    Task { await store.setComment(text) }
                }
            }
            ForEach(detail.seasons, id: \.number) { season in
                Section(isExpanded: isExpanded(season.number)) {
                    ForEach(season.episodes, id: \.number) { episode in
                        Button {
                            selected = EpisodeTarget(season: season.number, number: episode.number)
                        } label: {
                            EpisodeRow(episode: episode)
                        }
                        .tint(.primary)
                        .swipeActions(edge: .leading) {
                            if episode.aired {
                                Button(episode.watches.isEmpty ? "Gesehen" : "Erneut") {
                                    Task {
                                        await store.markEpisode(season: season.number, number: episode.number,
                                                                choice: .quick(alreadyWatched: !episode.watches.isEmpty))
                                        feedback += 1
                                    }
                                }
                                .tint(.green)
                                Button("Bis hier") {
                                    Task { await store.markUpTo(season: season.number, number: episode.number); feedback += 1 }
                                }
                                .tint(.blue)
                            }
                        }
                    }
                    CommentField(placeholder: "Kommentar zu \(season.title) …", saved: season.comment) { text in
                        Task { await store.setSeasonComment(season: season.number, text: text) }
                    }
                    .font(.callout)
                } header: {
                    SeasonHeader(season: season, rewatch: SeriesStore.fullyWatched(season), isExpanded: isExpanded(season.number)) {
                        bulk = BulkTarget(scope: .season(season.number), seasonTitle: season.title,
                                          preset: SeriesStore.bulkServicePreset(detail), rewatch: SeriesStore.fullyWatched(season))
                    }
                }
            }
        }
        .disabled(store.busy)
        .animation(.snappy, value: detail.next?.episodeId)
        .animation(.snappy, value: detail.seasons.map(\.watchedCount))
    }

    private func menu(_ detail: Components.Schemas.SeriesDetail) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Toggle(isOn: Binding(get: { detail.followed }, set: { value in Task { await store.setFollowed(value) } })) {
                    Label("Beobachten", systemImage: "bell")
                }
                Toggle(isOn: Binding(get: { detail.hidden }, set: { value in Task { await store.setHidden(value) } })) {
                    Label("Ausblenden", systemImage: "eye.slash")
                }
                Divider()
                let rewatch = SeriesStore.fullyWatched(detail)
                Button(rewatch ? "Gesamte Serie erneut gesehen" : "Gesamte Serie gesehen", systemImage: "checkmark.circle.fill") {
                    bulk = BulkTarget(scope: .series, seasonTitle: nil, preset: SeriesStore.bulkServicePreset(detail), rewatch: rewatch)
                }
            } label: {
                Image(systemName: "ellipsis.circle").accessibilityLabel("Aktionen")
            }
        }
    }
}

/// Tappable season header: chevron, title, progress, „Ganze Staffel (erneut) gesehen“.
private struct SeasonHeader: View {
    let season: Components.Schemas.Season
    /// Every aired episode is watched: the action marks a new round.
    let rewatch: Bool
    @Binding var isExpanded: Bool
    let onMarkSeason: () -> Void

    var body: some View {
        HStack {
            Button {
                isExpanded.toggle()
            } label: {
                HStack {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .font(.caption.bold())
                    Text(season.title)
                    Spacer()
                    Text("\(season.watchedCount)/\(season.episodes.count)")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(season.title), \(season.watchedCount) von \(season.episodes.count) gesehen")
            .accessibilityHint(isExpanded ? "Zuklappen" : "Aufklappen")
            Menu {
                Button(rewatch ? "Ganze Staffel erneut gesehen" : "Ganze Staffel gesehen", systemImage: "checkmark.circle",
                       action: onMarkSeason)
            } label: {
                Image(systemName: "ellipsis.circle").accessibilityLabel("Staffel-Aktionen")
            }
        }
    }
}

/// „Ganze Staffel gesehen“ / „Gesamte Serie gesehen“ with the service preselected as in the web; `rewatch` once
/// every aired episode is watched („… erneut gesehen“, a new round).
struct BulkTarget: Identifiable {
    enum Scope: Hashable { case season(Int), series }
    let scope: Scope
    let seasonTitle: String?
    let preset: ServiceChoice
    let rewatch: Bool
    var id: Scope { scope }
}

/// Asks for the service before a whole season or series is marked (without a date, as in the web).
private struct BulkWatchSheet: View {
    let target: BulkTarget
    let onSave: (ServiceChoice) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var service: ServiceChoice

    init(target: BulkTarget, onSave: @escaping (ServiceChoice) -> Void) {
        self.target = target
        self.onSave = onSave
        _service = State(initialValue: target.preset)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ServicePicker(selection: $service, allowsLastUsed: false)
                } footer: {
                    Text(footer)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gesehen") {
                        onSave(service)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var title: String {
        switch (target.seasonTitle == nil, target.rewatch) {
        case (true, false): "Gesamte Serie gesehen"
        case (true, true): "Gesamte Serie erneut gesehen"
        case (false, false): "Ganze Staffel gesehen"
        case (false, true): "Ganze Staffel erneut gesehen"
        }
    }

    private var footer: String {
        if target.rewatch {
            return target.seasonTitle.map { "Jede ausgestrahlte Folge von „\($0)“ bekommt eine weitere Sichtung ohne Datum. Schon einzeln erneut gesehene Folgen zählen nicht doppelt." }
                ?? "Jede ausgestrahlte Folge bekommt eine weitere Sichtung ohne Datum. Schon einzeln erneut gesehene Folgen zählen nicht doppelt."
        }
        return target.seasonTitle.map { "Alle ausgestrahlten Folgen von „\($0)“, die noch nicht gesehen sind, werden ohne Datum abgehakt." }
            ?? "Alle ausgestrahlten Folgen, die noch nicht gesehen sind, werden ohne Datum abgehakt."
    }
}

struct EpisodeTarget: Identifiable, Hashable {
    let season: Int
    let number: Int
    var id: String { "\(season)-\(number)" }
}
