import Foundation
import Testing
@testable import ContainerBar
@testable import ContainerBarCore

/// Additional edge-case coverage for `ContainerActionRouter`, complementing
/// the per-action dispatch tests in `ContainerActionRouterTests`. Focuses on
/// menu-reopen semantics (which actions do and do not reopen), repeated
/// dispatch, late callback rebinding, and degenerate ids.
@Suite("Container Action Router edge cases")
struct ContainerActionRouterEdgeTests {
    private enum WaitError: Error { case timedOut(String) }

    @MainActor
    private func makeRouter(
        containers: [DockerContainer] = [.mock(id: "abc")]
    ) -> (router: ContainerActionRouter, mock: MockDockerAPIClient) {
        let mock = MockDockerAPIClient()
        mock.mockContainers = containers
        let settings = SettingsStore(userDefaults: UserDefaults(suiteName: "routeredge.\(UUID())")!)
        let fetcher = ContainerFetcher(client: mock, host: .local)
        let store = ContainerStore(settings: settings, fetcher: fetcher)
        return (ContainerActionRouter(containerStore: store), mock)
    }

    private func waitForCallCount(
        _ method: String,
        atLeast count: Int,
        in mock: MockDockerAPIClient,
        timeout: Duration = .seconds(5)
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while mock.calledMethods.filter({ $0 == method }).count < count {
            guard clock.now < deadline else { throw WaitError.timedOut(method) }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: - Menu reopen semantics

    @Test("Side-effect actions never request a menu reopen")
    @MainActor
    func sideEffectActionsDoNotReopen() async throws {
        let (router, _) = makeRouter()
        var reopenCount = 0
        router.onMenuReopenRequested = { reopenCount += 1 }
        router.onRemoveRequested = { _ in }
        router.onViewLogsRequested = { _ in }
        router.onCopyIdRequested = { _ in }

        router.handleContainerAction(.remove("abc"))
        router.handleContainerAction(.viewLogs("abc"))
        router.handleContainerAction(.copyId("abc"))

        #expect(reopenCount == 0)
    }

    @Test("Each mutating action reopens the menu exactly once")
    @MainActor
    func mutatingActionsReopenOnce() async throws {
        let (router, _) = makeRouter()
        var reopenCount = 0
        router.onMenuReopenRequested = { reopenCount += 1 }

        router.handleContainerAction(.start("abc"))
        router.handleContainerAction(.stop("abc"))
        router.handleContainerAction(.restart("abc"))

        // Reopen is synchronous with dispatch, independent of the async store work.
        #expect(reopenCount == 3)
    }

    @Test("Dispatching the same action for distinct ids drives the store for each")
    @MainActor
    func dispatchAcrossDistinctIdsCallsStoreEach() async throws {
        // NOTE: the store debounces *concurrent same-id* actions via its
        // `actionInProgress` set, so two rapid `.stop("abc")` calls are not
        // guaranteed to both reach the client. Distinct ids are never
        // debounced against each other, which is what we assert here.
        let (router, mock) = makeRouter(containers: [.mock(id: "abc"), .mock(id: "def")])
        router.handleContainerAction(.stop("abc"))
        router.handleContainerAction(.stop("def"))

        try await waitForCallCount("stopContainer", atLeast: 2, in: mock)
        #expect(mock.calledMethods.filter { $0 == "stopContainer" }.count >= 2)
    }

    // MARK: - Callback rebinding

    @Test("Rebinding a callback routes to the most recent closure")
    @MainActor
    func rebindingCallbackUsesLatest() async throws {
        let (router, _) = makeRouter()
        var firstFired = false
        var secondFired = false
        router.onCopyIdRequested = { _ in firstFired = true }
        router.onCopyIdRequested = { _ in secondFired = true }

        router.handleContainerAction(.copyId("abc"))

        #expect(firstFired == false)
        #expect(secondFired == true)
    }

    // MARK: - Degenerate ids

    @Test("An empty container id is forwarded verbatim to side-effect callbacks")
    @MainActor
    func emptyIdForwardedVerbatim() async throws {
        let (router, _) = makeRouter()
        var captured: String?
        router.onViewLogsRequested = { captured = $0 }

        router.handleContainerAction(.viewLogs(""))

        #expect(captured == "")
    }

    @Test("Mutating an id absent from the store still dispatches to the store")
    @MainActor
    func unknownIdStillDispatches() async throws {
        // The router forwards ids blindly; existence checks belong to the store
        // and the daemon. A ghost id should still reach the store method.
        let (router, mock) = makeRouter(containers: [])
        router.handleContainerAction(.start("ghost"))

        try await waitForCallCount("startContainer", atLeast: 1, in: mock)
        #expect(mock.calledMethods.contains("startContainer"))
    }
}
