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
        await mutate { try await $0.setSeriesComment(path: .init(tmdbID: self.tmdbID), body: .json(.init(comment: comment))).ok.body.json }
    }

    public func setSeasonComment(season: Int, text: String) async {
        await mutate {
            try await $0.setSeasonComment(path: .init(tmdbID: self.tmdbID, season: season), body: .json(.init(comment: text))).ok.body.json
        }
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
