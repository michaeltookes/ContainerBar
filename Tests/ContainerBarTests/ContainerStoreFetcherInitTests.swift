import Foundation
import Testing
@testable import ContainerBar
@testable import ContainerBarCore

/// Fetcher-initialization error surfacing and retry (CB-077a).
///
/// The factory throws until `runtimeUp` is flipped, standing in for a local
/// Podman socket whose file appears when the runtime (or the forward) starts.
@Suite("ContainerStore Fetcher Init Tests")
@MainActor
struct ContainerStoreFetcherInitTests {

    @MainActor
    private final class Harness {
        let settings: SettingsStore
        let mock = MockDockerAPIClient()
        let host: DockerHost
        var runtimeUp = false
        var initError: Error
        private(set) var factoryCalls = 0

        init(runtime: ContainerRuntime = .podman) {
            settings = SettingsStore(userDefaults: UserDefaults(suiteName: "test.\(UUID())")!)
            host = DockerHost(
                name: "QA Runtime (socket)",
                connectionType: .unixSocket,
                runtime: runtime,
                isDefault: true,
                socketPath: "/tmp/cbqa-\(UUID()).sock"
            )
            initError = DockerAPIError.socketNotFound(host.socketPath ?? "")
            mock.mockContainers = [DockerContainer.mock(id: "c1", name: "cbqa-target", state: .running)]
            settings.addHost(host)
            settings.selectedHostId = host.id
        }

        func makeStore() -> ContainerStore {
            ContainerStore(
                settings: settings,
                fetcherFactory: { [self] host in
                    factoryCalls += 1
                    guard runtimeUp else { throw initError }
                    return ContainerFetcher(client: mock, host: host ?? .local)
                },
                startRefreshLoop: false,
                observeSettings: false
            )
        }
    }

    @Test("Missing socket on refresh shows the runtime-aware message, not 'not configured'")
    func refreshShowsInitError() async {
        let harness = Harness()
        let store = harness.makeStore()

        await store.refresh()

        let message = store.connectionError ?? ""
        #expect(message.hasPrefix("Podman is not running."))
        #expect(message.contains(harness.host.socketPath ?? "<missing>"))
        #expect(!message.contains("not configured"))
        #expect(store.isConnected == false)
        #expect(store.isRefreshing == false)
    }

    @Test("Init error is mapped at launch, before the first refresh")
    func initErrorMappedAtLaunch() {
        let harness = Harness(runtime: .docker)
        let store = harness.makeStore()

        #expect(store.connectionError?.hasPrefix("Docker is not running.") == true)
    }

    @Test("Refresh retries init after the runtime starts, without relaunch")
    func refreshRetriesInit() async {
        let harness = Harness()
        let store = harness.makeStore()
        await store.refresh()
        #expect(store.containers.isEmpty)

        harness.runtimeUp = true
        await store.refresh()

        #expect(store.isConnected)
        #expect(store.connectionError == nil)
        #expect(store.containers.map(\.id) == ["c1"])
        #expect(harness.factoryCalls >= 3)
    }

    @Test("A non-socket init error shows its own mapped message")
    func otherInitErrorMapped() async {
        let harness = Harness()
        harness.initError = DockerAPIError.unauthorized
        let store = harness.makeStore()

        await store.refresh()

        #expect(store.connectionError == "Access denied. Check Podman permissions.")
    }

    @Test("Action with no fetcher reports the init error")
    func actionReportsInitError() async {
        let harness = Harness()
        let store = harness.makeStore()

        await store.startContainer(id: "c1")

        let message = store.lastActionError?.message ?? ""
        #expect(message.hasPrefix("Unable to start container: Podman is not running."))
        #expect(!message.contains("not configured"))
        #expect(store.actionInProgress.isEmpty)
    }

    @Test("Action retries init once the runtime is up")
    func actionRetriesInit() async {
        let harness = Harness()
        let store = harness.makeStore()
        harness.runtimeUp = true

        await store.stopContainer(id: "c1")

        #expect(store.lastActionError == nil)
        #expect(harness.mock.calledMethods.contains("stopContainer"))
        #expect(store.isConnected)
    }
}
