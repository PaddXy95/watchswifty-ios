import Foundation

/// Why an entered server address is not accepted. `message` is shown to the user.
public enum ServerAddressError: Error, Equatable, Sendable {
    case empty, invalid, insecurePublic

    public var message: String {
        switch self {
        case .empty: "Bitte die Adresse deines WatchSwifty-Servers eingeben."
        case .invalid: "Das ist keine gültige Server-Adresse."
        case .insecurePublic: "Bitte eine https://-Adresse verwenden – sonst wäre die Anmeldung unverschlüsselt."
        }
    }
}

/// The address of a self-hosted WatchSwifty server, normalized (lowercase scheme and host, no trailing slash, no
/// query). Plain `http://` is only accepted for private targets (home network, VPN), where the tunnel or the LAN
/// protects the login; anywhere else the token would travel unencrypted (spec „Netzwerk“).
public struct ServerAddress: Sendable, Hashable, Codable {
    public let baseURL: URL

    /// Base of the App API; the generated client appends `/v1/…`.
    public var apiURL: URL { baseURL.appending(path: "api") }
    public var isInsecure: Bool { baseURL.scheme == "http" }

    public static func parse(_ input: String) throws(ServerAddressError) -> ServerAddress {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .empty }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard var components = URLComponents(string: withScheme),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let rawHost = components.host, !rawHost.isEmpty
        else { throw .invalid }
        let host = rawHost.lowercased()
        if scheme == "http", !Self.isPrivate(host: host) { throw .insecurePublic }

        components.scheme = scheme
        components.host = host
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        while components.path.hasSuffix("/") { components.path.removeLast() }
        guard let url = components.url else { throw .invalid }
        return ServerAddress(baseURL: url)
    }

    private static let privateSuffixes = [".local", ".lan", ".home.arpa", ".internal"]

    /// Private IP ranges, single-label names and local-only suffixes.
    static func isPrivate(host rawHost: String) -> Bool {
        var host = rawHost
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        if host.hasSuffix(".") { host.removeLast() }

        var v4 = in_addr()
        if inet_pton(AF_INET, host, &v4) == 1 {
            let b = withUnsafeBytes(of: v4.s_addr) { Array($0) }   // network byte order
            return b[0] == 10 || b[0] == 127
                || (b[0] == 172 && (16...31).contains(b[1]))
                || (b[0] == 192 && b[1] == 168)
                || (b[0] == 100 && (64...127).contains(b[1]))
        }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, host, &v6) == 1 {
            let b = withUnsafeBytes(of: v6) { Array($0) }
            let isLoopback = b.dropLast().allSatisfy { $0 == 0 } && b.last == 1
            return isLoopback || (b[0] & 0xFE) == 0xFC
        }
        if !host.contains(".") { return true }
        return privateSuffixes.contains { host.hasSuffix($0) }
    }
}
