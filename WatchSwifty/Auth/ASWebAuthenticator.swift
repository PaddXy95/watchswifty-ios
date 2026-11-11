import AuthenticationServices
import UIKit
import WatchSwiftyCore

/// The browser sheet for the login. Shares cookies with Safari (not ephemeral), so an existing web login only needs
/// „Verbinden“.
final class ASWebAuthenticator: NSObject, WebAuthenticator, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    @MainActor private var session: ASWebAuthenticationSession?

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            Task { @MainActor in
                let session = ASWebAuthenticationSession(url: url, callback: .customScheme(callbackScheme)) { callback, error in
                    if let callback {
                        once.resume(.success(callback))
                    } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                        once.resume(.failure(CancellationError()))
                    } else {
                        once.resume(.failure(error ?? URLError(.unknown)))
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                self.session = session
                if !session.start() { once.resume(.failure(URLError(.cannotLoadFromNetwork))) }
            }
        }
    }

    @MainActor
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor(windowScene: scenes[0])
    }
}

/// Resumes a continuation at most once (the session's completion and a failed `start()` must not both resume it).
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, any Error>?

    init(_ continuation: CheckedContinuation<URL, any Error>) { self.continuation = continuation }

    func resume(_ result: Result<URL, any Error>) {
        let pending = lock.withLock { () -> CheckedContinuation<URL, any Error>? in
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(with: result)
    }
}
