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

    public func unmarkEpisode(season: Int, number: Int) async {
        await mutate { try await $0.unmarkEpisode(path: .init(tmdbID: self.tmdbID, season: season, number: number)).ok.body.json }
    }

    public func markUpTo(season: Int, number: Int) async {
        await mutate { try await $0.markUpTo(path: .init(tmdbID: self.tmdbID, season: season, number: number)).ok.body.json }
    }

    public func markSeason(_ season: Int) async {
        await mutate { try await $0.markSeason(path: .init(tmdbID: self.tmdbID, season: season)).ok.body.json }
    }

    public func markAll() async {
        await mutate { try await $0.markSeries(path: .init(tmdbID: self.tmdbID)).ok.body.json }
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
