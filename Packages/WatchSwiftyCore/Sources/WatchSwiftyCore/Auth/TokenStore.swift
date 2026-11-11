import Foundation

/// The device token with what the app needs to know about it.
public struct StoredToken: Codable, Sendable, Equatable {
    public let token: String
    public let expiresAt: Date
    /// `Device.id` of this token, to mark „Dieses Gerät“ and to revoke it after renewing.
    public let deviceID: String

    public init(token: String, expiresAt: Date, deviceID: String) {
        self.token = token
        self.expiresAt = expiresAt
        self.deviceID = deviceID
    }
}

public protocol TokenStore: Sendable {
    func load() throws -> StoredToken?
    func save(_ token: StoredToken) throws
    func delete() throws
}

/// For previews and tests; keeps nothing across launches.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: StoredToken?

    public init(_ token: StoredToken? = nil) { stored = token }

    public func load() throws -> StoredToken? { lock.withLock { stored } }
    public func save(_ token: StoredToken) throws { lock.withLock { stored = token } }
    public func delete() throws { lock.withLock { stored = nil } }
}
