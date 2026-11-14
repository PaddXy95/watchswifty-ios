import Foundation
import Observation
import OpenAPIRuntime
import WatchSwiftyClient

/// „Benutzer“ (admins only): create, invite, reset passwords, SSO links, admin rights, delete. Never on the own
/// account (the server refuses it; the screen does not offer it).
///
/// Granting admin rights (also when creating an account) and setting the password of, or a linking link for, another
/// admin need the acting admin's own current password (`currentPassword`, security confirmation): a stolen device
/// alone must not mint or take over an admin. Accounts without a usable password confirm only in the browser.
@MainActor @Observable
public final class AdminUsersStore {
    public private(set) var users = Loadable<[Components.Schemas.UserSummary]>()
    public private(set) var busy = false
    public var actionError: UserFacingError?
    public var notice: String?
    /// A link that is shown exactly once (SSO link not sent by mail).
    public private(set) var oneTimeLink: String?
    /// The server wants the own current password for the last change (missing or wrong, `confirmationRequired`):
    /// its message, shown with a new password prompt. Kept apart from `actionError`, which ends in a plain alert.
    public var confirmationNeeded: String?

    @ObservationIgnored private let api: any APIProtocol
    @ObservationIgnored private let app: AppModel

    public init(api: any APIProtocol, app: AppModel) {
        self.api = api
        self.app = app
    }

    public func isSelf(_ user: Components.Schemas.UserSummary) -> Bool { user.username == app.me?.username }

    /// Whether the own account confirms with its password, as the server decides it: it needs one, and a linked
    /// account needs password login too. Otherwise the app asks for nothing and the server answers `confirmInBrowser`.
    public var confirmsWithPassword: Bool {
        guard let me = app.me else { return true }
        return me.hasPassword && (me.passwordLogin || !me.ssoLinked)
    }

    public func load() async {
        users.begin()
        let version = app.changeVersion
        let api = api
        guard let result = await runCatching({ try await api.listUsers().ok.body.json }) else { return users.cancel() }
        users.finish(result, at: version)
    }

    /// With a password: a normal account; without, but with e-mail: an invitation by mail. An admin account needs
    /// `currentPassword`.
    public func create(username: String, password: String?, email: String?, isAdmin: Bool,
                       currentPassword: String? = nil) async -> Bool {
        let input = Components.Schemas.NewUser(username: username, password: password, email: email, isAdmin: isAdmin,
                                               currentPassword: currentPassword)
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

    /// Another admin's account needs `currentPassword`.
    public func resetPassword(id: String, password: String, currentPassword: String? = nil) async -> Bool {
        let body = Components.Schemas.AdminPassword(password: password, currentPassword: currentPassword)
        let ok = await perform { _ = try await $0.resetUserPassword(path: .init(id: id), body: .json(body)).noContent } != nil
        if ok { notice = "Passwort gesetzt." }
        return ok
    }

    /// Another admin's account needs `currentPassword`; without one the request has no body (as before).
    public func createSSOLink(id: String, currentPassword: String? = nil) async {
        let body = currentPassword.map { Operations.createSSOLink.Input.Body.json(.init(currentPassword: $0)) }
        guard let result = await perform({ try await $0.createSSOLink(path: .init(id: id), body: body).ok.body.json }) else { return }
        if let url = result.url {
            oneTimeLink = url
        } else if result.mailed {
            notice = "Verknüpfungslink an \(result.emailHint ?? "die hinterlegte Adresse") geschickt."
        } else if let error = result.mailError {
            notice = error
        }
    }

    public func dismissOneTimeLink() { oneTimeLink = nil }

    /// Granting needs `currentPassword`; taking the right away does not.
    public func setAdmin(id: String, isAdmin: Bool, currentPassword: String? = nil) async {
        let body = Components.Schemas.AdminFlag(isAdmin: isAdmin, currentPassword: currentPassword)
        _ = await perform { try await $0.setUserAdmin(path: .init(id: id), body: .json(body)).ok.body.json }
    }

    public func delete(id: String) async {
        _ = await perform { _ = try await $0.deleteUser(path: .init(id: id)).noContent }
    }

    /// Runs a change, then reloads the user list. A missing or wrong own password lands in `confirmationNeeded`.
    private func perform<T: Sendable>(_ operation: @escaping (any APIProtocol) async throws -> T) async -> T? {
        guard !busy else { return nil }
        busy = true
        confirmationNeeded = nil
        defer { busy = false }
        let api = api
        guard let result = await runCatching({ try await operation(api) }) else { return nil }
        switch result {
        case .success(let value):
            await load()
            return value
        case .failure(let error) where error.kind == .server(code: "confirmationRequired"):
            confirmationNeeded = error.message
            return nil
        case .failure(let error):
            actionError = error
            return nil
        }
    }
}
