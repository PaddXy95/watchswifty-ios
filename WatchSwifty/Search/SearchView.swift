import SwiftUI
import WatchSwiftyClient
import WatchSwiftyCore

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var store: SearchStore?

    var body: some View {
        Group {
            if let store { SearchContent(store: store) } else { Color.clear }
        }
        .navigationTitle("Suche")
        .onAppear { if store == nil { store = SearchStore(api: model.api, app: model) } }
    }
}

private struct SearchContent: View {
    @Bindable var store: SearchStore

    var body: some View {
        List {
            if let error = store.results.error {
                ErrorView(error: error) { await store.refresh() }
                    .listRowSeparator(.hidden)
            } else if let hits = store.results.value {
                if hits.isEmpty {
                    ContentUnavailableView.search(text: store.query)
                }
                ForEach(hits, id: \.self) { hit in
                    NavigationLink(value: hit.kind == .tv ? Route.series(hit.tmdbId) : Route.movie(hit.tmdbId)) {
                        SearchHitRow(hit: hit)
                    }
                }
            } else if store.results.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .listStyle(.plain)
        .searchable(text: $store.query, prompt: "Serien und Filme")
        .onChange(of: store.query) { store.queryChanged() }
        .refreshable { await store.refresh() }
    }
}

private struct SearchHitRow: View {
    let hit: Components.Schemas.SearchHit

    var body: some View {
        HStack(spacing: 12) {
            PosterImage(path: hit.posterPath, width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.name)
                Text([hit.kind == .tv ? "Serie" : "Film", hit.year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                if hit.inLibrary {
                    Group {
                        if let watched = hit.watchedEpisodes, let total = hit.totalEpisodes {
                            Text("In der Bibliothek · \(watched)/\(total) gesehen")
                        } else {
                            Text("In der Bibliothek")
                        }
                    }
                    .font(.caption).foregroundStyle(.tint)
                }
            }
            Spacer()
            if let rating = hit.rating {
                Label("\(rating)", systemImage: "star.fill").font(.caption).foregroundStyle(.orange)
            }
        }
    }
}

extension Components.Schemas.SearchHit: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.kind == rhs.kind && lhs.tmdbId == rhs.tmdbId }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(kind.rawValue)
        hasher.combine(tmdbId)
    }
}
