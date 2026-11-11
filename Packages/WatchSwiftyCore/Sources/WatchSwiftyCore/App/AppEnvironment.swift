import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

/// Everything `AppModel` touches outside itself; tests and previews pass fakes.
public struct AppEnvironment: @unchecked Sendable {
    public var tokenStore: any TokenStore
    public var settings: UserDefaults
    public var transport: any ClientTransport
    /// The remembered start page (cleared on sign-out and when the server changes).
    public var snapshot: SnapshotCache
    public var minimumServerVersion: String
    public var now: @Sendable () -> Date

    public init(tokenStore: any TokenStore, settings: UserDefaults, transport: any ClientTransport,
                snapshot: SnapshotCache, minimumServerVersion: String = AppInfo.minimumServerVersion,
                now: @escaping @Sendable () -> Date = { .now }) {
        self.tokenStore = tokenStore
        self.settings = settings
        self.transport = transport
        self.snapshot = snapshot
        self.minimumServerVersion = minimumServerVersion
        self.now = now
    }

    public static func live() -> AppEnvironment {
        // 15 s instead of URLSession's 60 s: away from the home network or VPN the server simply does not answer.
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        let transport = URLSessionTransport(configuration: .init(session: URLSession(configuration: configuration)))
        return AppEnvironment(tokenStore: KeychainTokenStore(), settings: .standard, transport: transport, snapshot: .live())
    }
}
