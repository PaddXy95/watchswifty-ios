import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Adds `Authorization: Bearer ws_…` and reports every `401` (expired or revoked token) together with the token
/// that was sent, so a late answer for an older token can be told apart. Never logs the token.
public struct AuthMiddleware: ClientMiddleware {
    let token: @Sendable () -> String?
    let onUnauthorized: @Sendable (_ usedToken: String?) -> Void

    public init(token: @escaping @Sendable () -> String?, onUnauthorized: @escaping @Sendable (_ usedToken: String?) -> Void) {
        self.token = token
        self.onUnauthorized = onUnauthorized
    }

    public func intercept(
        _ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        let token = token()
        if let token { request.headerFields[.authorization] = "Bearer \(token)" }
        let (response, responseBody) = try await next(request, body, baseURL)
        if response.status == .unauthorized { onUnauthorized(token) }
        return (response, responseBody)
    }
}
