import Foundation
import OpenAPIRuntime
import WatchSwiftyClient

public enum SignInOutcome: Equatable, Sendable {
    case signedIn(StoredToken)
    /// Closed the sheet or tapped „Abbrechen“: no error message.
    case cancelled
}

/// One browser login: PKCE + state, consent in the browser, code exchange, token into the store.
public struct SignIn: Sendable {
    let api: any APIProtocol
    let web: any WebAuthenticator
    let tokenStore: any TokenStore

    public init(api: any APIProtocol, web: any WebAuthenticator, tokenStore: any TokenStore) {
        self.api = api
        self.web = web
        self.tokenStore = tokenStore
    }

    public func run(server: ServerAddress, deviceName: String) async throws(AuthError) -> SignInOutcome {
        let pkce = PKCE.generate()
        let state = Base64URL.random(bytes: 16)
        let url = AuthorizeRequest.url(server: server, pkce: pkce, state: state, deviceName: deviceName)

        let callback: URL
        do {
            callback = try await web.authenticate(url: url, callbackScheme: AuthorizeRequest.callbackScheme)
        } catch is CancellationError {
            return .cancelled
        } catch {
            throw .exchangeFailed("Das Anmeldefenster konnte nicht geöffnet werden.")
        }
        guard case .code(let code) = try AuthorizeRequest.parseCallback(callback, expectedState: state) else {
            return .cancelled
        }

        let grant: Components.Schemas.TokenGrant
        do {
            let request = Components.Schemas.TokenRequest(code: code, codeVerifier: pkce.verifier,
                                                         redirectUri: AuthorizeRequest.redirectURI)
            switch try await api.createToken(body: .json(request)) {
            case .ok(let ok): grant = try ok.body.json
            case .badRequest(let failure): throw AuthError.exchangeFailed(try failure.body.json.message)
            case .undocumented(let status, _):
                throw AuthError.exchangeFailed("Unerwartete Antwort vom Server (HTTP \(status)).")
            }
        } catch let error as AuthError {
            throw error
        } catch {
            // With APIErrorMiddleware the 400 arrives as a thrown UserFacingError; network errors map to „offline“.
            throw .exchangeFailed(UserFacingError.from(error).message)
        }

        let token = StoredToken(token: grant.token, expiresAt: grant.expiresAt, deviceID: grant.device.id)
        do { try tokenStore.save(token) } catch { throw .exchangeFailed("Das Token konnte nicht gespeichert werden.") }
        return .signedIn(token)
    }
}
