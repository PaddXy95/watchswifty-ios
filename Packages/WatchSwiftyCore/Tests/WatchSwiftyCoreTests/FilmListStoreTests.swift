import Foundation
import Testing
import WatchSwiftyClient
@testable import WatchSwiftyCore

@MainActor @Suite struct FilmListStoreTests {
    nonisolated static let entryID = "0F2B4D63-8E57-4E0A-9C5B-3B1E2D4F5A6B"

    nonisolated static func entry(status: String, candidates: String = "[]") -> String {
        #"{"id":"\#(entryID)","title":"Dune","year":2021,"watchCount":1,"status":"\#(status)","candidates":\#(candidates)}"#
    }

    nonisolated static func list(pending: Int, status: String = "review") -> String {
        #"{"counts":{"imported":0,"review":1,"notFound":0,"skipped":0,"pending":\#(pending)},"entries":[\#(entry(status: status))]}"#
    }

    @Test func filmUploadRejectsOver2MB() async {
        let transport = FakeTransport()
        let model = await Fixtures.readyModel(transport)
        let store = FilmListStore(api: model.api, app: model, pollInterval: .zero)
        #expect(await store.upload(data: Data(count: 2_097_153), filename: "filme.csv") == false)
        #expect(store.actionError?.message == "Die Datei ist zu groß.")
        #expect(!transport.requests.contains { $0.path == "/api/v1/imports/films" })
    }

    @Test func filmUploadSendsFile() async {
        let transport = FakeTransport()
        transport.on(.post, "/api/v1/imports/films", json: 200, #"{"films":12}"#)
        transport.on(.get, "/api/v1/imports/films", json: 200, Self.list(pending: 12))
        let model = await Fixtures.readyModel(transport)
        let store = FilmListStore(api: model.api, app: model, pollInterval: .zero)
        #expect(await store.upload(data: Data("Titel;Jahr\nDune;2021\n".utf8), filename: "filme.csv"))
        #expect(store.lastUploadCount == 12)
        #expect(store.list.value?.counts.pending == 12)
    }

    @Test func filmPollingStopsWhenNothingPending() async {
        let transport = FakeTransport()
        let calls = Counter()
        transport.on(.get, "/api/v1/imports/films") { _, _ in
            calls.increment()
            return FakeTransport.json(200, Self.list(pending: calls.value < 3 ? 2 : 0))
        }
        let model = await Fixtures.readyModel(transport)
        let store = FilmListStore(api: model.api, app: model, pollInterval: .zero)
        await store.pollWhilePending()
        #expect(calls.value == 3)
    }

    @Test func filmActionReplacesList() async {
        let transport = FakeTransport()
        let calls = Counter()
        transport.on(.get, "/api/v1/imports/films") { _, _ in
            calls.increment()
            return FakeTransport.json(200, Self.list(pending: 0, status: calls.value < 2 ? "review" : "imported"))
        }
        transport.on(.post, "/api/v1/imports/films/\(Self.entryID)/accept", json: 200, Self.entry(status: "imported"))
        let model = await Fixtures.readyModel(transport)
        let store = FilmListStore(api: model.api, app: model, pollInterval: .zero)
        await store.load()
        await store.accept(entryID: Self.entryID, tmdbID: 438631)
        #expect(store.list.value?.entries.first?.status == .imported)
        #expect(Fixtures.jsonObject(transport.requests.first { $0.path.hasSuffix("/accept") }?.body)["tmdbId"] as? Int == 438631)
        #expect(model.changeVersion == 1)
    }

    @Test func filmSearchReplacesEntryCandidates() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/imports/films", json: 200, Self.list(pending: 0))
        transport.on(.post, "/api/v1/imports/films/\(Self.entryID)/search", json: 200,
                     Self.entry(status: "review", candidates: #"[{"kind":"movie","tmdbId":438631,"name":"Dune"}]"#))
        let model = await Fixtures.readyModel(transport)
        let store = FilmListStore(api: model.api, app: model, pollInterval: .zero)
        await store.load()
        await store.search(entryID: Self.entryID, query: "Dune 2021")
        #expect(store.list.value?.entries.first?.candidates.first?.tmdbId == 438631)
        #expect(model.changeVersion == 0)
    }
}
