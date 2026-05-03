import Foundation
import Testing
@testable import ContainerBar
@testable import ContainerBarCore

@Suite("Container Action Router")
struct ContainerActionRouterTests {
    private enum WaitError: Error, CustomStringConvertible {
        case timedOut(method: String, calls: [String])

        var description: String {
            switch self {
            case .timedOut(let method, let calls):
                "Timed out waiting for \(method). Calls recorded: \(calls)"
            }
        }
    }

    @MainActor
    private func makeRouter(
        containers: [DockerContainer] = [.mock(id: "abc")]
    ) -> (router: ContainerActionRouter, mock: MockDockerAPIClient) {
        let mock = MockDockerAPIClient()
        mock.mockContainers = containers
        let settings = SettingsStore(userDefaults: UserDefaults(suiteName: "test.\(UUID())")!)
        let fetcher = ContainerFetcher(client: mock, host: .local)
        let store = ContainerStore(settings: settings, fetcher: fetcher)
        let router = ContainerActionRouter(containerStore: store)
        return (router, mock)
    }

    private func waitForCall(
        _ method: String,
        in mock: MockDockerAPIClient,
        timeout: Duration = .seconds(1)
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while !mock.calledMethods.contains(method) {
            guard clock.now < deadline else {
                throw WaitError.timedOut(method: method, calls: mock.calledMethods)
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: - Store-mutating actions

    @Test("`.start` dispatches to ContainerStore.startContainer and requests menu reopen")
    @MainActor
    func startDispatchesToStoreAndReopens() async throws {
        let (router, mock) = makeRouter()
        var reopenCount = 0
        router.onMenuReopenRequested = { reopenCount += 1 }

        router.handleContainerAction(.start("abc"))

        try await waitForCall("startContainer", in: mock)
        #expect(mock.calledMethods.contains("startContainer"))
        #expect(reopenCount == 1)
    }

    @Test("`.stop` dispatches to ContainerStore.stopContainer and requests menu reopen")
    @MainActor
    func stopDispatchesToStoreAndReopens() async throws {
        let (router, mock) = makeRouter()
        var reopenCount = 0
        router.onMenuReopenRequested = { reopenCount += 1 }

        router.handleContainerAction(.stop("abc"))

        try await waitForCall("stopContainer", in: mock)
        #expect(mock.calledMethods.contains("stopContainer"))
        #expect(reopenCount == 1)
    }

    @Test("`.restart` dispatches to ContainerStore.restartContainer and requests menu reopen")
    @MainActor
    func restartDispatchesToStoreAndReopens() async throws {
        let (router, mock) = makeRouter()
        var reopenCount = 0
        router.onMenuReopenRequested = { reopenCount += 1 }

        router.handleContainerAction(.restart("abc"))

        try await waitForCall("restartContainer", in: mock)
        #expect(mock.calledMethods.contains("restartContainer"))
        #expect(reopenCount == 1)
    }

    // MARK: - Side-effect actions

    @Test("`.remove` does not call the store directly; it forwards the id to onRemoveRequested")
    @MainActor
    func removeForwardsToCallback() async throws {
        let (router, mock) = makeRouter()
        var capturedId: String?
        router.onRemoveRequested = { capturedId = $0 }

        router.handleContainerAction(.remove("abc"))

        #expect(capturedId == "abc")
        // Removal goes through the host's confirmation alert, NOT directly
        // through the store. The store-side call only happens after the user
        // confirms inside the host-supplied callback.
        #expect(!mock.calledMethods.contains("removeContainer"))
    }

    @Test("`.viewLogs` forwards the id to onViewLogsRequested without touching the store")
    @MainActor
    func viewLogsForwardsToCallback() async throws {
        let (router, mock) = makeRouter()
        var capturedId: String?
        router.onViewLogsRequested = { capturedId = $0 }

        router.handleContainerAction(.viewLogs("abc"))

        #expect(capturedId == "abc")
        #expect(!mock.calledMethods.contains("getContainerLogs"))
    }

    @Test("`.copyId` forwards the id to onCopyIdRequested without touching the store")
    @MainActor
    func copyIdForwardsToCallback() async throws {
        let (router, _) = makeRouter()
        var capturedId: String?
        router.onCopyIdRequested = { capturedId = $0 }

        router.handleContainerAction(.copyId("abc"))

        #expect(capturedId == "abc")
    }

    // MARK: - No cross-talk between actions

    @Test("Each action only triggers its own callback")
    @MainActor
    func actionsAreIsolated() async throws {
        let (router, _) = makeRouter()
        var reopenCount = 0
        var removeFired = false
        var viewLogsFired = false
        var copyIdFired = false
        router.onMenuReopenRequested = { reopenCount += 1 }
        router.onRemoveRequested = { _ in removeFired = true }
        router.onViewLogsRequested = { _ in viewLogsFired = true }
        router.onCopyIdRequested = { _ in copyIdFired = true }

        router.handleContainerAction(.copyId("abc"))

        #expect(copyIdFired == true)
        #expect(reopenCount == 0)
        #expect(removeFired == false)
        #expect(viewLogsFired == false)
    }

    @Test("Default callbacks are no-ops — handling actions on a fresh router doesn't crash")
    @MainActor
    func defaultCallbacksAreNoOps() async throws {
        let (router, _) = makeRouter()
        // No callbacks wired. These should all be safe no-ops.
        router.handleContainerAction(.remove("abc"))
        router.handleContainerAction(.viewLogs("abc"))
        router.handleContainerAction(.copyId("abc"))
    }

    @Test("Container ID is passed through verbatim, not via lookup")
    @MainActor
    func containerIdIsPassedThroughVerbatim() async throws {
        // Even if the id isn't present in the store, the router still
        // forwards it. Lookups are the responsibility of the callback.
        let (router, _) = makeRouter(containers: [])
        var capturedId: String?
        router.onRemoveRequested = { capturedId = $0 }

        router.handleContainerAction(.remove("nonexistent-id"))

        #expect(capturedId == "nonexistent-id")
    }
}
