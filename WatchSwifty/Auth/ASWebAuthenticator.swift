import AuthenticationServices
import UIKit
import WatchSwiftyCore

/// The browser sheet for the login. Shares cookies with Safari (not ephemeral), so an existing web login only needs
/// „Verbinden“.
final class ASWebAuthenticator: NSObject, WebAuthenticator, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    @MainActor private var session: ASWebAuthenticationSession?

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let session = ASWebAuthenticationSession(url: url, callback: .customScheme(callbackScheme)) { callback, error in
                    if let callback {
                        continuation.resume(returning: callback)
                    } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuation.resume(throwing: error ?? URLError(.unknown))
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                self.session = session
                if !session.start() { continuation.resume(throwing: URLError(.cannotLoadFromNetwork)) }
            }
        }
    }

    @MainActor
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor(windowScene: scenes[0])
    }
}
