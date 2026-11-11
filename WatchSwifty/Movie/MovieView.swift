import SwiftUI
import WatchSwiftyClient
import WatchSwiftyCore

struct MovieView: View {
    let tmdbID: Int
    @Environment(AppModel.self) private var model
    @State private var store: MovieStore?

    var body: some View {
        Group {
            if let store { MovieContent(store: store) } else { ProgressView() }
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
    @State private var showComment = false
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
        .refreshable { await store.load() }
        .onAppear { Task { await store.reloadIfStale() } }
        .sheet(isPresented: $showWatchSheet) {
            WatchSheet(title: store.detail.value?.name ?? "") { choice in
                Task { await store.mark(choice: choice); feedback += 1 }
            }
        }
        .sheet(isPresented: $showComment) {
            CommentSheet(title: "Kommentar", text: store.detail.value?.comment ?? "") { text in
                Task { await store.setComment(text) }
            }
        }
        .alert("Das hat nicht geklappt", isPresented: Binding(get: { store.actionError != nil },
                                                                set: { if !$0 { store.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.actionError?.message ?? "")
        }
        .sensoryFeedback(.success, trigger: feedback)
    }

    private func list(_ detail: Components.Schemas.MovieDetail) -> some View {
        List {
            Section {
                TitleHeader(posterPath: detail.posterPath, title: detail.name,
                            subtitle: [detail.year.map(String.init), detail.runtime.map { "\($0) min" }]
                                .compactMap { $0 }.joined(separator: " · "),
                            overview: detail.overview)
                RatingControl(rating: detail.rating) { rating in Task { await store.setRating(rating) } }
                Button { showComment = true } label: {
                    LabeledContent("Kommentar") { Text(detail.comment ?? "Hinzufügen").lineLimit(2) }
                }
                LinksRow(links: detail.links)
            }
            Section("Gesehen") {
                ForEach(detail.watches, id: \.id) { watch in
                    VStack(alignment: .leading) {
                        Text(watch.day.map { Day.display($0) } ?? "Ohne Datum")
                        Text([watch.service?.displayName, watch.origin == .import ? "Import" : nil]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button(detail.watches.isEmpty ? "Gesehen …" : "Erneut gesehen …", systemImage: "checkmark.circle") {
                    showWatchSheet = true
                }
                if !detail.watches.isEmpty {
                    Button("Nicht gesehen", systemImage: "xmark.circle", role: .destructive) {
                        Task { await store.unmark() }
                    }
                }
            }
        }
        .disabled(store.busy)
    }
}
