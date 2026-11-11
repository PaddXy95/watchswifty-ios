import Foundation
import Observation
import OpenAPIRuntime
import WatchSwiftyClient

/// Connection state of the app: which server, whether signed in, who is signed in, and a counter that tells screens
/// their data may be outdated (`changeVersion`, spec „Schichten“).
@MainActor @Observable
public final class AppModel {
    public enum Phase: Equatable, Sendable {
        case launching, needsServer, needsLogin
        case serverTooOld(server: String, minimum: String)
        case ready
    }

    public nonisolated static let serverKey = "serverAddress"
    public nonisolated static let deviceNameKey = "deviceName"

    public private(set) var phase: Phase = .launching
    public private(set) var server: ServerAddress?
    public private(set) var me: Components.Schemas.Me?
    public private(set) var token: StoredToken?
    public private(set) var changeVersion = 0
    /// One-off hint for the login screen, e.g. after an expired token.
    public var notice: String?
    public var deviceName: String {
        didSet { environment.settings.set(deviceName, forKey: Self.deviceNameKey) }
    }
    /// Client for the current server, with error mapping and the bearer token.
    public private(set) var api: any APIProtocol

    @ObservationIgnored let environment: AppEnvironment
    @ObservationIgnored private let currentToken = TokenBox()

    public init(environment: AppEnvironment, defaultDeviceName: String = "iPhone") {
        self.environment = environment
        deviceName = environment.settings.string(forKey: Self.deviceNameKey) ?? defaultDeviceName
        api = makeClient(server: Fixed.placeholder, middlewares: [], transport: environment.transport)
    }

    // MARK: Start and server

    public func start() async {
        guard let stored = environment.settings.string(forKey: Self.serverKey),
              let server = try? ServerAddress.parse(stored)
        else {
            phase = .needsServer
            return
        }
        use(server: server)
        token = try? environment.tokenStore.load()
        currentToken.set(token?.token)

        if let version = try? await api.getVersion().ok.body.json.version,
           case .tooOld(let serverVersion, let minimum) = ServerVersion.check(serverVersion: version,
                                                                              minimum: environment.minimumServerVersion) {
            phase = .serverTooOld(server: serverVersion, minimum: minimum)
            return
        }
        guard token != nil else {
            phase = .needsLogin
            return
        }
        phase = .ready
        await refreshMe()
    }

    /// Checks the entered address („Weiter“ on the first screen) and remembers it.
    public func connect(to input: String) async throws(UserFacingError) {
        let server: ServerAddress
        do { server = try ServerAddress.parse(input) } catch { throw .validation(error.message) }

        let probe = makeClient(server: server, middlewares: [], transport: environment.transport)
        let version: String
        do {
            version = try await probe.getVersion().ok.body.json.version
        } catch {
            if case .offline = UserFacingError.from(error).kind { throw .offline }
            throw .validation("Unter dieser Adresse antwortet kein WatchSwifty-Server.")
        }
        if case .tooOld(let serverVersion, let minimum) = ServerVersion.check(serverVersion: version,
                                                                              minimum: environment.minimumServerVersion) {
            throw .validation("Der Server ist zu alt (\(serverVersion)). Diese App braucht mindestens \(minimum).")
        }
        environment.settings.set(server.baseURL.absoluteString, forKey: Self.serverKey)
        use(server: server)
        phase = .needsLogin
    }

    /// „Anderen Server wählen“: forget server and token (the token belongs to that server).
    public func forgetServer() async {
        if token != nil { _ = try? await api.revokeCurrentToken() }
        clearToken()
        environment.settings.removeObject(forKey: Self.serverKey)
        server = nil
        phase = .needsServer
    }

    // MARK: Login

    public func signIn(using web: any WebAuthenticator) async throws(UserFacingError) {
        guard let server else { return }
        let outcome: SignInOutcome
        do {
            outcome = try await SignIn(api: api, web: web, tokenStore: environment.tokenStore)
                .run(server: server, deviceName: deviceName)
        } catch {
            throw UserFacingError(kind: .validation, message: error.message)
        }
        guard case .signedIn(let newToken) = outcome else { return }
        token = newToken
        currentToken.set(newToken.token)
        notice = nil
        phase = .ready
        await refreshMe()
    }

    public func signOut() async {
        _ = try? await api.revokeCurrentToken()
        clearToken()
        phase = .needsLogin
    }

    /// A request came back `401`. Only the token that was actually sent counts: a late answer to a request made with
    /// an older token must not sign out the new session. Idempotent for many parallel failures.
    public func handleUnauthorized(usedToken: String?) {
        guard phase == .ready, let token, usedToken == token.token else { return }
        clearToken()
        notice = "Bitte erneut verbinden."
        phase = .needsLogin
    }

    public func refreshMe() async {
        if let me = try? await api.getMe().ok.body.json { self.me = me }
    }

    /// The device token runs out within 7 days („Verbindung läuft am … ab – jetzt erneuern“).
    public func tokenExpiresSoon() -> Bool {
        guard let token else { return false }
        return token.expiresAt.timeIntervalSince(environment.now()) < 7 * 86_400
    }

    /// Something was changed on the server; screens reload when they appear next.
    public func didChange() { changeVersion += 1 }

    // MARK: Private

    private func use(server: ServerAddress) {
        self.server = server
        let box = currentToken
        let auth = AuthMiddleware(token: { box.get() }, onUnauthorized: { [weak self] usedToken in
            Task { @MainActor in self?.handleUnauthorized(usedToken: usedToken) }
        })
        api = makeClient(server: server, middlewares: [APIErrorMiddleware(), auth], transport: environment.transport)
    }

    private func clearToken() {
        try? environment.tokenStore.delete()
        token = nil
        me = nil
        currentToken.set(nil)
    }

    private enum Fixed {
        static let placeholder = try! ServerAddress.parse("https://localhost")
    }
}

/// The token for the middleware, which runs off the main actor.
final class TokenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    func get() -> String? { lock.withLock { value } }
    func set(_ newValue: String?) { lock.withLock { value = newValue } }
}
