import Foundation
import Testing
@testable import WatchSwiftyCore

@Suite struct AuthMiddlewareTests {
    @Test func authMiddlewareAddsBearer() async throws {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/version", json: 200, #"{"version":"0.4.0"}"#)
        let middleware = AuthMiddleware(token: { "ws_secret" }, onUnauthorized: {})
        let api = makeClient(server: Fixtures.server, middlewares: [middleware], transport: transport)
        _ = try await api.getVersion()
        #expect(transport.requests[0].request.headerFields[.authorization] == "Bearer ws_secret")
    }

    @Test func noHeaderWithoutToken() async throws {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/version", json: 200, #"{"version":"0.4.0"}"#)
        let api = makeClient(server: Fixtures.server,
                             middlewares: [AuthMiddleware(token: { nil }, onUnauthorized: {})], transport: transport)
        _ = try await api.getVersion()
        #expect(transport.requests[0].request.headerFields[.authorization] == nil)
    }

    @Test func authMiddlewareReports401() async throws {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/me", json: 401, Fixtures.error("tokenExpired", "Abgelaufen."))
        let reported = Counter()
        let api = makeClient(server: Fixtures.server,
                             middlewares: [AuthMiddleware(token: { "ws_old" }, onUnauthorized: { reported.increment() })],
                             transport: transport)
        let output = try await api.getMe()
        guard case .unauthorized = output else { Issue.record("expected 401, got \(output)"); return }
        #expect(reported.value == 1)
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
