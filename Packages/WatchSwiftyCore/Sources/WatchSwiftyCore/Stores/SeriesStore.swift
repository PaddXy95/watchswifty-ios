import Observation
import OpenAPIRuntime
import WatchSwiftyClient

/// One series: details, seasons and every change the web offers on the series page. Every change answers with the
/// whole series, which replaces the shown one.
@MainActor @Observable
public final class SeriesStore {
    public let tmdbID: Int
    public private(set) var detail = Loadable<Components.Schemas.SeriesDetail>()
    /// A change is running; further changes are ignored until it is done (no double marking).
    public private(set) var busy = false
    public var actionError: UserFacingError?

    @ObservationIgnored private let api: any APIProtocol
    @ObservationIgnored private let app: AppModel

    public init(tmdbID: Int, api: any APIProtocol, app: AppModel) {
        self.tmdbID = tmdbID
        self.api = api
        self.app = app
    }

    private var path: Operations.getSeries.Input.Path { .init(tmdbID: tmdbID) }

    /// Seasons shown open when the page appears: the first season with an aired, unwatched episode; when everything
    /// aired is watched, the season still airing; a finished series starts collapsed.
    public nonisolated static func initiallyExpanded(_ detail: Components.Schemas.SeriesDetail) -> Set<Int> {
        // Season 0 holds TMDB's specials: always collapsed, never the season to continue with.
        let regular = detail.seasons.filter { $0.number != 0 }
        // The server's choice (season of the next episode) when it sends one; own rule only for older servers.
        if detail.seasons.contains(where: { $0.isOpen != nil }) {
            return Set(regular.filter { $0.isOpen == true }.map(\.number))
        }
        if let next = regular.first(where: { season in season.episodes.contains { $0.aired && $0.watches.isEmpty } }) {
            return [next.number]
        }
        if let running = regular.first(where: { season in season.episodes.contains { !$0.aired } }) {
            return [running.number]
        }
        return []
    }

    public func load() async {
        detail.begin()
        let version = app.changeVersion
        guard let result = await runCatching({ try await self.api.getSeries(path: self.path).ok.body.json }) else {
            return detail.cancel()
        }
        detail.finish(result, at: version)
    }

    public func reloadIfStale() async {
        if detail.isStale(app.changeVersion), !detail.isLoading { await load() }
    }

    /// „Gesehen“ on the next episode the server names (`detail.next`); the answer is a start card, so the series is
    /// reloaded afterwards.
    public func markNext() async {
        guard !busy, let next = detail.value?.next else { return }
        busy = true
        defer { busy = false }
        let api = api
        let tmdbID = tmdbID
        guard let result = await runCatching({
            _ = try await api.markNextEpisode(path: .init(tmdbID: tmdbID), body: .json(.init(episodeId: next.episodeId)))
        }) else { return }
        switch result {
        case .success:
            app.didChange()
            await load()
        case .failure(let error):
            actionError = error
        }
    }

    public func markEpisode(season: Int, number: Int, choice: WatchChoice) async {
        await mutate { try await $0.markEpisode(path: .init(tmdbID: self.tmdbID, season: season, number: number),
                                                body: .json(choice.input)).ok.body.json }
    }

    /// „Löschen“ on one viewing in the episode details (as in the web, which no longer deletes all of an episode's
    /// viewings at once). The answer has no body, so the series is reloaded afterwards.
    public func deleteWatch(id: String) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let api = api
        guard let result = await runCatching({ _ = try await api.deleteWatch(path: .init(id: id)).noContent }) else { return }
        switch result {
        case .success:
            app.didChange()
            await load()
        case .failure(let error):
            actionError = error
        }
    }

    // The undated marks below send an empty `WatchInput` (`{}`) although the body is optional: behind a reverse proxy
    // a POST without a body can arrive as an empty body, which the server cannot read as JSON.

    public func markUpTo(season: Int, number: Int) async {
        await mutate {
            try await $0.markUpTo(path: .init(tmdbID: self.tmdbID, season: season, number: number), body: .json(.init())).ok.body.json
        }
    }

    /// „Ganze Staffel gesehen“: every aired episode of the season not watched yet, undated, with `service`. With
    /// `rewatch` („Ganze Staffel erneut gesehen“) the server adds a new round instead: one more undated watch for every
    /// aired episode behind the highest watch count (all of them when they are level).
    public func markSeason(_ season: Int, service: ServiceChoice = .lastUsed, rewatch: Bool = false) async {
        let body = WatchChoice(service: service, rewatch: rewatch).input
        await mutate { try await $0.markSeason(path: .init(tmdbID: self.tmdbID, season: season), body: .json(body)).ok.body.json }
    }

    /// „Gesamte Serie gesehen“: every aired regular episode not watched yet, undated, with `service`; with `rewatch`
    /// („Gesamte Serie erneut gesehen“) a new round, as for a season.
    public func markAll(service: ServiceChoice = .lastUsed, rewatch: Bool = false) async {
        let body = WatchChoice(service: service, rewatch: rewatch).input
        await mutate { try await $0.markSeries(path: .init(tmdbID: self.tmdbID), body: .json(body)).ok.body.json }
    }

    /// Every aired episode of the season is watched (and there is one): the button reads „Ganze Staffel erneut
    /// gesehen“ and marks a new round, as in the web.
    public nonisolated static func fullyWatched(_ season: Components.Schemas.Season) -> Bool {
        allWatched(season.episodes)
    }

    /// Every aired regular episode (season ≥ 1) is watched: „Gesamte Serie erneut gesehen“.
    public nonisolated static func fullyWatched(_ detail: Components.Schemas.SeriesDetail) -> Bool {
        allWatched(detail.seasons.filter { $0.number > 0 }.flatMap(\.episodes))
    }

    private nonisolated static func allWatched(_ episodes: [Components.Schemas.Episode]) -> Bool {
        let aired = episodes.filter(\.aired)
        return !aired.isEmpty && aired.allSatisfy { !$0.watches.isEmpty }
    }

    /// Preselected service for a whole season or series: the one last used for the series, else „Ohne Dienst“ (as in
    /// the web).
    public nonisolated static func bulkServicePreset(_ detail: Components.Schemas.SeriesDetail) -> ServiceChoice {
        detail.lastService.map { .service($0) } ?? .none
    }

    public func setHidden(_ hidden: Bool) async {
        await mutate { try await $0.setHidden(path: .init(tmdbID: self.tmdbID), body: .json(.init(hidden: hidden))).ok.body.json }
    }

    public func setFollowed(_ followed: Bool) async {
        await mutate { try await $0.setFollowed(path: .init(tmdbID: self.tmdbID), body: .json(.init(followed: followed))).ok.body.json }
    }

    /// `nil` removes the rating.
    public func setRating(_ rating: Int?) async {
        await mutate { try await $0.setSeriesRating(path: .init(tmdbID: self.tmdbID), body: .json(.init(rating: rating))).ok.body.json }
    }

    public func setComment(_ comment: String) async {
        await waitUntilIdle()
        await mutate { try await $0.setSeriesComment(path: .init(tmdbID: self.tmdbID), body: .json(.init(comment: comment))).ok.body.json }
    }

    public func setSeasonComment(season: Int, text: String) async {
        await waitUntilIdle()
        await mutate {
            try await $0.setSeasonComment(path: .init(tmdbID: self.tmdbID, season: season), body: .json(.init(comment: text))).ok.body.json
        }
    }

    /// A comment must not be dropped by the double-tap guard: it waits for a running change instead.
    private func waitUntilIdle() async {
        while busy { try? await Task.sleep(for: .milliseconds(20)) }
    }

    private func mutate(_ operation: @escaping (any APIProtocol) async throws -> Components.Schemas.SeriesDetail) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let api = api
        guard let result = await runCatching({ try await operation(api) }) else { return }
        switch result {
        case .success(let updated):
            app.didChange()
            detail.value = updated
            detail.loadedAt = app.changeVersion
        case .failure(let error):
            actionError = error
        }
    }
}
