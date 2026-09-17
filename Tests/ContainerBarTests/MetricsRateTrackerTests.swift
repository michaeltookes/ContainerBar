import Foundation
import Testing
@testable import ContainerBar
@testable import ContainerBarCore

/// Covers `MetricsRateTracker.update`, which derives KB/s rates from the delta
/// between successive snapshots.
///
/// `update` reads the wall clock (`Date()`) internally and exposes no seam for
/// injecting time, so the exact `elapsed` divisor is unknowable from a test.
/// Rather than refactor the production store (out of scope for this branch),
/// the rate assertions here are deliberately time-independent:
///   - counts (how many rate points were appended) are exact;
///   - a counter reset and a zero delta both produce an exact 0.0 rate;
///   - a positive delta is checked for finiteness / positivity and for the
///     proportionality between the four rates, which all share one `elapsed`
///     and one 1024 divisor within a single call — so their ratios equal the
///     ratios of their byte deltas regardless of the actual elapsed time.
/// The `elapsed > 0` guard cannot be exercised without a time seam (two calls
/// can never be forced onto the same `Date()`); it is left to code review.
@Suite("MetricsRateTracker")
@MainActor
struct MetricsRateTrackerTests {

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
        let tracker = MetricsRateTracker()
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

    @Test("A second call with positive deltas appends proportional, finite rates")
    func secondCallAppendsProportionalRates() throws {
        let tracker = MetricsRateTracker()
        var history = AggregatedMetricsHistory()

        // Baseline.
        tracker.update(history: &history, snapshot: snapshot, stats: ["c1": stats()])
        // Deltas chosen with known ratios: rx=4096, tx=2048, read=1024, write=8192.
        tracker.update(
            history: &history,
            snapshot: snapshot,
            stats: ["c1": stats(rx: 4096, tx: 2048, read: 1024, write: 8192)]
        )

        #expect(history.networkRxRate.values.count == 1)
        #expect(history.networkTxRate.values.count == 1)
        #expect(history.diskReadRate.values.count == 1)
        #expect(history.diskWriteRate.values.count == 1)

        let rx = try #require(history.networkRxRate.latest)
        let tx = try #require(history.networkTxRate.latest)
        let read = try #require(history.diskReadRate.latest)
        let write = try #require(history.diskWriteRate.latest)

        // All rates are finite and strictly positive given positive deltas and
        // a positive elapsed interval (no divide-by-zero / NaN / Inf leaked).
        for rate in [rx, tx, read, write] {
            #expect(rate.isFinite)
            #expect(rate > 0)
        }

        // The four rates share one elapsed divisor within this call, so their
        // ratios equal their byte-delta ratios. rx = 2*tx, read = tx/2,
        // write = 4*tx. Assert against tx to stay time-independent.
        let tolerance = tx * 1e-9
        #expect(abs(rx - 2 * tx) <= tolerance)
        #expect(abs(read - tx / 2) <= tolerance)
        #expect(abs(write - 4 * tx) <= tolerance)
    }

    @Test("A counter reset (current < previous) saturates to a 0 rate, never negative")
    func counterResetSaturatesToZero() {
        let tracker = MetricsRateTracker()
        var history = AggregatedMetricsHistory()

        // Baseline with high counters.
        tracker.update(
            history: &history,
            snapshot: snapshot,
            stats: ["c1": stats(rx: 10_000, tx: 10_000, read: 10_000, write: 10_000)]
        )
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
        let tracker = MetricsRateTracker()
        var history = AggregatedMetricsHistory()

        tracker.update(history: &history, snapshot: snapshot, stats: ["c1": stats(rx: 500, tx: 500)])
        tracker.update(history: &history, snapshot: snapshot, stats: ["c1": stats(rx: 500, tx: 500)])

        #expect(history.networkRxRate.latest == 0)
        #expect(history.networkTxRate.latest == 0)
    }

    @Test("reset() clears the baseline so the next call appends no rates")
    func resetClearsBaseline() {
        let tracker = MetricsRateTracker()
        var history = AggregatedMetricsHistory()

        tracker.update(history: &history, snapshot: snapshot, stats: ["c1": stats(rx: 100)])
        tracker.update(history: &history, snapshot: snapshot, stats: ["c1": stats(rx: 200)])
        #expect(history.networkRxRate.values.count == 1)

        tracker.reset()

        // After reset there is no previous timestamp again, so the next call is
        // treated as a fresh baseline and appends no new rate point.
        tracker.update(history: &history, snapshot: snapshot, stats: ["c1": stats(rx: 999)])
        #expect(history.networkRxRate.values.count == 1)
    }

    @Test("Rates aggregate across every container in the snapshot")
    func ratesSumAcrossContainers() throws {
        let tracker = MetricsRateTracker()
        var history = AggregatedMetricsHistory()

        tracker.update(
            history: &history,
            snapshot: snapshot,
            stats: [
                "a": stats(rx: 0, id: "a"),
                "b": stats(rx: 0, id: "b")
            ]
        )
        // Only container "a" moves; "b" stays flat. The tracker sums counters
        // across containers, so a positive total delta still produces a rate.
        tracker.update(
            history: &history,
            snapshot: snapshot,
            stats: [
                "a": stats(rx: 3000, id: "a"),
                "b": stats(rx: 0, id: "b")
            ]
        )

        let rx = try #require(history.networkRxRate.latest)
        #expect(rx > 0)
        #expect(rx.isFinite)
    }
}
