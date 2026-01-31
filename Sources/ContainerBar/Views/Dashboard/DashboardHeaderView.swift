import SwiftUI
import AppKit

/// Dashboard header with logo and action buttons
struct DashboardHeaderView: View {
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // App logo and title
            HStack(spacing: 8) {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 24, height: 24)

                Text("ContainerBar")
                    .font(.headline)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 4) {
                HeaderButton(
                    icon: "arrow.clockwise",
                    isSpinning: isRefreshing,
                    action: onRefresh
                )
                .disabled(isRefreshing)
                .help("Refresh")

                HeaderButton(
                    icon: "gear",
                    action: onSettings
                )
                .help("Settings")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var appIcon: NSImage {
        if let icon = NSImage(named: NSImage.applicationIconName) {
            return icon
        }
        return NSApp.applicationIconImage
    }
}

/// Circular header button with icon
struct HeaderButton: View {
    let icon: String
    var isSpinning: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(isHovered ? Color.primary.opacity(0.1) : Color.clear)
                )
                .rotationEffect(.degrees(isSpinning ? 360 : 0))
                .animation(
                    isSpinning ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                    value: isSpinning
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
        DashboardHeaderView(
            isRefreshing: false,
            onRefresh: {},
            onSettings: {}
        )
        .background(.regularMaterial)

        DashboardHeaderView(
            isRefreshing: true,
            onRefresh: {},
            onSettings: {}
        )
        .background(.regularMaterial)
    }
    .frame(width: 380)
    .padding()
}
#endif
