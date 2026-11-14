import SwiftUI
import WatchSwiftyClient
import WatchSwiftyCore

struct MovieView: View {
    let tmdbID: Int
    @Environment(AppModel.self) private var model
    @State private var store: MovieStore?

    var body: some View {
        Group {
            if let store { MovieContent(store: store) } else { DetailSkeleton(rows: 1) }
        }
        .task {
            if store == nil { store = MovieStore(tmdbID: tmdbID, api: model.api, app: model) }
            await store?.load()
        }
    }
}

private struct MovieContent: View {
    @Bindable var store: MovieStore
    @State private var showWatchSheet = false
    @State private var deleting: Components.Schemas.WatchSummary?
    @State private var feedback = 0

    var body: some View {
        Group {
            if let detail = store.detail.value {
                list(detail)
            } else if let error = store.detail.error {
                ErrorView(error: error) { await store.load() }
            } else {
                DetailSkeleton(rows: 1)
            }
        }
        .navigationTitle(store.detail.value?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.load() }
        .staleBanner(store.detail.value == nil ? nil : store.detail.error) { await store.load() }
        .onAppear { Task { await store.reloadIfStale() } }
        .sheet(isPresented: $showWatchSheet) {
            WatchSheet(title: store.detail.value?.name ?? "", rewatch: !(store.detail.value?.watches.isEmpty ?? true)) { choice in
                Task { await store.mark(choice: choice); feedback += 1 }
            }
        }
        .alert("Das hat nicht geklappt", isPresented: Binding(get: { store.actionError != nil },
                                                                set: { if !$0 { store.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.actionError?.message ?? "")
        }
        .sensoryFeedback(.success, trigger: feedback)
        .confirmationDialog("Diese Sichtung löschen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { watch in
            Button("Löschen", role: .destructive) { Task { await store.deleteWatch(id: watch.id) } }
        }
    }

    private func list(_ detail: Components.Schemas.MovieDetail) -> some View {
        List {
            Section {
                TitleHeader(posterPath: detail.posterPath, title: detail.name,
                            subtitle: [detail.year.map(String.init), detail.runtime.map { "\($0) min" }]
                                .compactMap { $0 }.joined(separator: " · "),
                            genres: detail.genres, overview: detail.overview)
                RatingControl(rating: detail.rating) { rating in Task { await store.setRating(rating) } }
                LinksRow(links: detail.links)
            }
            Section("Kommentar") {
                CommentField(placeholder: "Was hältst du von dem Film?", saved: detail.comment) { text in
                    Task { await store.setComment(text) }
                }
            }
            Section("Gesehen") {
                ForEach(detail.watches, id: \.id) { watch in
                    WatchRow(watch: watch) { deleting = watch }
                }
                Button(detail.watches.isEmpty ? "Gesehen …" : "Erneut gesehen …", systemImage: "checkmark.circle") {
                    showWatchSheet = true
                }
            }
        }
        .disabled(store.busy)
    }
}
