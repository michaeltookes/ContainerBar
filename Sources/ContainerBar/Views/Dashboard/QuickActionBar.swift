import SwiftUI

/// Bottom action bar with quick action buttons
struct QuickActionBar: View {
    let onRefresh: () -> Void
    let onHosts: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ActionBarButton(
                title: "Refresh",
                icon: "arrow.clockwise",
                action: onRefresh
            )
            .frame(maxWidth: .infinity)

            Divider()
                .frame(height: 20)

            ActionBarButton(
                title: "Hosts",
                icon: "server.rack",
                action: onHosts
            )
            .frame(maxWidth: .infinity)

            Divider()
                .frame(height: 20)

            ActionBarButton(
                title: "Settings",
                icon: "gear",
                action: onSettings
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

/// Individual action bar button
struct ActionBarButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))

                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.1) : Color.primary.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
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
            onSettings: {}
        )
    }
    .frame(width: 380, height: 200)
    .background(Color(nsColor: .windowBackgroundColor))
}
#endif
