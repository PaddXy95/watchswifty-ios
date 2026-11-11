import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Adds `Authorization: Bearer ws_…` and reports every `401` (expired or revoked token). Never logs the token.
public struct AuthMiddleware: ClientMiddleware {
    let token: @Sendable () -> String?
    let onUnauthorized: @Sendable () -> Void

    public init(token: @escaping @Sendable () -> String?, onUnauthorized: @escaping @Sendable () -> Void) {
        self.token = token
        self.onUnauthorized = onUnauthorized
    }

    public func intercept(
        _ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        if let token = token() { request.headerFields[.authorization] = "Bearer \(token)" }
        let (response, responseBody) = try await next(request, body, baseURL)
        if response.status == .unauthorized { onUnauthorized() }
        return (response, responseBody)
    }
}
