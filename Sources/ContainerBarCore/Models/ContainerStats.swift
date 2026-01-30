import Foundation

/// Real-time container statistics
public struct ContainerStats: Codable, Sendable, Equatable {
    public let containerId: String
    public let timestamp: Date

    // CPU metrics
    public let cpuPercent: Double
    public let cpuSystemUsage: UInt64
    public let cpuContainerUsage: UInt64
    public let onlineCPUs: Int

    // Memory metrics
    public let memoryUsageBytes: UInt64
    public let memoryLimitBytes: UInt64
    public let memoryPercent: Double
    public let memoryCache: UInt64?

    // Network metrics
    public let networkRxBytes: UInt64
    public let networkTxBytes: UInt64
    public let networkRxPackets: UInt64
    public let networkTxPackets: UInt64

    // Block I/O metrics
    public let blockReadBytes: UInt64
    public let blockWriteBytes: UInt64

    public init(
        containerId: String,
        timestamp: Date,
        cpuPercent: Double,
        cpuSystemUsage: UInt64,
        cpuContainerUsage: UInt64,
        onlineCPUs: Int,
        memoryUsageBytes: UInt64,
        memoryLimitBytes: UInt64,
        memoryPercent: Double,
        memoryCache: UInt64?,
        networkRxBytes: UInt64,
        networkTxBytes: UInt64,
        networkRxPackets: UInt64,
        networkTxPackets: UInt64,
        blockReadBytes: UInt64,
        blockWriteBytes: UInt64
    ) {
        self.containerId = containerId
        self.timestamp = timestamp
        self.cpuPercent = cpuPercent
        self.cpuSystemUsage = cpuSystemUsage
        self.cpuContainerUsage = cpuContainerUsage
        self.onlineCPUs = onlineCPUs
        self.memoryUsageBytes = memoryUsageBytes
        self.memoryLimitBytes = memoryLimitBytes
        self.memoryPercent = memoryPercent
        self.memoryCache = memoryCache
        self.networkRxBytes = networkRxBytes
        self.networkTxBytes = networkTxBytes
        self.networkRxPackets = networkRxPackets
        self.networkTxPackets = networkTxPackets
        self.blockReadBytes = blockReadBytes
        self.blockWriteBytes = blockWriteBytes
    }

    // MARK: - Computed Properties

    public var memoryUsedMB: Double {
        Double(memoryUsageBytes) / 1_048_576.0
    }

    public var memoryLimitMB: Double {
        Double(memoryLimitBytes) / 1_048_576.0
    }

    public var networkRxMB: Double {
        Double(networkRxBytes) / 1_048_576.0
    }

    public var networkTxMB: Double {
        Double(networkTxBytes) / 1_048_576.0
    }

    public var blockReadMB: Double {
        Double(blockReadBytes) / 1_048_576.0
    }

    public var blockWriteMB: Double {
        Double(blockWriteBytes) / 1_048_576.0
    }
}

/// Aggregated metrics snapshot for all containers
public struct ContainerMetricsSnapshot: Codable, Sendable, Equatable {
    public let containers: [ContainerStats]
    public let totalCPUPercent: Double
    public let totalMemoryUsedBytes: UInt64
    public let totalMemoryLimitBytes: UInt64
    public let runningCount: Int
    public let stoppedCount: Int
    public let pausedCount: Int
    public let totalCount: Int
    public let updatedAt: Date

    public init(
        containers: [ContainerStats],
        totalCPUPercent: Double,
        totalMemoryUsedBytes: UInt64,
        totalMemoryLimitBytes: UInt64,
        runningCount: Int,
        stoppedCount: Int,
        pausedCount: Int,
        totalCount: Int,
        updatedAt: Date
    ) {
        self.containers = containers
        self.totalCPUPercent = totalCPUPercent
        self.totalMemoryUsedBytes = totalMemoryUsedBytes
        self.totalMemoryLimitBytes = totalMemoryLimitBytes
        self.runningCount = runningCount
        self.stoppedCount = stoppedCount
        self.pausedCount = pausedCount
        self.totalCount = totalCount
        self.updatedAt = updatedAt
    }

    public var overallHealth: HealthStatus {
        if runningCount == 0 && totalCount > 0 { return .critical }
        guard totalMemoryLimitBytes > 0 else { return .unknown }
        let memoryPercent = Double(totalMemoryUsedBytes) / Double(totalMemoryLimitBytes)
        if totalCPUPercent > 90 || memoryPercent > 0.95 {
            return .warning
        }
        return .healthy
    }

    public var totalMemoryUsedMB: Double {
        Double(totalMemoryUsedBytes) / 1_048_576.0
    }

    public var totalMemoryLimitMB: Double {
        Double(totalMemoryLimitBytes) / 1_048_576.0
    }

    public var memoryUsagePercent: Double {
        guard totalMemoryLimitBytes > 0 else { return 0 }
        return (Double(totalMemoryUsedBytes) / Double(totalMemoryLimitBytes)) * 100
    }
}

public enum HealthStatus: String, Codable, Sendable {
    case healthy
    case warning
    case critical
    case unknown
}

#if DEBUG
extension ContainerStats {
    /// Creates mock stats for testing and previews
    public static func mock(
        containerId: String = "abc123",
        cpuPercent: Double = 5.2,
        memoryUsageBytes: UInt64 = 134_217_728, // 128 MB
        memoryLimitBytes: UInt64 = 536_870_912  // 512 MB
    ) -> ContainerStats {
        ContainerStats(
            containerId: containerId,
            timestamp: Date(),
            cpuPercent: cpuPercent,
            cpuSystemUsage: 100_000_000,
            cpuContainerUsage: 5_200_000,
            onlineCPUs: 4,
            memoryUsageBytes: memoryUsageBytes,
            memoryLimitBytes: memoryLimitBytes,
            memoryPercent: Double(memoryUsageBytes) / Double(memoryLimitBytes) * 100,
            memoryCache: 10_485_760,
            networkRxBytes: 1_048_576,
            networkTxBytes: 524_288,
            networkRxPackets: 1000,
            networkTxPackets: 500,
            blockReadBytes: 10_485_760,
            blockWriteBytes: 5_242_880
        )
    }
}

extension ContainerMetricsSnapshot {
    /// Creates a mock snapshot for testing and previews
    public static func mock(
        runningCount: Int = 5,
        stoppedCount: Int = 2,
        pausedCount: Int = 0
    ) -> ContainerMetricsSnapshot {
        ContainerMetricsSnapshot(
            containers: [],
            totalCPUPercent: 25.5,
            totalMemoryUsedBytes: 2_147_483_648,  // 2 GB
            totalMemoryLimitBytes: 8_589_934_592, // 8 GB
            runningCount: runningCount,
            stoppedCount: stoppedCount,
            pausedCount: pausedCount,
            totalCount: runningCount + stoppedCount + pausedCount,
            updatedAt: Date()
        )
    }
}
#endif
