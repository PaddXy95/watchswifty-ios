import Foundation
import Observation
import OpenAPIRuntime
import WatchSwiftyClient

/// „Benutzer“ (admins only): create, invite, reset passwords, SSO links, admin rights, delete. Never on the own
/// account (the server refuses it; the screen does not offer it).
@MainActor @Observable
public final class AdminUsersStore {
    public private(set) var users = Loadable<[Components.Schemas.UserSummary]>()
    public private(set) var busy = false
    public var actionError: UserFacingError?
    public var notice: String?
    /// A link that is shown exactly once (SSO link not sent by mail).
    public private(set) var oneTimeLink: String?

    @ObservationIgnored private let api: any APIProtocol
    @ObservationIgnored private let app: AppModel

    public init(api: any APIProtocol, app: AppModel) {
        self.api = api
        self.app = app
    }

    public func isSelf(_ user: Components.Schemas.UserSummary) -> Bool { user.username == app.me?.username }

    public func load() async {
        users.begin()
        let version = app.changeVersion
        let api = api
        guard let result = await runCatching({ try await api.listUsers().ok.body.json }) else { return users.cancel() }
        users.finish(result, at: version)
    }

    /// With a password: a normal account; without, but with e-mail: an invitation by mail.
    public func create(username: String, password: String?, email: String?, isAdmin: Bool) async -> Bool {
        let input = Components.Schemas.NewUser(username: username, password: password, email: email, isAdmin: isAdmin)
        guard let created = await perform({ try await $0.createUser(body: .json(input)).created.body.json }) else { return false }
        if let mailError = created.value2.inviteMailError {
            notice = "Konto angelegt, aber die Einladung ging nicht raus: \(mailError)"
        } else {
            notice = created.value1.invitePending ? "Konto angelegt, Einladung verschickt." : "Konto angelegt."
        }
        return true
    }

    public func resendInvite(id: String) async {
        if await perform({ try await $0.resendInvite(path: .init(id: id)).ok.body.json }) != nil {
            notice = "Einladung erneut verschickt."
        }
    }

    public func resetPassword(id: String, password: String) async -> Bool {
        let ok = await perform { _ = try await $0.resetUserPassword(path: .init(id: id), body: .json(.init(password: password))).noContent } != nil
        if ok { notice = "Passwort gesetzt." }
        return ok
    }

    public func createSSOLink(id: String) async {
        guard let result = await perform({ try await $0.createSSOLink(path: .init(id: id)).ok.body.json }) else { return }
        if let url = result.url {
            oneTimeLink = url
        } else if result.mailed {
            notice = "Verknüpfungslink an \(result.emailHint ?? "die hinterlegte Adresse") geschickt."
        } else if let error = result.mailError {
            notice = error
        }
    }

    public func dismissOneTimeLink() { oneTimeLink = nil }

    public func setAdmin(id: String, isAdmin: Bool) async {
        _ = await perform { try await $0.setUserAdmin(path: .init(id: id), body: .json(.init(isAdmin: isAdmin))).ok.body.json }
    }

    public func delete(id: String) async {
        _ = await perform { _ = try await $0.deleteUser(path: .init(id: id)).noContent }
    }

    /// Runs a change, then reloads the user list.
    private func perform<T: Sendable>(_ operation: @escaping (any APIProtocol) async throws -> T) async -> T? {
        guard !busy else { return nil }
        busy = true
        defer { busy = false }
        let api = api
        guard let result = await runCatching({ try await operation(api) }) else { return nil }
        switch result {
        case .success(let value):
            await load()
            return value
        case .failure(let error):
            actionError = error
            return nil
        }
    }
}
