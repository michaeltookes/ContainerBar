import SwiftUI
import Charts
import ContainerBarCore

/// A metric card with sparkline chart for dashboard display
struct MetricSparklineCard: View {
    let title: String
    let value: String
    let subtitle: String?
    let history: MetricsHistory
    let tint: Color
    let icon: String

    init(
        title: String,
        value: String,
        subtitle: String? = nil,
        history: MetricsHistory,
        tint: Color,
        icon: String
    ) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.history = history
        self.tint = tint
        self.icon = icon
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header with icon and title
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(tint)

                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Value display with fixed height to ensure consistency
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(height: 32, alignment: .top) // Fixed height for value section

            // Sparkline chart
            sparklineChart
                .frame(height: 24)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .overlay(alignment: .bottom) {
            // Glowing colored bar at bottom
            RoundedRectangle(cornerRadius: 2)
                .fill(tint)
                .frame(height: 3)
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
                .shadow(color: tint.opacity(0.6), radius: 4, y: 0)
                .shadow(color: tint.opacity(0.3), radius: 8, y: 0)
        }
        .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
    }

    @ViewBuilder
    private var sparklineChart: some View {
        if history.hasData {
            Chart(history.values) { point in
                // Shadow/gradient area under the line
                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [tint.opacity(0.5), tint.opacity(0.2), tint.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // The line itself
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...(maxChartValue))
        } else {
            // Placeholder when no data
            Rectangle()
                .fill(Color.secondary.opacity(0.1))
                .overlay(
                    Text("...")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                )
        }
    }

    private var maxChartValue: Double {
        let maxValue = history.values.map(\.value).max() ?? 100
        // Ensure minimum scale of 10, and add 10% headroom
        return max(10, maxValue * 1.1)
    }
}

#if DEBUG
#Preview {
    let history: MetricsHistory = {
        var h = MetricsHistory(maxPoints: 30)
        for i in 0..<20 {
            h.append(Double.random(in: 10...60) + Double(i))
        }
        return h
    }()

    return VStack {
        HStack(spacing: 8) {
            MetricSparklineCard(
                title: "CPU",
                value: "23.4%",
                history: history,
                tint: .blue,
                icon: "cpu"
            )

            MetricSparklineCard(
                title: "RAM",
                value: "2.4",
                subtitle: "GB",
                history: history,
                tint: .purple,
                icon: "memorychip"
            )
        }

        HStack(spacing: 8) {
            MetricSparklineCard(
                title: "Network",
                value: "367",
                subtitle: "KB/s",
                history: history,
                tint: .green,
                icon: "network"
            )

            MetricSparklineCard(
                title: "Disk",
                value: "1.2",
                subtitle: "MB/s",
                history: history,
                tint: .orange,
                icon: "externaldrive"
            )
        }
    }
    .padding()
    .frame(width: 380)
    .background(Color(nsColor: .windowBackgroundColor))
}
#endif
