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
    public private(set) var entries = Loadable<[Components.Schemas.LibraryEntry]>()

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

    public func load() async {
        entries.begin()
        let version = app.changeVersion
        let query = Operations.getLibrary.Input.Query(filter: .init(rawValue: filter.rawValue), sort: .init(rawValue: sort.rawValue))
        let api = api
        guard let result = await runCatching({ try await api.getLibrary(query: query).ok.body.json }) else { return entries.cancel() }
        entries.finish(result, at: version)
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
