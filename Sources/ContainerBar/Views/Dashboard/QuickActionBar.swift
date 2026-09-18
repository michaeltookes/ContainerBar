import SwiftUI

/// Bottom action bar with quick action buttons
struct QuickActionBar: View {
    var isHostsActive: Bool = false
    var isLogsActive: Bool = false
    let onRefresh: () -> Void
    let onHosts: () -> Void
    let onLogs: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ActionBarButton(
                title: "Refresh",
                icon: "arrow.clockwise",
                accessibilityLabel: "Refresh containers",
                accessibilityIdentifier: "actionBar-refresh",
                action: onRefresh
            )
            .frame(maxWidth: .infinity)

            Divider()
                .frame(height: 24)

            ActionBarButton(
                title: "Hosts",
                icon: "server.rack",
                isActive: isHostsActive,
                accessibilityLabel: isHostsActive ? "Hide hosts panel" : "Show hosts panel",
                accessibilityIdentifier: "actionBar-hosts",
                action: onHosts
            )
            .frame(maxWidth: .infinity)

            Divider()
                .frame(height: 24)

            ActionBarButton(
                title: "Logs",
                icon: "doc.text",
                isActive: isLogsActive,
                accessibilityLabel: isLogsActive ? "Hide logs panel" : "Show logs panel",
                accessibilityIdentifier: "actionBar-logs",
                action: onLogs
            )
            .frame(maxWidth: .infinity)

            Divider()
                .frame(height: 24)

            ActionBarButton(
                title: "Settings",
                icon: "gear",
                accessibilityLabel: "Open settings",
                accessibilityIdentifier: "actionBar-settings",
                action: onSettings
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

/// Individual action bar button
struct ActionBarButton: View {
    let title: String
    let icon: String
    var isActive: Bool = false
    /// Human phrase announced by VoiceOver; falls back to the visible title.
    var accessibilityLabel: String = ""
    /// Stable identifier for UI automation (Prowl hunts); independent of the label.
    var accessibilityIdentifier: String = ""
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))

                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isActive ? .white : .primary.opacity(isHovered ? 1.0 : 0.8))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel.isEmpty ? title : accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }

    private var backgroundColor: Color {
        if isActive {
            return .accentColor
        } else if isHovered {
            return Color.primary.opacity(0.1)
        } else {
            return .clear
        }
    }
}

#if DEBUG
#Preview {
    VStack {
        Spacer()

        QuickActionBar(
            onRefresh: {},
            onHosts: {},
            onLogs: {},
            onSettings: {}
        )
    }
    .frame(width: 380, height: 200)
    .background(Color(nsColor: .windowBackgroundColor))
}
#endif
