import Foundation
import Testing
import WatchSwiftyClient
@testable import WatchSwiftyCore

@MainActor @Suite struct LibraryStatsTests {
    static let library = #"[{"kind":"tv","tmdbId":1,"name":"Severance","hidden":true,"rating":9}]"#
    static let period = #"{"movies":1,"series":2,"episodes":30,"minutes":1500,"unknownRuntime":0}"#
    static var stats: String {
        #"{"year":2026,"period":\#(period),"chart":[],"services":[],"topSeries":[],"total":\#(period),"undated":\#(period),"years":[],"ratings":[],"missingRuntimeTitles":0}"#
    }

    @Test func libraryPassesFilterAndSort() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/library", json: 200, Self.library)
        let model = await Fixtures.readyModel(transport)
        let store = LibraryStore(api: model.api, app: model)
        await store.set(filter: .hidden, sort: .rating)
        #expect(transport.requests.last?.query == "filter=hidden&sort=rating")
        #expect(store.entries.value?.first?.name == "Severance")
    }

    @Test func libraryGenreFilterAndChoices() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/library") { request, _ in
            let body = request.path?.contains("genre=crime") == true
                ? #"[{"kind":"tv","tmdbId":1,"name":"Severance","hidden":false,"genres":["crime"]}]"#
                : #"[{"kind":"tv","tmdbId":1,"name":"Severance","hidden":false,"genres":["crime","drama"]},{"kind":"movie","tmdbId":2,"name":"Alien","hidden":false,"genres":["science_fiction","horror","sorcery"]}]"#
            return FakeTransport.json(200, body)
        }
        let model = await Fixtures.readyModel(transport)
        let store = LibraryStore(api: model.api, app: model)
        await store.load()
        #expect(transport.requests.last?.query == "filter=all&sort=recent")
        // German order; an unknown genre from a newer server is kept and shown neutrally.
        #expect(store.availableGenres.map(\.displayName) == ["Anderes Genre", "Drama", "Horror", "Krimi", "Science-Fiction"])
        await store.set(genre: .crime)
        #expect(transport.requests.last?.query == "filter=all&sort=recent&genre=crime")
        #expect(store.entries.value?.count == 1)
        #expect(store.availableGenres.count == 5)   // a genre-filtered load keeps the choices
        await store.set(genre: nil)
        #expect(transport.requests.last?.query == "filter=all&sort=recent")
    }

    @Test func libraryWithoutGenresFromOlderServer() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/library", json: 200, Self.library)
        let model = await Fixtures.readyModel(transport)
        let store = LibraryStore(api: model.api, app: model)
        await store.load()
        #expect(store.entries.value?.first?.genres == nil)
        #expect(store.availableGenres.isEmpty)
    }

    @Test func statsReadsNewListsAndStaysCompatible() async {
        let transport = FakeTransport()
        let full = Self.stats.replacingOccurrences(of: #""services":[]"#, with: #"""
        "services":[{"service":"netflix","minutes":120,"episodes":3,"movies":1}],
        "longestMovies":[{"tmdbId":2,"name":"Alien","watches":2,"minutes":234}],
        "mostWatchedMovies":[{"tmdbId":2,"name":"Alien","watches":2,"minutes":234,"rating":8}],
        "mostWatchedEpisodes":[{"tmdbId":1,"seriesName":"Severance","season":1,"number":2,"name":"Half Loop","watches":3}],
        "mostCompletedSeries":[{"tmdbId":1,"name":"Severance","completions":2}],
        "genres":[{"genre":"drama","seriesMinutes":90,"movieMinutes":0,"series":1,"movies":0}]
        """#)
        transport.on(.get, "/api/v1/stats", json: 200, full)
        let model = await Fixtures.readyModel(transport)
        let store = StatsStore(api: model.api, app: model)
        await store.load()
        let stats = store.stats.value
        #expect(stats?.services.first?.episodes == 3)
        #expect(stats?.longestMovies?.first?.minutes == 234)
        #expect(stats?.mostWatchedMovies?.first?.rating == 8)
        #expect(stats?.mostWatchedEpisodes?.first?.name == "Half Loop")
        #expect(stats?.mostCompletedSeries?.first?.completions == 2)
        #expect(stats?.genres?.first?.genre == .drama)

        transport.on(.get, "/api/v1/stats", json: 200, Self.stats)   // 0.4 server: none of the new lists
        await store.load()
        #expect(store.stats.value?.genres == nil)
        #expect(store.stats.value?.longestMovies == nil)
    }

    @Test func libraryLabelsMatchWeb() {
        #expect(LibraryStore.Filter.allCases.map(\.label) == ["Alle", "Serien", "Filme", "Ausgeblendet"])
        #expect(LibraryStore.Sort.allCases.map(\.label) == ["Zuletzt gesehen", "Bewertung", "Name"])
    }

    @Test func statsLoadsSelectedYear() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/stats", json: 200, Self.stats)
        let model = await Fixtures.readyModel(transport)
        let store = StatsStore(api: model.api, app: model)
        await store.select(year: 2025)
        #expect(transport.requests.last?.query == "year=2025")
        #expect(store.stats.value?.period.episodes == 30)
        await store.select(year: nil)
        #expect(transport.requests.last?.query == nil)
    }
}
