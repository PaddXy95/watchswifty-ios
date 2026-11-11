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

    func store(_ transport: FakeTransport) async -> (AdminUsersStore, AppModel) {
        transport.on(.get, "/api/v1/admin/users", json: 200, Self.users)
        let model = await Fixtures.readyModel(transport)
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
}
