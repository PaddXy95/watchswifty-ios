import Foundation
import HTTPTypes
import Testing
import WatchSwiftyClient
@testable import WatchSwiftyCore

@MainActor @Suite struct SeriesStoreTests {
    @Test func loadShowsDetail() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/tv/1", json: 200, Fixtures.series())
        let model = await Fixtures.readyModel(transport)
        let store = SeriesStore(tmdbID: 1, api: model.api, app: model)
        await store.load()
        #expect(store.detail.value?.name == "Severance")
        #expect(!store.detail.isStale(model.changeVersion))
    }

    @Test func seriesMutationReplacesDetail() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/tv/1", json: 200, Fixtures.series())
        transport.on(.post, "/api/v1/tv/1/episodes/1/1/watch", json: 200, Fixtures.series(watched: true))
        let model = await Fixtures.readyModel(transport)
        let store = SeriesStore(tmdbID: 1, api: model.api, app: model)
        await store.load()
        await store.markEpisode(season: 1, number: 1, choice: WatchChoice())
        #expect(store.detail.value?.seasons[0].watchedCount == 1)
        #expect(model.changeVersion == 1)
        #expect(!store.detail.isStale(model.changeVersion))
    }

    @Test func markEpisodeSendsChoice() async {
        let transport = FakeTransport()
        transport.on(.post, "/api/v1/tv/1/episodes/1/1/watch", json: 200, Fixtures.series(watched: true))
        let model = await Fixtures.readyModel(transport)
        let store = SeriesStore(tmdbID: 1, api: model.api, app: model)
        await store.markEpisode(season: 1, number: 1,
                                choice: WatchChoice(day: "2026-11-07", service: .service(.netflix), rewatch: true))
        let body = Fixtures.jsonObject(transport.requests.last?.body)
        #expect(body["day"] as? String == "2026-11-07")
        #expect(body["service"] as? String == "netflix")
        #expect(body["rewatch"] as? Bool == true)
    }

    @Test func noServiceSendsUnknown() {
        #expect(WatchChoice(service: .none).input.service?.rawValue == "unknown")
        #expect(WatchChoice(service: .lastUsed).input.service == nil)
        #expect(WatchChoice().input.rewatch == nil)
    }

    @Test func unknownServiceChoiceIsOmitted() {
        #expect(WatchChoice(service: .service(ServiceValue(rawValue: "crunchyroll"))).input.service == nil)
    }

    @Test func mutationErrorKeepsDetail() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/tv/1", json: 200, Fixtures.series())
        transport.on(.put, "/api/v1/tv/1/rating", json: 422, Fixtures.error("validation", "Bewertung von 1 bis 10."))
        let model = await Fixtures.readyModel(transport)
        let store = SeriesStore(tmdbID: 1, api: model.api, app: model)
        await store.load()
        await store.setRating(11)
        #expect(store.actionError?.message == "Bewertung von 1 bis 10.")
        #expect(store.detail.value?.rating == nil)
        #expect(model.changeVersion == 0)
    }

    @Test func secondMutationWhileBusyIgnored() async {
        let transport = FakeTransport()
        let gate = Gate()
        transport.on(.post, "/api/v1/tv/1/watch-all") { _, _ in
            await gate.wait()
            return FakeTransport.json(200, Fixtures.series(watched: true))
        }
        let model = await Fixtures.readyModel(transport)
        let store = SeriesStore(tmdbID: 1, api: model.api, app: model)
        let first = Task { await store.markAll() }
        await waitUntil { store.busy }
        await store.markAll()
        gate.release()
        await first.value
        #expect(transport.requests.filter { $0.path == "/api/v1/tv/1/watch-all" }.count == 1)
    }

    @Test func otherMutationsUseTheirRoutes() async {
        let transport = FakeTransport()
        for (method, path): (HTTPRequest.Method, String) in [(.post, "/api/v1/tv/1/episodes/1/1/watch-up-to"), (.post, "/api/v1/tv/1/seasons/1/watch"),
                               (.put, "/api/v1/tv/1/hidden"), (.put, "/api/v1/tv/1/follow"), (.put, "/api/v1/tv/1/comment"),
                               (.put, "/api/v1/tv/1/seasons/1/comment")] {
            transport.on(method, path, json: 200, Fixtures.series(watched: true))
        }
        let model = await Fixtures.readyModel(transport)
        let store = SeriesStore(tmdbID: 1, api: model.api, app: model)
        await store.markUpTo(season: 1, number: 1)
        await store.markSeason(1)
        await store.setHidden(true)
        await store.setFollowed(false)
        await store.setComment("Gut")
        await store.setSeasonComment(season: 1, text: "Stark")
        #expect(store.actionError == nil)
        #expect(model.changeVersion == 6)
        #expect(Fixtures.jsonObject(transport.requests.last?.body)["comment"] as? String == "Stark")
    }

    @Test func seasonAndSeriesSendTheChosenService() async {
        let transport = FakeTransport()
        for path in ["/api/v1/tv/1/seasons/2/watch", "/api/v1/tv/1/watch-all"] {
            transport.on(.post, path, json: 200, Fixtures.series(watched: true))
        }
        let model = await Fixtures.readyModel(transport)
        let store = SeriesStore(tmdbID: 1, api: model.api, app: model)
        await store.markSeason(2, service: .service(.disneyPlus))
        #expect(Fixtures.jsonObject(transport.requests.last?.body) as NSDictionary == ["service": "disney_plus"])
        await store.markAll(service: .none)
        #expect(Fixtures.jsonObject(transport.requests.last?.body) as NSDictionary == ["service": "unknown"])
        #expect(store.actionError == nil)
    }

    @Test func seasonAndSeriesRewatchSendTheFlag() async {
        let transport = FakeTransport()
        for path in ["/api/v1/tv/1/seasons/1/watch", "/api/v1/tv/1/watch-all"] {
            transport.on(.post, path, json: 200, Fixtures.series(watched: true))
        }
        let model = await Fixtures.readyModel(transport)
        let store = SeriesStore(tmdbID: 1, api: model.api, app: model)
        await store.markSeason(1, service: .service(.netflix), rewatch: true)
        #expect(Fixtures.jsonObject(transport.requests.last?.body) as NSDictionary == ["service": "netflix", "rewatch": true])
        await store.markAll(service: .none, rewatch: true)
        #expect(Fixtures.jsonObject(transport.requests.last?.body) as NSDictionary == ["service": "unknown", "rewatch": true])
        #expect(store.actionError == nil)
    }

    /// Like the web: „erneut gesehen“ once every aired episode is watched; episodes not aired yet do not count, and a
    /// season without aired episodes is never fully watched. Specials (season 0) do not count for the series.
    @Test func fullyWatchedCountsAiredEpisodesOnly() throws {
        func episode(_ number: Int, aired: Bool, watched: Bool) -> String {
            let watches = watched ? #"[{"id":"0F2B4D63-8E57-4E0A-9C5B-3B1E2D4F5A6\#(number)","origin":"manual"}]"# : "[]"
            return #"{"season":1,"number":\#(number),"name":"E\#(number)","aired":\#(aired),"watches":\#(watches)}"#
        }
        func season(_ number: Int, _ episodes: [String]) -> String {
            #"{"number":\#(number),"title":"S\#(number)","watchedCount":0,"episodes":[\#(episodes.joined(separator: ","))]}"#
        }
        func detail(_ seasons: [String]) throws -> Components.Schemas.SeriesDetail {
            let json = #"{"tmdbId":1,"name":"X","links":{"tmdb":"","imdb":"","rottenTomatoes":""},"hidden":false,"followed":false,"seasons":[\#(seasons.joined(separator: ","))]}"#
            return try JSONDecoder().decode(Components.Schemas.SeriesDetail.self, from: Data(json.utf8))
        }
        let done = try detail([season(0, [episode(1, aired: true, watched: false)]),
                               season(1, [episode(1, aired: true, watched: true), episode(2, aired: false, watched: false)])])
        #expect(SeriesStore.fullyWatched(done))
        #expect(!SeriesStore.fullyWatched(done.seasons[0]))
        #expect(SeriesStore.fullyWatched(done.seasons[1]))
        let open = try detail([season(1, [episode(1, aired: true, watched: true), episode(2, aired: true, watched: false)])])
        #expect(!SeriesStore.fullyWatched(open))
        #expect(!SeriesStore.fullyWatched(open.seasons[0]))
        let upcoming = try detail([season(1, [episode(1, aired: false, watched: false)])])
        #expect(!SeriesStore.fullyWatched(upcoming))
        #expect(!SeriesStore.fullyWatched(upcoming.seasons[0]))
    }

    /// One viewing goes, not all of the episode's; the series is read again (the delete answers without a body).
    @Test func deleteWatchRemovesOneViewingAndReloads() async {
        let transport = FakeTransport()
        let watchID = "0F2B4D63-8E57-4E0A-9C5B-3B1E2D4F5A6B"
        let deleted = Counter()
        transport.on(.get, "/api/v1/tv/1") { _, _ in FakeTransport.json(200, Fixtures.series(watched: deleted.value == 0)) }
        transport.on(.delete, "/api/v1/watches/\(watchID)") { _, _ in
            deleted.increment()
            return FakeTransport.empty(204)
        }
        let model = await Fixtures.readyModel(transport)
        let store = SeriesStore(tmdbID: 1, api: model.api, app: model)
        await store.load()
        await store.deleteWatch(id: watchID)
        #expect(deleted.value == 1)
        #expect(store.actionError == nil)
        #expect(store.detail.value?.seasons.first?.episodes.first?.watches.isEmpty == true)
        #expect(model.changeVersion == 1)
        #expect(!transport.requests.contains { $0.path == "/api/v1/tv/1/episodes/1/1/watch" })
    }

    @Test func bulkServicePresetIsTheLastUsedService() throws {
        let decoder = JSONDecoder()
        let withService = try decoder.decode(Components.Schemas.SeriesDetail.self, from: Data(Fixtures.series(watched: true, service: "wow").utf8))
        #expect(SeriesStore.bulkServicePreset(withService) == .service(.wow))
        var without = withService
        without.lastService = nil
        #expect(SeriesStore.bulkServicePreset(without) == ServiceChoice.none)
    }

    /// Behind a reverse proxy a POST without a body can reach the server as an empty body, which the server then fails
    /// to read as JSON („The given data was not valid JSON“). Marks without a date therefore always send `{}`.
    @Test func undatedMarksSendAnEmptyJSONObject() async throws {
        let transport = FakeTransport()
        for path in ["/api/v1/tv/1/seasons/1/watch", "/api/v1/tv/1/watch-all", "/api/v1/tv/1/episodes/1/1/watch-up-to"] {
            transport.on(.post, path, json: 200, Fixtures.series(watched: true))
        }
        let model = await Fixtures.readyModel(transport)
        let store = SeriesStore(tmdbID: 1, api: model.api, app: model)
        await store.markSeason(1)
        await store.markAll()
        await store.markUpTo(season: 1, number: 1)
        #expect(store.actionError == nil)
        let marks = transport.requests.filter { $0.method == .post }
        #expect(marks.map(\.path) == ["/api/v1/tv/1/seasons/1/watch", "/api/v1/tv/1/watch-all",
                                      "/api/v1/tv/1/episodes/1/1/watch-up-to"])
        for mark in marks {
            let body = try #require(mark.body, "\(mark.path) sends no body")
            #expect((try JSONSerialization.jsonObject(with: body) as? [String: Any])?.isEmpty == true, "\(mark.path)")
            #expect(mark.request.headerFields[.contentType]?.hasPrefix("application/json") == true, "\(mark.path)")
        }
    }

    @Test func quickChoiceRewatchesWatchedEpisode() {
        #expect(WatchChoice.quick(alreadyWatched: true).input.rewatch == true)
        #expect(WatchChoice.quick(alreadyWatched: false).input.rewatch == nil)
    }

    @Test func commentSaveWaitsForRunningMutation() async {
        let transport = FakeTransport()
        let gate = Gate()
        transport.on(.post, "/api/v1/tv/1/watch-all") { _, _ in
            await gate.wait()
            return FakeTransport.json(200, Fixtures.series(watched: true))
        }
        transport.on(.put, "/api/v1/tv/1/seasons/1/comment", json: 200, Fixtures.series(watched: true))
        let model = await Fixtures.readyModel(transport)
        let store = SeriesStore(tmdbID: 1, api: model.api, app: model)
        let mark = Task { await store.markAll() }
        await waitUntil { store.busy }
        let comment = Task { await store.setSeasonComment(season: 1, text: "Stark") }
        gate.release()
        await mark.value
        await comment.value
        #expect(transport.requests.contains { $0.path == "/api/v1/tv/1/seasons/1/comment" })
    }

    @Test func markNextSendsEpisodeIdAndReloads() async {
        let transport = FakeTransport()
        let loads = Counter()
        transport.on(.get, "/api/v1/tv/1") { _, _ in
            loads.increment()
            return FakeTransport.json(200, Fixtures.series(watched: loads.value > 1, next: loads.value == 1))
        }
        transport.on(.post, "/api/v1/tv/1/next") { _, _ in FakeTransport.empty(204) }
        let model = await Fixtures.readyModel(transport)
        let store = SeriesStore(tmdbID: 1, api: model.api, app: model)
        await store.load()
        #expect(store.detail.value?.next?.number == 2)
        await store.markNext()
        let body = Fixtures.jsonObject(transport.requests.first { $0.path == "/api/v1/tv/1/next" }?.body)
        #expect(body["episodeId"] as? String == "11111111-0000-0000-0000-000000000002")
        #expect(loads.value == 2)
        #expect(store.detail.value?.next == nil)
        #expect(model.changeVersion == 1)
    }
}
