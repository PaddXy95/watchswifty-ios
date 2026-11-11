import SwiftUI
import WatchSwiftyClient
import WatchSwiftyCore

struct StartView: View {
    @Environment(AppModel.self) private var model
    @State private var store: HomeStore?

    var body: some View {
        Group {
            if let store { StartContent(store: store) } else { ProgressView() }
        }
        .navigationTitle("Start")
        .task {
            if store == nil { store = HomeStore(api: model.api, app: model, snapshot: .live()) }
            await store?.load()
        }
    }
}

private struct StartContent: View {
    @Bindable var store: HomeStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var feedback = 0

    var body: some View {
        Group {
            if store.cards.value == nil, let error = store.cards.error {
                ErrorView(error: error) { await store.load() }
            } else if let cards = store.cards.value, cards.cards.isEmpty, isEmptyNotes {
                ContentUnavailableView("Nichts zum Weiterschauen", systemImage: "tv",
                                       description: Text("Suche eine Serie und markiere die erste Folge als gesehen."))
            } else {
                list
            }
        }
        .refreshable { await store.load() }
        .onAppear { Task { await store.reloadIfStale() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.load() } } }
        .alert("Das hat nicht geklappt", isPresented: Binding(get: { store.actionError != nil },
                                                                set: { if !$0 { store.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.actionError?.message ?? "")
        }
        .sensoryFeedback(.success, trigger: feedback)
    }

    private var isEmptyNotes: Bool {
        guard let notes = store.notes.value else { return true }
        return notes.newEpisodes.isEmpty && notes.upcoming.isEmpty
    }

    private var list: some View {
        List {
            Section("Weiterschauen") {
                ForEach(store.cards.value?.cards ?? [], id: \.tmdbId) { card in
                    NavigationLink(value: Route.series(card.tmdbId)) {
                        ContinueCardRow(card: card, busy: store.inFlight.contains(card.tmdbId)) { markNext(card.tmdbId) }
                    }
                    .swipeActions(edge: .leading) {
                        Button("Gesehen", systemImage: "checkmark") { markNext(card.tmdbId) }.tint(.green)
                    }
                }
                if let older = store.cards.value?.olderCount, older > 0 || store.showAll {
                    Button(store.showAll ? "Nur aktuelle anzeigen" : "Ältere anzeigen (\(older))") {
                        Task { await store.setShowAll(!store.showAll) }
                    }
                }
            }
            .redacted(reason: store.cards.value == nil ? .placeholder : [])
            if let notes = store.notes.value {
                if !notes.newEpisodes.isEmpty {
                    Section("Neue Folgen") {
                        ForEach(notes.newEpisodes, id: \.tmdbId) { note in
                            NavigationLink(value: Route.series(note.tmdbId)) {
                                HStack {
                                    PosterImage(path: note.posterPath, width: 40)
                                    VStack(alignment: .leading) {
                                        Text(note.name)
                                        Text(note.count == 1 ? "Neue Folge S\(note.first.season)E\(note.first.number)"
                                                             : "\(note.count) neue Folgen ab S\(note.first.season)E\(note.first.number)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .swipeActions {
                                Button("Ausblenden", systemImage: "eye.slash") {
                                    Task { await store.dismissNewEpisodes(tmdbID: note.tmdbId) }
                                }
                            }
                        }
                    }
                }
                if !notes.upcoming.isEmpty {
                    Section("Demnächst") {
                        ForEach(notes.upcoming, id: \.tmdbId) { note in
                            NavigationLink(value: Route.series(note.tmdbId)) {
                                VStack(alignment: .leading) {
                                    Text(note.name)
                                    Text("S\(note.next.season)E\(note.next.number)"
                                         + (note.next.airDate.map { " am \(Day.display($0))" } ?? ""))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func markNext(_ id: Int) {
        Task {
            await store.markNext(tmdbID: id)
            if store.actionError == nil { feedback += 1 }
        }
    }
}

struct ContinueCardRow: View {
    let card: Components.Schemas.ContinueCard
    let busy: Bool
    let onWatched: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 12) {
            PosterImage(path: card.posterPath, width: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(card.name).font(.headline)
                Text("S\(card.next.season)E\(card.next.number) · \(card.next.name)")
                    .font(.subheadline).lineLimit(1)
                HStack(spacing: 8) {
                    Text(card.remaining == 1 ? "noch 1 Folge" : "noch \(card.remaining) Folgen")
                    if let link = card.watchLink, let url = URL(string: link.url) {
                        Button("Ansehen bei \(link.label)") { openURL(url) }
                            .buttonStyle(.borderless)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onWatched) {
                if busy {
                    ProgressView()
                } else {
                    Image(systemName: "checkmark.circle").font(.title2)
                }
            }
            .buttonStyle(.borderless)
            .disabled(busy)
            .accessibilityLabel("Gesehen")
        }
    }
}
