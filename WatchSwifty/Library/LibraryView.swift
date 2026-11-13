import SwiftUI
import WatchSwiftyClient
import WatchSwiftyCore

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var store: LibraryStore?

    var body: some View {
        Group {
            if let store { LibraryContent(store: store) } else { GridSkeleton() }
        }
        .navigationTitle("Bibliothek")
        .task {
            if store == nil { store = LibraryStore(api: model.api, app: model) }
            await store?.reloadIfStale()
        }
    }
}

private struct LibraryContent: View {
    let store: LibraryStore
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 12)]

    /// The selected genre stays choosable even when no loaded title has it any more.
    private var genreChoices: [GenreValue] {
        store.genre.map { GenreValue.sortedByName(store.availableGenres + [$0]) } ?? store.availableGenres
    }

    var body: some View {
        Group {
            if store.entries.value == nil, let error = store.entries.error {
                ErrorView(error: error) { await store.load() }
            } else if store.entries.value == nil {
                GridSkeleton()
            } else if let entries = store.entries.value, entries.isEmpty, let genre = store.genre {
                ContentUnavailableView {
                    Label("Keine Titel", systemImage: "books.vertical")
                } description: {
                    Text("Kein Titel mit dem Genre „\(genre.displayName)“.")
                } actions: {
                    Button("Alle Genres zeigen") { Task { await store.set(genre: nil) } }
                }
            } else if let entries = store.entries.value, entries.isEmpty {
                ContentUnavailableView("Keine Titel", systemImage: "books.vertical",
                                       description: Text("Hier erscheint alles, was du gesehen, bewertet oder kommentiert hast."))
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(store.entries.value ?? [], id: \.self) { entry in
                            NavigationLink(value: entry.kind == .tv ? Route.series(entry.tmdbId) : Route.movie(entry.tmdbId)) {
                                LibraryTile(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .refreshable { await store.load() }
        .staleBanner(store.entries.value == nil ? nil : store.entries.error) { await store.load() }
        .onAppear { Task { await store.reloadIfStale() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Anzeigen", selection: Binding(get: { store.filter },
                                                          set: { value in Task { await store.set(filter: value, sort: store.sort) } })) {
                        ForEach(LibraryStore.Filter.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("Sortieren", selection: Binding(get: { store.sort },
                                                           set: { value in Task { await store.set(filter: store.filter, sort: value) } })) {
                        ForEach(LibraryStore.Sort.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    if !store.availableGenres.isEmpty || store.genre != nil {
                        Picker("Genre", selection: Binding(get: { store.genre },
                                                           set: { value in Task { await store.set(genre: value) } })) {
                            Text("Alle Genres").tag(GenreValue?.none)
                            ForEach(genreChoices, id: \.self) { Text($0.displayName).tag(GenreValue?.some($0)) }
                        }
                        .pickerStyle(.menu)
                    }
                } label: {
                    Image(systemName: store.genre == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        .accessibilityLabel("Filter und Sortierung")
                }
            }
        }
    }
}

private struct LibraryTile: View {
    let entry: Components.Schemas.LibraryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PosterImage(path: entry.posterPath, width: 100)
                .overlay(alignment: .topTrailing) {
                    if let rating = entry.rating {
                        Text("★ \(rating)")
                            .font(.caption2.bold())
                            .padding(4)
                            .background(.thinMaterial, in: Capsule())
                            .padding(4)
                    }
                }
            Text(entry.name).font(.caption).lineLimit(2)
        }
        .frame(width: 100)
        .opacity(entry.hidden ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }
}

extension Components.Schemas.LibraryEntry: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.kind == rhs.kind && lhs.tmdbId == rhs.tmdbId }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(kind.rawValue)
        hasher.combine(tmdbId)
    }
}
