import SwiftUI
import WatchSwiftyClient
import WatchSwiftyCore

struct StartView: View {
    @Environment(AppModel.self) private var model
    @State private var store: HomeStore?

    var body: some View {
        Group {
            if let store { StartContent(store: store) } else { ListSkeleton(rows: 6, poster: true) }
        }
        .navigationTitle("Start")
        .task {
            if store == nil { store = HomeStore(api: model.api, app: model, snapshot: model.snapshot) }
            await store?.load()
        }
    }
}

private struct StartContent: View {
    @Bindable var store: HomeStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var feedback = 0
    /// The cards as shown; updated inside `withAnimation`, so the list animates row heights, inserts and removals.
    @State private var shownCards: [Components.Schemas.ContinueCard] = []

    var body: some View {
        Group {
            if store.cards.value == nil, let error = store.cards.error {
                ErrorView(error: error) { await store.load() }
            } else if store.cards.value == nil {
                ListSkeleton(rows: 6, poster: true)
            } else if store.isEmpty {
                ContentUnavailableView("Nichts zum Weiterschauen", systemImage: "tv",
                                       description: Text("Suche eine Serie und markiere die erste Folge als gesehen."))
            } else {
                list
            }
        }
        .onChange(of: store.cards.value?.cards ?? [], initial: true) { old, new in
            if old.isEmpty { shownCards = new } else { withAnimation(.snappy(duration: 0.4)) { shownCards = new } }
        }
        .refreshable { await store.load() }
        .staleBanner(store.cards.value == nil ? nil : store.cards.error) { await store.load() }
        .onAppear { Task { await store.reloadIfStale() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.load() } } }
        .alert("Das hat nicht geklappt", isPresented: Binding(get: { store.actionError != nil },
                                                                set: { if !$0 { store.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.actionError?.message ?? "")
        }
        .sensoryFeedback(.success, trigger: feedback)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                let soon = store.hasUpcomingSoon(today: Day.string(from: Date()))
                // Value-based like every other link in this stack: mixing it with `navigationDestination(isPresented:)`
                // made SwiftUI push and pop in a loop when a series was opened from „Demnächst“.
                NavigationLink(value: StartDestination.upcoming) {
                    Image(systemName: soon ? "calendar.badge.exclamationmark" : "calendar")
                        .symbolRenderingMode(soon ? .multicolor : .monochrome)
                }
                .accessibilityLabel(soon ? "Demnächst, bald neue Folgen" : "Demnächst")
            }
        }
        .navigationDestination(for: StartDestination.self) { _ in UpcomingView(store: store) }
    }

    private var list: some View {
        List {
            Section("Weiterschauen") {
                ForEach(shownCards, id: \.tmdbId) { card in
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
            }
        }
        .animation(.snappy, value: store.notes.value?.newEpisodes.map(\.tmdbId) ?? [])
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
                // The marked episode slides up and out, the new one comes in from below.
                Text("S\(card.next.season)E\(card.next.number) · \(card.next.name)")
                    .font(.subheadline).lineLimit(1)
                    .id(card.next.episodeId)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .move(edge: .top).combined(with: .opacity)))
                // One line each, so the card keeps its height when the count changes.
                Text(card.remaining == 1 ? "noch 1 Folge" : "noch \(card.remaining) Folgen")
                    .contentTransition(.numericText(value: Double(card.remaining)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let link = card.watchLink, let url = URL(string: link.url) {
                    Button(link.label) { openURL(url) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
            .clipped()
            .animation(.snappy(duration: 0.4), value: card.next.episodeId)
            Spacer()
            Button(action: onWatched) {
                ZStack {
                    Text("Gesehen").opacity(busy ? 0 : 1)
                    if busy { ProgressView().controlSize(.small) }
                }
                .animation(.easeInOut(duration: 0.2), value: busy)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.green)
            .disabled(busy)
        }
    }
}

/// Screens reached from Start only.
enum StartDestination: Hashable {
    case upcoming
}
