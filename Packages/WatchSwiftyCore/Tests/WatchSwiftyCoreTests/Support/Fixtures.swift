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
