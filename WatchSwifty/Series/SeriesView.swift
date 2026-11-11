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
    @State private var confirmAll = false
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
        .onAppear { Task { await store.reloadIfStale() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.load() } } }
        .onChange(of: store.detail.value?.tmdbId, initial: true) {
            if expanded == nil, let detail = store.detail.value { expanded = SeriesStore.initiallyExpanded(detail) }
        }
        .sheet(item: $selected) { target in
            EpisodeSheet(store: store, target: target) { feedback += 1 }
        }
        .confirmationDialog("Alle Folgen als gesehen markieren?", isPresented: $confirmAll, titleVisibility: .visible) {
            Button("Alles gesehen") { Task { await store.markAll(); feedback += 1 } }
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
            Section {
                TitleHeader(posterPath: detail.posterPath, title: detail.name,
                            subtitle: [detail.year.map(String.init), detail.status].compactMap { $0 }.joined(separator: " · "),
                            overview: detail.overview)
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
                                Button("Gesehen") {
                                    Task { await store.markEpisode(season: season.number, number: episode.number, choice: WatchChoice()); feedback += 1 }
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
                    SeasonHeader(season: season, isExpanded: isExpanded(season.number)) {
                        Task { await store.markSeason(season.number); feedback += 1 }
                    }
                }
            }
        }
        .disabled(store.busy)
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
                Button("Alles gesehen", systemImage: "checkmark.circle.fill") { confirmAll = true }
            } label: {
                Image(systemName: "ellipsis.circle").accessibilityLabel("Aktionen")
            }
        }
    }
}

/// Tappable season header: chevron, title, progress, „Staffel gesehen“.
private struct SeasonHeader: View {
    let season: Components.Schemas.Season
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
                Button("Staffel gesehen", systemImage: "checkmark.circle", action: onMarkSeason)
            } label: {
                Image(systemName: "ellipsis.circle").accessibilityLabel("Staffel-Aktionen")
            }
        }
    }
}

struct EpisodeTarget: Identifiable, Hashable {
    let season: Int
    let number: Int
    var id: String { "\(season)-\(number)" }
}
