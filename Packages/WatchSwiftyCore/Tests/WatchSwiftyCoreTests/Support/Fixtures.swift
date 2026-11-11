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
