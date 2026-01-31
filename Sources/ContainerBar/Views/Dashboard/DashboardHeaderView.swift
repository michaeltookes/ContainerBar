import SwiftUI
import AppKit

/// Dashboard header with logo and action buttons
struct DashboardHeaderView: View {
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onSearch: () -> Void
    let onAdd: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // App logo and title
            HStack(spacing: 8) {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 28, height: 28)

                Text("ContainerBar")
                    .font(.system(size: 15, weight: .semibold))
            }

            Spacer()

            // Action buttons
            HStack(spacing: 2) {
                HeaderButton(
                    icon: "arrow.clockwise",
                    isSpinning: isRefreshing,
                    action: onRefresh
                )
                .disabled(isRefreshing)
                .help("Refresh")

                HeaderButton(
                    icon: "magnifyingglass",
                    action: onSearch
                )
                .help("Search containers")

                HeaderButton(
                    icon: "plus",
                    action: onAdd
                )
                .help("New container")

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
        // Try to load custom logo from bundle resources
        if let logoURL = Bundle.module.url(forResource: "AppLogo", withExtension: "png"),
           let logo = NSImage(contentsOf: logoURL) {
            return logo
        }
        // Fallback to app icon
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
                .foregroundStyle(.primary.opacity(0.8))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(isHovered ? Color.primary.opacity(0.12) : Color.primary.opacity(0.05))
                )
                .rotationEffect(.degrees(isSpinning ? 360 : 0))
                .animation(
                    isSpinning ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                    value: isSpinning
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

#if DEBUG
#Preview {
    VStack {
        DashboardHeaderView(
            isRefreshing: false,
            onRefresh: {},
            onSearch: {},
            onAdd: {},
            onSettings: {}
        )
        .background(.regularMaterial)

        DashboardHeaderView(
            isRefreshing: true,
            onRefresh: {},
            onSearch: {},
            onAdd: {},
            onSettings: {}
        )
        .background(.regularMaterial)
    }
    .frame(width: 380)
    .padding()
}
#endif
