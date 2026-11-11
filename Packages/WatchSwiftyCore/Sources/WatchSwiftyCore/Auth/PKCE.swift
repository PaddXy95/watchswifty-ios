import CryptoKit
import Foundation

/// Proof Key for Code Exchange (RFC 7636, S256): the app keeps `verifier`, the browser login only sees `challenge`.
public struct PKCE: Sendable {
    public let verifier: String
    public let challenge: String

    public init(verifier: String) {
        self.verifier = verifier
        challenge = Base64URL.encode(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    public static func generate() -> PKCE {
        PKCE(verifier: Base64URL.random(bytes: 32))
    }
}

enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func random(bytes count: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        return encode(Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
    }
}
