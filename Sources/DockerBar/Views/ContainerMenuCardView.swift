import SwiftUI
import DockerBarCore

/// Main menu card view showing container overview and list
///
/// Following UI_UX design specifications:
/// - Width: 320pt (fixed)
/// - Padding: 16pt all sides
/// - Section spacing: 12pt
struct ContainerMenuCardView: View {
    @Environment(ContainerStore.self) private var store
    @Environment(SettingsStore.self) private var settings

    let onAction: (ContainerAction) -> Void

    @State private var showMetricsPopover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            header
                .padding(.bottom, 12)

            Divider()

            // Connection status
            connectionStatus
                .padding(.vertical, 12)

            // Overview metrics (only if connected with running containers)
            if store.isConnected && !store.containers.isEmpty {
                Divider()

                overviewSection
                    .padding(.vertical, 12)
            }

            Divider()

            // Container list
            containerListSection
                .padding(.top, 12)
        }
        .padding(16)
        .frame(width: 320)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("DockerBar")
                .font(.headline)

            Spacer()

            if store.isRefreshing {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Refreshing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let lastRefresh = store.lastRefreshAt {
                Text(lastRefresh, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Connection Status

    private var connectionStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(connectionStatusColor)
                    .frame(width: 8, height: 8)

                Text(connectionStatusText)
                    .font(.subheadline)
            }

            if store.isConnected {
                HStack(spacing: 8) {
                    StatusCount(count: runningCount, label: "running", color: .green)
                    StatusCount(count: stoppedCount, label: "stopped", color: .secondary)
                    if pausedCount > 0 {
                        StatusCount(count: pausedCount, label: "paused", color: .yellow)
                    }
                }
                .font(.caption)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(connectionAccessibilityLabel)
    }

    // MARK: - Overview Section

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Overview")

            if let metrics = store.metricsSnapshot {
                VStack(spacing: 8) {
                    MetricProgressBar(
                        title: "CPU Usage",
                        percent: metrics.totalCPUPercent,
                        tint: .blue
                    )

                    MetricProgressBar(
                        title: "Memory Usage",
                        percent: metrics.memoryUsagePercent,
                        subtitle: formatMemoryRange(used: metrics.totalMemoryUsedMB, limit: metrics.totalMemoryLimitMB),
                        tint: .purple
                    )
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(showMetricsPopover ? 0.1 : 0))
                )
                .onHover { hovering in
                    showMetricsPopover = hovering
                }
                .popover(isPresented: $showMetricsPopover, arrowEdge: .trailing) {
                    MetricsGaugePopover(
                        cpuPercent: metrics.totalCPUPercent,
                        memoryPercent: metrics.memoryUsagePercent,
                        memoryUsed: formatMemory(metrics.totalMemoryUsedMB),
                        memoryLimit: formatMemory(metrics.totalMemoryLimitMB)
                    )
                }
            }
        }
    }

    // MARK: - Container List

    private var containerListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Containers")

            if store.containers.isEmpty {
                emptyState
            } else {
                containerList
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            if store.isRefreshing {
                ProgressView()
                    .controlSize(.regular)

                Text("Loading containers...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "shippingbox")
                    .font(.system(size: 24))
                    .foregroundStyle(.tertiary)

                Text("No containers")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Start some containers to see them here")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var containerList: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(displayedContainers) { container in
                    ContainerRowView(
                        container: container,
                        stats: store.stats[container.id],
                        onAction: onAction
                    )
                }
            }
        }
        .frame(maxHeight: maxContainerListHeight)
    }

    /// Maximum height for the container list (roughly 8 rows)
    private var maxContainerListHeight: CGFloat {
        let rowHeight: CGFloat = 44 // Approximate height per container row
        let maxRows: CGFloat = 8
        let containerCount = CGFloat(displayedContainers.count)
        return min(containerCount * rowHeight, maxRows * rowHeight)
    }

    // MARK: - Computed Properties

    private var displayedContainers: [DockerContainer] {
        let sorted = store.containers.sorted { lhs, rhs in
            // Running containers first, then by name
            if lhs.state == .running && rhs.state != .running { return true }
            if lhs.state != .running && rhs.state == .running { return false }
            return lhs.displayName < rhs.displayName
        }

        // Filter based on settings
        return settings.showStoppedContainers
            ? sorted
            : sorted.filter { $0.state.isActive }
    }

    private var runningCount: Int {
        store.containers.filter { $0.state == .running }.count
    }

    private var stoppedCount: Int {
        store.containers.filter { $0.state == .exited || $0.state == .dead }.count
    }

    private var pausedCount: Int {
        store.containers.filter { $0.state == .paused }.count
    }

    private var connectionStatusColor: Color {
        if store.connectionError != nil { return .red }
        if store.isConnected { return .green }
        return .yellow
    }

    private var connectionStatusText: String {
        if let error = store.connectionError {
            return "Error: \(error)"
        }
        let hostName = settings.selectedHost?.name ?? "Local Docker"
        if store.isRefreshing && !store.isConnected {
            return "Connecting to \(hostName)..."
        }
        if store.isConnected {
            return "Connected to \(hostName)"
        }
        return "Connecting..."
    }

    private var connectionAccessibilityLabel: String {
        var label = connectionStatusText
        if store.isConnected {
            label += ", \(runningCount) running, \(stoppedCount) stopped"
        }
        return label
    }

    // MARK: - Helpers

    private func formatMemoryRange(used: Double, limit: Double) -> String {
        let usedStr = formatMemory(used)
        let limitStr = formatMemory(limit)
        return "\(usedStr) / \(limitStr)"
    }

    private func formatMemory(_ mb: Double) -> String {
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
    }
}

// MARK: - Supporting Views

/// Section header with uppercase styling
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }
}

/// Status count display (e.g., "5 running")
struct StatusCount: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(count) \(label)")
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Connected with Containers") {
    let store = ContainerStore(settings: SettingsStore())
    let settings = SettingsStore()

    return ContainerMenuCardView(onAction: { _ in })
        .environment(store)
        .environment(settings)
}
#endif
