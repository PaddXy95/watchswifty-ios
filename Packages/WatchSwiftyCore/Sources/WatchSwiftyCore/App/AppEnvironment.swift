import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

/// Everything `AppModel` touches outside itself; tests and previews pass fakes.
public struct AppEnvironment: @unchecked Sendable {
    public var tokenStore: any TokenStore
    public var settings: UserDefaults
    public var transport: any ClientTransport
    public var minimumServerVersion: String
    public var now: @Sendable () -> Date

    public init(tokenStore: any TokenStore, settings: UserDefaults, transport: any ClientTransport,
                minimumServerVersion: String = AppInfo.minimumServerVersion, now: @escaping @Sendable () -> Date = { .now }) {
        self.tokenStore = tokenStore
        self.settings = settings
        self.transport = transport
        self.minimumServerVersion = minimumServerVersion
        self.now = now
    }

    public static func live() -> AppEnvironment {
        AppEnvironment(tokenStore: KeychainTokenStore(), settings: .standard, transport: URLSessionTransport())
    }
}
