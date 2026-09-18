import Foundation
import ContainerBarCore
@testable import ContainerBar

/// Shared fixtures for the Settings-pane view-body tests (CB-060).
///
/// Everything here keeps the view tests hermetic: stores are bound to
/// throwaway `UserDefaults` suites so a test never reads or writes the
/// developer's real preferences (the same isolation pattern used by
/// `SettingsStoreHostSectionTests`), and any `ContainerFetcher` is backed by
/// the in-memory `MockDockerAPIClient` so no test ever opens a real Unix
/// socket or SSH tunnel.
@MainActor
enum SettingsPaneViewTestSupport {

    /// A `SettingsStore` bound to a freshly wiped, uniquely named `UserDefaults`
    /// suite. The suite name embeds a UUID so parallel tests never collide, and
    /// the domain is removed up front so no prior run bleeds in.
    static func isolatedSettingsStore(_ label: String = #function) -> SettingsStore {
        let name = "SettingsPaneViewTests.\(label).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return SettingsStore(userDefaults: defaults)
    }

    /// A fetcher factory that always yields a fetcher backed by the in-memory
    /// mock client, guaranteeing `ConnectionSettingsPane` can never reach a real
    /// socket or SSH host even if a connection test were triggered.
    static func mockFetcherFactory() -> ContainerStore.FetcherFactory {
        { host in
            ContainerFetcher(client: MockDockerAPIClient(), host: host ?? .local)
        }
    }

    /// A `ContainerStore` wired to the mock client through the DEBUG test-only
    /// initializer, so no refresh loop starts and no real fetcher is built.
    static func mockContainerStore(settings: SettingsStore) -> ContainerStore {
        ContainerStore(
            settings: settings,
            fetcher: ContainerFetcher(client: MockDockerAPIClient(), host: .local)
        )
    }
}
