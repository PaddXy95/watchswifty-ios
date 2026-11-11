import Foundation
import Testing
import WatchSwiftyClient
@testable import WatchSwiftyCore

@MainActor @Suite struct NetflixImportStoreTests {
    nonisolated static let reviewID = "0F2B4D63-8E57-4E0A-9C5B-3B1E2D4F5A6B"

    nonisolated static func state(running: Bool, review: Bool = true) -> String {
        let reviews = review
            ? #"[{"id":"\#(reviewID)","netflixName":"Dark","kind":"tv","rowCount":3,"candidates":[{"kind":"tv","tmdbId":5,"name":"Dark"}]}]"#
            : "[]"
        return #"""
        {"progress":{"running":\#(running),"pendingRows":\#(running ? 10 : 0),"waitingForReview":1},
         "review":\#(reviews),"unmatched":[],"unmatchedTotal":0,"mappings":[]}
        """#
    }

    @Test func uploadRejectsOver10MB() async {
        let transport = FakeTransport()
        let model = await Fixtures.readyModel(transport)
        let store = NetflixImportStore(api: model.api, app: model, pollInterval: .zero)
        let ok = await store.upload(data: Data(count: 10_485_761), filename: "NetflixViewingHistory.csv")
        #expect(!ok)
        #expect(store.actionError == UserFacingError(kind: .validation, message: "Die Datei ist zu groß."))
        #expect(!transport.requests.contains { $0.path == "/api/v1/imports/netflix" })
    }

    @Test func uploadSendsMultipartFile() async throws {
        let transport = FakeTransport()
        transport.on(.post, "/api/v1/imports/netflix", json: 200, #"{"new":3,"known":1,"skipped":0}"#)
        transport.on(.get, "/api/v1/imports/netflix", json: 200, Self.state(running: true))
        let model = await Fixtures.readyModel(transport)
        let store = NetflixImportStore(api: model.api, app: model, pollInterval: .zero)
        let ok = await store.upload(data: Data("Title,Date\n\"Dark: Staffel 1: Geheimnisse\",\"7.11.26\"\n".utf8),
                                    filename: "NetflixViewingHistory.csv")
        #expect(ok)
        #expect(store.lastUpload?.new == 3)
        let request = try #require(transport.requests.first { $0.path == "/api/v1/imports/netflix" && $0.method == .post })
        let body = String(decoding: request.body ?? Data(), as: UTF8.self)
        #expect(body.contains(#"name="file""#))
        #expect(body.contains(#"filename="NetflixViewingHistory.csv""#))
        #expect(body.contains("Dark: Staffel 1"))
        #expect(store.state.value?.progress.running == true)
        #expect(model.changeVersion == 1)
    }

    @Test func pollingStopsWhenFinished() async {
        let transport = FakeTransport()
        let calls = Counter()
        transport.on(.get, "/api/v1/imports/netflix") { _, _ in
            calls.increment()
            return FakeTransport.json(200, Self.state(running: calls.value < 2))
        }
        let model = await Fixtures.readyModel(transport)
        let store = NetflixImportStore(api: model.api, app: model, pollInterval: .zero)
        await store.pollWhileRunning()
        #expect(calls.value == 2)
        #expect(store.state.value?.progress.running == false)
    }

    @Test func pollingStopsOnCancel() async {
        let transport = FakeTransport()
        let calls = Counter()
        transport.on(.get, "/api/v1/imports/netflix") { _, _ in
            calls.increment()
            return FakeTransport.json(200, Self.state(running: true))
        }
        let model = await Fixtures.readyModel(transport)
        let store = NetflixImportStore(api: model.api, app: model, pollInterval: .milliseconds(5))
        let polling = Task { await store.pollWhileRunning() }
        await waitUntil { calls.value >= 2 }
        polling.cancel()
        await polling.value
        let afterCancel = calls.value
        try? await Task.sleep(for: .milliseconds(30))
        #expect(calls.value == afterCancel)
    }

    @Test func mappingActionReplacesState() async {
        let transport = FakeTransport()
        let calls = Counter()
        transport.on(.get, "/api/v1/imports/netflix") { _, _ in
            calls.increment()
            return FakeTransport.json(200, Self.state(running: false, review: calls.value < 2))
        }
        transport.on(.post, "/api/v1/imports/netflix/mappings/\(Self.reviewID)/accept", json: 200,
                     #"{"id":"\#(Self.reviewID)","netflixName":"Dark","kind":"tv","status":"confirmed","title":{"tmdbId":5,"name":"Dark"}}"#)
        let model = await Fixtures.readyModel(transport)
        let store = NetflixImportStore(api: model.api, app: model, pollInterval: .zero)
        await store.load()
        #expect(store.state.value?.review.count == 1)
        await store.accept(mappingID: Self.reviewID, kind: .tv, tmdbID: 5)
        #expect(store.state.value?.review.isEmpty == true)
        let body = Fixtures.jsonObject(transport.requests.first { $0.path.hasSuffix("/accept") }?.body)
        #expect(body["tmdbId"] as? Int == 5)
        #expect(model.changeVersion == 1)
    }

    @Test func mappingFilterIsSent() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/imports/netflix", json: 200, Self.state(running: false))
        let model = await Fixtures.readyModel(transport)
        let store = NetflixImportStore(api: model.api, app: model, pollInterval: .zero)
        await store.setMappingFilter(.ignored)
        #expect(transport.requests.last?.query == "mappings=ignored")
    }
}
