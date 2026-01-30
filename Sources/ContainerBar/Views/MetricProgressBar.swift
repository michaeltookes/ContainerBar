import SwiftUI

/// A progress bar for displaying metrics with label and optional subtitle
///
/// Following UI_UX design system:
/// - Bar height: 4pt (macOS standard)
/// - Corner radius: 2pt (half height, fully rounded)
/// - Uses semantic colors for proper dark mode support
struct MetricProgressBar: View {
    let title: String
    let percent: Double
    var subtitle: String? = nil
    var tint: Color = .blue

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header row with title and percentage
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(formattedPercent)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.2))

                    // Filled portion
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor)
                        .frame(width: max(0, geometry.size.width * clampedPercent))
                }
            }
            .frame(height: 4)

            // Optional subtitle
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(formattedPercent)")
        .accessibilityValue(subtitle ?? "")
    }

    // MARK: - Computed Properties

    private var formattedPercent: String {
        String(format: "%.1f%%", percent)
    }

    private var clampedPercent: CGFloat {
        CGFloat(max(0, min(100, percent)) / 100)
    }

    /// Color based on usage level
    private var barColor: Color {
        if percent >= 90 {
            return .red
        } else if percent >= 75 {
            return .orange
        } else {
            return tint
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("CPU Usage") {
    VStack(spacing: 16) {
        MetricProgressBar(
            title: "CPU Usage",
            percent: 45.2,
            tint: .blue
        )

        MetricProgressBar(
            title: "Memory Usage",
            percent: 78.5,
            subtitle: "4.9 GB / 8 GB",
            tint: .purple
        )

        MetricProgressBar(
            title: "Critical",
            percent: 95.0,
            tint: .blue
        )
    }
    .padding()
    .frame(width: 280)
}
#endif
