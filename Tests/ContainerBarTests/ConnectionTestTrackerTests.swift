import Foundation
import Testing
@testable import ContainerBar

/// CB-080: a connection-test result belongs to the host it ran against.
///
/// `ConnectionSettingsPane`'s body cannot be inspected on this toolchain (see
/// `ConnectionSettingsPaneViewTests`), so the scoping is tested on the value
/// type the pane reads its per-host result and in-flight state from.
@Suite("ConnectionTestTracker")
struct ConnectionTestTrackerTests {
    private let hostA = UUID()
    private let hostB = UUID()

    @Test("A result for host A does not show for host B")
    func resultIsScopedToItsHost() {
        var tracker = ConnectionTestTracker()
        let token = tracker.begin(hostId: hostA)
        tracker.finish(hostId: hostA, token: token, result: .success)

        #expect(tracker.result(for: hostA) == .success)
        #expect(tracker.result(for: hostB) == nil)
        #expect(!tracker.isTesting(hostB))
    }

    @Test("A test in flight for A never renders under B, and A's result shows on reselect")
    func inFlightResultLandsOnItsOwnHost() {
        var tracker = ConnectionTestTracker()
        let token = tracker.begin(hostId: hostA)

        #expect(tracker.isTesting(hostA))
        #expect(!tracker.isTesting(hostB))

        // The user selects B, then A's test completes.
        let acceptedForA = tracker.finish(hostId: hostA, token: token, result: .failure("refused"))
        #expect(acceptedForA)

        #expect(tracker.result(for: hostB) == nil)
        #expect(tracker.result(for: hostA) == .failure("refused"))
        #expect(!tracker.isTesting(hostA))
    }

    @Test("B's failure shows only under B; A keeps its own result")
    func failureStaysOnItsHost() {
        var tracker = ConnectionTestTracker()
        let tokenA = tracker.begin(hostId: hostA)
        tracker.finish(hostId: hostA, token: tokenA, result: .success)
        let tokenB = tracker.begin(hostId: hostB)
        tracker.finish(hostId: hostB, token: tokenB, result: .failure("unreachable"))

        #expect(tracker.result(for: hostA) == .success)
        #expect(tracker.result(for: hostB) == .failure("unreachable"))
    }

    @Test("Starting a new test clears that host's old result, not other hosts'")
    func beginClearsOnlyItsHost() {
        var tracker = ConnectionTestTracker()
        let tokenA = tracker.begin(hostId: hostA)
        tracker.finish(hostId: hostA, token: tokenA, result: .success)
        let tokenB = tracker.begin(hostId: hostB)
        tracker.finish(hostId: hostB, token: tokenB, result: .success)

        _ = tracker.begin(hostId: hostA)

        #expect(tracker.result(for: hostA) == nil)
        #expect(tracker.isTesting(hostA))
        #expect(tracker.result(for: hostB) == .success)
    }

    @Test("A superseded run's completion is dropped")
    func supersededRunIsDropped() {
        var tracker = ConnectionTestTracker()
        let first = tracker.begin(hostId: hostA)
        let second = tracker.begin(hostId: hostA)

        let staleAccepted = tracker.finish(hostId: hostA, token: first, result: .failure("stale"))
        #expect(!staleAccepted)
        #expect(tracker.result(for: hostA) == nil)
        #expect(tracker.isTesting(hostA))

        let currentAccepted = tracker.finish(hostId: hostA, token: second, result: .success)
        #expect(currentAccepted)
        #expect(tracker.result(for: hostA) == .success)
    }

    @Test("Editing a host clears its result and drops its in-flight run")
    func invalidateClearsResultAndInFlightRun() {
        var tracker = ConnectionTestTracker()
        let tokenB = tracker.begin(hostId: hostB)
        tracker.finish(hostId: hostB, token: tokenB, result: .success)
        let tokenA = tracker.begin(hostId: hostA)

        tracker.invalidate(hostId: hostA)
        #expect(!tracker.isTesting(hostA))
        let invalidatedAccepted = tracker.finish(hostId: hostA, token: tokenA, result: .success)
        #expect(!invalidatedAccepted)
        #expect(tracker.result(for: hostA) == nil)

        tracker.invalidate(hostId: hostB)
        #expect(tracker.result(for: hostB) == nil)
    }
}
