import Foundation
import Observation
import OpenAPIRuntime
import WatchSwiftyClient

/// „Konto“: password, e-mail, TMDB token, devices, followed series.
@MainActor @Observable
public final class AccountStore {
    public private(set) var devices = Loadable<[Components.Schemas.Device]>()
    public private(set) var followed = Loadable<[Components.Schemas.FollowedSeries]>()
    public private(set) var busy = false
    public var actionError: UserFacingError?
    /// Short confirmation after a successful change.
    public var notice: String?

    @ObservationIgnored private let api: any APIProtocol
    @ObservationIgnored private let app: AppModel

    public init(api: any APIProtocol, app: AppModel) {
        self.api = api
        self.app = app
    }

    public var me: Components.Schemas.Me? { app.me }
    /// Only accounts with a password, and only while the server allows password login (as in the web).
    public var canChangePassword: Bool { me.map { $0.hasPassword && $0.passwordLogin } ?? false }
    public var currentDeviceID: String? { app.token?.deviceID }
    /// Konto page in the browser (manual tokens, SSO linking).
    public var webAccountURL: URL? { app.server?.baseURL.appending(path: "account") }

    public func isCurrent(_ device: Components.Schemas.Device) -> Bool {
        device.id.caseInsensitiveCompare(currentDeviceID ?? "") == .orderedSame
    }

    public func load() async {
        devices.begin()
        followed.begin()
        let version = app.changeVersion
        let api = api
        async let devicesResult = runCatching { try await api.listDevices().ok.body.json }
        async let followedResult = runCatching { try await api.getFollowed().ok.body.json }
        if let result = await devicesResult { devices.finish(result, at: version) } else { devices.cancel() }
        if let result = await followedResult { followed.finish(result, at: version) } else { followed.cancel() }
        await app.refreshMe()
    }

    public func changePassword(current: String, new: String) async -> Bool {
        await perform(notice: "Passwort geändert.") {
            _ = try await $0.changePassword(body: .json(.init(currentPassword: current, newPassword: new))).noContent
        }
    }

    /// Empty `email` removes the address.
    public func setEmail(_ email: String, currentPassword: String) async -> Bool {
        await perform(notice: "E-Mail-Adresse gespeichert.") { api in
            let me = try await api.setEmail(body: .json(.init(email: email, currentPassword: currentPassword))).ok.body.json
            await self.app.update(me: me)
        }
    }

    public func setTMDBToken(_ token: String) async -> Bool {
        await perform(notice: "TMDB-Token gespeichert.") { api in
            let me = try await api.setTMDBToken(body: .json(.init(token: token))).ok.body.json
            await self.app.update(me: me)
        }
    }

    public func deleteTMDBToken() async {
        _ = await perform(notice: "TMDB-Token entfernt.") { api in
            let me = try await api.deleteTMDBToken().ok.body.json
            await self.app.update(me: me)
        }
    }

    /// Signs out another device; this device is signed out completely.
    public func revokeDevice(id: String) async {
        if id.caseInsensitiveCompare(currentDeviceID ?? "") == .orderedSame {
            await app.signOut()
            return
        }
        let ok = await perform(notice: nil) { _ = try await $0.revokeDevice(path: .init(id: id)).noContent }
        if ok, var list = devices.value {
            list.removeAll { $0.id.caseInsensitiveCompare(id) == .orderedSame }
            devices.value = list
        }
    }

    /// „Jetzt erneuern“: new browser login, then the old device token is revoked with the new one.
    public func renewConnection(using web: any WebAuthenticator) async {
        let old = currentDeviceID
        do {
            try await app.signIn(using: web)
        } catch {
            actionError = error
            return
        }
        guard let old, old != currentDeviceID else { return }
        _ = await perform(notice: "Verbindung erneuert.") { _ = try await $0.revokeDevice(path: .init(id: old)).noContent }
    }

    private func perform(notice message: String?, _ operation: @escaping (any APIProtocol) async throws -> Void) async -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        let api = app.api
        guard let result = await runCatching({ try await operation(api) }) else { return false }
        switch result {
        case .success:
            notice = message
            return true
        case .failure(let error):
            actionError = error
            return false
        }
    }
}
