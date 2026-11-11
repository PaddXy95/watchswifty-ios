import Foundation
import HTTPTypes
import OpenAPIRuntime

/// A request the `FakeTransport` received.
public struct RecordedRequest: Sendable {
    public let request: HTTPRequest
    public let body: Data?
    public var method: HTTPRequest.Method { request.method }
    /// Full path including the API base (`/api/v1/…`), without the query.
    public let path: String
    public let query: String?
}

/// Canned server for tests and SwiftUI previews: answers by `METHOD path` (path including `/api`, without query),
/// records every request. Unknown routes answer `404 notFound`.
public final class FakeTransport: ClientTransport, @unchecked Sendable {
    public typealias Handler = @Sendable (HTTPRequest, Data?) async throws -> (HTTPResponse, HTTPBody?)

    private let lock = NSLock()
    private var handlers: [String: Handler] = [:]
    private var recorded: [RecordedRequest] = []

    public init() {}

    public var requests: [RecordedRequest] { lock.withLock { recorded } }

    public func on(_ method: HTTPRequest.Method, _ path: String, respond: @escaping Handler) {
        lock.withLock { handlers["\(method.rawValue) \(path)"] = respond }
    }

    public func on(_ method: HTTPRequest.Method, _ path: String, json status: Int, _ body: String) {
        on(method, path) { _, _ in FakeTransport.json(status, body) }
    }

    public static func json(_ status: Int, _ body: String) -> (HTTPResponse, HTTPBody?) {
        (HTTPResponse(status: .init(code: status), headerFields: [.contentType: "application/json; charset=utf-8"]),
         HTTPBody(body))
    }

    public static func empty(_ status: Int) -> (HTTPResponse, HTTPBody?) {
        (HTTPResponse(status: .init(code: status)), nil)
    }

    public func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String) async throws
        -> (HTTPResponse, HTTPBody?)
    {
        let data: Data? = if let body { try await Data(collecting: body, upTo: 50 * 1024 * 1024) } else { nil }
        let parts = (request.path ?? "").split(separator: "?", maxSplits: 1).map(String.init)
        let path = baseURL.path + (parts.first ?? "")
        let record = RecordedRequest(request: request, body: data, path: path, query: parts.count > 1 ? parts[1] : nil)
        let handler = lock.withLock { () -> Handler? in
            recorded.append(record)
            return handlers["\(request.method.rawValue) \(path)"]
        }
        guard let handler else { return Self.json(404, #"{"code":"notFound","message":"Nicht gefunden."}"#) }
        return try await handler(request, data)
    }
}
