import Foundation

/// Raw stats response from Docker API /containers/{id}/stats endpoint
///
/// This matches the Docker Engine API v1.43 format exactly.
/// We parse this into the user-friendly ContainerStats model.
struct DockerRawStats: Codable, Sendable {
    let read: String
    let preread: String
    let cpuStats: CPUStats
    let precpuStats: CPUStats
    let memoryStats: MemoryStats
    let networks: [String: NetworkStats]?
    let blkioStats: BlkioStats

    private enum CodingKeys: String, CodingKey {
        case read
        case preread
        case cpuStats = "cpu_stats"
        case precpuStats = "precpu_stats"
        case memoryStats = "memory_stats"
        case networks
        case blkioStats = "blkio_stats"
    }

    struct CPUStats: Codable, Sendable {
        let cpuUsage: CPUUsage
        let systemCpuUsage: UInt64?
        let onlineCpus: Int?

        private enum CodingKeys: String, CodingKey {
            case cpuUsage = "cpu_usage"
            case systemCpuUsage = "system_cpu_usage"
            case onlineCpus = "online_cpus"
        }

        struct CPUUsage: Codable, Sendable {
            let totalUsage: UInt64
            let percpuUsage: [UInt64]?
            let usageInKernelmode: UInt64?
            let usageInUsermode: UInt64?

            private enum CodingKeys: String, CodingKey {
                case totalUsage = "total_usage"
                case percpuUsage = "percpu_usage"
                case usageInKernelmode = "usage_in_kernelmode"
                case usageInUsermode = "usage_in_usermode"
            }
        }
    }

    struct MemoryStats: Codable, Sendable {
        let usage: UInt64?
        let maxUsage: UInt64?
        let stats: Stats?
        let limit: UInt64?

        private enum CodingKeys: String, CodingKey {
            case usage
            case maxUsage = "max_usage"
            case stats
            case limit
        }

        struct Stats: Codable, Sendable {
            let cache: UInt64?
        }
    }

    struct NetworkStats: Codable, Sendable {
        let rxBytes: UInt64
        let rxPackets: UInt64
        let txBytes: UInt64
        let txPackets: UInt64

        private enum CodingKeys: String, CodingKey {
            case rxBytes = "rx_bytes"
            case rxPackets = "rx_packets"
            case txBytes = "tx_bytes"
            case txPackets = "tx_packets"
        }
    }

    struct BlkioStats: Codable, Sendable {
        let ioServiceBytesRecursive: [IOStat]?

        private enum CodingKeys: String, CodingKey {
            case ioServiceBytesRecursive = "io_service_bytes_recursive"
        }

        struct IOStat: Codable, Sendable {
            let major: Int
            let minor: Int
            let op: String
            let value: UInt64
        }
    }
}

// MARK: - ContainerStats Extension

extension ContainerStats {
    /// Initialize from raw Docker API stats response
    init(from raw: DockerRawStats, containerId: String) {
        let timestamp = ISO8601DateFormatter().date(from: raw.read) ?? Date()

        // Calculate CPU percentage
        // Formula: (container_delta / system_delta) * num_cpus * 100
        let cpuDelta = Double(raw.cpuStats.cpuUsage.totalUsage) - Double(raw.precpuStats.cpuUsage.totalUsage)
        let systemDelta = Double(raw.cpuStats.systemCpuUsage ?? 0) - Double(raw.precpuStats.systemCpuUsage ?? 0)
        let numCPUs = Double(raw.cpuStats.onlineCpus ?? 1)
        let cpuPercent = systemDelta > 0 ? (cpuDelta / systemDelta) * numCPUs * 100.0 : 0.0

        // Memory stats
        let memoryUsage = raw.memoryStats.usage ?? 0
        let memoryLimit = raw.memoryStats.limit ?? 0
        let memoryPercent = memoryLimit > 0 ? (Double(memoryUsage) / Double(memoryLimit)) * 100.0 : 0.0
        let memoryCache = raw.memoryStats.stats?.cache

        // Network stats (sum all interfaces)
        var totalRxBytes: UInt64 = 0
        var totalTxBytes: UInt64 = 0
        var totalRxPackets: UInt64 = 0
        var totalTxPackets: UInt64 = 0

        for (_, netStats) in raw.networks ?? [:] {
            totalRxBytes += netStats.rxBytes
            totalTxBytes += netStats.txBytes
            totalRxPackets += netStats.rxPackets
            totalTxPackets += netStats.txPackets
        }

        // Block I/O stats
        var totalReadBytes: UInt64 = 0
        var totalWriteBytes: UInt64 = 0

        for stat in raw.blkioStats.ioServiceBytesRecursive ?? [] {
            switch stat.op.lowercased() {
            case "read":
                totalReadBytes += stat.value
            case "write":
                totalWriteBytes += stat.value
            default:
                break
            }
        }

        self.init(
            containerId: containerId,
            timestamp: timestamp,
            cpuPercent: max(0, min(cpuPercent, 100 * numCPUs)), // Clamp to reasonable range
            cpuSystemUsage: raw.cpuStats.systemCpuUsage ?? 0,
            cpuContainerUsage: raw.cpuStats.cpuUsage.totalUsage,
            onlineCPUs: raw.cpuStats.onlineCpus ?? 1,
            memoryUsageBytes: memoryUsage,
            memoryLimitBytes: memoryLimit,
            memoryPercent: memoryPercent,
            memoryCache: memoryCache,
            networkRxBytes: totalRxBytes,
            networkTxBytes: totalTxBytes,
            networkRxPackets: totalRxPackets,
            networkTxPackets: totalTxPackets,
            blockReadBytes: totalReadBytes,
            blockWriteBytes: totalWriteBytes
        )
    }
}
