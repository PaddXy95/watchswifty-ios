import Observation
import OpenAPIRuntime
import WatchSwiftyClient

/// „Bibliothek“: every title with a watch, rating or comment; filter and order as in the web.
@MainActor @Observable
public final class LibraryStore {
    public enum Filter: String, CaseIterable, Sendable {
        case all, tv, movie, hidden
        public var label: String {
            switch self {
            case .all: "Alle"
            case .tv: "Serien"
            case .movie: "Filme"
            case .hidden: "Ausgeblendet"
            }
        }
    }

    public enum Sort: String, CaseIterable, Sendable {
        case recent, rating, name
        public var label: String {
            switch self {
            case .recent: "Zuletzt gesehen"
            case .rating: "Bewertung"
            case .name: "Name"
            }
        }
    }

    public private(set) var filter = Filter.all
    public private(set) var sort = Sort.recent
    /// Only titles with this genre (`nil` = all genres).
    public private(set) var genre: GenreValue?
    public private(set) var entries = Loadable<[Components.Schemas.LibraryEntry]>()
    /// Genres for the filter: those of the titles seen in loads without a genre (the API has no list of its own; the
    /// web offers the genres of the whole library). Empty on servers without genres, so the filter stays hidden.
    public private(set) var availableGenres: [GenreValue] = []

    @ObservationIgnored private let api: any APIProtocol
    @ObservationIgnored private let app: AppModel

    public init(api: any APIProtocol, app: AppModel) {
        self.api = api
        self.app = app
    }

    public func set(filter: Filter, sort: Sort) async {
        self.filter = filter
        self.sort = sort
        await load()
    }

    public func set(genre: GenreValue?) async {
        self.genre = genre
        await load()
    }

    public func load() async {
        entries.begin()
        let version = app.changeVersion
        let (filter, genre) = (filter, genre)
        let query = Operations.getLibrary.Input.Query(filter: .init(rawValue: filter.rawValue), sort: .init(rawValue: sort.rawValue),
                                                      genre: genre)
        let api = api
        guard let result = await runCatching({ try await api.getLibrary(query: query).ok.body.json }) else { return entries.cancel() }
        entries.finish(result, at: version)
        if genre == nil, case .success(let titles) = result {
            let found = titles.flatMap { $0.genres ?? [] }
            // „Alle“ covers every visible title, so it replaces the list; the other filters only add (hidden titles).
            availableGenres = GenreValue.sortedByName(filter == .all ? found : availableGenres + found)
        }
    }

    public func reloadIfStale() async {
        if entries.isStale(app.changeVersion), !entries.isLoading { await load() }
    }
}

/// „Statistik“ for a year (`nil` = the server's default period).
@MainActor @Observable
public final class StatsStore {
    public private(set) var year: Int?
    public private(set) var stats = Loadable<Components.Schemas.Stats>()

    @ObservationIgnored private let api: any APIProtocol
    @ObservationIgnored private let app: AppModel

    public init(api: any APIProtocol, app: AppModel) {
        self.api = api
        self.app = app
    }

    public func select(year: Int?) async {
        self.year = year
        await load()
    }

    public func load() async {
        stats.begin()
        let version = app.changeVersion
        let year = year
        let api = api
        guard let result = await runCatching({ try await api.getStats(query: .init(year: year)).ok.body.json }) else {
            return stats.cancel()
        }
        stats.finish(result, at: version)
    }

    public func reloadIfStale() async {
        if stats.isStale(app.changeVersion), !stats.isLoading { await load() }
    }
}
