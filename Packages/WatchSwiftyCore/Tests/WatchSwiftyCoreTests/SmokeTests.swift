import Testing
import WatchSwiftyClient
@testable import WatchSwiftyCore

@Suite struct SmokeTests {
    @Test func clientTypesResolve() {
        #expect(ServiceValue.netflix.rawValue == "netflix")
        #expect(AppInfo.minimumServerVersion == "0.0.0")
    }
}
