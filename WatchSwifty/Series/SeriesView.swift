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
            if let store {
                SeriesContent(store: store)
            } else {
                ProgressView()
            }
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
    @State private var watchTarget: EpisodeTarget?
    @State private var watchesEpisode: Components.Schemas.Episode?
    @State private var commentTarget: CommentTarget?
    @State private var confirmAll = false
    @State private var feedback = 0

    var body: some View {
        Group {
            if let detail = store.detail.value {
                list(detail)
            } else if let error = store.detail.error {
                ErrorView(error: error) { await store.load() }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(store.detail.value?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if let detail = store.detail.value { menu(detail) } }
        .refreshable { await store.load() }
        .onAppear { Task { await store.reloadIfStale() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.load() } } }
        .sheet(item: $watchTarget) { target in
            WatchSheet(title: target.title) { choice in
                Task { await store.markEpisode(season: target.season, number: target.number, choice: choice); feedback += 1 }
            }
        }
        .sheet(item: $watchesEpisode) { episode in WatchesSheet(episode: episode) }
        .sheet(item: $commentTarget) { target in
            CommentSheet(title: target.title, text: target.text) { text in
                Task {
                    if let season = target.season { await store.setSeasonComment(season: season, text: text) }
                    else { await store.setComment(text) }
                }
            }
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

    private func list(_ detail: Components.Schemas.SeriesDetail) -> some View {
        List {
            Section {
                TitleHeader(posterPath: detail.posterPath, title: detail.name,
                            subtitle: [detail.year.map(String.init), detail.status].compactMap { $0 }.joined(separator: " · "),
                            overview: detail.overview)
                RatingControl(rating: detail.rating) { rating in Task { await store.setRating(rating) } }
                Button {
                    commentTarget = CommentTarget(title: "Kommentar", text: detail.comment ?? "", season: nil)
                } label: {
                    LabeledContent("Kommentar") { Text(detail.comment ?? "Hinzufügen").lineLimit(2) }
                }
                LinksRow(links: detail.links)
            }
            ForEach(detail.seasons, id: \.number) { season in
                Section {
                    ForEach(season.episodes, id: \.number) { episode in
                        EpisodeRow(episode: episode)
                            .contentShape(Rectangle())
                            .onTapGesture { if !episode.watches.isEmpty { watchesEpisode = episode } }
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
                            .contextMenu {
                                if episode.aired {
                                    Button("Gesehen am …", systemImage: "calendar") {
                                        watchTarget = EpisodeTarget(season: season.number, number: episode.number,
                                                                    title: "S\(season.number)E\(episode.number) · \(episode.name)")
                                    }
                                }
                                if !episode.watches.isEmpty {
                                    Button("Nicht gesehen", systemImage: "xmark.circle", role: .destructive) {
                                        Task { await store.unmarkEpisode(season: season.number, number: episode.number) }
                                    }
                                }
                            }
                    }
                } header: {
                    HStack {
                        Text(season.title)
                        Spacer()
                        Text("\(season.watchedCount)/\(season.episodes.count)")
                        Menu {
                            Button("Staffel gesehen", systemImage: "checkmark.circle") {
                                Task { await store.markSeason(season.number); feedback += 1 }
                            }
                            Button("Staffelkommentar", systemImage: "text.bubble") {
                                commentTarget = CommentTarget(title: season.title, text: season.comment ?? "", season: season.number)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle").accessibilityLabel("Staffel-Aktionen")
                        }
                    }
                } footer: {
                    if let comment = season.comment, !comment.isEmpty { Text(comment) }
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

private struct EpisodeTarget: Identifiable {
    let season: Int
    let number: Int
    let title: String
    var id: String { "\(season)-\(number)" }
}

struct CommentTarget: Identifiable {
    let title: String
    let text: String
    let season: Int?
    var id: String { "\(season ?? -1)" }
}

extension Components.Schemas.Episode: @retroactive Identifiable {
    public var id: String { "\(season)-\(number)" }
}
