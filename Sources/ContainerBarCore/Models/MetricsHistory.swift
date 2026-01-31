import Foundation

/// A single data point for sparkline charts
public struct MetricsDataPoint: Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let value: Double

    public init(value: Double, timestamp: Date = Date()) {
        self.id = UUID()
        self.timestamp = timestamp
        self.value = value
    }
}

/// Rolling history of metric values for sparkline display
public struct MetricsHistory: Sendable {
    private var points: [MetricsDataPoint]
    public let maxPoints: Int

    public init(maxPoints: Int = 30) {
        self.maxPoints = maxPoints
        self.points = []
    }

    /// Append a new value, removing oldest if at capacity
    public mutating func append(_ value: Double) {
        let point = MetricsDataPoint(value: value)
        points.append(point)

        if points.count > maxPoints {
            points.removeFirst()
        }
    }

    /// All data points for chart display
    public var values: [MetricsDataPoint] {
        points
    }

    /// Most recent value
    public var latest: Double? {
        points.last?.value
    }

    /// Whether there's enough data to display a sparkline
    public var hasData: Bool {
        points.count >= 2
    }

    /// Clear all history
    public mutating func clear() {
        points.removeAll()
    }
}

/// Aggregated metrics history for all system stats
public struct AggregatedMetricsHistory: Sendable {
    public var cpu: MetricsHistory
    public var memory: MetricsHistory
    public var networkRxRate: MetricsHistory  // KB/s
    public var networkTxRate: MetricsHistory  // KB/s
    public var diskReadRate: MetricsHistory   // KB/s
    public var diskWriteRate: MetricsHistory  // KB/s

    public init(maxPoints: Int = 30) {
        self.cpu = MetricsHistory(maxPoints: maxPoints)
        self.memory = MetricsHistory(maxPoints: maxPoints)
        self.networkRxRate = MetricsHistory(maxPoints: maxPoints)
        self.networkTxRate = MetricsHistory(maxPoints: maxPoints)
        self.diskReadRate = MetricsHistory(maxPoints: maxPoints)
        self.diskWriteRate = MetricsHistory(maxPoints: maxPoints)
    }

    /// Clear all history (useful when switching hosts)
    public mutating func clearAll() {
        cpu.clear()
        memory.clear()
        networkRxRate.clear()
        networkTxRate.clear()
        diskReadRate.clear()
        diskWriteRate.clear()
    }
}
