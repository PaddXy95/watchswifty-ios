import Foundation
@testable import WatchSwiftyCore

enum Fixtures {
    static let server = try! ServerAddress.parse("https://example.de")
    static let subPathServer = try! ServerAddress.parse("https://example.de/watch")

    static let tokenGrant = #"""
    {"token":"ws_abc","expiresAt":"2027-02-05T12:00:00Z",
     "device":{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"iPhone","kind":"device",
               "createdAt":"2026-11-07T12:00:00Z","expiresAt":"2027-02-05T12:00:00Z"},
     "user":{"username":"pat","isAdmin":true}}
    """#

    static func error(_ code: String, _ message: String) -> String {
        #"{"code":"\#(code)","message":"\#(message)"}"#
    }
}

/// Answers the browser login like the server would: echoes `state`, returns a fixed code, remembers the challenge.
final class FakeWebAuthenticator: WebAuthenticator, @unchecked Sendable {
    enum Mode { case approve, deny, cancel, wrongState }
    let mode: Mode
    private(set) var openedURL: URL?
    init(_ mode: Mode = .approve) { self.mode = mode }

    var challenge: String? { query("code_challenge") }

    func query(_ name: String) -> String? {
        openedURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.first { $0.name == name }?.value
    }

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        openedURL = url
        let state = query("state") ?? ""
        switch mode {
        case .approve: return URL(string: "\(callbackScheme):/auth?code=abc&state=\(state)")!
        case .deny: return URL(string: "\(callbackScheme):/auth?error=access_denied&state=\(state)")!
        case .cancel: throw CancellationError()
        case .wrongState: return URL(string: "\(callbackScheme):/auth?code=abc&state=other")!
        }
    }
}

extension Fixtures {
    static let me = #"""
    {"username":"pat","isAdmin":true,"hasPassword":true,"ssoLinked":false,"passwordLogin":true,
     "tmdbToken":{"state":"stored","suffix":"…abcd"}}
    """#

    static let token = StoredToken(token: "ws_current", expiresAt: Date(timeIntervalSince1970: 1_801_828_800),
                                   deviceID: "6F9619FF-8B86-D011-B42D-00C04FC964FF")

    static func settings() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        return defaults
    }

    /// Environment with a fake server; `server` is stored as already chosen unless nil.
    static func environment(transport: FakeTransport, token: StoredToken? = nil, server: ServerAddress? = Fixtures.server,
                            minimum: String = "0.4.0", tokenStore: (any TokenStore)? = nil,
                            now: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> AppEnvironment {
        let settings = settings()
        if let server { settings.set(server.baseURL.absoluteString, forKey: AppModel.serverKey) }
        return AppEnvironment(tokenStore: tokenStore ?? InMemoryTokenStore(token), settings: settings,
                              transport: transport, minimumServerVersion: minimum, now: { now })
    }
}

final class CountingTokenStore: TokenStore, @unchecked Sendable {
    private let inner: InMemoryTokenStore
    private let deletes = Counter()
    init(_ token: StoredToken?) { inner = InMemoryTokenStore(token) }
    var deleteCount: Int { deletes.value }
    func load() throws -> StoredToken? { try inner.load() }
    func save(_ token: StoredToken) throws { try inner.save(token) }
    func delete() throws { deletes.increment(); try inner.delete() }
}

@MainActor func waitUntil(_ condition: @MainActor () -> Bool) async {
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(2)
    while !condition(), clock.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
}

extension Fixtures {
    static func series(watched: Bool = false, service: String = "netflix", rating: Int? = nil) -> String {
        let watches = watched ? #"[{"id":"0F2B4D63-8E57-4E0A-9C5B-3B1E2D4F5A6B","day":"2026-11-07","service":"\#(service)","origin":"manual"}]"# : "[]"
        let ratingField = rating.map { #""rating":\#($0),"# } ?? ""
        return #"""
        {"tmdbId":1,"name":"Severance",\#(ratingField)"links":{"tmdb":"https://tmdb","imdb":"https://imdb","rottenTomatoes":"https://rt"},
         "hidden":false,"followed":true,"lastService":"\#(service)",
         "seasons":[{"number":1,"title":"Staffel 1","watchedCount":\#(watched ? 1 : 0),
           "episodes":[{"season":1,"number":1,"name":"Pilot","aired":true,"watches":\#(watches)}]}]}
        """#
    }

    /// An AppModel that is signed in against `transport` (version + me answered).
    @MainActor static func readyModel(_ transport: FakeTransport) async -> AppModel {
        transport.on(.get, "/api/v1/version", json: 200, #"{"version":"0.4.0"}"#)
        transport.on(.get, "/api/v1/me", json: 200, me)
        let model = AppModel(environment: environment(transport: transport, token: token))
        await model.start()
        return model
    }

    static func jsonObject(_ data: Data?) -> [String: Any] {
        (data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
    }
}

/// A handler that answers only when `release()` is called (to test in-flight guards).
final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func wait() async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock { () -> Bool in
                if released { return true }
                self.continuation = continuation
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func release() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            released = true
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume()
    }
}
