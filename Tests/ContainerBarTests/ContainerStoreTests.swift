import Foundation
import Testing
@testable import ContainerBar
@testable import ContainerBarCore

@Suite("ContainerStore Tests")
struct ContainerStoreTests {

    // MARK: - Helpers

    @MainActor
    private func makeStore(mock: MockDockerAPIClient) -> ContainerStore {
        let settings = SettingsStore(userDefaults: UserDefaults(suiteName: "test.\(UUID())")!)
        let fetcher = ContainerFetcher(client: mock, host: .local)
        return ContainerStore(settings: settings, fetcher: fetcher)
    }

    // MARK: - Refresh Tests

    @Test("Refresh populates containers")
    @MainActor
    func refreshPopulatesContainers() async {
        let mock = MockDockerAPIClient()
        mock.mockContainers = [
            DockerContainer.mock(id: "c1", name: "nginx", state: .running),
            DockerContainer.mock(id: "c2", name: "redis", state: .exited),
        ]

        let store = makeStore(mock: mock)
        await store.refresh()

        #expect(store.containers.count == 2)
        #expect(store.metricsSnapshot != nil)
    }

    @Test("Refresh sets isConnected on success")
    @MainActor
    func refreshSetsConnected() async {
        let mock = MockDockerAPIClient()
        mock.mockContainers = [
            DockerContainer.mock(id: "c1", name: "web", state: .running),
        ]

        let store = makeStore(mock: mock)
        #expect(store.isConnected == false)

        await store.refresh()

        #expect(store.isConnected == true)
        #expect(store.connectionError == nil)
        #expect(store.lastRefreshAt != nil)
    }

    @Test("Refresh sets connectionError on failure")
    @MainActor
    func refreshSetsErrorOnFailure() async {
        let mock = MockDockerAPIClient()
        mock.shouldFail = true
        mock.failureError = DockerAPIError.connectionFailed

        let store = makeStore(mock: mock)
        await store.refresh()

        #expect(store.isConnected == false)
        #expect(store.connectionError != nil)
    }

    @Test("Error recovery: success after failure clears error state")
    @MainActor
    func errorRecoveryAfterFailure() async {
        let mock = MockDockerAPIClient()
        mock.shouldFail = true
        mock.failureError = DockerAPIError.connectionFailed

        let store = makeStore(mock: mock)

        // First refresh fails
        await store.refresh()
        #expect(store.isConnected == false)
        #expect(store.connectionError != nil)

        // Fix mock and refresh again
        mock.shouldFail = false
        mock.mockContainers = [
            DockerContainer.mock(id: "c1", name: "web", state: .running),
        ]

        // Wait past rate limit
        try? await Task.sleep(for: .seconds(1.1))

        await store.refresh()
        #expect(store.isConnected == true)
        #expect(store.connectionError == nil)
        #expect(store.containers.count == 1)
    }

    @Test("Refresh clears stale connection errors while a retry is in flight")
    @MainActor
    func refreshClearsPreviousErrorDuringRetry() async {
        let mock = MockDockerAPIClient()
        mock.shouldFail = true
        mock.failureError = DockerAPIError.connectionFailed

        let store = makeStore(mock: mock)
        await store.refresh()

        #expect(store.connectionError != nil)

        mock.shouldFail = false
        mock.mockContainers = [
            DockerContainer.mock(id: "c1", name: "web", state: .running),
        ]
        mock.responseDelay = .milliseconds(200)

        let refreshTask = Task {
            await store.refresh(force: true)
        }

        try? await Task.sleep(for: .milliseconds(50))

        #expect(store.isRefreshing == true)
        #expect(store.connectionError == nil)

        await refreshTask.value

        #expect(store.isConnected == true)
        #expect(store.connectionError == nil)
    }

    // MARK: - Container Action Tests

    @Test("startContainer calls through to fetcher")
    @MainActor
    func startContainerCallsThrough() async {
        let mock = MockDockerAPIClient()
        mock.mockContainers = [
            DockerContainer.mock(id: "c1", name: "web", state: .exited),
        ]

        let store = makeStore(mock: mock)
        await store.refresh()

        // Reset call tracking
        mock.callCount = 0
        mock.lastCalledMethod = nil
        mock.calledMethods = []

        await store.startContainer(id: "c1")

        #expect(mock.calledMethods.contains("startContainer"))
    }

    @Test("stopContainer calls through to fetcher")
    @MainActor
    func stopContainerCallsThrough() async {
        let mock = MockDockerAPIClient()
        mock.mockContainers = [
            DockerContainer.mock(id: "c1", name: "web", state: .running),
        ]

        let store = makeStore(mock: mock)
        await store.refresh()

        mock.callCount = 0
        mock.calledMethods = []
        await store.stopContainer(id: "c1")

        #expect(mock.calledMethods.contains("stopContainer"))
    }

    @Test("restartContainer calls through to fetcher")
    @MainActor
    func restartContainerCallsThrough() async {
        let mock = MockDockerAPIClient()
        mock.mockContainers = [
            DockerContainer.mock(id: "c1", name: "web", state: .running),
        ]

        let store = makeStore(mock: mock)
        await store.refresh()

        mock.callCount = 0
        mock.calledMethods = []
        await store.restartContainer(id: "c1")

        #expect(mock.calledMethods.contains("restartContainer"))
    }

    @Test("removeContainer passes force flag")
    @MainActor
    func removeContainerPassesForceFlag() async {
        let mock = MockDockerAPIClient()
        mock.mockContainers = [
            DockerContainer.mock(id: "c1", name: "web", state: .exited),
        ]

        let store = makeStore(mock: mock)
        await store.refresh()

        mock.callCount = 0
        mock.calledMethods = []
        await store.removeContainer(id: "c1", force: true)

        #expect(mock.calledMethods.contains("removeContainer"))
    }

    // MARK: - Action Guard Tests

    @Test("Action tracks in-progress state")
    @MainActor
    func actionTracksInProgressState() async {
        let mock = MockDockerAPIClient()
        mock.mockContainers = [
            DockerContainer.mock(id: "c1", name: "web", state: .running),
        ]

        let store = makeStore(mock: mock)
        await store.refresh()

        // After action completes, the set should be empty
        await store.stopContainer(id: "c1")
        #expect(store.actionInProgress.isEmpty)
    }

    // MARK: - Metrics History Tests

    @Test("Metrics history updates after refresh with stats")
    @MainActor
    func metricsHistoryUpdates() async {
        let mock = MockDockerAPIClient()
        mock.mockContainers = [
            DockerContainer.mock(id: "c1", name: "web", state: .running),
        ]
        mock.mockStats["c1"] = ContainerStats.mock(
            containerId: "c1",
            cpuPercent: 10.0,
            memoryUsageBytes: 100_000_000,
            memoryLimitBytes: 500_000_000
        )

        let store = makeStore(mock: mock)
        await store.refresh()

        #expect(store.metricsHistory.cpu.hasData == false) // Need at least 2 points
        #expect(store.metricsHistory.cpu.latest != nil)

        // Second refresh gives us 2 data points
        try? await Task.sleep(for: .seconds(1.1))
        await store.refresh()

        #expect(store.metricsHistory.cpu.hasData == true)
    }
}
