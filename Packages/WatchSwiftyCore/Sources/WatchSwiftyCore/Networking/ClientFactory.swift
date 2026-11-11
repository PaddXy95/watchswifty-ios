import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
import WatchSwiftyClient

/// The generated client for one server. Tests and previews pass a `FakeTransport`.
public func makeClient(server: ServerAddress, middlewares: [any ClientMiddleware],
                       transport: any ClientTransport = URLSessionTransport()) -> Client {
    Client(serverURL: server.apiURL, transport: transport, middlewares: middlewares)
}
