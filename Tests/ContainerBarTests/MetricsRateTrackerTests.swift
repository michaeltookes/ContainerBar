import Foundation
import Testing
@testable import ContainerBar
@testable import ContainerBarCore

/// Covers `MetricsRateTracker.update`, which derives KB/s rates from the delta
/// between successive snapshots. The tracker takes an injectable clock, so
/// every test drives elapsed time explicitly and asserts exact rates.
@Suite("MetricsRateTracker")
@MainActor
struct MetricsRateTrackerTests {

    /// Manually advanced clock handed to the tracker.
    @MainActor
    private final class StepClock {
        private(set) var current = Date(timeIntervalSince1970: 1_000_000)
        func now() -> Date { current }
        func advance(by seconds: TimeInterval) { current = current.addingTimeInterval(seconds) }
    }

    private func makeTracker() -> (MetricsRateTracker, StepClock) {
        let clock = StepClock()
        return (MetricsRateTracker(now: { clock.now() }), clock)
    }

    /// Builds a `ContainerStats` with explicit cumulative counters; the shared
    /// `.mock` does not expose the network/block byte fields this suite drives.
    private func stats(
        rx: UInt64 = 0,
        tx: UInt64 = 0,
        read: UInt64 = 0,
        write: UInt64 = 0,
        id: String = "c1"
    ) -> ContainerStats {
        ContainerStats(
            containerId: id,
            timestamp: Date(),
            cpuPercent: 1,
            cpuSystemUsage: 0,
            cpuContainerUsage: 0,
            onlineCPUs: 1,
            memoryUsageBytes: 0,
            memoryLimitBytes: 1024,
            memoryPercent: 0,
            memoryCache: nil,
            networkRxBytes: rx,
            networkTxBytes: tx,
            networkRxPackets: 0,
            networkTxPackets: 0,
            blockReadBytes: read,
            blockWriteBytes: write
        )
    }

    private let snapshot = ContainerMetricsSnapshot.mock()

    @Test("First call establishes a baseline: cpu/memory recorded, no rates yet")
    func firstCallEstablishesBaseline() {
        let (tracker, _) = makeTracker()
        var history = AggregatedMetricsHistory()

        tracker.update(history: &history, snapshot: snapshot, stats: ["c1": stats(rx: 100)])

        // CPU/memory are appended unconditionally on every call.
        #expect(history.cpu.values.count == 1)
        #expect(history.memory.values.count == 1)
        // Rates need a previous timestamp, so none are appended on the first call.
        #expect(history.networkRxRate.values.isEmpty)
        #expect(history.networkTxRate.values.isEmpty)
        #expect(history.diskReadRate.values.isEmpty)
        #expect(history.diskWriteRate.values.isEmpty)
    }

    @Test("A second call after two seconds appends exact KB/s rates")
    func secondCallAppendsExactRates() {
        let (tracker, clock) = makeTracker()
        var history = AggregatedMetricsHistory()

        tracker.update(history: &history, snapshot: snapshot, stats: ["c1": stats()])
        clock.advance(by: 2)
        tracker.update(
            history: &history,
            snapshot: snapshot,
            stats: ["c1": stats(rx: 4096, tx: 2048, read: 1024, write: 8192)]
        )

        // bytes / 2 s / 1024 -> KB/s, all exactly representable.
        #expect(history.networkRxRate.values.count == 1)
        #expect(history.networkRxRate.latest == 2.0)
        #expect(history.networkTxRate.latest == 1.0)
        #expect(history.diskReadRate.latest == 0.5)
        #expect(history.diskWriteRate.latest == 4.0)
    }

    @Test("A zero elapsed interval appends no rates and does not divide")
    func zeroElapsedSkipsRates() {
        let (tracker, _) = makeTracker()
        var history = AggregatedMetricsHistory()

        tracker.update(history: &history, snapshot: snapshot, stats: ["c1": stats(rx: 100)])
        // Clock not advanced: same timestamp as the baseline.
        tracker.update(history: &history, snapshot: snapshot, stats: ["c1": stats(rx: 5_000)])

        #expect(history.cpu.values.count == 2)
        #expect(history.networkRxRate.values.isEmpty)
    }

    @Test("A counter reset (current < previous) saturates to a 0 rate, never negative")
    func counterResetSaturatesToZero() {
        let (tracker, clock) = makeTracker()
        var history = AggregatedMetricsHistory()

        tracker.update(
            history: &history,
            snapshot: snapshot,
            stats: ["c1": stats(rx: 10_000, tx: 10_000, read: 10_000, write: 10_000)]
        )
        clock.advance(by: 1)
        // Counters drop below the baseline (e.g. container restart).
        tracker.update(
            history: &history,
            snapshot: snapshot,
            stats: ["c1": stats(rx: 1, tx: 1, read: 1, write: 1)]
        )

        #expect(history.networkRxRate.latest == 0)
        #expect(history.networkTxRate.latest == 0)
        #expect(history.diskReadRate.latest == 0)
        #expect(history.diskWriteRate.latest == 0)
    }

    @Test("Unchanged counters yield a 0 rate")
    func zeroDeltaYieldsZeroRate() {
        let (tracker, clock) = makeTracker()
        var history = AggregatedMetricsHistory()

        tracker.update(history: &history, snapshot: snapshot, stats: ["c1": stats(rx: 500, tx: 500)])
        clock.advance(by: 1)
        tracker.update(history: &history, snapshot: snapshot, stats: ["c1": stats(rx: 500, tx: 500)])

        #expect(history.networkRxRate.latest == 0)
        #expect(history.networkTxRate.latest == 0)
    }

    @Test("reset() clears the baseline so the next call appends no rates")
    func resetClearsBaseline() {
        let (tracker, clock) = makeTracker()
        var history = AggregatedMetricsHistory()

        tracker.update(history: &history, snapshot: snapshot, stats: ["c1": stats(rx: 100)])
        clock.advance(by: 1)
        tracker.update(history: &history, snapshot: snapshot, stats: ["c1": stats(rx: 200)])
        #expect(history.networkRxRate.values.count == 1)

        tracker.reset()
        clock.advance(by: 1)

        // After reset there is no previous timestamp again, so the next call is
        // treated as a fresh baseline and appends no new rate point.
        tracker.update(history: &history, snapshot: snapshot, stats: ["c1": stats(rx: 999)])
        #expect(history.networkRxRate.values.count == 1)
    }

    @Test("Rates sum across every container in the snapshot")
    func ratesSumAcrossContainers() {
        let (tracker, clock) = makeTracker()
        var history = AggregatedMetricsHistory()

        tracker.update(
            history: &history,
            snapshot: snapshot,
            stats: ["a": stats(rx: 0, id: "a"), "b": stats(rx: 0, id: "b")]
        )
        clock.advance(by: 1)
        // Both move; the tracker sums counters across containers: 2048 + 1024.
        tracker.update(
            history: &history,
            snapshot: snapshot,
            stats: ["a": stats(rx: 2048, id: "a"), "b": stats(rx: 1024, id: "b")]
        )

        #expect(history.networkRxRate.latest == 3.0)
    }
}
