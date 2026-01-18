import SwiftUI
import DockerBarCore

/// Popover showing detailed container information
struct ContainerDetailPopover: View {
    let container: DockerContainer
    let stats: ContainerStats?
    let onAction: ((ContainerAction) -> Void)?

    init(container: DockerContainer, stats: ContainerStats?, onAction: ((ContainerAction) -> Void)? = nil) {
        self.container = container
        self.stats = stats
        self.onAction = onAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with name and state
            HStack {
                Text(container.displayName)
                    .font(.headline)
                Spacer()
                StatusBadge(state: container.state)
            }

            Divider()

            // Details grid
            VStack(alignment: .leading, spacing: 8) {
                DetailRow(label: "Image", value: container.image)

                DetailRow(label: "ID", value: String(container.id.prefix(12))) {
                    Button(action: copyContainerId) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Copy full container ID")
                }

                if !container.ports.isEmpty {
                    portsSection
                }

                if let networkMode = container.networkMode {
                    DetailRow(label: "Network", value: networkMode)
                }

                DetailRow(label: "Created", value: formatDate(container.created))

                if !container.command.isEmpty {
                    DetailRow(label: "Command", value: truncateCommand(container.command))
                }
            }

            // Stats section for running containers
            if container.state == .running, let stats {
                Divider()

                HStack(spacing: 16) {
                    MiniStat(label: "CPU", value: formatPercent(stats.cpuPercent), color: .blue)
                    MiniStat(label: "Memory", value: formatMemory(stats.memoryUsedMB), color: .purple)
                }
            }

            // Actions
            if let onAction {
                Divider()

                HStack(spacing: 8) {
                    Button {
                        onAction(.viewLogs(container.id))
                    } label: {
                        Label("View Logs", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    if container.state == .running {
                        Button {
                            onAction(.stop(container.id))
                        } label: {
                            Image(systemName: "stop.fill")
                        }
                        .buttonStyle(.bordered)
                        .help("Stop container")

                        Button {
                            onAction(.restart(container.id))
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .help("Restart container")
                    } else {
                        Button {
                            onAction(.start(container.id))
                        } label: {
                            Image(systemName: "play.fill")
                        }
                        .buttonStyle(.bordered)
                        .help("Start container")
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    // MARK: - Ports Section

    private var portsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ports")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(container.ports.prefix(5), id: \.privatePort) { port in
                HStack(spacing: 4) {
                    if let publicPort = port.publicPort {
                        Text("\(port.ip ?? "0.0.0.0"):\(publicPort)")
                            .foregroundStyle(.primary)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text("\(port.privatePort)/\(port.type)")
                        .foregroundStyle(port.publicPort != nil ? .primary : .secondary)
                }
                .font(.system(.caption, design: .monospaced))
            }

            if container.ports.count > 5 {
                Text("+ \(container.ports.count - 5) more")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Actions

    private func copyContainerId() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(container.id, forType: .string)
    }

    // MARK: - Formatters

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formatPercent(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    private func formatMemory(_ mb: Double) -> String {
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
    }

    private func truncateCommand(_ command: String) -> String {
        if command.count > 40 {
            return String(command.prefix(37)) + "..."
        }
        return command
    }
}

// MARK: - Supporting Views

/// A row showing label and value with optional trailing content
struct DetailRow<Trailing: View>: View {
    let label: String
    let value: String
    let trailing: Trailing

    init(label: String, value: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.label = label
        self.value = value
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .textSelection(.enabled)

            Spacer()

            trailing
        }
    }
}

/// Small stat display for the popover
struct MiniStat: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Container Detail") {
    ContainerDetailPopover(
        container: .mock(
            name: "nginx-proxy-manager",
            image: "jc21/nginx-proxy-manager:latest",
            state: .running
        ),
        stats: .mock(cpuPercent: 2.3, memoryUsageBytes: 134_217_728)
    )
}
#endif
