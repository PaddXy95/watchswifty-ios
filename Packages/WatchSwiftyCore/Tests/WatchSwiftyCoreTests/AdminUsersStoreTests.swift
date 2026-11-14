import Foundation
import Testing
import WatchSwiftyClient
@testable import WatchSwiftyCore

@MainActor @Suite struct AdminUsersStoreTests {
    nonisolated static let otherID = "11111111-2222-3333-4444-555555555555"

    nonisolated static func user(_ id: String, _ name: String, admin: Bool = false) -> String {
        #"{"id":"\#(id)","username":"\#(name)","isAdmin":\#(admin),"hasTMDBToken":true,"invitePending":false,"ssoLinked":false}"#
    }

    nonisolated static var users: String {
        "[\(user("00000000-0000-0000-0000-000000000001", "pat", admin: true)),\(user(otherID, "anna"))]"
    }

    nonisolated static func me(hasPassword: Bool = true, ssoLinked: Bool = false, passwordLogin: Bool = true) -> String {
        #"{"username":"pat","isAdmin":true,"hasPassword":\#(hasPassword),"ssoLinked":\#(ssoLinked),"passwordLogin":\#(passwordLogin),"tmdbToken":{"state":"stored"}}"#
    }

    func store(_ transport: FakeTransport, me: String = Fixtures.me) async -> (AdminUsersStore, AppModel) {
        transport.on(.get, "/api/v1/admin/users", json: 200, Self.users)
        let model = await Fixtures.readyModel(transport, me: me)
        let store = AdminUsersStore(api: model.api, app: model)
        await store.load()
        return (store, model)
    }

    @Test func selfRowHasNoAdminActions() async throws {
        let (store, _) = await store(FakeTransport())
        let users = try #require(store.users.value)
        #expect(users.map { store.isSelf($0) } == [true, false])
    }

    @Test func createUserReloadsListAndReportsMailError() async {
        let transport = FakeTransport()
        transport.on(.post, "/api/v1/admin/users") { _, _ in
            FakeTransport.json(201, #"{"id":"\#(Self.otherID)","username":"ben","isAdmin":false,"hasTMDBToken":false,"invitePending":true,"ssoLinked":false,"inviteMailError":"SMTP nicht erreichbar."}"#)
        }
        let (store, _) = await store(transport)
        let ok = await store.create(username: "ben", password: nil, email: "ben@example.org", isAdmin: false)
        #expect(ok)
        #expect(store.notice == "Konto angelegt, aber die Einladung ging nicht raus: SMTP nicht erreichbar.")
        #expect(transport.requests.filter { $0.path == "/api/v1/admin/users" && $0.method == .get }.count == 2)
        let body = Fixtures.jsonObject(transport.requests.first { $0.method == .post }?.body)
        #expect(body["email"] as? String == "ben@example.org")
        #expect(body["password"] == nil)
    }

    @Test func ssoLinkShownOnce() async {
        let transport = FakeTransport()
        transport.on(.post, "/api/v1/admin/users/\(Self.otherID)/sso-link", json: 200,
                     #"{"mailed":false,"url":"https://example.de/auth/oidc/link?token=abc"}"#)
        let (store, _) = await store(transport)
        await store.createSSOLink(id: Self.otherID)
        #expect(store.oneTimeLink == "https://example.de/auth/oidc/link?token=abc")
        store.dismissOneTimeLink()
        #expect(store.oneTimeLink == nil)
    }

    @Test func adminActionRefreshesList() async {
        let transport = FakeTransport()
        transport.on(.put, "/api/v1/admin/users/\(Self.otherID)/admin", json: 200, Self.user(Self.otherID, "anna", admin: true))
        transport.on(.delete, "/api/v1/admin/users/\(Self.otherID)") { _, _ in FakeTransport.empty(204) }
        transport.on(.put, "/api/v1/admin/users/\(Self.otherID)/password") { _, _ in FakeTransport.empty(204) }
        let (store, _) = await store(transport)
        await store.setAdmin(id: Self.otherID, isAdmin: true)
        #expect(await store.resetPassword(id: Self.otherID, password: "neues-passwort"))
        await store.delete(id: Self.otherID)
        #expect(store.actionError == nil)
        #expect(transport.requests.filter { $0.path == "/api/v1/admin/users" && $0.method == .get }.count == 4)
    }

    // MARK: Security confirmation: the own current password for changes that grant or reach admin rights

    nonisolated static let wrongPassword = "Aktuelles Passwort ist falsch."

    func listLoads(_ transport: FakeTransport) -> Int {
        transport.requests.filter { $0.path == "/api/v1/admin/users" && $0.method == .get }.count
    }

    @Test func grantingAndCreatingAdminsSendTheOwnPassword() async {
        let transport = FakeTransport()
        transport.on(.put, "/api/v1/admin/users/\(Self.otherID)/admin", json: 200, Self.user(Self.otherID, "anna", admin: true))
        transport.on(.post, "/api/v1/admin/users", json: 201, Self.user(Self.otherID, "ben", admin: true))
        let (store, _) = await store(transport)
        await store.setAdmin(id: Self.otherID, isAdmin: true, currentPassword: "mein-passwort")
        #expect(await store.create(username: "ben", password: "geheim-genug", email: nil, isAdmin: true,
                                   currentPassword: "mein-passwort"))
        let grant = Fixtures.jsonObject(transport.requests.first { $0.method == .put }?.body)
        #expect(grant["isAdmin"] as? Bool == true)
        #expect(grant["currentPassword"] as? String == "mein-passwort")
        let create = Fixtures.jsonObject(transport.requests.first { $0.method == .post }?.body)
        #expect(create["isAdmin"] as? Bool == true)
        #expect(create["currentPassword"] as? String == "mein-passwort")
        #expect(store.actionError == nil)
        #expect(store.confirmationNeeded == nil)
    }

    @Test func passwordAndSSOLinkForAnAdminSendTheOwnPassword() async {
        let transport = FakeTransport()
        transport.on(.put, "/api/v1/admin/users/\(Self.otherID)/password") { _, _ in FakeTransport.empty(204) }
        transport.on(.post, "/api/v1/admin/users/\(Self.otherID)/sso-link", json: 200,
                     #"{"mailed":false,"url":"https://example.de/auth/oidc/link?token=abc"}"#)
        let (store, _) = await store(transport)
        #expect(await store.resetPassword(id: Self.otherID, password: "neues-passwort", currentPassword: "mein-passwort"))
        await store.createSSOLink(id: Self.otherID, currentPassword: "mein-passwort")
        let reset = Fixtures.jsonObject(transport.requests.first { $0.method == .put }?.body)
        #expect(reset["password"] as? String == "neues-passwort")
        #expect(reset["currentPassword"] as? String == "mein-passwort")
        let link = Fixtures.jsonObject(transport.requests.first { $0.path.hasSuffix("/sso-link") }?.body)
        #expect(link["currentPassword"] as? String == "mein-passwort")
        #expect(store.oneTimeLink == "https://example.de/auth/oidc/link?token=abc")
    }

    @Test func otherChangesSendNoPassword() async {
        let transport = FakeTransport()
        transport.on(.put, "/api/v1/admin/users/\(Self.otherID)/admin", json: 200, Self.user(Self.otherID, "anna"))
        transport.on(.post, "/api/v1/admin/users", json: 201, Self.user(Self.otherID, "ben"))
        transport.on(.put, "/api/v1/admin/users/\(Self.otherID)/password") { _, _ in FakeTransport.empty(204) }
        transport.on(.post, "/api/v1/admin/users/\(Self.otherID)/sso-link", json: 200, #"{"mailed":true,"emailHint":"a…@example.org"}"#)
        transport.on(.delete, "/api/v1/admin/users/\(Self.otherID)") { _, _ in FakeTransport.empty(204) }
        let (store, _) = await store(transport)
        await store.setAdmin(id: Self.otherID, isAdmin: false)
        #expect(await store.create(username: "ben", password: "geheim-genug", email: nil, isAdmin: false))
        #expect(await store.resetPassword(id: Self.otherID, password: "neues-passwort"))
        await store.createSSOLink(id: Self.otherID)
        await store.delete(id: Self.otherID)
        let changes = transport.requests.filter { $0.method != .get }
        #expect(changes.count == 5)
        for change in changes { #expect(Fixtures.jsonObject(change.body)["currentPassword"] == nil) }
        #expect(transport.requests.first { $0.path.hasSuffix("/sso-link") }?.body == nil)
    }

    @Test func wrongPasswordAsksAgainWithTheServersMessage() async {
        let transport = FakeTransport()
        transport.on(.put, "/api/v1/admin/users/\(Self.otherID)/admin") { _, body in
            guard Fixtures.jsonObject(body)["currentPassword"] as? String == "richtig" else {
                return FakeTransport.json(403, Fixtures.error("confirmationRequired", Self.wrongPassword))
            }
            return FakeTransport.json(200, Self.user(Self.otherID, "anna", admin: true))
        }
        let (store, _) = await store(transport)
        await store.setAdmin(id: Self.otherID, isAdmin: true, currentPassword: "falsch")
        #expect(store.confirmationNeeded == Self.wrongPassword)
        #expect(store.actionError == nil)
        #expect(listLoads(transport) == 1)
        await store.setAdmin(id: Self.otherID, isAdmin: true, currentPassword: "richtig")
        #expect(store.confirmationNeeded == nil)
        #expect(store.actionError == nil)
        #expect(listLoads(transport) == 2)
    }

    /// The list was stale (the account became an admin meanwhile): the server asks, the sheet then asks too.
    @Test func missingPasswordForAnAdminTargetAsks() async {
        let transport = FakeTransport()
        let message = "Zur Bestätigung bitte dein aktuelles Passwort mitschicken."
        transport.on(.put, "/api/v1/admin/users/\(Self.otherID)/password", json: 403, Fixtures.error("confirmationRequired", message))
        let (store, _) = await store(transport)
        #expect(await !store.resetPassword(id: Self.otherID, password: "neues-passwort"))
        #expect(store.confirmationNeeded == message)
        #expect(store.notice == nil)
    }

    @Test func passwordlessAdminConfirmsInTheBrowser() async {
        let transport = FakeTransport()
        let message = "Dein Konto hat kein Passwort – Admin-Rechte bitte im Browser vergeben."
        transport.on(.put, "/api/v1/admin/users/\(Self.otherID)/admin", json: 403, Fixtures.error("confirmInBrowser", message))
        let (store, _) = await store(transport, me: Self.me(hasPassword: false, ssoLinked: true))
        #expect(!store.confirmsWithPassword)
        await store.setAdmin(id: Self.otherID, isAdmin: true)
        #expect(store.actionError?.message == message)
        #expect(store.confirmationNeeded == nil)
    }

    /// Asks for the password only where the server takes it: accounts with a password, unless they are linked
    /// and password login is off (those confirm in the browser).
    @Test func asksForThePasswordOnlyWhenTheServerTakesIt() async {
        let withPassword = await store(FakeTransport()).0
        let linkedWithoutPasswordLogin = await store(FakeTransport(), me: Self.me(ssoLinked: true, passwordLogin: false)).0
        let unlinkedWithoutPasswordLogin = await store(FakeTransport(), me: Self.me(passwordLogin: false)).0
        let withoutPassword = await store(FakeTransport(), me: Self.me(hasPassword: false)).0
        #expect(withPassword.confirmsWithPassword)
        #expect(!linkedWithoutPasswordLogin.confirmsWithPassword)
        #expect(unlinkedWithoutPasswordLogin.confirmsWithPassword)
        #expect(!withoutPassword.confirmsWithPassword)
    }
}
