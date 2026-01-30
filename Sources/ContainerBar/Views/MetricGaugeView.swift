import SwiftUI

/// A circular gauge chart for displaying metrics
struct MetricGaugeView: View {
    let title: String
    let percent: Double
    let tint: Color
    var subtitle: String? = nil

    private let lineWidth: CGFloat = 8

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: lineWidth)

                // Progress arc
                Circle()
                    .trim(from: 0, to: clampedPercent)
                    .stroke(
                        gaugeColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: percent)

                // Center text
                VStack(spacing: 2) {
                    Text(formattedPercent)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: 80, height: 80)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var formattedPercent: String {
        String(format: "%.1f%%", percent)
    }

    private var clampedPercent: CGFloat {
        CGFloat(max(0, min(100, percent)) / 100)
    }

    private var gaugeColor: Color {
        if percent >= 90 {
            return .red
        } else if percent >= 75 {
            return .orange
        } else {
            return tint
        }
    }
}

/// Popover view showing detailed metrics with gauge charts
struct MetricsGaugePopover: View {
    let cpuPercent: Double
    let memoryPercent: Double
    let memoryUsed: String
    let memoryLimit: String

    var body: some View {
        VStack(spacing: 16) {
            Text("Resource Usage")
                .font(.headline)

            HStack(spacing: 24) {
                MetricGaugeView(
                    title: "CPU",
                    percent: cpuPercent,
                    tint: .blue
                )

                MetricGaugeView(
                    title: "Memory",
                    percent: memoryPercent,
                    tint: .purple,
                    subtitle: memoryUsed
                )
            }

            // Memory details
            HStack {
                Text("Memory:")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(memoryUsed) / \(memoryLimit)")
                    .font(.system(.caption, design: .monospaced))
            }
            .font(.caption)
        }
        .padding(16)
        .frame(width: 220)
    }
}

#if DEBUG
#Preview("Gauge") {
    MetricGaugeView(
        title: "CPU",
        percent: 45.2,
        tint: .blue
    )
    .padding()
}

#Preview("Popover") {
    MetricsGaugePopover(
        cpuPercent: 45.2,
        memoryPercent: 62.5,
        memoryUsed: "5.0 GB",
        memoryLimit: "8.0 GB"
    )
}
#endif
