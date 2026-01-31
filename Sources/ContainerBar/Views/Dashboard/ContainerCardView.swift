import SwiftUI
import ContainerBarCore

/// Individual container card with hover effects
struct ContainerCardView: View {
    let container: DockerContainer
    let stats: ContainerStats?
    let onAction: (ContainerAction) -> Void

    @State private var isHovered = false
    @State private var showDetailPopover = false

    var body: some View {
        HStack(spacing: 10) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            // Container info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(container.displayName)
                        .font(.system(.body, weight: .medium))
                        .lineLimit(1)

                    Spacer()

                    // Status badge for non-running
                    if container.state != .running {
                        Text(container.state.rawValue.capitalized)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(statusColor.opacity(0.15))
                            .foregroundStyle(statusColor)
                            .clipShape(Capsule())
                    }
                }

                // Stats or status
                if container.state == .running, let stats {
                    HStack(spacing: 12) {
                        Label(formatPercent(stats.cpuPercent), systemImage: "cpu")
                        Label(formatMemory(stats.memoryUsedMB), systemImage: "memorychip")
                        Spacer()
                        Text(container.uptimeString)
                            .foregroundStyle(.tertiary)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                } else {
                    Text(container.status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // Quick action button (visible on hover)
            if isHovered {
                quickActionButton
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hoverColor)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            showDetailPopover.toggle()
        }
        .popover(isPresented: $showDetailPopover, arrowEdge: .trailing) {
            ContainerDetailPopover(container: container, stats: stats) { action in
                showDetailPopover = false
                onAction(action)
            }
        }
    }

    // MARK: - Quick Action Button

    @ViewBuilder
    private var quickActionButton: some View {
        if container.state == .running {
            Button {
                onAction(.stop(container.id))
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10))
                    .frame(width: 24, height: 24)
                    .background(Color.red.opacity(0.15))
                    .foregroundStyle(.red)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Stop container")
        } else {
            Button {
                onAction(.start(container.id))
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 10))
                    .frame(width: 24, height: 24)
                    .background(Color.green.opacity(0.15))
                    .foregroundStyle(.green)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Start container")
        }
    }

    // MARK: - Computed Properties

    private var statusColor: Color {
        switch container.state {
        case .running: return .green
        case .paused: return .yellow
        case .restarting: return .orange
        case .exited, .dead: return .red
        case .created, .removing: return .gray
        }
    }

    private var hoverColor: Color {
        guard isHovered else { return .clear }

        switch container.state {
        case .running:
            return Color.green.opacity(0.1)
        case .paused, .restarting:
            return Color.yellow.opacity(0.1)
        case .exited, .dead, .created, .removing:
            return Color.red.opacity(0.1)
        }
    }

    // MARK: - Formatters

    private func formatPercent(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    private func formatMemory(_ mb: Double) -> String {
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
    }
}

// MARK: - DockerContainer Extension

extension DockerContainer {
    /// Human-readable uptime string
    var uptimeString: String {
        // Extract uptime from status if available (e.g., "Up 2 hours")
        if status.lowercased().hasPrefix("up ") {
            return status
        }
        return ""
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 4) {
        ContainerCardView(
            container: .mock(name: "nginx-proxy", state: .running),
            stats: .mock(cpuPercent: 2.3, memoryUsageBytes: 134_217_728),
            onAction: { _ in }
        )

        ContainerCardView(
            container: .mock(name: "postgres-db", state: .running),
            stats: .mock(cpuPercent: 15.2, memoryUsageBytes: 512_000_000),
            onAction: { _ in }
        )

        ContainerCardView(
            container: .mock(name: "backup-service", state: .exited, status: "Exited (0) 2 hours ago"),
            stats: nil,
            onAction: { _ in }
        )
    }
    .padding()
    .frame(width: 350)
    .background(Color(nsColor: .windowBackgroundColor))
}
#endif
