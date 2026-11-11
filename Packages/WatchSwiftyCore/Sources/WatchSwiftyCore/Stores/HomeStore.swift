import Observation
import OpenAPIRuntime
import WatchSwiftyClient

/// Start page: „Weiterschauen“ cards, „Neue Folgen“ and „Demnächst“.
@MainActor @Observable
public final class HomeStore {
    public private(set) var cards: Loadable<Components.Schemas.ContinueWatching>
    public private(set) var notes = Loadable<Components.Schemas.Notes>()
    /// Also series paused for more than 3 months (`all=true`).
    public private(set) var showAll = false
    /// Cards whose „Gesehen“ request is running; a second tap is ignored (no double marking).
    public private(set) var inFlight: Set<Int> = []
    public var actionError: UserFacingError?

    @ObservationIgnored private let api: any APIProtocol
    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private let snapshot: SnapshotCache

    public init(api: any APIProtocol, app: AppModel, snapshot: SnapshotCache) {
        self.api = api
        self.app = app
        self.snapshot = snapshot
        cards = Loadable(value: snapshot.load())
    }

    public func load() async {
        cards.begin()
        notes.begin()
        let version = app.changeVersion
        let all = showAll
        async let cardsResult = runCatching { try await self.api.getContinueWatching(query: .init(all: all ? true : nil)).ok.body.json }
        async let notesResult = runCatching { try await self.api.getNotes().ok.body.json }
        if let result = await cardsResult {
            cards.finish(result, at: version)
            if case .success(let value) = result, !all { snapshot.save(value) }
        } else {
            cards.cancel()
        }
        if let result = await notesResult { notes.finish(result, at: version) } else { notes.cancel() }
    }

    public func reloadIfStale() async {
        if cards.isStale(app.changeVersion), !cards.isLoading { await load() }
    }

    public func setShowAll(_ value: Bool) async {
        showAll = value
        await load()
    }

    /// „Gesehen“ on a card: marks the episode the card shows (the server ignores a stale `episodeId`).
    public func markNext(tmdbID: Int) async {
        guard !inFlight.contains(tmdbID), let card = cards.value?.cards.first(where: { $0.tmdbId == tmdbID }) else { return }
        inFlight.insert(tmdbID)
        defer { inFlight.remove(tmdbID) }
        let api = api
        let result = await runCatching { () -> Components.Schemas.ContinueCard? in
            switch try await api.markNextEpisode(path: .init(tmdbID: tmdbID), body: .json(.init(episodeId: card.next.episodeId))) {
            case .ok(let ok): return try ok.body.json
            case .noContent: return nil
            default: throw UserFacingError.unexpected(status: 0)
            }
        }
        guard let result else { return }
        switch result {
        case .success(let updated):
            app.didChange()
            if var value = cards.value, let index = value.cards.firstIndex(where: { $0.tmdbId == tmdbID }) {
                if let updated { value.cards[index] = updated } else { value.cards.remove(at: index) }
                cards.value = value
                cards.loadedAt = app.changeVersion
                if !showAll { snapshot.save(value) }
            }
        case .failure(let error):
            actionError = error
        }
    }

    /// „Ausblenden“ on a „Neue Folgen“ note.
    public func dismissNewEpisodes(tmdbID: Int) async {
        let api = api
        guard let result = await runCatching({ _ = try await api.dismissNewEpisodes(path: .init(tmdbID: tmdbID)) }) else { return }
        switch result {
        case .success:
            if var value = notes.value {
                value.newEpisodes.removeAll { $0.tmdbId == tmdbID }
                notes.value = value
            }
        case .failure(let error):
            actionError = error
        }
    }
}
