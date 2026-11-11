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
