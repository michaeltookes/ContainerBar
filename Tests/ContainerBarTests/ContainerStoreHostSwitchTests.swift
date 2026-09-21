import Foundation
import Testing
@testable import ContainerBar
@testable import ContainerBarCore

/// Generation-fencing and host-switch convergence tests (CB-064, CB-065).
///
/// These drive the store through the injected `FetcherFactory` so a host
/// switch rebuilds against a different mock, and keep the auto-refresh timer
/// and settings observation off so the tests stay deterministic — the
/// convergence decision is exercised by calling `handleSettingsChange()`
/// directly. Mid-flight ordering uses `MockDockerAPIClient`'s gate rather than
/// sleeps.
@Suite("ContainerStore Host Switching Tests")
@MainActor
struct ContainerStoreHostSwitchTests {

    /// A small harness holding two hosts, their mocks, and a counting factory.
    @MainActor
    private final class Harness {
        let settings: SettingsStore
        let mockA = MockDockerAPIClient()
        let mockB = MockDockerAPIClient()
        let hostA: DockerHost
        let hostB: DockerHost
        private(set) var factoryCalls = 0

        init() {
            settings = SettingsStore(userDefaults: UserDefaults(suiteName: "test.\(UUID())")!)
            hostA = DockerHost(name: "Host A", connectionType: .unixSocket, isDefault: true, socketPath: "/tmp/a-\(UUID()).sock")
            hostB = DockerHost(name: "Host B", connectionType: .unixSocket, isDefault: false, socketPath: "/tmp/b-\(UUID()).sock")
            mockA.mockContainers = [DockerContainer.mock(id: "a1", name: "alpha", state: .running)]
            mockB.mockContainers = [DockerContainer.mock(id: "b1", name: "bravo", state: .running)]
            settings.addHost(hostA)
            settings.addHost(hostB)
        }

        func makeStore() -> ContainerStore {
            ContainerStore(
                settings: settings,
                fetcherFactory: { [self] host in
                    factoryCalls += 1
                    let client: MockDockerAPIClient = (host?.id == hostB.id) ? mockB : mockA
                    return ContainerFetcher(client: client, host: host ?? .local)
                },
                startRefreshLoop: false,
                observeSettings: false
            )
        }
    }

    // MARK: - CB-064

    @Test("Host switch mid-fetch drops the stale result")
    func hostSwitchMidFetchDropsStaleResult() async {
        let harness = Harness()
        harness.settings.selectedHostId = harness.hostA.id
        let store = harness.makeStore()

        // Park the in-flight refresh against host A inside its list call.
        harness.mockA.armGate()
        let refreshA = Task { await store.refresh() }
        await harness.mockA.waitUntilEntered()
        #expect(store.isRefreshing == true)

        // Switch to host B while A is still parked; B answers immediately.
        harness.settings.selectedHostId = harness.hostB.id
        store.switchHost()
        await store.refresh()

        #expect(store.containers.map(\.id) == ["b1"])
        #expect(store.isRefreshing == false)

        // Let the superseded host-A refresh complete; it must not apply.
        harness.mockA.proceed()
        await refreshA.value

        #expect(store.containers.map(\.id) == ["b1"])
        #expect(store.isConnected == true)
        #expect(store.isRefreshing == false)
    }

    @Test("Force refresh cancels and restarts rather than overlapping")
    func forceRefreshCancelsAndRestarts() async {
        let harness = Harness()
        harness.settings.selectedHostId = harness.hostA.id
        let store = harness.makeStore()

        // First refresh parks inside host A's list call.
        harness.mockA.armGate()
        let firstRefresh = Task { await store.refresh() }
        await harness.mockA.waitUntilEntered()

        // Change the data the same host will return, then force a restart.
        harness.mockA.mockContainers = [DockerContainer.mock(id: "a2", name: "alpha-2", state: .running)]
        await store.refresh(force: true)

        // The forced (second) refresh applied; it did not skip while busy.
        #expect(store.containers.map(\.id) == ["a2"])
        #expect(store.isRefreshing == false)

        // Release the superseded first refresh; its older result is discarded.
        harness.mockA.proceed()
        await firstRefresh.value

        #expect(store.containers.map(\.id) == ["a2"])
        #expect(store.isRefreshing == false)
        let listCalls = harness.mockA.calledMethods.filter { $0 == "listContainers" }.count
        #expect(listCalls == 2)
    }

    // MARK: - CB-065

    @Test("Removing the active host reinitializes against the fallback host")
    func removingActiveHostReinitializesToFallback() async {
        let harness = Harness()
        harness.settings.selectedHostId = harness.hostB.id
        let store = harness.makeStore()

        await store.refresh()
        #expect(store.containers.map(\.id) == ["b1"])

        // Remove the active host; selection falls back to the default (A).
        harness.settings.removeHost(id: harness.hostB.id)
        store.handleSettingsChange()
        await store.refresh()

        #expect(store.containers.map(\.id) == ["a1"])
        #expect(store.isConnected == true)
    }

    @Test("Editing the active host's config reinitializes the fetcher")
    func editingActiveHostReinitializes() async {
        let harness = Harness()
        harness.settings.selectedHostId = harness.hostB.id
        let store = harness.makeStore()

        await store.refresh()
        let callsBefore = harness.factoryCalls

        var editedB = harness.hostB
        editedB.socketPath = "/tmp/b-edited-\(UUID()).sock"
        harness.settings.updateHost(editedB)
        store.handleSettingsChange()

        // switchHost rebuilds the fetcher synchronously before refreshing.
        #expect(harness.factoryCalls == callsBefore + 1)

        await store.refresh()
        #expect(store.isRefreshing == false)
    }

    @Test("Editing a non-selected host does not reinitialize the fetcher")
    func editingNonSelectedHostDoesNotReinitialize() async {
        let harness = Harness()
        harness.settings.selectedHostId = harness.hostB.id
        let store = harness.makeStore()

        await store.refresh()
        let callsBefore = harness.factoryCalls

        // Edit host A while host B is the active/selected host.
        var editedA = harness.hostA
        editedA.socketPath = "/tmp/a-edited-\(UUID()).sock"
        harness.settings.updateHost(editedA)
        store.handleSettingsChange()

        #expect(harness.factoryCalls == callsBefore)
        #expect(store.containers.map(\.id) == ["b1"])
    }
}
