import Foundation
import Testing
import WatchSwiftyClient
@testable import WatchSwiftyCore

@MainActor @Suite struct HistoryStoreTests {
    nonisolated static func item(_ index: Int, service: String = "netflix") -> String {
        let id = String(format: "00000000-0000-0000-0000-%012d", index)
        return #"{"id":"\#(id)","kind":"tv","tmdbId":1,"title":"Severance","day":"2026-11-07","service":"\#(service)","origin":"manual"}"#
    }

    nonisolated static func page(_ range: Range<Int>, total: Int, page: Int, service: String = "netflix") -> String {
        #"{"items":[\#(range.map { item($0, service: service) }.joined(separator: ","))],"total":\#(total),"page":\#(page),"perPage":50}"#
    }

    @Test func historyLoadsNextPageAtEnd() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/history") { request, _ in
            request.path?.contains("page=2") == true
                ? FakeTransport.json(200, Self.page(50..<60, total: 60, page: 2))
                : FakeTransport.json(200, Self.page(0..<50, total: 60, page: 1))
        }
        let model = await Fixtures.readyModel(transport)
        let store = HistoryStore(api: model.api, app: model)
        await store.loadFirstPage()
        #expect(store.items.count == 50)
        await store.loadMoreIfNeeded(after: store.items[10])
        #expect(store.items.count == 50)
        await store.loadMoreIfNeeded(after: store.items[49])
        #expect(store.items.count == 60)
        let queries = transport.requests.filter { $0.path == "/api/v1/history" }.compactMap(\.query)
        #expect(queries == ["page=1&perPage=50", "page=2&perPage=50"])
    }

    @Test func historyNoRequestBeyondTotal() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/history", json: 200, Self.page(0..<2, total: 2, page: 1))
        let model = await Fixtures.readyModel(transport)
        let store = HistoryStore(api: model.api, app: model)
        await store.loadFirstPage()
        await store.loadMoreIfNeeded(after: store.items[1])
        #expect(transport.requests.filter { $0.path == "/api/v1/history" }.count == 1)
    }

    @Test func editKeepsUnknownService() async throws {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/history", json: 200, Self.page(0..<1, total: 1, page: 1, service: "crunchyroll"))
        let id = "00000000-0000-0000-0000-000000000000"
        transport.on(.put, "/api/v1/watches/\(id)", json: 200, Self.item(0, service: "crunchyroll"))
        let model = await Fixtures.readyModel(transport)
        let store = HistoryStore(api: model.api, app: model)
        await store.loadFirstPage()
        let item = try #require(store.items.first)
        await store.update(id: item.id, day: "2026-11-08", service: item.service)
        let body = Fixtures.jsonObject(transport.requests.last?.body)
        #expect(body["service"] as? String == "crunchyroll")
        #expect(body["day"] as? String == "2026-11-08")
        #expect(model.changeVersion == 1)
    }

    @Test func deleteRemovesItemAndBumpsChange() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/history", json: 200, Self.page(0..<2, total: 2, page: 1))
        transport.on(.delete, "/api/v1/watches/00000000-0000-0000-0000-000000000001") { _, _ in FakeTransport.empty(204) }
        let model = await Fixtures.readyModel(transport)
        let store = HistoryStore(api: model.api, app: model)
        await store.loadFirstPage()
        await store.delete(id: "00000000-0000-0000-0000-000000000001")
        #expect(store.items.count == 1)
        #expect(store.total == 1)
        #expect(model.changeVersion == 1)
    }
}
