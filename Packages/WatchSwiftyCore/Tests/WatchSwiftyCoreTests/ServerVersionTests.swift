import Testing
@testable import WatchSwiftyCore

@Suite struct ServerVersionTests {
    @Test(arguments: [
        ("0.4.0", "0.4.0", Compatibility.compatible),
        ("0.3.2", "0.4.0", Compatibility.tooOld(server: "0.3.2", minimum: "0.4.0")),
        ("0.4.0-beta", "0.4.0", Compatibility.compatible),
        ("0.3.3-beta", "0.4.0", Compatibility.tooOld(server: "0.3.3-beta", minimum: "0.4.0")),
        ("dev", "0.4.0", Compatibility.compatible),
        ("0.10.0", "0.9.0", Compatibility.compatible),
        ("1.0.0", "0.0.0", Compatibility.compatible),
    ])
    func versionCompatibility(server: String, minimum: String, expected: Compatibility) {
        #expect(ServerVersion.check(serverVersion: server, minimum: minimum) == expected)
    }

    @Test func parsesVersions() {
        #expect(ServerVersion("v1.2.3") == ServerVersion("1.2.3"))
        #expect(ServerVersion("1.2") == nil)
        #expect(ServerVersion("dev") == nil)
        #expect(ServerVersion("0.9.9")! < ServerVersion("0.10.0")!)
    }
}
