import Foundation
import Testing
@testable import ContainerBarCore

@Suite("ContainerStats Tests")
struct ContainerStatsTests {

    @Test("Memory conversion to MB is correct")
    func memoryConversionToMB() {
        let stats = ContainerStats(
            containerId: "test",
            timestamp: Date(),
            cpuPercent: 5.0,
            cpuSystemUsage: 100,
            cpuContainerUsage: 5,
            onlineCPUs: 4,
            memoryUsageBytes: 134_217_728, // 128 MB
            memoryLimitBytes: 536_870_912,  // 512 MB
            memoryPercent: 25.0,
            memoryCache: nil,
            networkRxBytes: 1_048_576, // 1 MB
            networkTxBytes: 524_288,   // 0.5 MB
            networkRxPackets: 1000,
            networkTxPackets: 500,
            blockReadBytes: 0,
            blockWriteBytes: 0
        )

        #expect(stats.memoryUsedMB == 128.0)
        #expect(stats.memoryLimitMB == 512.0)
        #expect(stats.networkRxMB == 1.0)
        #expect(stats.networkTxMB == 0.5)
    }
}

@Suite("ContainerMetricsSnapshot Tests")
struct ContainerMetricsSnapshotTests {

    @Test("Health status is critical when no containers running")
    func healthCriticalWhenNoRunning() {
        let snapshot = ContainerMetricsSnapshot(
            containers: [],
            totalCPUPercent: 0,
            totalMemoryUsedBytes: 0,
            totalMemoryLimitBytes: 1000,
            runningCount: 0,
            stoppedCount: 5,
            pausedCount: 0,
            totalCount: 5,
            updatedAt: Date()
        )

        #expect(snapshot.overallHealth == .critical)
    }

    @Test("Health status is warning when CPU too high")
    func healthWarningWhenCPUHigh() {
        let snapshot = ContainerMetricsSnapshot(
            containers: [],
            totalCPUPercent: 95.0,
            totalMemoryUsedBytes: 1000,
            totalMemoryLimitBytes: 10000,
            runningCount: 3,
            stoppedCount: 0,
            pausedCount: 0,
            totalCount: 3,
            updatedAt: Date()
        )

        #expect(snapshot.overallHealth == .warning)
    }

    @Test("Health status is warning when memory too high")
    func healthWarningWhenMemoryHigh() {
        let snapshot = ContainerMetricsSnapshot(
            containers: [],
            totalCPUPercent: 50.0,
            totalMemoryUsedBytes: 9600,
            totalMemoryLimitBytes: 10000, // 96% usage
            runningCount: 3,
            stoppedCount: 0,
            pausedCount: 0,
            totalCount: 3,
            updatedAt: Date()
        )

        #expect(snapshot.overallHealth == .warning)
    }

    @Test("Health status is healthy under normal conditions")
    func healthHealthyNormal() {
        let snapshot = ContainerMetricsSnapshot(
            containers: [],
            totalCPUPercent: 50.0,
            totalMemoryUsedBytes: 5000,
            totalMemoryLimitBytes: 10000, // 50% usage
            runningCount: 3,
            stoppedCount: 0,
            pausedCount: 0,
            totalCount: 3,
            updatedAt: Date()
        )

        #expect(snapshot.overallHealth == .healthy)
    }

    @Test("Memory percentage calculation is correct")
    func memoryPercentageCalculation() {
        let snapshot = ContainerMetricsSnapshot(
            containers: [],
            totalCPUPercent: 0,
            totalMemoryUsedBytes: 2500,
            totalMemoryLimitBytes: 10000,
            runningCount: 1,
            stoppedCount: 0,
            pausedCount: 0,
            totalCount: 1,
            updatedAt: Date()
        )

        #expect(snapshot.memoryUsagePercent == 25.0)
    }
}
