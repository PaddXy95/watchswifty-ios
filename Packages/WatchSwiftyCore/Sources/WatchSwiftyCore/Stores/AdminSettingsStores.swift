import Foundation
import Observation
import OpenAPIRuntime
import WatchSwiftyClient

private extension String {
    /// `nil` for empty input (the server keeps the stored value or leaves the field unset).
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// „System“: version and the update check.
@MainActor @Observable
public final class SystemStore {
    public private(set) var system = Loadable<Components.Schemas.System>()
    public private(set) var busy = false
    public var actionError: UserFacingError?

    @ObservationIgnored private let api: any APIProtocol
    @ObservationIgnored private let app: AppModel

    public init(api: any APIProtocol, app: AppModel) {
        self.api = api
        self.app = app
    }

    public func load() async {
        system.begin()
        let version = app.changeVersion
        let api = api
        guard let result = await runCatching({ try await api.getSystem().ok.body.json }) else { return system.cancel() }
        system.finish(result, at: version)
    }

    public func setUpdateCheck(_ enabled: Bool) async {
        await replace { try await $0.setUpdateCheck(body: .json(.init(enabled: enabled))).ok.body.json }
    }

    public func checkNow() async {
        await replace { try await $0.checkUpdatesNow().ok.body.json }
    }

    private func replace(_ operation: @escaping (any APIProtocol) async throws -> Components.Schemas.System) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let api = api
        switch await runCatching({ try await operation(api) }) {
        case .success(let value)?:
            system.value = value
        case .failure(let error)?:
            actionError = error
        case nil:
            break
        }
    }
}

/// „Anmeldung über OIDC (SSO)“: provider settings, connection test, password login switch.
@MainActor @Observable
public final class OIDCSettingsStore {
    public private(set) var settings = Loadable<Components.Schemas.OIDCSettings>()
    public private(set) var busy = false
    public var actionError: UserFacingError?
    public var notice: String?

    @ObservationIgnored private let api: any APIProtocol
    @ObservationIgnored private let app: AppModel

    public init(api: any APIProtocol, app: AppModel) {
        self.api = api
        self.app = app
    }

    public func load() async {
        settings.begin()
        let version = app.changeVersion
        let api = api
        guard let result = await runCatching({ try await api.getOIDCSettings().ok.body.json }) else { return settings.cancel() }
        settings.finish(result, at: version)
    }

    /// Empty client secret keeps the stored one (the server refuses that when issuer or client ID change).
    public func save(displayName: String, issuer: String, clientID: String, clientSecret: String, baseURL: String) async -> Bool {
        let update = Components.Schemas.OIDCSettingsUpdate(displayName: displayName.nonEmpty, issuer: issuer.trimmingCharacters(in: .whitespaces),
                                                           clientId: clientID.trimmingCharacters(in: .whitespaces),
                                                           clientSecret: clientSecret.nonEmpty,
                                                           baseUrl: baseURL.trimmingCharacters(in: .whitespaces))
        guard let saved = await perform({ try await $0.setOIDCSettings(body: .json(update)).ok.body.json }) else { return false }
        settings.value = saved
        notice = saved.checkError.map { "Gespeichert, aber die Prüfung schlug fehl: \($0)" } ?? "Gespeichert."
        return true
    }

    public func test() async {
        guard let check = await perform({ try await $0.testOIDCSettings().ok.body.json }) else { return }
        notice = "Verbindung in Ordnung: \(check.keyCount) Schlüssel von \(check.issuer)."
    }

    public func delete() async {
        guard await perform({ _ = try await $0.deleteOIDCSettings().noContent }) != nil else { return }
        await load()
    }

    public func setPasswordLogin(_ enabled: Bool) async {
        guard let saved = await perform({ try await $0.setPasswordLogin(body: .json(.init(enabled: enabled))).ok.body.json }) else { return }
        settings.value = saved
        await app.refreshMe()
    }

    private func perform<T: Sendable>(_ operation: @escaping (any APIProtocol) async throws -> T) async -> T? {
        guard !busy else { return nil }
        busy = true
        defer { busy = false }
        let api = api
        switch await runCatching({ try await operation(api) }) {
        case .success(let value)?: return value
        case .failure(let error)?: actionError = error; return nil
        case nil: return nil
        }
    }
}

/// The mail form's fields as typed (text), turned into the API's update.
public struct MailForm: Sendable, Equatable {
    public var host: String
    public var port: String
    public var encryption: Components.Schemas.MailEncryption
    public var username: String
    /// Empty keeps the stored password.
    public var password: String
    public var fromAddress: String
    public var fromName: String
    public var caFile: String
    public var baseURL: String

    public init(host: String = "", port: String = "", encryption: Components.Schemas.MailEncryption = .starttls,
                username: String = "", password: String = "", fromAddress: String = "", fromName: String = "",
                caFile: String = "", baseURL: String = "") {
        self.host = host
        self.port = port
        self.encryption = encryption
        self.username = username
        self.password = password
        self.fromAddress = fromAddress
        self.fromName = fromName
        self.caFile = caFile
        self.baseURL = baseURL
    }

    public init(_ settings: Components.Schemas.MailSettings) {
        self.init(host: settings.host ?? "", port: settings.port.map(String.init) ?? "", encryption: settings.encryption ?? .starttls,
                  username: settings.username ?? "", fromAddress: settings.fromAddress ?? "", fromName: settings.fromName ?? "",
                  caFile: settings.caFile ?? "", baseURL: settings.baseUrl ?? "")
    }

    var update: Components.Schemas.MailSettingsUpdate {
        .init(host: host.trimmingCharacters(in: .whitespaces), port: Int(port.trimmingCharacters(in: .whitespaces)),
              encryption: encryption, username: username.nonEmpty, password: password.isEmpty ? nil : password,
              fromAddress: fromAddress.trimmingCharacters(in: .whitespaces), fromName: fromName.nonEmpty,
              caFile: caFile.nonEmpty, baseUrl: baseURL.trimmingCharacters(in: .whitespaces))
    }
}

/// „Mail“: SMTP settings and a test mail.
@MainActor @Observable
public final class MailSettingsStore {
    public private(set) var settings = Loadable<Components.Schemas.MailSettings>()
    public private(set) var busy = false
    public var actionError: UserFacingError?
    public var notice: String?

    @ObservationIgnored private let api: any APIProtocol
    @ObservationIgnored private let app: AppModel

    public init(api: any APIProtocol, app: AppModel) {
        self.api = api
        self.app = app
    }

    public func load() async {
        settings.begin()
        let version = app.changeVersion
        let api = api
        guard let result = await runCatching({ try await api.getMailSettings().ok.body.json }) else { return settings.cancel() }
        settings.finish(result, at: version)
    }

    public func save(_ form: MailForm) async -> Bool {
        let update = form.update
        guard let saved = await perform({ try await $0.setMailSettings(body: .json(update)).ok.body.json }) else { return false }
        settings.value = saved
        notice = "Gespeichert."
        return true
    }

    public func sendTest(to address: String) async {
        guard await perform({ _ = try await $0.sendTestMail(body: .json(.init(to: address))).noContent }) != nil else { return }
        notice = "Testmail an \(address) verschickt."
    }

    public func delete() async {
        guard await perform({ _ = try await $0.deleteMailSettings().noContent }) != nil else { return }
        await load()
    }

    private func perform<T: Sendable>(_ operation: @escaping (any APIProtocol) async throws -> T) async -> T? {
        guard !busy else { return nil }
        busy = true
        defer { busy = false }
        let api = api
        switch await runCatching({ try await operation(api) }) {
        case .success(let value)?: return value
        case .failure(let error)?: actionError = error; return nil
        case nil: return nil
        }
    }
}
