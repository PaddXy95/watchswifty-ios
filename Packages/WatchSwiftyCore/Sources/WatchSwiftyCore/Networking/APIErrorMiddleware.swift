import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Turns every error response (status ≥ 400) into a thrown `UserFacingError` with the server's code and message, so
/// stores only handle success cases (`try await api.x().ok.body.json`). Put it before `AuthMiddleware`, which must
/// still see the 401.
public struct APIErrorMiddleware: ClientMiddleware {
    private struct Body: Decodable { let code: String; let message: String }

    public init() {}

    public func intercept(
        _ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let (response, responseBody) = try await next(request, body, baseURL)
        guard response.status.code >= 400 else { return (response, responseBody) }
        let data = if let responseBody { try? await Data(collecting: responseBody, upTo: 1024 * 1024) } else { Data?.none }
        if let data, let error = try? JSONDecoder().decode(Body.self, from: data) {
            throw UserFacingError(code: error.code, message: error.message)
        }
        throw UserFacingError.unexpected(status: response.status.code)
    }
}
