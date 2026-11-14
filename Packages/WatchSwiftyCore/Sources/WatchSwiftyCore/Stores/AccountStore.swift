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
    /// Konto → TMDB-Token → „Alle Daten von TMDB neu laden“: progress of the last run since the server started; `nil`
    /// until loaded and on servers before 0.5.1, which have no reload.
    public private(set) var libraryRefresh: Components.Schemas.LibraryRefresh?
    public private(set) var busy = false
    public var actionError: UserFacingError?
    /// Short confirmation after a successful change.
    public var notice: String?

    @ObservationIgnored private let api: any APIProtocol
    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private let pollInterval: Duration

    public init(api: any APIProtocol, app: AppModel, pollInterval: Duration = .seconds(2)) {
        self.api = api
        self.app = app
        self.pollInterval = pollInterval
    }

    public var me: Components.Schemas.Me? { app.me }
    /// Only accounts with a password, and only while the server allows password login (as in the web).
    public var canChangePassword: Bool { me.map { $0.hasPassword && $0.passwordLogin } ?? false }
    public var currentDeviceID: String? { app.token?.deviceID }
    /// Servers before 0.5.0 ask for the current password when the KNot key is set or removed, on accounts that have
    /// one (SSO-only ones have none); newer servers need none and ignore it.
    public var webhookKeyNeedsPassword: Bool {
        guard me?.hasPassword ?? true else { return false }
        guard let reported = app.serverVersion else { return true }   // not answered yet: ask, an old server needs it
        guard let version = ServerVersion(reported) else { return false }   // e.g. `dev`: a current build
        return version < Self.webhookKeyWithoutPassword
    }

    private static let webhookKeyWithoutPassword = ServerVersion("0.5.0")!
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
        async let refresh: Void = loadLibraryRefresh()
        if let result = await devicesResult { devices.finish(result, at: version) } else { devices.cancel() }
        if let result = await followedResult { followed.finish(result, at: version) } else { followed.cancel() }
        if let result = await notificationsResult { notifications.finish(result, at: version) } else { notifications.cancel() }
        await refresh
        await app.refreshMe()
    }

    /// „Alle Daten von TMDB neu laden“: the server reloads every title of the account in the background with the own
    /// token; a run that is already going is returned instead of a new one. Follow it with `pollLibraryRefresh()`.
    public func startLibraryRefresh() async {
        guard let state = await run({ try await $0.startLibraryRefresh().accepted.body.json }) else { return }
        libraryRefresh = state
    }

    /// Asks every `pollInterval` for the progress while a run is going; stops when it is done or when the task is
    /// cancelled (screen closed). A finished run marks the data as changed, so open screens reload the new titles.
    public func pollLibraryRefresh() async {
        while libraryRefresh?.running == true, !Task.isCancelled {
            try? await Task.sleep(for: pollInterval)
            guard !Task.isCancelled else { return }
            await loadLibraryRefresh()
        }
    }

    /// A failure (also a server without the reload) keeps what is shown; the section hides while nothing was read.
    private func loadLibraryRefresh() async {
        let api = api
        guard case .success(let state)? = await runCatching({ try await api.getLibraryRefresh().ok.body.json }) else { return }
        let finished = libraryRefresh?.running == true && !state.running
        libraryRefresh = state
        if finished { app.didChange() }
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
