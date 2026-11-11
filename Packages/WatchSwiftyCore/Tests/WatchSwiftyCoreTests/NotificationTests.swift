import Foundation
import Testing
import WatchSwiftyClient
@testable import WatchSwiftyCore

@MainActor @Suite struct NotificationPrefsTests {
    nonisolated static func prefs(announced: Bool = false, soon: Bool = false, today: Bool = false, channel: String = "mail",
                                  active: String? = "mail", available: [String] = ["mail"], webhookConfigured: Bool = false,
                                  hasKey: Bool = false) -> String {
        let activeField = active.map { #""activeChannel":"\#($0)","# } ?? ""
        let availableList = available.map { "\"\($0)\"" }.joined(separator: ",")
        return #"""
        {"announced":\#(announced),"soon":\#(soon),"today":\#(today),"channel":"\#(channel)",\#(activeField)
         "availableChannels":[\#(availableList)],"webhookConfigured":\#(webhookConfigured),"hasWebhookKey":\#(hasKey),"dailyRunTime":"07:00"}
        """#
    }

    static func loadedStore(_ transport: FakeTransport, prefs: String = prefs()) async -> AccountStore {
        transport.on(.get, "/api/v1/me/notifications", json: 200, prefs)
        let model = await Fixtures.readyModel(transport)
        let store = AccountStore(api: model.api, app: model)
        await store.load()
        return store
    }

    @Test func loadReadsPrefs() async {
        let store = await Self.loadedStore(FakeTransport(), prefs: Self.prefs(soon: true, webhookConfigured: true))
        let prefs = store.notifications.value
        #expect(prefs?.soon == true)
        #expect(prefs?.channel == .mail)
        #expect(prefs?.webhookConfigured == true)
        #expect(prefs?.dailyRunTime == "07:00")
    }

    @Test func serverWithoutNotificationsLeavesSectionEmpty() async {
        let model = await Fixtures.readyModel(FakeTransport())
        let store = AccountStore(api: model.api, app: model)
        await store.load()
        #expect(store.notifications.value == nil)
        #expect(store.actionError == nil)
    }

    @Test func toggleSendsAllSwitchesAndStoredChannel() async {
        let transport = FakeTransport()
        // Webhook chosen but gone for now: mail is used, the stored choice must be sent back unchanged.
        let store = await Self.loadedStore(transport, prefs: Self.prefs(channel: "webhook", active: "mail", available: ["mail"]))
        transport.on(.put, "/api/v1/me/notifications", json: 200,
                     Self.prefs(today: true, channel: "webhook", active: "mail", available: ["mail"]))
        await store.updateNotifications { $0.today = true }
        let body = Fixtures.jsonObject(transport.requests.last?.body)
        #expect(body["announced"] as? Bool == false)
        #expect(body["soon"] as? Bool == false)
        #expect(body["today"] as? Bool == true)
        #expect(body["channel"] as? String == "webhook")
        #expect(store.notifications.value?.today == true)
        #expect(store.notifications.value?.activeChannel == .mail)
    }

    @Test func toggleShowsAtOnceAndRevertsOnFailure() async {
        let transport = FakeTransport()
        let store = await Self.loadedStore(transport)
        let gate = Gate()
        transport.on(.put, "/api/v1/me/notifications") { _, _ in
            await gate.wait()
            return FakeTransport.json(422, Fixtures.error("validation", "Ungültige Anfrage."))
        }
        let task = Task { await store.updateNotifications { $0.announced = true } }
        await waitUntil { store.busy }
        #expect(store.notifications.value?.announced == true)
        gate.release()
        await task.value
        #expect(store.notifications.value?.announced == false)
        #expect(store.actionError?.message == "Ungültige Anfrage.")
    }

    @Test func choosingChannelShowsItAsActive() async {
        let transport = FakeTransport()
        let both = ["mail", "webhook"]
        let store = await Self.loadedStore(transport, prefs: Self.prefs(available: both, webhookConfigured: true, hasKey: true))
        let gate = Gate()
        transport.on(.put, "/api/v1/me/notifications") { _, _ in
            await gate.wait()
            return FakeTransport.json(200, Self.prefs(channel: "webhook", active: "webhook", available: both, webhookConfigured: true, hasKey: true))
        }
        let task = Task { await store.updateNotifications { $0.channel = .webhook } }
        await waitUntil { store.busy }
        #expect(store.notifications.value?.activeChannel == .webhook)
        gate.release()
        await task.value
        #expect(Fixtures.jsonObject(transport.requests.last?.body)["channel"] as? String == "webhook")
        #expect(store.notifications.value?.channel == .webhook)
    }

    @Test func unchangedUpdateSendsNothing() async {
        let transport = FakeTransport()
        let store = await Self.loadedStore(transport)
        let count = transport.requests.count
        await store.updateNotifications { $0.announced = false }
        #expect(transport.requests.count == count)
    }

    @Test func webhookKeyIsTrimmedAndSentWithPassword() async {
        let transport = FakeTransport()
        let store = await Self.loadedStore(transport, prefs: Self.prefs(webhookConfigured: true))
        transport.on(.put, "/api/v1/me/notifications/webhook-key", json: 200,
                     Self.prefs(available: ["mail", "webhook"], webhookConfigured: true, hasKey: true))
        let ok = await store.setWebhookKey("  0123456789abcdef\n", currentPassword: "geheim")
        #expect(ok)
        let body = Fixtures.jsonObject(transport.requests.last?.body)
        #expect(body["key"] as? String == "0123456789abcdef")
        #expect(body["currentPassword"] as? String == "geheim")
        #expect(store.notifications.value?.hasWebhookKey == true)
        #expect(store.notice == "Webhook-Schlüssel gespeichert.")
    }

    @Test func webhookKeyWithoutPasswordForSSOOnlyAccount() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/version", json: 200, #"{"version":"0.4.0"}"#)
        transport.on(.get, "/api/v1/me", json: 200, Fixtures.me.replacingOccurrences(of: #""hasPassword":true"#, with: #""hasPassword":false"#))
        transport.on(.put, "/api/v1/me/notifications/webhook-key", json: 200, Self.prefs(webhookConfigured: true, hasKey: true))
        let model = AppModel(environment: Fixtures.environment(transport: transport, token: Fixtures.token))
        await model.start()
        await model.startupChecks?.value
        let store = AccountStore(api: model.api, app: model)
        #expect(store.webhookKeyNeedsPassword == false)
        #expect(await store.setWebhookKey("0123456789abcdef", currentPassword: "egal"))
        #expect(Fixtures.jsonObject(transport.requests.last?.body)["currentPassword"] == nil)
    }

    @Test func wrongPasswordShowsServerMessage() async {
        let transport = FakeTransport()
        let store = await Self.loadedStore(transport, prefs: Self.prefs(webhookConfigured: true))
        transport.on(.put, "/api/v1/me/notifications/webhook-key", json: 422,
                     Fixtures.error("validation", "Das aktuelle Passwort stimmt nicht."))
        let ok = await store.setWebhookKey("0123456789abcdef", currentPassword: "falsch")
        #expect(!ok)
        #expect(store.actionError?.message == "Das aktuelle Passwort stimmt nicht.")
        #expect(store.notifications.value?.hasWebhookKey == false)
    }

    @Test func removingKeySendsPassword() async {
        let transport = FakeTransport()
        let store = await Self.loadedStore(transport, prefs: Self.prefs(webhookConfigured: true, hasKey: true))
        transport.on(.delete, "/api/v1/me/notifications/webhook-key", json: 200, Self.prefs(webhookConfigured: true))
        #expect(await store.deleteWebhookKey(currentPassword: "geheim"))
        let request = transport.requests.last
        #expect(request?.method == .delete)
        #expect(Fixtures.jsonObject(request?.body)["currentPassword"] as? String == "geheim")
        #expect(store.notifications.value?.hasWebhookKey == false)
        #expect(store.notice == "Webhook-Schlüssel entfernt.")
    }

    @Test func testNotificationReportsSuccess() async {
        let transport = FakeTransport()
        let store = await Self.loadedStore(transport)
        transport.on(.post, "/api/v1/me/notifications/test") { _, _ in FakeTransport.empty(204) }
        await store.sendTestNotification()
        #expect(store.notice == "Testnachricht gesendet.")
    }

    @Test(arguments: [(422, "notificationsNotConfigured", "Für dein Konto ist noch kein Versandweg eingerichtet."),
                      (503, "notifyFailed", "KNot kennt den Schlüssel nicht.")])
    func testNotificationShowsServerMessage(status: Int, code: String, message: String) async {
        let transport = FakeTransport()
        let store = await Self.loadedStore(transport)
        transport.on(.post, "/api/v1/me/notifications/test", json: status, Fixtures.error(code, message))
        await store.sendTestNotification()
        #expect(store.notice == nil)
        #expect(store.actionError == UserFacingError(code: code, message: message))
    }
}

@MainActor @Suite struct AdminNotificationSettingsTests {
    nonisolated static func settings(time: String = "07:00", webhook: String? = nil, lastRun: Bool = true) -> String {
        let webhookField = webhook.map { #""webhookUrl":"\#($0)","# } ?? ""
        let lastField = lastRun ? #""lastRunAt":"2026-11-11T06:00:00Z","# : ""
        return #"{"dailyRunTime":"\#(time)","timeZone":"Europe/Berlin",\#(webhookField)\#(lastField)"nextRunAt":"2026-11-12T06:00:00Z"}"#
    }

    static func loadedStore(_ transport: FakeTransport, settings: String = settings()) async -> SystemStore {
        transport.on(.get, "/api/v1/admin/system", json: 200, AdminSettingsTests.system(latest: nil))
        transport.on(.get, "/api/v1/admin/notifications", json: 200, settings)
        let model = await Fixtures.readyModel(transport)
        let store = SystemStore(api: model.api, app: model)
        await store.load()
        return store
    }

    @Test func loadReadsSystemAndNotifications() async {
        let store = await Self.loadedStore(FakeTransport(), settings: Self.settings(webhook: "https://knot.example.lan/hook"))
        #expect(store.system.value?.version.version == "0.4.0")
        let settings = store.notifications.value
        #expect(settings?.timeZone == "Europe/Berlin")
        #expect(settings?.webhookUrl == "https://knot.example.lan/hook")
        #expect(settings?.lastRunAt == Date(timeIntervalSince1970: 1_794_376_800))
    }

    @Test func serverWithoutNotificationsStillShowsSystem() async {
        let transport = FakeTransport()
        transport.on(.get, "/api/v1/admin/system", json: 200, AdminSettingsTests.system(latest: nil))
        let model = await Fixtures.readyModel(transport)
        let store = SystemStore(api: model.api, app: model)
        await store.load()
        #expect(store.system.value != nil)
        #expect(store.notifications.value == nil)
    }

    @Test func saveSendsTimeAndTrimmedAddress() async {
        let transport = FakeTransport()
        let store = await Self.loadedStore(transport)
        transport.on(.put, "/api/v1/admin/notifications", json: 200, Self.settings(time: "06:30", webhook: "https://knot.example.lan/hook"))
        let ok = await store.saveNotifications(dailyRunTime: ClockTime(hour: 6, minute: 30)!, webhookURL: " https://knot.example.lan/hook ")
        #expect(ok)
        let body = Fixtures.jsonObject(transport.requests.last?.body)
        #expect(body["dailyRunTime"] as? String == "06:30")
        #expect(body["webhookUrl"] as? String == "https://knot.example.lan/hook")
        #expect(store.notifications.value?.dailyRunTime == "06:30")
        #expect(store.notice == "Benachrichtigungen gespeichert.")
    }

    @Test func emptyAddressTurnsWebhookOff() async {
        let transport = FakeTransport()
        let store = await Self.loadedStore(transport, settings: Self.settings(webhook: "https://knot.example.lan/hook"))
        transport.on(.put, "/api/v1/admin/notifications", json: 200, Self.settings())
        #expect(await store.saveNotifications(dailyRunTime: ClockTime(hour: 7, minute: 0)!, webhookURL: "  "))
        #expect(Fixtures.jsonObject(transport.requests.last?.body)["webhookUrl"] == nil)
        #expect(store.notifications.value?.webhookUrl == nil)
    }

    @Test func removeWebhookKeepsTime() async {
        let transport = FakeTransport()
        let store = await Self.loadedStore(transport, settings: Self.settings(time: "05:15", webhook: "https://knot.example.lan/hook"))
        transport.on(.put, "/api/v1/admin/notifications", json: 200, Self.settings(time: "05:15"))
        await store.removeWebhook()
        let body = Fixtures.jsonObject(transport.requests.last?.body)
        #expect(body["dailyRunTime"] as? String == "05:15")
        #expect(body["webhookUrl"] == nil)
        #expect(store.notice == "Webhook entfernt.")
    }

    @Test func invalidAddressShowsServerMessage() async {
        let transport = FakeTransport()
        let store = await Self.loadedStore(transport)
        let message = "Die Webhook-Adresse darf weder Benutzerdaten noch ?… oder #… enthalten."
        transport.on(.put, "/api/v1/admin/notifications", json: 422, Fixtures.error("validation", message))
        let ok = await store.saveNotifications(dailyRunTime: ClockTime(hour: 7, minute: 0)!, webhookURL: "https://knot.example.lan/hook?apiKey=x")
        #expect(!ok)
        #expect(store.actionError?.message == message)
        #expect(store.notifications.value?.webhookUrl == nil)
    }
}

@Suite struct ClockTimeTests {
    @Test(arguments: [("07:00", 7, 0), ("7:05", 7, 5), ("23:59", 23, 59), ("00:00", 0, 0)])
    func parses(text: String, hour: Int, minute: Int) {
        #expect(ClockTime(text) == ClockTime(hour: hour, minute: minute))
    }

    @Test(arguments: ["24:00", "07:60", "0700", "7:5", "", "ab:cd", "07:00:00", "-1:00", "٠٧:٠٠"])
    func rejects(text: String) {
        #expect(ClockTime(text) == nil)
    }

    @Test func formatsWithLeadingZeros() {
        #expect(ClockTime(hour: 7, minute: 5)?.text == "07:05")
        #expect(ClockTime(hour: 18, minute: 30)?.text == "18:30")
    }

    @Test func roundTripsThroughPickerDate() {
        let calendar = ClockTime.pickerCalendar
        let time = ClockTime(hour: 2, minute: 30)!
        // 2026-03-29 is a daylight-saving day in Europe; the picker calendar has no gap.
        let day = Date(timeIntervalSince1970: 1_774_742_400)
        #expect(ClockTime(time.date(on: day, in: calendar), in: calendar) == time)
    }

    @Test func channelNames() {
        #expect(NotifyChannelValue.mail.displayName == "E-Mail")
        #expect(NotifyChannelValue.webhook.displayName == "Webhook (KNot)")
        #expect(NotifyChannelValue(rawValue: "push").displayName == "push")
    }
}
