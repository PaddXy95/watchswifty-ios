import Foundation
import OpenAPIRuntime
import WatchSwiftyClient

/// An error as the user sees it: German text, plus what kind it is so a view can offer the right way out
/// (e.g. „TMDB-Token eintragen“). Server messages are shown verbatim (same texts as the web UI).
public struct UserFacingError: Error, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// `{"code", "message"}` from the server.
        case server(code: String)
        case missingTMDBToken
        case offline
        /// Input the app rejects itself (address, file size …).
        case validation
        case unexpected
    }

    public let kind: Kind
    public let message: String

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }

    public init(code: String, message: String) {
        self.init(kind: code == "missingTMDBToken" ? .missingTMDBToken : .server(code: code), message: message)
    }

    public init(_ body: Components.Schemas._Error) {
        self.init(code: body.code, message: body.message)
    }

    public static let offline = UserFacingError(kind: .offline, message: "Server nicht erreichbar.")

    public static func unexpected(status: Int) -> UserFacingError {
        UserFacingError(kind: .unexpected, message: "Unerwartete Antwort vom Server (HTTP \(status)).")
    }

    public static func validation(_ message: String) -> UserFacingError {
        UserFacingError(kind: .validation, message: message)
    }

    public static func from(_ error: any Error) -> UserFacingError {
        switch error {
        case let error as UserFacingError: error
        case let error as ClientError: from(error.underlyingError)
        case is URLError: .offline
        default: UserFacingError(kind: .unexpected, message: "Die Antwort des Servers konnte nicht gelesen werden.")
        }
    }

    /// The task was cancelled (screen closed, newer search): show nothing.
    public static func isCancellation(_ error: any Error) -> Bool {
        switch error {
        case is CancellationError: true
        case let error as URLError: error.code == .cancelled
        case let error as ClientError: isCancellation(error.underlyingError)
        default: false
        }
    }
}
