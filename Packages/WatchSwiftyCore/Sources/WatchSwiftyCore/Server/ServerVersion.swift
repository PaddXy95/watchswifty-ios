/// Result of comparing the server's version with the oldest one this app supports.
public enum Compatibility: Equatable, Sendable {
    case compatible
    case tooOld(server: String, minimum: String)
}

/// `major.minor.patch` of a server version. A suffix (`0.4.0-beta`) is ignored: beta servers already carry the
/// API of the version they lead up to.
public struct ServerVersion: Comparable, Sendable {
    let parts: [Int]

    public init?(_ string: String) {
        var core = Substring(string)
        if core.hasPrefix("v") { core = core.dropFirst() }
        if let end = core.firstIndex(where: { $0 == "-" || $0 == "+" }) { core = core[..<end] }
        let numbers = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard numbers.count == 3, numbers.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        parts = numbers.map { $0! }
    }

    public static func < (lhs: ServerVersion, rhs: ServerVersion) -> Bool {
        lhs.parts.lexicographicallyPrecedes(rhs.parts)
    }

    /// Versions that cannot be read (e.g. `dev` on a local build) count as compatible.
    public static func check(serverVersion: String, minimum: String) -> Compatibility {
        guard let server = ServerVersion(serverVersion), let required = ServerVersion(minimum), server < required
        else { return .compatible }
        return .tooOld(server: serverVersion, minimum: minimum)
    }
}
