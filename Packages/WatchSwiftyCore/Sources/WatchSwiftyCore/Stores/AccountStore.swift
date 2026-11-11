import Foundation
import Observation
import OpenAPIRuntime
import WatchSwiftyClient

/// „Konto“: password, e-mail, TMDB token, notifications, devices, followed series.
@MainActor @Observable
public final class AccountStore {
    public private(set) var devices = Loadable<[Components.Schemas.Device]>()
    public private(set) var followed = Loadable<[Components.Schemas.FollowedSeries]>()
    /// Konto → Benachrichtigungen; stays empty on a server without notifications.
    public private(set) var notifications = Loadable<Components.Schemas.NotificationPrefs>()
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
    /// Setting or removing the KNot key asks for the current password on accounts that have one (SSO-only ones have none).
    public var webhookKeyNeedsPassword: Bool { me?.hasPassword ?? true }
    /// Konto page in the browser (manual tokens, SSO linking).
    public var webAccountURL: URL? { app.server?.baseURL.appending(path: "account") }

    public func isCurrent(_ device: Components.Schemas.Device) -> Bool {
        device.id.caseInsensitiveCompare(currentDeviceID ?? "") == .orderedSame
    }

    public func load() async {
        devices.begin()
        followed.begin()
        notifications.begin()
        let version = app.changeVersion
        let api = api
        async let devicesResult = runCatching { try await api.listDevices().ok.body.json }
        async let followedResult = runCatching { try await api.getFollowed().ok.body.json }
        async let notificationsResult = runCatching { try await api.getNotificationPrefs().ok.body.json }
        if let result = await devicesResult { devices.finish(result, at: version) } else { devices.cancel() }
        if let result = await followedResult { followed.finish(result, at: version) } else { followed.cancel() }
        if let result = await notificationsResult { notifications.finish(result, at: version) } else { notifications.cancel() }
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

    /// Saves the three switches and the channel at once (no password). The change shows right away and is undone when
    /// saving fails. Without a choice between channels the stored `channel` is sent unchanged.
    public func updateNotifications(_ change: (inout Components.Schemas.NotificationPrefsUpdate) -> Void) async {
        guard !busy, let current = notifications.value else { return }
        var update = current.update
        change(&update)
        guard update != current.update else { return }
        var shown = current
        shown.announced = update.announced
        shown.soon = update.soon
        shown.today = update.today
        shown.channel = update.channel
        if current.availableChannels.contains(update.channel) { shown.activeChannel = update.channel }
        notifications.value = shown
        let body = update
        if let saved = await run({ try await $0.setNotificationPrefs(body: .json(body)).ok.body.json }) {
            notifications.value = saved
        } else if notifications.value == shown {
            notifications.value = current
        }
    }

    /// Stores the KNot key (sealed on the server, never shown again).
    public func setWebhookKey(_ key: String, currentPassword: String) async -> Bool {
        let body = Components.Schemas.WebhookKeyChange(key: key.trimmingCharacters(in: .whitespacesAndNewlines),
                                                       currentPassword: webhookKeyNeedsPassword ? currentPassword : nil)
        guard let saved = await run({ try await $0.setWebhookKey(body: .json(body)).ok.body.json }) else { return false }
        notifications.value = saved
        notice = "Webhook-Schlüssel gespeichert."
        return true
    }

    public func deleteWebhookKey(currentPassword: String) async -> Bool {
        let body: Operations.deleteWebhookKey.Input.Body? = webhookKeyNeedsPassword ? .json(.init(currentPassword: currentPassword)) : nil
        guard let saved = await run({ try await $0.deleteWebhookKey(body: body).ok.body.json }) else { return false }
        notifications.value = saved
        notice = "Webhook-Schlüssel entfernt."
        return true
    }

    /// Sends a short message over the channel in use; the server's reason is shown when that fails.
    public func sendTestNotification() async {
        _ = await perform(notice: "Testnachricht gesendet.") { _ = try await $0.sendTestNotification().noContent }
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
        guard await run(operation) != nil else { return false }
        notice = message
        return true
    }

    /// One change at a time; failures go to `actionError`, `nil` also when cancelled.
    private func run<T: Sendable>(_ operation: @escaping (any APIProtocol) async throws -> T) async -> T? {
        guard !busy else { return nil }
        busy = true
        defer { busy = false }
        let api = app.api
        switch await runCatching({ try await operation(api) }) {
        case .success(let value)?: return value
        case .failure(let error)?: actionError = error; return nil
        case nil: return nil
        }
    }
}

extension Components.Schemas.NotificationPrefs {
    /// The stored choice as an update (switches and the stored, not the active, channel).
    public var update: Components.Schemas.NotificationPrefsUpdate {
        .init(announced: announced, soon: soon, today: today, channel: channel)
    }
}
