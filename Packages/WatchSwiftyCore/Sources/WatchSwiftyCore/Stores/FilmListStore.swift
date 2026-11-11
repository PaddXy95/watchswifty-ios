import Foundation
import Observation
import OpenAPIRuntime
import WatchSwiftyClient

/// Film list import (e.g. a Letterboxd or own CSV): upload, follow the matching, decide per film.
@MainActor @Observable
public final class FilmListStore {
    public private(set) var list = Loadable<Components.Schemas.FilmList>()
    /// Films in the last uploaded file.
    public private(set) var lastUploadCount: Int?
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
        list.begin()
        let version = app.changeVersion
        let api = api
        guard let result = await runCatching({ try await api.getFilmList().ok.body.json }) else { return list.cancel() }
        list.finish(result, at: version)
    }

    /// Reloads while films are still waiting for matching; stops when done or when the screen closes.
    public func pollWhilePending() async {
        while !Task.isCancelled {
            await load()
            guard (list.value?.counts.pending ?? 0) > 0, !Task.isCancelled else { return }
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
        guard data.count <= ImportFile.filmListLimit else {
            actionError = ImportFile.tooLarge
            return false
        }
        let result = await perform { api in
            try await api.uploadFilmList(body: .multipartForm([
                .file(.init(payload: .init(body: HTTPBody(data)), filename: filename)),
            ])).ok.body.json
        }
        guard let result else { return false }
        lastUploadCount = result.films
        return true
    }

    public func retry() async {
        _ = await perform { try await $0.retryFilmList().ok.body.json }
    }

    public func accept(entryID: String, tmdbID: Int) async {
        _ = await perform { try await $0.acceptFilm(path: .init(id: entryID), body: .json(.init(tmdbId: tmdbID))).ok.body.json }
    }

    public func skip(entryID: String) async {
        _ = await perform { try await $0.skipFilm(path: .init(id: entryID)).ok.body.json }
    }

    /// New TMDB search for one film; only its candidates change.
    public func search(entryID: String, query: String) async {
        let api = api
        let result = await runCatching {
            try await api.searchFilm(path: .init(id: entryID), body: .json(.init(q: query))).ok.body.json
        }
        switch result {
        case .success(let entry)?:
            if var value = list.value, let index = value.entries.firstIndex(where: { $0.id == entryID }) {
                value.entries[index] = entry
                list.value = value
            }
        case .failure(let error)?:
            actionError = error
        case nil:
            break
        }
    }

    /// Runs a change, then reloads the list (counts change on the server).
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
