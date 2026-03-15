import SwiftUI
import ContainerBarCore

/// Displays a service icon for a container based on its image name
struct ServiceIcon: View {
    let container: DockerContainer
    let size: CGFloat

    /// Whether to show the status indicator overlay
    var showStatusIndicator: Bool = true

    /// Whether to show the runtime badge
    var showRuntimeBadge: Bool = true

    init(container: DockerContainer, size: CGFloat = 24, showStatusIndicator: Bool = true, showRuntimeBadge: Bool = true) {
        self.container = container
        self.size = size
        self.showStatusIndicator = showStatusIndicator
        self.showRuntimeBadge = showRuntimeBadge
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Main icon
            iconView
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.2))

            // Status indicator (small dot)
            if showStatusIndicator {
                Circle()
                    .fill(statusColor)
                    .frame(width: size * 0.35, height: size * 0.35)
                    .overlay(
                        Circle()
                            .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5)
                    )
                    .offset(x: size * 0.15, y: size * 0.15)
            }

            // Runtime badge (for Podman)
            if showRuntimeBadge && container.runtime == .podman {
                Image(systemName: container.runtime.badgeIconName)
                    .font(.system(size: size * 0.3, weight: .bold))
                    .foregroundStyle(.purple)
                    .offset(x: size * 0.15, y: -size * 0.4)
            }
        }
    }

    // MARK: - Icon View

    @ViewBuilder
    private var iconView: some View {
        if let iconName = container.serviceIconName,
           let image = loadServiceIcon(named: iconName) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            // Fallback to generic container icon
            genericContainerIcon
        }
    }

    private var genericContainerIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2)
                .fill(Color.secondary.opacity(0.15))

            Image(systemName: "shippingbox.fill")
                .font(.system(size: size * 0.5))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Status Color

    private var statusColor: Color {
        switch container.state {
        case .running: return .green
        case .paused: return .yellow
        case .restarting: return .orange
        case .exited, .dead: return .red
        case .created, .removing: return .gray
        }
    }

    // MARK: - Icon Loading

    @MainActor private static var iconCache: [String: NSImage] = [:]

    private func loadServiceIcon(named name: String) -> NSImage? {
        if let cached = Self.iconCache[name] {
            return cached
        }

        // Load from SPM bundle (resources are flattened by .process())
        if let url = Bundle.module.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            Self.iconCache[name] = image
            return image
        }

        return nil
    }
}

// MARK: - Compact Service Icon

/// A more compact version of ServiceIcon without status overlay
struct CompactServiceIcon: View {
    let container: DockerContainer
    let size: CGFloat

    init(container: DockerContainer, size: CGFloat = 16) {
        self.container = container
        self.size = size
    }

    var body: some View {
        ServiceIcon(
            container: container,
            size: size,
            showStatusIndicator: false,
            showRuntimeBadge: false
        )
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Service Icons") {
    VStack(spacing: 16) {
        HStack(spacing: 16) {
            ServiceIcon(
                container: .mock(name: "nginx-proxy", image: "nginx:alpine", state: .running),
                size: 32
            )

            ServiceIcon(
                container: .mock(name: "grafana", image: "grafana/grafana:latest", state: .running),
                size: 32
            )

            ServiceIcon(
                container: .mock(name: "plex", image: "linuxserver/plex:latest", state: .running),
                size: 32
            )

            ServiceIcon(
                container: .mock(name: "custom-app", image: "mycompany/custom:v1", state: .running),
                size: 32
            )
        }

        HStack(spacing: 16) {
            ServiceIcon(
                container: .mock(name: "redis", image: "redis:7", state: .exited),
                size: 32
            )

            ServiceIcon(
                container: .mock(name: "postgres", image: "postgres:15", state: .paused),
                size: 32
            )

            ServiceIcon(
                container: .mock(name: "podman-traefik", image: "traefik:v2", state: .running, runtime: .podman),
                size: 32
            )
        }
    }
    .padding()
    .background(Color(nsColor: .windowBackgroundColor))
}
#endif
