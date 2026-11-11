import Testing
@testable import WatchSwiftyCore

@Suite struct ServerAddressTests {
    @Test(arguments: [
        ("watch.example.de", "https://watch.example.de", "https://watch.example.de/api", false),
        (" HTTPS://Watch.Example.de/ ", "https://watch.example.de", "https://watch.example.de/api", false),
        ("https://example.de/watch/", "https://example.de/watch", "https://example.de/watch/api", false),
        ("https://example.de:8443/?x=1#top", "https://example.de:8443", "https://example.de:8443/api", false),
        ("http://192.168.1.10:8080", "http://192.168.1.10:8080", "http://192.168.1.10:8080/api", true),
        ("http://100.101.102.103", "http://100.101.102.103", "http://100.101.102.103/api", true),
        ("http://10.0.0.5", "http://10.0.0.5", "http://10.0.0.5/api", true),
        ("http://172.20.1.1", "http://172.20.1.1", "http://172.20.1.1/api", true),
        ("http://nas", "http://nas", "http://nas/api", true),
        ("http://nas.local", "http://nas.local", "http://nas.local/api", true),
        ("http://media.home.arpa", "http://media.home.arpa", "http://media.home.arpa/api", true),
        ("http://watch.lan", "http://watch.lan", "http://watch.lan/api", true),
        ("http://box.internal", "http://box.internal", "http://box.internal/api", true),
        ("http://localhost:8080", "http://localhost:8080", "http://localhost:8080/api", true),
        ("http://127.0.0.1:8080", "http://127.0.0.1:8080", "http://127.0.0.1:8080/api", true),
        ("http://[fd12::1]:8080", "http://[fd12::1]:8080", "http://[fd12::1]:8080/api", true),
    ])
    func serverAddressNormalization(input: String, base: String, api: String, insecure: Bool) throws {
        let address = try ServerAddress.parse(input)
        #expect(address.baseURL.absoluteString == base)
        #expect(address.apiURL.absoluteString == api)
        #expect(address.isInsecure == insecure)
    }

    @Test(arguments: ["http://example.de", "http://8.8.8.8", "http://172.32.0.1", "http://100.128.0.1",
                      "http://[2001:db8::1]", "http://nas.fritz.box"])
    func insecurePublicRejected(input: String) {
        #expect(throws: ServerAddressError.insecurePublic) { try ServerAddress.parse(input) }
    }

    @Test(arguments: ["ftp://x.de", "https://", "https:// x .de"])
    func invalidRejected(input: String) {
        #expect(throws: ServerAddressError.invalid) { try ServerAddress.parse(input) }
    }

    @Test func emptyRejected() {
        #expect(throws: ServerAddressError.empty) { try ServerAddress.parse("   ") }
    }

    @Test func messagesAreGerman() {
        #expect(ServerAddressError.empty.message == "Bitte die Adresse deines WatchSwifty-Servers eingeben.")
        #expect(ServerAddressError.invalid.message == "Das ist keine gültige Server-Adresse.")
        #expect(ServerAddressError.insecurePublic.message
            == "Bitte eine https://-Adresse verwenden – sonst wäre die Anmeldung unverschlüsselt.")
    }
}
