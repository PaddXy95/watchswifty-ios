import Foundation
import Testing
import WatchSwiftyClient
@testable import WatchSwiftyCore

@MainActor @Suite struct AppModelTests {
    @Test func startWithoutServerNeedsServer() async {
        let model = AppModel(environment: Fixtures.environment(transport: FakeTransport(), server: nil))
        await model.start()
        #expect(model.phase == .needsServer)
    }

    @Test func startWithOldServerShowsTooOld() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/version", json: 200, #"{"version":"0.3.2"}"#)
        let model = AppModel(environment: Fixtures.environment(transport: transport, token: Fixtures.token))
        await model.start()
        #expect(model.phase == .serverTooOld(server: "0.3.2", minimum: "0.4.0"))
    }

    @Test func startWithTokenIsReady() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/version", json: 200, #"{"version":"0.4.0"}"#)
        transport.on(.get, "/api/v1/me", json: 200, Fixtures.me)
        let model = AppModel(environment: Fixtures.environment(transport: transport, token: Fixtures.token))
        await model.start()
        #expect(model.phase == .ready)
        #expect(model.me?.username == "pat")
        #expect(model.server == Fixtures.server)
        #expect(transport.requests.last?.request.headerFields[.authorization] == "Bearer ws_current")
    }

    @Test func startWithoutTokenNeedsLogin() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/version", json: 200, #"{"version":"0.4.0"}"#)
        let model = AppModel(environment: Fixtures.environment(transport: transport))
        await model.start()
        #expect(model.phase == .needsLogin)
    }

    @Test func startOfflineWithTokenIsReady() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/version") { _, _ in throw URLError(.notConnectedToInternet) }
        let model = AppModel(environment: Fixtures.environment(transport: transport, token: Fixtures.token))
        await model.start()
        #expect(model.phase == .ready)
    }

    @Test func connectSavesServer() async throws {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/version", json: 200, #"{"version":"0.4.0"}"#)
        let env = Fixtures.environment(transport: transport, server: nil)
        let model = AppModel(environment: env)
        await model.start()
        try await model.connect(to: " example.de/ ")
        #expect(model.phase == .needsLogin)
        #expect(model.server == Fixtures.server)
        #expect(env.settings.string(forKey: AppModel.serverKey) == "https://example.de")
    }

    @Test func connectRejectsInvalidAddress() async {
        let model = AppModel(environment: Fixtures.environment(transport: FakeTransport(), server: nil))
        await #expect(throws: UserFacingError(kind: .validation, message: ServerAddressError.insecurePublic.message)) {
            try await model.connect(to: "http://example.de")
        }
    }

    @Test func connectRejectsNonWatchSwifty() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/version") { _, _ in
            (.init(status: .ok, headerFields: [.contentType: "text/html"]), .init("<html></html>"))
        }
        let model = AppModel(environment: Fixtures.environment(transport: transport, server: nil))
        await #expect(throws: UserFacingError(kind: .validation,
                                              message: "Unter dieser Adresse antwortet kein WatchSwifty-Server.")) {
            try await model.connect(to: "example.de")
        }
        #expect(model.server == nil)
    }

    @Test func connectRejectsOldServer() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/version", json: 200, #"{"version":"0.3.2"}"#)
        let model = AppModel(environment: Fixtures.environment(transport: transport, server: nil))
        await #expect(throws: UserFacingError(kind: .validation,
                                              message: "Der Server ist zu alt (0.3.2). Diese App braucht mindestens 0.4.0.")) {
            try await model.connect(to: "example.de")
        }
    }

    @Test func signInMakesReady() async throws {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/version", json: 200, #"{"version":"0.4.0"}"#)
        transport.on(.post, "/api/v1/auth/token", json: 200, Fixtures.tokenGrant)
        transport.on(.get, "/api/v1/me", json: 200, Fixtures.me)
        let model = AppModel(environment: Fixtures.environment(transport: transport))
        await model.start()
        model.notice = "Bitte erneut verbinden."
        try await model.signIn(using: FakeWebAuthenticator())
        #expect(model.phase == .ready)
        #expect(model.token?.token == "ws_abc")
        #expect(model.notice == nil)
        #expect(model.me?.username == "pat")
    }

    @Test func concurrent401sSignOutOnce() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/version", json: 200, #"{"version":"0.4.0"}"#)
        transport.on(.get, "/api/v1/me", json: 200, Fixtures.me)
        let store = CountingTokenStore(Fixtures.token)
        let model = AppModel(environment: Fixtures.environment(transport: transport, tokenStore: store))
        await model.start()
        transport.on(.get, "/api/v1/stats", json: 401, Fixtures.error("tokenExpired", "Abgelaufen."))
        let api = model.api
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 { group.addTask { _ = try? await api.getStats() } }
        }
        await waitUntil { model.phase == .needsLogin }
        await Task.yield()
        #expect(model.phase == .needsLogin)
        #expect(store.deleteCount == 1)
        #expect(model.notice == "Bitte erneut verbinden.")
        #expect(model.server == Fixtures.server)
    }

    @Test func late401FromOldTokenIsIgnored() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/version", json: 200, #"{"version":"0.4.0"}"#)
        transport.on(.get, "/api/v1/me", json: 200, Fixtures.me)
        let model = AppModel(environment: Fixtures.environment(transport: transport, token: Fixtures.token))
        await model.start()
        model.handleUnauthorized(usedToken: "ws_previous")
        #expect(model.phase == .ready)
    }

    @Test func signOutDeletesEvenIfRevokeFails() async throws {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/version", json: 200, #"{"version":"0.4.0"}"#)
        transport.on(.get, "/api/v1/me", json: 200, Fixtures.me)
        transport.on(.delete, "/api/v1/auth/token") { _, _ in throw URLError(.timedOut) }
        let store = InMemoryTokenStore(Fixtures.token)
        let model = AppModel(environment: Fixtures.environment(transport: transport, tokenStore: store))
        await model.start()
        await model.signOut()
        #expect(model.phase == .needsLogin)
        #expect(try store.load() == nil)
        #expect(model.token == nil)
    }

    @Test func forgetServerNeedsServer() async throws {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/version", json: 200, #"{"version":"0.3.2"}"#)
        let env = Fixtures.environment(transport: transport, token: Fixtures.token)
        let model = AppModel(environment: env)
        await model.start()
        await model.forgetServer()
        #expect(model.phase == .needsServer)
        #expect(env.settings.string(forKey: AppModel.serverKey) == nil)
        #expect(try env.tokenStore.load() == nil)
    }

    @Test(arguments: [(6.0, true), (8.0, false)])
    func tokenExpiresSoonWithin7Days(daysLeft: Double, soon: Bool) async {
        let now = Fixtures.token.expiresAt.addingTimeInterval(-daysLeft * 86_400)
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/version", json: 200, #"{"version":"0.4.0"}"#)
        let model = AppModel(environment: Fixtures.environment(transport: transport, token: Fixtures.token, now: now))
        await model.start()
        #expect(model.tokenExpiresSoon() == soon)
    }

    @Test func didChangeBumpsVersion() {
        let model = AppModel(environment: Fixtures.environment(transport: FakeTransport()))
        model.didChange()
        #expect(model.changeVersion == 1)
    }
}
