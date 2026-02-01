import SwiftUI
import ContainerBarCore

/// Individual container card with hover effects - Docker Desktop style
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
                .shadow(color: statusColor.opacity(0.4), radius: 2)

            // Container info
            VStack(alignment: .leading, spacing: 4) {
                // Row 1: Name and status chip
                HStack {
                    Text(container.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    Spacer()

                    // Status chip (always shown)
                    Text(container.state.rawValue.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.3)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(statusColor.opacity(container.state == .running ? 0.15 : 0.12))
                        .foregroundStyle(statusColor)
                        .clipShape(Capsule())
                }

                // Row 2: CPU and Memory stats
                if container.state == .running, let stats {
                    HStack(spacing: 16) {
                        HStack(spacing: 3) {
                            Text("CPU")
                                .foregroundStyle(.tertiary)
                            Text(formatPercent(stats.cpuPercent))
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 3) {
                            Text("MEM")
                                .foregroundStyle(.tertiary)
                            Text(formatMemory(stats.memoryUsedMB))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                }

                // Row 3: Uptime and Ports
                HStack {
                    if container.state == .running {
                        Text(container.uptimeString)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(container.status)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Ports (if available)
                    if !container.ports.isEmpty {
                        portsLabel
                    }
                }
            }

            // Quick action button (visible on hover) or chevron
            if isHovered {
                quickActionButton
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isHovered ? statusColor.opacity(0.3) : Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(isHovered ? 0.06 : 0.02), radius: isHovered ? 4 : 2, y: 1)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            showDetailPopover.toggle()
        }
        .popover(isPresented: $showDetailPopover, arrowEdge: .trailing) {
            ContainerDetailPopover(container: container, stats: stats)
        }
    }

    // MARK: - Ports Label

    private var portsLabel: some View {
        let portText = formatPorts()
        return Text(portText)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func formatPorts() -> String {
        let publicPorts = container.ports.compactMap { $0.publicPort }
        if publicPorts.isEmpty {
            return ""
        } else if publicPorts.count == 1 {
            return ":\(publicPorts[0])"
        } else if publicPorts.count <= 2 {
            return publicPorts.map { ":\($0)" }.joined(separator: " ")
        } else {
            return ":\(publicPorts[0]) +\(publicPorts.count - 1)"
        }
    }

    // MARK: - Card Background

    private var cardBackground: Color {
        if isHovered {
            return statusColor.opacity(0.08)
        }
        return Color.primary.opacity(0.03)
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
