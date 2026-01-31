import SwiftUI

/// Connection status bar with host name and container count badges
struct ConnectionStatusBar: View {
    let hostName: String
    let isConnected: Bool
    let runningCount: Int
    let stoppedCount: Int

    var body: some View {
        HStack(spacing: 12) {
            // Connection indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)

                Text(isConnected ? "Connected to \(hostName)" : "Disconnected")
                    .font(.subheadline)
                    .lineLimit(1)
            }

            Spacer()

            // Status badges
            if isConnected {
                HStack(spacing: 8) {
                    StatusPill(count: runningCount, label: "Running", color: .green)
                    if stoppedCount > 0 {
                        StatusPill(count: stoppedCount, label: "Stopped", color: .secondary)
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
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text("\(count)")
                .font(.system(.caption, weight: .semibold))

            Text(label)
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 0) {
        ConnectionStatusBar(
            hostName: "Local Docker",
            isConnected: true,
            runningCount: 13,
            stoppedCount: 2
        )

        Divider()

        ConnectionStatusBar(
            hostName: "Remote Server",
            isConnected: false,
            runningCount: 0,
            stoppedCount: 0
        )
    }
    .frame(width: 380)
}
#endif
