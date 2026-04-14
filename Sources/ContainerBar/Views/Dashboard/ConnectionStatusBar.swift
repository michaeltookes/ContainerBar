import SwiftUI

/// Connection status bar with host name and container count badges
struct ConnectionStatusBar: View {
    let presentation: ConnectionStatusPresentation
    let runningCount: Int
    let stoppedCount: Int

    private var isConnected: Bool {
        presentation.state == .connected
    }

    var body: some View {
        HStack(spacing: 12) {
            // Connection indicator
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(presentation.indicatorColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: presentation.indicatorShadowColor, radius: 3)

                    Text(presentation.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.9))
                        .lineLimit(1)
                }

                if let detail = presentation.detail {
                    Text(detail)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Status badges
            if isConnected {
                HStack(spacing: 6) {
                    StatusPill(count: runningCount, label: "Running", color: .green)
                    if stoppedCount > 0 {
                        StatusPill(count: stoppedCount, label: "Stopped", color: .orange)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

/// Status count pill badge
struct StatusPill: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(color)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary.opacity(0.8))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 0) {
        ConnectionStatusBar(
            presentation: .make(
                hostName: "Local Docker",
                isConnected: true,
                isRefreshing: false,
                connectionError: nil
            ),
            runningCount: 13,
            stoppedCount: 2
        )

        Divider()

        ConnectionStatusBar(
            presentation: .make(
                hostName: "Remote Server",
                isConnected: false,
                isRefreshing: true,
                connectionError: nil
            ),
            runningCount: 0,
            stoppedCount: 0
        )
    }
    .frame(width: 380)
}
#endif
