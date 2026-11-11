import CryptoKit
import Foundation
import OpenAPIRuntime
import Testing
@testable import WatchSwiftyCore

@Suite struct AuthTests {
    @Test func pkceMatchesRFC7636() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func generatedVerifierIsBase64URL() {
        let pkce = PKCE.generate()
        #expect(pkce.verifier.count == 43)
        #expect(!pkce.verifier.contains { "=+/".contains($0) })
        #expect(PKCE.generate().verifier != pkce.verifier)
    }

    @Test func authorizeURLContainsAllParameters() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let url = AuthorizeRequest.url(server: Fixtures.subPathServer, pkce: pkce, state: "s1", deviceName: "Pats iPhone ü")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        #expect(url.absoluteString.hasPrefix("https://example.de/watch/api/auth/authorize?"))
        let items = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value!) })
        #expect(items == ["redirect_uri": "dev.patmei.watchswifty:/auth", "state": "s1",
                          "code_challenge": "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
                          "code_challenge_method": "S256", "device_name": "Pats iPhone ü"])
        #expect(url.absoluteString.contains("Pats%20iPhone%20%C3%BC"))
    }

    @Test func callbackWithCode() throws {
        let url = URL(string: "dev.patmei.watchswifty:/auth?code=abc&state=s1")!
        #expect(try AuthorizeRequest.parseCallback(url, expectedState: "s1") == .code("abc"))
    }

    @Test func callbackStateMismatchRejected() {
        let url = URL(string: "dev.patmei.watchswifty:/auth?code=abc&state=evil")!
        #expect(throws: AuthError.stateMismatch) { try AuthorizeRequest.parseCallback(url, expectedState: "s1") }
    }

    @Test func callbackDeniedIsSilent() throws {
        let url = URL(string: "dev.patmei.watchswifty:/auth?error=access_denied&state=s1")!
        #expect(try AuthorizeRequest.parseCallback(url, expectedState: "s1") == .denied)
    }

    @Test func callbackWithoutCodeIsMalformed() {
        let url = URL(string: "dev.patmei.watchswifty:/auth?state=s1")!
        #expect(throws: AuthError.malformedCallback) { try AuthorizeRequest.parseCallback(url, expectedState: "s1") }
    }

    @Test func signInStoresToken() async throws {
        let transport = FakeTransport()
        transport.on(.post, "/api/v1/auth/token", json: 200, Fixtures.tokenGrant)
        let web = FakeWebAuthenticator()
        let store = InMemoryTokenStore()
        let api = makeClient(server: Fixtures.server, middlewares: [], transport: transport)

        let outcome = try await SignIn(api: api, web: web, tokenStore: store).run(server: Fixtures.server, deviceName: "iPhone")

        let expected = StoredToken(token: "ws_abc", expiresAt: Date(timeIntervalSince1970: 1_801_828_800),
                                   deviceID: "6F9619FF-8B86-D011-B42D-00C04FC964FF")
        #expect(outcome == .signedIn(expected))
        #expect(try store.load() == expected)
        let body = try JSONSerialization.jsonObject(with: transport.requests[0].body!) as! [String: String]
        #expect(body["code"] == "abc")
        #expect(body["redirectUri"] == "dev.patmei.watchswifty:/auth")
        #expect(PKCE(verifier: body["codeVerifier"]!).challenge == web.challenge)
        #expect(web.query("device_name") == "iPhone")
    }

    @Test func signInCancelledStoresNothing() async throws {
        let transport = FakeTransport()
        let store = InMemoryTokenStore()
        let api = makeClient(server: Fixtures.server, middlewares: [], transport: transport)
        let outcome = try await SignIn(api: api, web: FakeWebAuthenticator(.cancel), tokenStore: store)
            .run(server: Fixtures.server, deviceName: "iPhone")
        #expect(outcome == .cancelled)
        #expect(try store.load() == nil)
        #expect(transport.requests.isEmpty)
    }

    @Test func signInDeniedIsCancelled() async throws {
        let api = makeClient(server: Fixtures.server, middlewares: [], transport: FakeTransport())
        let outcome = try await SignIn(api: api, web: FakeWebAuthenticator(.deny), tokenStore: InMemoryTokenStore())
            .run(server: Fixtures.server, deviceName: "iPhone")
        #expect(outcome == .cancelled)
    }

    @Test func signInWithForeignStateFails() async {
        let api = makeClient(server: Fixtures.server, middlewares: [], transport: FakeTransport())
        await #expect(throws: AuthError.stateMismatch) {
            try await SignIn(api: api, web: FakeWebAuthenticator(.wrongState), tokenStore: InMemoryTokenStore())
                .run(server: Fixtures.server, deviceName: "iPhone")
        }
    }

    @Test func signInBadCodeShowsServerMessage() async {
        let transport = FakeTransport()
        transport.on(.post, "/api/v1/auth/token", json: 400,
                     Fixtures.error("invalidGrant", "Der Anmeldecode ist ungültig oder abgelaufen."))
        let api = makeClient(server: Fixtures.server, middlewares: [], transport: transport)
        await #expect(throws: AuthError.exchangeFailed("Der Anmeldecode ist ungültig oder abgelaufen.")) {
            try await SignIn(api: api, web: FakeWebAuthenticator(), tokenStore: InMemoryTokenStore())
                .run(server: Fixtures.server, deviceName: "iPhone")
        }
    }
}
