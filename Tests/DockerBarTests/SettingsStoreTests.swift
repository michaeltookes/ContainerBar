import Foundation
import Testing
@testable import DockerBar
@testable import DockerBarCore

@Suite("SettingsStore Tests")
struct SettingsStoreTests {

    @Test("Default refresh interval is 10 seconds")
    @MainActor
    func defaultRefreshInterval() {
        let defaults = UserDefaults(suiteName: "TestSettingsStore")!
        defaults.removePersistentDomain(forName: "TestSettingsStore")

        let store = SettingsStore(userDefaults: defaults)

        #expect(store.refreshInterval == .seconds10)
        #expect(store.refreshInterval.seconds == 10)
    }

    @Test("Default shows stopped containers")
    @MainActor
    func defaultShowsStoppedContainers() {
        let defaults = UserDefaults(suiteName: "TestSettingsStore2")!
        defaults.removePersistentDomain(forName: "TestSettingsStore2")

        let store = SettingsStore(userDefaults: defaults)

        #expect(store.showStoppedContainers == true)
    }

    @Test("Default icon style is container count")
    @MainActor
    func defaultIconStyle() {
        let defaults = UserDefaults(suiteName: "TestSettingsStore3")!
        defaults.removePersistentDomain(forName: "TestSettingsStore3")

        let store = SettingsStore(userDefaults: defaults)

        #expect(store.iconStyle == .containerCount)
    }

    @Test("Local host is added by default")
    @MainActor
    func localHostAddedByDefault() {
        let defaults = UserDefaults(suiteName: "TestSettingsStore4")!
        defaults.removePersistentDomain(forName: "TestSettingsStore4")

        let store = SettingsStore(userDefaults: defaults)

        #expect(store.hosts.count == 1)
        #expect(store.hosts.first?.connectionType == .unixSocket)
        #expect(store.hosts.first?.isDefault == true)
    }

    @Test("Selected host returns default when no selection")
    @MainActor
    func selectedHostReturnsDefault() {
        let defaults = UserDefaults(suiteName: "TestSettingsStore5")!
        defaults.removePersistentDomain(forName: "TestSettingsStore5")

        let store = SettingsStore(userDefaults: defaults)
        store.selectedHostId = nil

        #expect(store.selectedHost?.isDefault == true)
    }

    @Test("Refresh interval seconds are correct")
    func refreshIntervalSeconds() {
        #expect(RefreshInterval.seconds5.seconds == 5)
        #expect(RefreshInterval.seconds10.seconds == 10)
        #expect(RefreshInterval.seconds30.seconds == 30)
        #expect(RefreshInterval.minute1.seconds == 60)
        #expect(RefreshInterval.minutes5.seconds == 300)
        #expect(RefreshInterval.manual.seconds == nil)
    }

    @Test("Icon style display names are set")
    func iconStyleDisplayNames() {
        #expect(IconStyle.containerCount.displayName == "Container Count")
        #expect(IconStyle.cpuMemoryBars.displayName == "CPU + Memory Bars")
        #expect(IconStyle.healthIndicator.displayName == "Health Indicator")
    }
}
