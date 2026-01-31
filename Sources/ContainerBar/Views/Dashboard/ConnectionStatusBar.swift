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
                    .shadow(color: isConnected ? .green.opacity(0.5) : .red.opacity(0.5), radius: 3)

                Text(isConnected ? "Connected to \(hostName)" : "Disconnected")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.9))
                    .lineLimit(1)
            }

            Spacer()

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
