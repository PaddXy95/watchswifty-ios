import Foundation
import Testing
import WatchSwiftyClient
@testable import WatchSwiftyCore

@MainActor @Suite struct AccountStoreTests {
    static let newGrant = #"""
    {"token":"ws_new","expiresAt":"2027-02-09T12:00:00Z",
     "device":{"id":"11111111-2222-3333-4444-555555555555","name":"iPhone","kind":"device",
               "createdAt":"2026-11-11T12:00:00Z","expiresAt":"2027-02-09T12:00:00Z"},
     "user":{"username":"pat","isAdmin":true}}
    """#

    @Test func passwordHiddenForSSOOnlyAccount() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/version", json: 200, #"{"version":"0.4.0"}"#)
        transport.on(.get, "/api/v1/me", json: 200, Fixtures.me.replacingOccurrences(of: #""hasPassword":true"#, with: #""hasPassword":false"#))
        let model = AppModel(environment: Fixtures.environment(transport: transport, token: Fixtures.token))
        await model.start()
        let store = AccountStore(api: model.api, app: model)
        #expect(store.canChangePassword == false)
    }

    @Test func passwordShownWithPasswordLogin() async {
        let model = await Fixtures.readyModel(FakeTransport())
        #expect(AccountStore(api: model.api, app: model).canChangePassword)
    }

    @Test func changePasswordReportsSuccess() async {
        let transport = FakeTransport()
        transport.on(.put, "/api/v1/me/password") { _, _ in FakeTransport.empty(204) }
        let model = await Fixtures.readyModel(transport)
        let store = AccountStore(api: model.api, app: model)
        let ok = await store.changePassword(current: "alt-passwort", new: "neues-passwort")
        #expect(ok)
        #expect(store.notice == "Passwort geändert.")
        let body = Fixtures.jsonObject(transport.requests.last?.body)
        #expect(body["currentPassword"] as? String == "alt-passwort")
    }

    @Test func revokingCurrentDeviceSignsOut() async {
        let transport = FakeTransport()
        transport.on(.delete, "/api/v1/auth/token") { _, _ in FakeTransport.empty(204) }
        let model = await Fixtures.readyModel(transport)
        let store = AccountStore(api: model.api, app: model)
        await store.revokeDevice(id: Fixtures.token.deviceID.lowercased())
        #expect(model.phase == .needsLogin)
        #expect(transport.requests.contains { $0.path == "/api/v1/auth/token" && $0.method == .delete })
    }

    @Test func revokingOtherDeviceRemovesIt() async {
        let transport = FakeTransport()
        let other = "11111111-2222-3333-4444-555555555555"
        transport.on(.get, "/api/v1/me/devices", json: 200, #"""
        [{"id":"\#(other)","name":"iPad","kind":"device","createdAt":"2026-11-01T12:00:00Z","expiresAt":"2027-01-30T12:00:00Z"}]
        """#)
        transport.on(.delete, "/api/v1/me/devices/\(other)") { _, _ in FakeTransport.empty(204) }
        let model = await Fixtures.readyModel(transport)
        let store = AccountStore(api: model.api, app: model)
        await store.load()
        await store.revokeDevice(id: other)
        #expect(store.devices.value?.isEmpty == true)
        #expect(model.phase == .ready)
    }

    @Test func renewRevokesOldDevice() async {
        let transport = FakeTransport()
        transport.on(.post, "/api/v1/auth/token", json: 200, Self.newGrant)
        transport.on(.delete, "/api/v1/me/devices/\(Fixtures.token.deviceID)") { _, _ in FakeTransport.empty(204) }
        let model = await Fixtures.readyModel(transport)
        let store = AccountStore(api: model.api, app: model)
        await store.renewConnection(using: FakeWebAuthenticator())
        #expect(model.token?.token == "ws_new")
        let revoke = transport.requests.last { $0.path == "/api/v1/me/devices/\(Fixtures.token.deviceID)" }
        #expect(revoke?.request.headerFields[.authorization] == "Bearer ws_new")
    }

    @Test func tmdbTokenSaveRefreshesMe() async {
        let transport = FakeTransport()
        transport.on(.put, "/api/v1/me/tmdb-token", json: 200, Fixtures.me.replacingOccurrences(of: "…abcd", with: "…wxyz"))
        let model = await Fixtures.readyModel(transport)
        let store = AccountStore(api: model.api, app: model)
        #expect(await store.setTMDBToken("eyJ.neu"))
        #expect(model.me?.tmdbToken.suffix == "…wxyz")
    }

    // MARK: „Alle Daten von TMDB neu laden“

    nonisolated static func refresh(running: Bool, done: Int = 0, total: Int = 0, failed: Int = 0, error: String? = nil) -> String {
        let finished = running ? "" : #","finishedAt":"2026-11-14T10:00:00Z""#
        let errorField = error.map { #","error":"\#($0)""# } ?? ""
        return #"{"running":\#(running),"done":\#(done),"total":\#(total),"failed":\#(failed)\#(finished)\#(errorField)}"#
    }

    @Test func loadReadsTheReloadProgress() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/library/refresh", json: 200, Self.refresh(running: false, done: 12, total: 12, failed: 2))
        let model = await Fixtures.readyModel(transport)
        let store = AccountStore(api: model.api, app: model)
        await store.load()
        #expect(store.libraryRefresh?.done == 12)
        #expect(store.libraryRefresh?.failed == 2)
        #expect(store.libraryRefresh?.finishedAt != nil)
    }

    /// Servers before 0.5.1 have no reload: the section stays hidden and nothing is reported.
    @Test func olderServerHasNoReload() async {
        let model = await Fixtures.readyModel(FakeTransport())
        let store = AccountStore(api: model.api, app: model)
        await store.load()
        #expect(store.libraryRefresh == nil)
        #expect(store.actionError == nil)
    }

    @Test func startThenPollUntilDoneMarksDataChanged() async {
        let transport = FakeTransport()
        let polls = Counter()
        transport.on(.post, "/api/v1/library/refresh", json: 202, Self.refresh(running: true, total: 3))
        transport.on(.get, "/api/v1/library/refresh") { _, _ in
            polls.increment()
            return FakeTransport.json(200, polls.value < 2 ? Self.refresh(running: true, done: 1, total: 3)
                                                           : Self.refresh(running: false, done: 3, total: 3))
        }
        let model = await Fixtures.readyModel(transport)
        let store = AccountStore(api: model.api, app: model, pollInterval: .zero)
        await store.startLibraryRefresh()
        #expect(store.libraryRefresh?.running == true)
        let before = model.changeVersion
        await store.pollLibraryRefresh()
        #expect(polls.value == 2)
        #expect(store.libraryRefresh?.running == false)
        #expect(store.libraryRefresh?.done == 3)
        #expect(model.changeVersion == before + 1)
    }

    @Test func refusedStartShowsTheServersMessage() async {
        let transport = FakeTransport()
        let message = "Hinterlege zuerst deinen TMDB-Token."
        transport.on(.post, "/api/v1/library/refresh", json: 422, Fixtures.error("validation", message))
        let model = await Fixtures.readyModel(transport)
        let store = AccountStore(api: model.api, app: model, pollInterval: .zero)
        await store.startLibraryRefresh()
        #expect(store.actionError?.message == message)
        #expect(store.libraryRefresh == nil)
        await store.pollLibraryRefresh()
        #expect(!transport.requests.contains { $0.path == "/api/v1/library/refresh" && $0.method == .get })
    }
}
