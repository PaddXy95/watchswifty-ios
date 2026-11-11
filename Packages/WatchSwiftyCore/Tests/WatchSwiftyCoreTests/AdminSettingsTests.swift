import Foundation
import Testing
import WatchSwiftyClient
@testable import WatchSwiftyCore

@MainActor @Suite struct AdminSettingsTests {
    nonisolated static func system(latest: String?) -> String {
        let latestField = latest.map { #","latestVersion":"\#($0)","updateAvailable":true"# } ?? ""
        return #"{"version":{"version":"0.4.0"},"updateCheck":{"enabled":true\#(latestField)}}"#
    }

    nonisolated static let oidc = #"""
    {"configured":true,"unreadable":false,"displayName":"Authentik","issuer":"https://auth.example.de/application/o/watch/",
     "clientId":"watch","hasClientSecret":true,"baseUrl":"https://watch.example.de","passwordLogin":true,"passwordLoginForced":false}
    """#

    nonisolated static let mail = #"""
    {"configured":true,"unreadable":false,"host":"smtp.example.de","port":587,"encryption":"starttls","username":"watch",
     "hasPassword":true,"fromAddress":"watch@example.de","baseUrl":"https://watch.example.de"}
    """#

    @Test func checkNowRefreshesSystem() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/admin/system", json: 200, Self.system(latest: nil))
        transport.on(.post, "/api/v1/admin/system/check-now", json: 200, Self.system(latest: "0.5.0"))
        let model = await Fixtures.readyModel(transport)
        let store = SystemStore(api: model.api, app: model)
        await store.load()
        await store.checkNow()
        #expect(store.system.value?.updateCheck.latestVersion == "0.5.0")
    }

    @Test func updateCheckToggleSendsValue() async {
        let transport = FakeTransport()
        transport.on(.put, "/api/v1/admin/system/update-check", json: 200, Self.system(latest: nil))
        let model = await Fixtures.readyModel(transport)
        let store = SystemStore(api: model.api, app: model)
        await store.setUpdateCheck(false)
        #expect(Fixtures.jsonObject(transport.requests.last?.body)["enabled"] as? Bool == false)
    }

    @Test func oidcTestReturnsResult() async {
        let transport = FakeTransport()
        transport.on(.post, "/api/v1/admin/oidc/test", json: 200, #"{"issuer":"https://auth.example.de/application/o/watch/","keyCount":2}"#)
        let model = await Fixtures.readyModel(transport)
        let store = OIDCSettingsStore(api: model.api, app: model)
        await store.test()
        #expect(store.notice == "Verbindung in Ordnung: 2 Schlüssel von https://auth.example.de/application/o/watch/.")
    }

    @Test func oidcSaveKeepsSecretWhenEmpty() async {
        let transport = FakeTransport()
        transport.on(.put, "/api/v1/admin/oidc", json: 200, Self.oidc)
        let model = await Fixtures.readyModel(transport)
        let store = OIDCSettingsStore(api: model.api, app: model)
        let ok = await store.save(displayName: "Authentik", issuer: "https://auth.example.de/application/o/watch/",
                                  clientID: "watch", clientSecret: "", baseURL: "https://watch.example.de")
        #expect(ok)
        let body = Fixtures.jsonObject(transport.requests.last?.body)
        #expect(body["clientSecret"] == nil)
        #expect(body["clientId"] as? String == "watch")
    }

    @Test func passwordLoginToggleSendsValue() async {
        let transport = FakeTransport()
        transport.on(.put, "/api/v1/admin/oidc/password-login", json: 200, Self.oidc)
        let model = await Fixtures.readyModel(transport)
        let store = OIDCSettingsStore(api: model.api, app: model)
        await store.setPasswordLogin(false)
        let request = transport.requests.first { $0.path == "/api/v1/admin/oidc/password-login" }
        #expect(Fixtures.jsonObject(request?.body)["enabled"] as? Bool == false)
        #expect(store.settings.value?.configured == true)
    }

    @Test func mailSaveOmitsEmptyPassword() async {
        let transport = FakeTransport()
        transport.on(.put, "/api/v1/admin/mail", json: 200, Self.mail)
        let model = await Fixtures.readyModel(transport)
        let store = MailSettingsStore(api: model.api, app: model)
        let form = MailForm(host: "smtp.example.de", port: "587", encryption: .starttls, username: "watch", password: "",
                            fromAddress: "watch@example.de", fromName: "", caFile: "", baseURL: "https://watch.example.de")
        #expect(await store.save(form))
        let body = Fixtures.jsonObject(transport.requests.last?.body)
        #expect(body["password"] == nil)
        #expect(body["port"] as? Int == 587)
        #expect(body["fromName"] == nil)
    }

    @Test func testMailReportsSuccess() async {
        let transport = FakeTransport()
        transport.on(.post, "/api/v1/admin/mail/test") { _, _ in FakeTransport.empty(204) }
        let model = await Fixtures.readyModel(transport)
        let store = MailSettingsStore(api: model.api, app: model)
        await store.sendTest(to: "pat@example.de")
        #expect(store.notice == "Testmail an pat@example.de verschickt.")
    }
}
