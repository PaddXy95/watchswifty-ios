import Foundation
import Testing
import WatchSwiftyClient
@testable import WatchSwiftyCore

@MainActor @Suite struct SearchStoreTests {
    nonisolated static func hits(_ name: String) -> String {
        #"[{"kind":"tv","tmdbId":1,"name":"\#(name)","inLibrary":false}]"#
    }

    @Test func searchDebouncesAndUsesLatest() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/search") { request, _ in
            FakeTransport.json(200, Self.hits(request.path ?? ""))
        }
        let model = await Fixtures.readyModel(transport)
        let store = SearchStore(api: model.api, app: model, debounce: .milliseconds(50))
        store.query = "sev"
        store.queryChanged()
        store.query = "seve"
        store.queryChanged()
        await store.waitForPendingSearch()
        let searches = transport.requests.filter { $0.path == "/api/v1/search" }
        #expect(searches.map(\.query) == ["q=seve"])
        #expect(store.results.value?.count == 1)
    }

    @Test func staleSearchResponseIgnored() async {
        let transport = FakeTransport()
        let gate = Gate()
        let slowDone = Counter()
        transport.on(.get, "/api/v1/search") { request, _ in
            if request.path?.hasSuffix("q=sev") == true {
                await gate.wait()
                slowDone.increment()
                return FakeTransport.json(200, Self.hits("Alt"))
            }
            return FakeTransport.json(200, Self.hits("Severance"))
        }
        let model = await Fixtures.readyModel(transport)
        let store = SearchStore(api: model.api, app: model, debounce: .zero)
        store.query = "sev"
        store.queryChanged()
        await waitUntil { transport.requests.contains { $0.query == "q=sev" } }
        store.query = "seve"
        store.queryChanged()
        await store.waitForPendingSearch()
        gate.release()
        await waitUntil { slowDone.value == 1 }
        for _ in 0..<5 { await Task.yield() }
        #expect(store.results.value?.first?.name == "Severance")
    }

    @Test func emptyQueryClears() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/search", json: 200, Self.hits("Severance"))
        let model = await Fixtures.readyModel(transport)
        let store = SearchStore(api: model.api, app: model, debounce: .zero)
        store.query = "sev"
        store.queryChanged()
        await store.waitForPendingSearch()
        store.query = "  "
        store.queryChanged()
        await store.waitForPendingSearch()
        #expect(store.results.value == nil)
        #expect(transport.requests.filter { $0.path == "/api/v1/search" }.count == 1)
    }

    @Test func searchWithoutTMDBTokenShowsHint() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/search", json: 422, Fixtures.error("missingTMDBToken", "Bitte hinterlege deinen TMDB-Token."))
        let model = await Fixtures.readyModel(transport)
        let store = SearchStore(api: model.api, app: model, debounce: .zero)
        store.query = "sev"
        store.queryChanged()
        await store.waitForPendingSearch()
        #expect(store.results.error?.kind == .missingTMDBToken)
    }
}
