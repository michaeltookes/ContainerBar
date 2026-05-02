import Foundation
import ContainerBarCore

/// Tracks delta-based rates (network rx/tx, disk read/write) between successive
/// metrics snapshots and appends them to the rolling sparkline history.
@MainActor
final class MetricsRateTracker {
    private var previousNetworkRx: UInt64 = 0
    private var previousNetworkTx: UInt64 = 0
    private var previousBlockRead: UInt64 = 0
    private var previousBlockWrite: UInt64 = 0
    private var previousTimestamp: Date?

    func update(
        history: inout AggregatedMetricsHistory,
        snapshot: ContainerMetricsSnapshot,
        stats: [String: ContainerStats]
    ) {
        let now = Date()

        history.cpu.append(snapshot.totalCPUPercent)
        history.memory.append(snapshot.memoryUsagePercent)

        let totalNetworkRx = stats.values.reduce(0) { $0 + $1.networkRxBytes }
        let totalNetworkTx = stats.values.reduce(0) { $0 + $1.networkTxBytes }
        let totalBlockRead = stats.values.reduce(0) { $0 + $1.blockReadBytes }
        let totalBlockWrite = stats.values.reduce(0) { $0 + $1.blockWriteBytes }

        if let prevTime = previousTimestamp {
            let elapsed = now.timeIntervalSince(prevTime)
            if elapsed > 0 {
                // Saturating subtraction handles counter resets.
                let rxDelta = totalNetworkRx >= previousNetworkRx ? totalNetworkRx - previousNetworkRx : 0
                let txDelta = totalNetworkTx >= previousNetworkTx ? totalNetworkTx - previousNetworkTx : 0
                let readDelta = totalBlockRead >= previousBlockRead ? totalBlockRead - previousBlockRead : 0
                let writeDelta = totalBlockWrite >= previousBlockWrite ? totalBlockWrite - previousBlockWrite : 0

                let rxRate = Double(rxDelta) / elapsed / 1024.0
                let txRate = Double(txDelta) / elapsed / 1024.0
                let readRate = Double(readDelta) / elapsed / 1024.0
                let writeRate = Double(writeDelta) / elapsed / 1024.0

                history.networkRxRate.append(max(0, rxRate))
                history.networkTxRate.append(max(0, txRate))
                history.diskReadRate.append(max(0, readRate))
                history.diskWriteRate.append(max(0, writeRate))
            }
        }

        previousNetworkRx = totalNetworkRx
        previousNetworkTx = totalNetworkTx
        previousBlockRead = totalBlockRead
        previousBlockWrite = totalBlockWrite
        previousTimestamp = now
    }

    func reset() {
        previousNetworkRx = 0
        previousNetworkTx = 0
        previousBlockRead = 0
        previousBlockWrite = 0
        previousTimestamp = nil
    }
}
