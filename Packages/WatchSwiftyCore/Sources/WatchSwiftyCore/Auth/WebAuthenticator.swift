import Foundation

/// Opens the login page in a browser sheet and returns the redirect URL. Throws `CancellationError` when the user
/// closes the sheet. The app target implements it with `ASWebAuthenticationSession`.
public protocol WebAuthenticator: Sendable {
    func authenticate(url: URL, callbackScheme: String) async throws -> URL
}
