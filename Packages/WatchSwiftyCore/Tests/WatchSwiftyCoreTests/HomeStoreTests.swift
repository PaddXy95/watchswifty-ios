import Foundation
import Testing
import WatchSwiftyClient
@testable import WatchSwiftyCore

@MainActor @Suite struct HomeStoreTests {
    nonisolated static let episodeID = "0F2B4D63-8E57-4E0A-9C5B-3B1E2D4F5A6B"

    nonisolated static func card(_ id: Int, _ name: String, episode: Int) -> String {
        #"""
        {"tmdbId":\#(id),"name":"\#(name)","next":{"episodeId":"\#(episodeID)","season":2,"number":\#(episode),"name":"Folge \#(episode)"},
         "remaining":6,"lastService":"netflix","watchLink":{"label":"Netflix","url":"https://www.netflix.com/title/1"}}
        """#
    }

    nonisolated static func cards(_ cards: String...) -> String { #"{"cards":[\#(cards.joined(separator: ","))],"olderCount":2}"# }

    nonisolated static let notes = #"""
    {"newEpisodes":[{"tmdbId":3,"name":"Andor","count":2,"first":{"episodeId":"\#(episodeID)","season":2,"number":1,"name":"Eins"}}],
     "upcoming":[]}
    """#

    func setUp(_ transport: FakeTransport) {
        transport.on(.get, "/api/v1/continue-watching", json: 200, Self.cards(Self.card(1, "Severance", episode: 4)))
        transport.on(.get, "/api/v1/notes", json: 200, Self.notes)
    }

    func snapshot() -> SnapshotCache {
        SnapshotCache(directory: FileManager.default.temporaryDirectory.appending(path: "home-\(UUID().uuidString)"))
    }

    @Test func homeShowsSnapshotThenFresh() async throws {
        let cache = snapshot()
        let old = try JSONDecoder().decode(Components.Schemas.ContinueWatching.self,
                                           from: Data(Self.cards(Self.card(9, "Alt", episode: 1)).utf8))
        cache.save(old)
        let transport = FakeTransport()
        setUp(transport)
        let model = await Fixtures.readyModel(transport)
        let store = HomeStore(api: model.api, app: model, snapshot: cache)
        #expect(store.cards.value?.cards.first?.name == "Alt")
        await store.load()
        #expect(store.cards.value?.cards.map(\.name) == ["Severance"])
        #expect(store.notes.value?.newEpisodes.count == 1)
    }

    @Test func snapshotSavedAfterLoad() async {
        let cache = snapshot()
        let transport = FakeTransport()
        setUp(transport)
        let model = await Fixtures.readyModel(transport)
        await HomeStore(api: model.api, app: model, snapshot: cache).load()
        #expect(cache.load()?.cards.first?.name == "Severance")
    }

    @Test func markNextReplacesCard() async {
        let transport = FakeTransport()
        setUp(transport)
        transport.on(.post, "/api/v1/tv/1/next", json: 200, Self.card(1, "Severance", episode: 5))
        let model = await Fixtures.readyModel(transport)
        let store = HomeStore(api: model.api, app: model, snapshot: snapshot())
        await store.load()
        await store.markNext(tmdbID: 1)
        #expect(store.cards.value?.cards.first?.next.number == 5)
        #expect(model.changeVersion == 1)
        #expect(Fixtures.jsonObject(transport.requests.last?.body)["episodeId"] as? String == Self.episodeID)
    }

    @Test func markNextCaughtUpRemovesCard() async {
        let transport = FakeTransport()
        setUp(transport)
        transport.on(.post, "/api/v1/tv/1/next") { _, _ in FakeTransport.empty(204) }
        let model = await Fixtures.readyModel(transport)
        let store = HomeStore(api: model.api, app: model, snapshot: snapshot())
        await store.load()
        await store.markNext(tmdbID: 1)
        #expect(store.cards.value?.cards.isEmpty == true)
    }

    @Test func markNextIgnoresSecondTapWhileInFlight() async {
        let transport = FakeTransport()
        setUp(transport)
        let gate = Gate()
        transport.on(.post, "/api/v1/tv/1/next") { _, _ in
            await gate.wait()
            return FakeTransport.json(200, Self.card(1, "Severance", episode: 5))
        }
        let model = await Fixtures.readyModel(transport)
        let store = HomeStore(api: model.api, app: model, snapshot: snapshot())
        await store.load()
        let first = Task { await store.markNext(tmdbID: 1) }
        await waitUntil { store.inFlight.contains(1) }
        await store.markNext(tmdbID: 1)
        gate.release()
        await first.value
        #expect(transport.requests.filter { $0.path == "/api/v1/tv/1/next" }.count == 1)
        #expect(store.inFlight.isEmpty)
    }

    @Test func dismissRemovesNote() async {
        let transport = FakeTransport()
        setUp(transport)
        transport.on(.post, "/api/v1/tv/3/new-episodes/dismiss") { _, _ in FakeTransport.empty(204) }
        let model = await Fixtures.readyModel(transport)
        let store = HomeStore(api: model.api, app: model, snapshot: snapshot())
        await store.load()
        await store.dismissNewEpisodes(tmdbID: 3)
        #expect(store.notes.value?.newEpisodes.isEmpty == true)
    }

    @Test func showAllRequestsOlderCards() async {
        let transport = FakeTransport()
        setUp(transport)
        let model = await Fixtures.readyModel(transport)
        let store = HomeStore(api: model.api, app: model, snapshot: snapshot())
        await store.setShowAll(true)
        #expect(transport.requests.first { $0.path == "/api/v1/continue-watching" }?.query == "all=true")
    }

    @Test func startNotEmptyWithOlderCards() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/continue-watching", json: 200, #"{"cards":[],"olderCount":4}"#)
        transport.on(.get, "/api/v1/notes", json: 200, #"{"newEpisodes":[],"upcoming":[]}"#)
        let model = await Fixtures.readyModel(transport)
        let store = HomeStore(api: model.api, app: model, snapshot: snapshot())
        await store.load()
        #expect(!store.isEmpty)
        transport.on(.get, "/api/v1/continue-watching", json: 200, #"{"cards":[],"olderCount":0}"#)
        await store.load()
        #expect(store.isEmpty)
    }

    @Test func upcomingSoonFlag() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/continue-watching", json: 200, #"{"cards":[],"olderCount":0}"#)
        transport.on(.get, "/api/v1/notes", json: 200, #"""
        {"newEpisodes":[],"upcoming":[{"tmdbId":5,"name":"Andor","count":1,
          "next":{"episodeId":"\#(Self.episodeID)","season":3,"number":1,"name":"Eins","airDate":"2026-11-13"}}]}
        """#)
        let model = await Fixtures.readyModel(transport)
        let store = HomeStore(api: model.api, app: model, snapshot: snapshot())
        await store.load()
        #expect(store.hasUpcomingSoon(today: "2026-11-11"))
        #expect(!store.hasUpcomingSoon(today: "2026-11-09"))
        #expect(store.isEmpty)   // „Demnächst“ lives behind the toolbar button, not on Start
    }
}
