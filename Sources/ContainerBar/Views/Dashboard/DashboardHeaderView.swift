import SwiftUI
import AppKit

/// Dashboard header with logo and action buttons
struct DashboardHeaderView: View {
    let isRefreshing: Bool
    var isSearching: Bool = false
    let onRefresh: () -> Void
    let onSearch: () -> Void
    let onQuit: () -> Void
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
                    isActive: isSearching,
                    action: onSearch
                )
                .help(isSearching ? "Close search" : "Search containers")

                HeaderButton(
                    icon: "power",
                    action: onQuit
                )
                .help("Quit ContainerBar")

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
    var isActive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isActive ? .white : .primary.opacity(0.8))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(backgroundColor)
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

    private var backgroundColor: Color {
        if isActive {
            return .accentColor
        } else if isHovered {
            return Color.primary.opacity(0.12)
        } else {
            return Color.primary.opacity(0.05)
        }
    }
}

#if DEBUG
#Preview {
    VStack {
        DashboardHeaderView(
            isRefreshing: false,
            isSearching: false,
            onRefresh: {},
            onSearch: {},
            onQuit: {},
            onSettings: {}
        )
        .background(.regularMaterial)

        DashboardHeaderView(
            isRefreshing: false,
            isSearching: true,
            onRefresh: {},
            onSearch: {},
            onQuit: {},
            onSettings: {}
        )
        .background(.regularMaterial)
    }
    .frame(width: 380)
    .padding()
}
#endif
