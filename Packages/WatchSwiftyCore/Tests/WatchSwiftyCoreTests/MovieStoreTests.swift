import Foundation
import Testing
import WatchSwiftyClient
@testable import WatchSwiftyCore

@MainActor @Suite struct MovieStoreTests {
    nonisolated static func movie(watched: Bool) -> String {
        let watches = watched ? #"[{"id":"0F2B4D63-8E57-4E0A-9C5B-3B1E2D4F5A6B","day":"2026-11-07","service":"cinema","origin":"manual"}]"# : "[]"
        return #"{"tmdbId":2,"name":"Dune","links":{"tmdb":"t","imdb":"i","rottenTomatoes":"r"},"watches":\#(watches)}"#
    }

    @Test func movieMarkReplacesDetail() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/movies/2", json: 200, Self.movie(watched: false))
        transport.on(.post, "/api/v1/movies/2/watch", json: 200, Self.movie(watched: true))
        let model = await Fixtures.readyModel(transport)
        let store = MovieStore(tmdbID: 2, api: model.api, app: model)
        await store.load()
        await store.mark(choice: WatchChoice(service: .service(.cinema)))
        #expect(store.detail.value?.watches.count == 1)
        #expect(Fixtures.jsonObject(transport.requests.last?.body)["service"] as? String == "cinema")
        #expect(model.changeVersion == 1)
    }

    @Test func movieErrorKeepsDetail() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/movies/2", json: 200, Self.movie(watched: true))
        transport.on(.delete, "/api/v1/watches/0F2B4D63-8E57-4E0A-9C5B-3B1E2D4F5A6B", json: 404,
                     Fixtures.error("notFound", "Nicht gefunden."))
        let model = await Fixtures.readyModel(transport)
        let store = MovieStore(tmdbID: 2, api: model.api, app: model)
        await store.load()
        await store.deleteWatch(id: "0F2B4D63-8E57-4E0A-9C5B-3B1E2D4F5A6B")
        #expect(store.actionError?.message == "Nicht gefunden.")
        #expect(store.detail.value?.watches.count == 1)
    }

    @Test func deleteWatchRemovesOneViewingAndReloads() async {
        let transport = FakeTransport()
        let deleted = Counter()
        transport.on(.get, "/api/v1/movies/2") { _, _ in FakeTransport.json(200, Self.movie(watched: deleted.value == 0)) }
        transport.on(.delete, "/api/v1/watches/0F2B4D63-8E57-4E0A-9C5B-3B1E2D4F5A6B") { _, _ in
            deleted.increment()
            return FakeTransport.empty(204)
        }
        let model = await Fixtures.readyModel(transport)
        let store = MovieStore(tmdbID: 2, api: model.api, app: model)
        await store.load()
        await store.deleteWatch(id: "0F2B4D63-8E57-4E0A-9C5B-3B1E2D4F5A6B")
        #expect(store.actionError == nil)
        #expect(store.detail.value?.watches.isEmpty == true)
        #expect(model.changeVersion == 1)
        #expect(!transport.requests.contains { $0.path == "/api/v1/movies/2/watch" && $0.method == .delete })
    }

    @Test func ratingAndCommentRoutes() async {
        let transport = FakeTransport()
        transport.on(.put, "/api/v1/movies/2/rating", json: 200, Self.movie(watched: true))
        transport.on(.put, "/api/v1/movies/2/comment", json: 200, Self.movie(watched: true))
        let model = await Fixtures.readyModel(transport)
        let store = MovieStore(tmdbID: 2, api: model.api, app: model)
        await store.setRating(8)
        await store.setComment("Großartig")
        #expect(store.actionError == nil)
        #expect(model.changeVersion == 2)
    }
}
