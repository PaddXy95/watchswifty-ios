import Foundation
import Observation
import OpenAPIRuntime
import WatchSwiftyClient

/// Netflix import as in the web: upload the viewing history, follow the matching, review mappings, assign rows.
@MainActor @Observable
public final class NetflixImportStore {
    public enum MappingFilter: String, CaseIterable, Sendable {
        case all, auto, confirmed, ignored
        public var label: String {
            switch self {
            case .all: "Alle"
            case .auto: "Automatisch"
            case .confirmed: "Bestätigt"
            case .ignored: "Ignoriert"
            }
        }
    }

    public private(set) var state = Loadable<Components.Schemas.NetflixImport>()
    public private(set) var mappingFilter = MappingFilter.all
    /// Result of the last upload (new, known, skipped rows).
    public private(set) var lastUpload: Components.Schemas.ImportSummary?
    public private(set) var busy = false
    public var actionError: UserFacingError?

    @ObservationIgnored private let api: any APIProtocol
    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private let pollInterval: Duration

    public init(api: any APIProtocol, app: AppModel, pollInterval: Duration = .seconds(2)) {
        self.api = api
        self.app = app
        self.pollInterval = pollInterval
    }

    public func load() async {
        state.begin()
        let version = app.changeVersion
        let query = Operations.getNetflixImport.Input.Query(mappings: .init(rawValue: mappingFilter.rawValue))
        let api = api
        guard let result = await runCatching({ try await api.getNetflixImport(query: query).ok.body.json }) else {
            return state.cancel()
        }
        state.finish(result, at: version)
    }

    public func setMappingFilter(_ filter: MappingFilter) async {
        mappingFilter = filter
        await load()
    }

    /// Reloads every `pollInterval` while the server is still matching; stops when done or when the task is cancelled
    /// (screen closed).
    public func pollWhileRunning() async {
        while !Task.isCancelled {
            await load()
            guard state.value?.progress.running == true, !Task.isCancelled else { return }
            try? await Task.sleep(for: pollInterval)
        }
    }

    public func upload(fileURL: URL) async -> Bool {
        do {
            return await upload(data: try ImportFile.read(fileURL), filename: fileURL.lastPathComponent)
        } catch {
            actionError = .validation("Die Datei konnte nicht gelesen werden.")
            return false
        }
    }

    public func upload(data: Data, filename: String) async -> Bool {
        guard data.count <= ImportFile.netflixLimit else {
            actionError = ImportFile.tooLarge
            return false
        }
        let summary: Components.Schemas.ImportSummary? = await perform { api in
            try await api.uploadNetflix(body: .multipartForm([
                .file(.init(payload: .init(body: HTTPBody(data)), filename: filename)),
            ])).ok.body.json
        }
        guard let summary else { return false }
        lastUpload = summary
        return true
    }

    public func retry() async {
        _ = await perform { try await $0.retryNetflix().ok.body.json }
    }

    public func accept(mappingID: String, kind: Components.Schemas.MappingDecision.kindPayload, tmdbID: Int) async {
        _ = await perform {
            try await $0.acceptMapping(path: .init(id: mappingID), body: .json(.init(kind: kind, tmdbId: tmdbID))).ok.body.json
        }
    }

    public func change(mappingID: String, kind: Components.Schemas.MappingDecision.kindPayload, tmdbID: Int) async {
        _ = await perform {
            try await $0.changeMapping(path: .init(id: mappingID), body: .json(.init(kind: kind, tmdbId: tmdbID))).ok.body.json
        }
    }

    public func ignore(mappingID: String) async {
        _ = await perform { try await $0.ignoreMapping(path: .init(id: mappingID)).ok.body.json }
    }

    public func reset(mappingID: String) async {
        _ = await perform { try await $0.resetMapping(path: .init(id: mappingID)).ok.body.json }
    }

    public func assign(rowID: String, episodeID: String) async {
        _ = await perform { _ = try await $0.assignRow(path: .init(id: rowID), body: .json(.init(episodeId: episodeID))).noContent }
    }

    public func ignore(rowID: String) async {
        _ = await perform { _ = try await $0.ignoreRow(path: .init(id: rowID)).noContent }
    }

    /// Titles to choose from when changing a mapping.
    public func searchCandidates(mappingID: String, query: String) async -> [Components.Schemas.SearchResult] {
        let api = api
        let result = await runCatching {
            try await api.searchMappingCandidates(path: .init(id: mappingID), query: .init(q: query)).ok.body.json
        }
        if case .failure(let error)? = result { actionError = error }
        return (try? result?.get()) ?? []
    }

    /// Episodes an unmatched row can be assigned to.
    public func rowOptions(rowID: String) async -> [Components.Schemas.EpisodeOption] {
        let api = api
        let result = await runCatching { try await api.getRowOptions(path: .init(id: rowID)).ok.body.json }
        if case .failure(let error)? = result { actionError = error }
        return (try? result?.get()) ?? []
    }

    /// Runs a change, then reloads the whole import state (a decision moves rows between lists on the server).
    private func perform<T: Sendable>(_ operation: @escaping (any APIProtocol) async throws -> T) async -> T? {
        guard !busy else { return nil }
        busy = true
        defer { busy = false }
        let api = api
        guard let result = await runCatching({ try await operation(api) }) else { return nil }
        switch result {
        case .success(let value):
            app.didChange()
            await load()
            return value
        case .failure(let error):
            actionError = error
            return nil
        }
    }
}
