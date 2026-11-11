import Foundation
import WatchSwiftyClient

/// The last „Weiterschauen“ answer as a file, so a cold start shows the start page at once (spec „Schichten“).
/// Only titles, episodes and poster paths; replaced right after the next load.
public struct SnapshotCache: Sendable {
    let file: URL

    public init(directory: URL) {
        file = directory.appending(path: "continue-watching.json")
    }

    public static func live() -> SnapshotCache {
        SnapshotCache(directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0])
    }

    public func load() -> Components.Schemas.ContinueWatching? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Components.Schemas.ContinueWatching.self, from: data)
    }

    public func save(_ value: Components.Schemas.ContinueWatching) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(value).write(to: file, options: .atomic)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: file)
    }
}
