import Foundation
import Testing
@testable import ContainerBar

@Suite("HuntMode Tests")
struct HuntModeTests {
    @Test("Default hunt defaults suite does not reuse the hunt bundle identifier")
    func defaultSuiteDoesNotReuseBundleIdentifier() {
        #expect(HuntMode.defaultsSuite != "com.tookes.ContainerBar.hunt")
    }

    @Test("Defaults creation fails closed when the hunt suite is unavailable")
    func defaultsCreationFailsClosed() {
        #expect(throws: HuntMode.Failure.defaultsSuiteUnavailable("unavailable")) {
            _ = try HuntMode.makeUserDefaults(suiteName: "unavailable") { _ in nil }
        }
    }

    @Test("Defaults suite is cleared before hunt mode uses it")
    func defaultsSuiteIsClearedBeforeUse() throws {
        let suiteName = "test.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set("stale", forKey: "sentinel")

        let huntDefaults = try HuntMode.makeUserDefaults(suiteName: suiteName)

        #expect(huntDefaults.string(forKey: "sentinel") == nil)
        huntDefaults.removePersistentDomain(forName: suiteName)
    }
}
