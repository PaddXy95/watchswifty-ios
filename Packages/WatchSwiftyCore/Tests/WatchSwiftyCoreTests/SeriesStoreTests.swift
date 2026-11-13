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
        for (method, path): (HTTPRequest.Method, String) in [(.delete, "/api/v1/tv/1/episodes/1/1/watch"),
                               (.post, "/api/v1/tv/1/episodes/1/1/watch-up-to"), (.post, "/api/v1/tv/1/seasons/1/watch"),
                               (.put, "/api/v1/tv/1/hidden"), (.put, "/api/v1/tv/1/follow"), (.put, "/api/v1/tv/1/comment"),
                               (.put, "/api/v1/tv/1/seasons/1/comment")] {
            transport.on(method, path, json: 200, Fixtures.series(watched: true))
        }
        let model = await Fixtures.readyModel(transport)
        let store = SeriesStore(tmdbID: 1, api: model.api, app: model)
        await store.unmarkEpisode(season: 1, number: 1)
        await store.markUpTo(season: 1, number: 1)
        await store.markSeason(1)
        await store.setHidden(true)
        await store.setFollowed(false)
        await store.setComment("Gut")
        await store.setSeasonComment(season: 1, text: "Stark")
        #expect(store.actionError == nil)
        #expect(model.changeVersion == 7)
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
