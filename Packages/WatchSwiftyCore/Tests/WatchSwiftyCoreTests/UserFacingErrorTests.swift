import Foundation
import Testing
import WatchSwiftyClient
@testable import WatchSwiftyCore

@Suite struct UserFacingErrorTests {
    func failure(_ respond: @escaping FakeTransport.Handler) async -> UserFacingError? {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/me", respond: respond)
        let api = makeClient(server: Fixtures.server, middlewares: [APIErrorMiddleware()], transport: transport)
        do {
            _ = try await api.getMe().ok
            return nil
        } catch {
            return UserFacingError.from(error)
        }
    }

    @Test func errorUsesServerMessage() async {
        let error = await failure { _, _ in FakeTransport.json(422, Fixtures.error("validation", "Bitte prüfen.")) }
        #expect(error == UserFacingError(kind: .server(code: "validation"), message: "Bitte prüfen."))
    }

    @Test func missingTMDBTokenKind() async {
        let error = await failure { _, _ in FakeTransport.json(422, Fixtures.error("missingTMDBToken", "Kein Token.")) }
        #expect(error?.kind == .missingTMDBToken)
        #expect(error?.message == "Kein Token.")
    }

    @Test func transportErrorIsOffline() async {
        let error = await failure { _, _ in throw URLError(.cannotConnectToHost) }
        #expect(error == UserFacingError(kind: .offline, message: "Server nicht erreichbar."))
    }

    @Test func undocumentedStatusMessage() async {
        let error = await failure { _, _ in
            (.init(status: .badGateway, headerFields: [.contentType: "text/html"]), .init("<html>Bad gateway</html>"))
        }
        #expect(error == UserFacingError(kind: .unexpected, message: "Unerwartete Antwort vom Server (HTTP 502)."))
    }

    @Test func cancellationIsRecognized() {
        #expect(UserFacingError.isCancellation(CancellationError()))
        #expect(UserFacingError.isCancellation(URLError(.cancelled)))
        #expect(!UserFacingError.isCancellation(URLError(.timedOut)))
    }

    @Test func loadableStaleness() {
        var loadable = Loadable<Int>()
        #expect(loadable.isStale(0))
        loadable.finish(.success(3), at: 2)
        #expect(loadable.value == 3)
        #expect(!loadable.isStale(2))
        #expect(loadable.isStale(3))
        loadable.begin()
        #expect(loadable.isLoading)
        loadable.finish(.failure(.offline), at: 3)
        #expect(loadable.value == 3)
        #expect(loadable.error == .offline)
    }
}
