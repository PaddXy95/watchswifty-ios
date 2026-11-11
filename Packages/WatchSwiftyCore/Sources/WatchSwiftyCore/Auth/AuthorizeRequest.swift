import Foundation

/// What can go wrong during the browser login. `message` is shown to the user.
public enum AuthError: Error, Equatable, Sendable {
    case stateMismatch
    case malformedCallback
    case exchangeFailed(String)

    public var message: String {
        switch self {
        case .stateMismatch, .malformedCallback: "Die Anmeldung konnte nicht bestätigt werden. Bitte erneut versuchen."
        case .exchangeFailed(let message): message
        }
    }
}

/// Result of the redirect back into the app.
public enum CallbackResult: Equatable, Sendable {
    case code(String)
    /// The user tapped „Abbrechen“ on the consent page.
    case denied
}

/// The browser login of the App API (spec 2026-11-08 „Anmeldung der App“): open `/api/auth/authorize`, come back
/// through `dev.patmei.watchswifty:/auth` with a one-time code.
public enum AuthorizeRequest {
    public static let redirectURI = "dev.patmei.watchswifty:/auth"
    public static let callbackScheme = "dev.patmei.watchswifty"

    public static func url(server: ServerAddress, pkce: PKCE, state: String, deviceName: String) -> URL {
        var components = URLComponents(url: server.apiURL.appending(path: "auth/authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "device_name", value: deviceName),
        ]
        return components.url!
    }

    public static func parseCallback(_ url: URL, expectedState: String) throws(AuthError) -> CallbackResult {
        guard url.scheme == callbackScheme,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { throw .malformedCallback }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard value("state") == expectedState else { throw .stateMismatch }
        if value("error") != nil { return .denied }
        guard let code = value("code"), !code.isEmpty else { throw .malformedCallback }
        return .code(code)
    }
}
