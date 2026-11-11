import Observation
import OpenAPIRuntime
import WatchSwiftyClient

/// TMDB search as in the web: waits for a short typing pause, and only the answer for the current text counts.
@MainActor @Observable
public final class SearchStore {
    public var query = ""
    public private(set) var results = Loadable<[Components.Schemas.SearchHit]>()

    @ObservationIgnored private let api: any APIProtocol
    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var pending: Task<Void, Never>?

    public init(api: any APIProtocol, app: AppModel, debounce: Duration = .milliseconds(300)) {
        self.api = api
        self.app = app
        self.debounce = debounce
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Call on every change of `query`.
    public func queryChanged() {
        pending?.cancel()
        let text = trimmedQuery
        guard !text.isEmpty else {
            pending = nil
            results = Loadable()
            return
        }
        let delay = debounce
        pending = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            await self?.search(text)
        }
    }

    /// Waits for the search that is about to run (tests, pull-to-refresh).
    public func waitForPendingSearch() async {
        await pending?.value
    }

    public func refresh() async {
        guard !trimmedQuery.isEmpty else { return }
        await search(trimmedQuery)
    }

    private func search(_ text: String) async {
        results.begin()
        let version = app.changeVersion
        let api = api
        let result = await runCatching { try await api.search(query: .init(q: text)).ok.body.json }
        guard text == trimmedQuery else { return }   // a newer text is being searched
        guard let result else { return results.cancel() }
        results.finish(result, at: version)
    }
}
