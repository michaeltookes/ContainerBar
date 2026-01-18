import SwiftUI
import DockerBarCore

/// A row displaying a single container with status and quick stats
struct ContainerRowView: View {
    let container: DockerContainer
    let stats: ContainerStats?
    let onAction: (ContainerAction) -> Void

    @State private var isHovered = false
    @State private var showDetailPopover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Main row
            HStack(spacing: 8) {
                // Status indicator
                statusIndicator

                // Container name
                Text(container.displayName)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                // State badge
                StatusBadge(state: container.state)
            }

            // Stats row (only for running containers)
            if container.state == .running, let stats {
                HStack(spacing: 12) {
                    StatItem(label: "CPU", value: formatPercent(stats.cpuPercent))
                    StatItem(label: "MEM", value: formatMemory(stats.memoryUsedMB))
                    StatItem(label: "", value: container.status)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text(container.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            showDetailPopover.toggle()
        }
        .popover(isPresented: $showDetailPopover, arrowEdge: .trailing) {
            // Pass nil for onAction since buttons don't work in NSMenu context
            ContainerDetailPopover(container: container, stats: stats, onAction: nil)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Click for details, use Container Actions menu for controls")
    }

    // MARK: - Subviews

    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
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

    private var accessibilityLabel: String {
        var label = "\(container.displayName), \(container.state.rawValue)"
        if let stats, container.state == .running {
            label += ", CPU \(formatPercent(stats.cpuPercent)), Memory \(formatMemory(stats.memoryUsedMB))"
        }
        return label
    }

    // MARK: - Helpers

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

// MARK: - Supporting Views

/// Container state badge
struct StatusBadge: View {
    let state: ContainerState

    var body: some View {
        Text(state.rawValue.capitalized)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor.opacity(0.15))
            .foregroundStyle(backgroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch state {
        case .running: return .green
        case .paused: return .yellow
        case .restarting: return .orange
        case .exited, .dead: return .red
        case .created, .removing: return .gray
        }
    }
}

/// Small stat item for inline display
struct StatItem: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            if !label.isEmpty {
                Text(label)
                    .foregroundStyle(.tertiary)
            }
            Text(value)
        }
    }
}

// MARK: - Container Actions

/// Actions that can be performed on a container
enum ContainerAction {
    case start(String)
    case stop(String)
    case restart(String)
    case remove(String)
    case copyId(String)
    case viewLogs(String)
}

// MARK: - Previews

#if DEBUG
#Preview("Running Container") {
    ContainerRowView(
        container: .mock(name: "nginx-proxy", state: .running),
        stats: .mock(cpuPercent: 2.3, memoryUsageBytes: 134_217_728),
        onAction: { _ in }
    )
    .frame(width: 300)
    .padding()
}

#Preview("Stopped Container") {
    ContainerRowView(
        container: .mock(name: "backup-service", state: .exited, status: "Exited (0) 2 hours ago"),
        stats: nil,
        onAction: { _ in }
    )
    .frame(width: 300)
    .padding()
}
#endif
