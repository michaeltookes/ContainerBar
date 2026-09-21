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

    @Test("Force refresh joins the in-flight refresh and re-fetches post-action state")
    func forceRefreshJoinsAndReFetchesWithoutCancelling() async {
        let harness = Harness()
        harness.settings.selectedHostId = harness.hostA.id
        let store = harness.makeStore()

        // First (timer-style) refresh parks inside host A's list call.
        harness.mockA.armGate()
        let firstRefresh = Task { await store.refresh() }
        await harness.mockA.waitUntilEntered()

        // Simulate a container action mutating the list, then a forced refresh
        // (as performContainerAction issues). It must join the in-flight
        // refresh rather than cancelling it (cancelling would tear down the
        // live transport — switchHost() is the only cancel path, verified by
        // hostSwitchMidFetchDropsStaleResult), then re-fetch with the fetcher's
        // rate-limit cache bypassed so the mutation is reflected instead of the
        // cached pre-action list.
        harness.mockA.mockContainers = [
            DockerContainer.mock(id: "a1", name: "alpha", state: .running),
            DockerContainer.mock(id: "a2", name: "alpha-2", state: .running)
        ]
        let forced = Task { await store.refresh(force: true) }

        harness.mockA.proceed()
        await firstRefresh.value
        await forced.value

        // Not cancelled (no mid-fetch teardown); the forced refresh made a
        // second real daemon round-trip (bypassing the 1s cache), so the
        // changed list is applied and the store settles idle.
        #expect(harness.mockA.cancelledAfterGate == false)
        let listCalls = harness.mockA.calledMethods.filter { $0 == "listContainers" }.count
        #expect(listCalls == 2)
        #expect(store.containers.map(\.id) == ["a1", "a2"])
        #expect(store.isRefreshing == false)
    }

    @Test("Multiple forced refreshes coalesce after joining the same in-flight refresh")
    func multipleForceRefreshesCoalesceAfterJoin() async {
        let harness = Harness()
        harness.settings.selectedHostId = harness.hostA.id
        let store = harness.makeStore()

        harness.mockA.armGate()
        let firstRefresh = Task { await store.refresh() }
        await harness.mockA.waitUntilEntered()

        harness.mockA.mockContainers = [
            DockerContainer.mock(id: "a1", name: "alpha", state: .running),
            DockerContainer.mock(id: "a2", name: "alpha-2", state: .running)
        ]
        let forcedOne = Task { await store.refresh(force: true) }
        let forcedTwo = Task { await store.refresh(force: true) }

        await Task.yield()
        await Task.yield()

        harness.mockA.proceed()
        await firstRefresh.value
        await forcedOne.value
        await forcedTwo.value

        #expect(harness.mockA.cancelledAfterGate == false)
        let listCalls = harness.mockA.calledMethods.filter { $0 == "listContainers" }.count
        #expect(listCalls == 2)
        #expect(store.containers.map(\.id) == ["a1", "a2"])
        #expect(store.isRefreshing == false)
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

    @Test("Renaming the active host does not reinitialize the fetcher")
    func renamingActiveHostDoesNotReinitialize() async {
        let harness = Harness()
        harness.settings.selectedHostId = harness.hostB.id
        let store = harness.makeStore()

        await store.refresh()
        let callsBefore = harness.factoryCalls

        // A rename changes only a cosmetic field, not the connection identity.
        var renamedB = harness.hostB
        renamedB.name = "Host B (renamed)"
        harness.settings.updateHost(renamedB)
        store.handleSettingsChange()

        #expect(harness.factoryCalls == callsBefore)
        #expect(store.containers.map(\.id) == ["b1"])
    }

    @Test("Marking another host default does not reinitialize the active host")
    func markingAnotherHostDefaultDoesNotReinitialize() async {
        let harness = Harness()
        harness.settings.selectedHostId = harness.hostB.id
        let store = harness.makeStore()

        await store.refresh()
        let callsBefore = harness.factoryCalls

        // setDefaultHost rewrites `isDefault` across every host; the active
        // host's connection identity is unchanged, so no reinit should occur.
        harness.settings.setDefaultHost(id: harness.hostA.id)
        store.handleSettingsChange()

        #expect(harness.factoryCalls == callsBefore)
        #expect(store.containers.map(\.id) == ["b1"])
    }
}
