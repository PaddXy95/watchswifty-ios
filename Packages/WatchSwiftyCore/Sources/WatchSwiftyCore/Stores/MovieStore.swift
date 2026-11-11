import Observation
import OpenAPIRuntime
import WatchSwiftyClient

/// One movie: details, watches, rating and comment. Every change answers with the whole movie.
@MainActor @Observable
public final class MovieStore {
    public let tmdbID: Int
    public private(set) var detail = Loadable<Components.Schemas.MovieDetail>()
    public private(set) var busy = false
    public var actionError: UserFacingError?

    @ObservationIgnored private let api: any APIProtocol
    @ObservationIgnored private let app: AppModel

    public init(tmdbID: Int, api: any APIProtocol, app: AppModel) {
        self.tmdbID = tmdbID
        self.api = api
        self.app = app
    }

    public func load() async {
        detail.begin()
        let version = app.changeVersion
        guard let result = await runCatching({ try await self.api.getMovie(path: .init(tmdbID: self.tmdbID)).ok.body.json }) else {
            return detail.cancel()
        }
        detail.finish(result, at: version)
    }

    public func reloadIfStale() async {
        if detail.isStale(app.changeVersion), !detail.isLoading { await load() }
    }

    public func mark(choice: WatchChoice) async {
        await mutate { try await $0.markMovie(path: .init(tmdbID: self.tmdbID), body: .json(choice.input)).ok.body.json }
    }

    public func unmark() async {
        await mutate { try await $0.unmarkMovie(path: .init(tmdbID: self.tmdbID)).ok.body.json }
    }

    public func setRating(_ rating: Int?) async {
        await mutate { try await $0.setMovieRating(path: .init(tmdbID: self.tmdbID), body: .json(.init(rating: rating))).ok.body.json }
    }

    public func setComment(_ comment: String) async {
        while busy { try? await Task.sleep(for: .milliseconds(20)) }   // never drop a comment (see SeriesStore)
        await mutate { try await $0.setMovieComment(path: .init(tmdbID: self.tmdbID), body: .json(.init(comment: comment))).ok.body.json }
    }

    private func mutate(_ operation: @escaping (any APIProtocol) async throws -> Components.Schemas.MovieDetail) async {
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
