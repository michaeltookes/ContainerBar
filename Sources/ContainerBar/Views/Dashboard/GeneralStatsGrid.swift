import SwiftUI
import ContainerBarCore

/// 2x2 grid of metric sparkline cards
struct GeneralStatsGrid: View {
    let metrics: ContainerMetricsSnapshot?
    let history: AggregatedMetricsHistory

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            HStack {
                Text("GENERAL STATS")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)

                Spacer()
            }

            // 2x2 Grid of metric cards
            LazyVGrid(columns: columns, spacing: 8) {
                MetricSparklineCard(
                    title: "CPU",
                    value: formatPercent(metrics?.totalCPUPercent ?? 0),
                    history: history.cpu,
                    tint: .blue,
                    icon: "cpu"
                )

                MetricSparklineCard(
                    title: "RAM",
                    value: formatMemory(metrics?.totalMemoryUsedMB ?? 0),
                    subtitle: formatMemoryLimit(metrics),
                    history: history.memory,
                    tint: .purple,
                    icon: "memorychip"
                )

                MetricSparklineCard(
                    title: "Network",
                    value: formatRate(history.networkRxRate.latest ?? 0),
                    subtitle: "KB/s",
                    history: history.networkRxRate,
                    tint: .green,
                    icon: "network"
                )

                MetricSparklineCard(
                    title: "Disk",
                    value: formatRate(history.diskReadRate.latest ?? 0),
                    subtitle: "KB/s",
                    history: history.diskReadRate,
                    tint: .orange,
                    icon: "externaldrive"
                )
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Formatters

    private func formatPercent(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    private func formatMemory(_ mb: Double) -> String {
        if mb >= 1024 {
            return String(format: "%.1f", mb / 1024)
        }
        return String(format: "%.0f", mb)
    }

    private func formatMemoryLimit(_ metrics: ContainerMetricsSnapshot?) -> String? {
        guard let metrics, metrics.totalMemoryLimitMB > 0 else { return nil }

        let limitGB = metrics.totalMemoryLimitMB / 1024

        if metrics.totalMemoryUsedMB >= 1024 {
            return String(format: "GB / %.0f GB", limitGB)
        }
        return "MB"
    }

    private func formatRate(_ kbPerSec: Double) -> String {
        if kbPerSec >= 1024 {
            return String(format: "%.1f", kbPerSec / 1024)
        }
        return String(format: "%.0f", kbPerSec)
    }
}

#if DEBUG
#Preview {
    let history: AggregatedMetricsHistory = {
        var h = AggregatedMetricsHistory(maxPoints: 30)
        for _ in 0..<20 {
            h.cpu.append(Double.random(in: 5...40))
            h.memory.append(Double.random(in: 30...70))
            h.networkRxRate.append(Double.random(in: 100...500))
            h.diskReadRate.append(Double.random(in: 50...200))
        }
        return h
    }()

    return GeneralStatsGrid(
        metrics: nil,
        history: history
    )
    .padding(.vertical)
    .frame(width: 380)
    .background(Color(nsColor: .windowBackgroundColor))
}
#endif
