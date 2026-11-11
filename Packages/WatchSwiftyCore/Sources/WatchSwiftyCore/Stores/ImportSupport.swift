import Foundation
import OpenAPIRuntime

/// Reading a picked file (Dateien-App) and the size limits of the server.
public enum ImportFile {
    public static let netflixLimit = 10_485_760
    public static let filmListLimit = 2_097_152
    public static let tooLarge = UserFacingError.validation("Die Datei ist zu groß.")

    /// Reads a file from the document picker (security-scoped URL).
    public static func read(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }
}
