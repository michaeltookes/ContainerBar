import Foundation

/// Host total memory lookup and the metrics snapshot it feeds (CB-069).
extension ContainerFetcher {

    /// How long a successfully read host memory total is reused before
    /// `/info` is asked again (the host's memory can change, for example
    /// when a Podman machine is resized).
    static let hostMemoryRefreshInterval: TimeInterval = 300

    /// How long to wait before retrying `/info` after it failed or reported 0.
    static let hostMemoryRetryInterval: TimeInterval = 30

    /// The host's total memory from `/info` `MemTotal`, cached between
    /// refreshes. Returns `nil` when it is unavailable; a failure here never
    /// fails the fetch, it only switches the denominator to its fallback.
    func currentHostMemoryTotal(now: Date = Date()) async -> UInt64? {
        if let checkedAt = hostMemoryCheckedAt {
            let interval = hostMemoryTotal == nil ? Self.hostMemoryRetryInterval : Self.hostMemoryRefreshInterval
            if now.timeIntervalSince(checkedAt) < interval {
                return hostMemoryTotal
            }
        }
        // A cancelled refresh is discarded anyway; do not spend a request.
        if Task.isCancelled { return hostMemoryTotal }

        do {
            let info = try await client.getSystemInfo()
            hostMemoryCheckedAt = now
            if info.memoryTotal > 0 {
                hostMemoryTotal = info.memoryTotal
            } else {
                logger.debug("Host reported MemTotal = 0; using the fallback memory denominator")
                hostMemoryTotal = nil
            }
        } catch {
            if !(error is CancellationError || Task.isCancelled) {
                hostMemoryCheckedAt = now
                logger.debug("Host memory lookup failed: \(error.localizedDescription)")
            }
            // Keep a previously read value rather than flapping the tile.
        }
        return hostMemoryTotal
    }

    func buildMetricsSnapshot(
        containers: [DockerContainer],
        stats: [String: ContainerStats],
        hostMemoryTotal: UInt64?
    ) -> ContainerMetricsSnapshot {
        let statsList = Array(stats.values)

        let totalCPU = statsList.reduce(0.0) { $0 + $1.cpuPercent }
        // Usage counts every container, constrained or not.
        let totalMemUsed = AggregateMemoryLimit.saturatingSum(statsList.map(\.memoryUsageBytes))
        let totalMemLimit = AggregateMemoryLimit.denominator(
            limits: statsList.map(\.memoryLimitBytes),
            hostMemoryTotal: hostMemoryTotal
        )

        let runningCount = containers.filter { $0.state == .running }.count
        let stoppedCount = containers.filter { $0.state == .exited || $0.state == .dead }.count
        let pausedCount = containers.filter { $0.state == .paused }.count

        return ContainerMetricsSnapshot(
            containers: statsList,
            totalCPUPercent: totalCPU,
            totalMemoryUsedBytes: totalMemUsed,
            totalMemoryLimitBytes: totalMemLimit,
            runningCount: runningCount,
            stoppedCount: stoppedCount,
            pausedCount: pausedCount,
            totalCount: containers.count,
            updatedAt: Date()
        )
    }
}
