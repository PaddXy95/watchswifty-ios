import Observation
import OpenAPIRuntime
import WatchSwiftyClient

/// „Verlauf“: all watches, newest first, loaded page by page when the list reaches its end.
@MainActor @Observable
public final class HistoryStore {
    public static let perPage = 50

    public private(set) var items: [Components.Schemas.HistoryItem] = []
    public private(set) var total = 0
    public private(set) var isLoading = false
    public private(set) var error: UserFacingError?
    public private(set) var busy = false
    public var actionError: UserFacingError?
    /// Loaded at least once (to tell „empty“ from „not loaded yet“).
    public private(set) var hasLoaded = false

    @ObservationIgnored private let api: any APIProtocol
    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private var page = 0
    @ObservationIgnored private var loadedAt: Int?

    public init(api: any APIProtocol, app: AppModel) {
        self.api = api
        self.app = app
    }

    public func loadFirstPage() async {
        await fetch(page: 1)
    }

    public func reloadIfStale() async {
        if loadedAt != app.changeVersion, !isLoading { await loadFirstPage() }
    }

    /// Call when a row appears; loads the next page when it is the last row and more exist.
    public func loadMoreIfNeeded(after item: Components.Schemas.HistoryItem) async {
        guard item.id == items.last?.id, items.count < total, !isLoading else { return }
        await fetch(page: page + 1)
    }

    /// Replaces date and service (`nil` day = ohne Datum, `nil` service = ohne Dienst). Pass an unknown service
    /// unchanged, otherwise it would be erased.
    public func update(id: String, day: String?, service: ServiceValue?) async {
        await mutate {
            let updated = try await $0.updateWatch(path: .init(id: id), body: .json(.init(day: day, service: service))).ok.body.json
            return { items in
                if let index = items.firstIndex(where: { $0.id == id }) { items[index] = updated }
            }
        }
    }

    public func delete(id: String) async {
        await mutate {
            _ = try await $0.deleteWatch(path: .init(id: id))
            return { items in items.removeAll { $0.id == id } }
        }
    }

    private func fetch(page requested: Int) async {
        isLoading = true
        defer { isLoading = false }
        let version = app.changeVersion
        let api = api
        let result = await runCatching {
            try await api.getHistory(query: .init(page: requested, perPage: Self.perPage)).ok.body.json
        }
        switch result {
        case .success(let page)?:
            items = requested == 1 ? page.items : items + page.items
            total = page.total
            self.page = requested
            error = nil
            hasLoaded = true
            if requested == 1 { loadedAt = version }
        case .failure(let failure)?:
            error = failure
        case nil:
            break
        }
    }

    private func mutate(_ operation: @escaping (any APIProtocol) async throws -> @Sendable (inout [Components.Schemas.HistoryItem]) -> Void) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let api = api
        guard let result = await runCatching({ try await operation(api) }) else { return }
        switch result {
        case .success(let apply):
            let before = items.count
            apply(&items)
            total -= before - items.count
            app.didChange()
            loadedAt = app.changeVersion
        case .failure(let error):
            actionError = error
        }
    }
}
