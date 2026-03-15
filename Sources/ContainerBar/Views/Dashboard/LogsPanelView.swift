import SwiftUI
import ContainerBarCore

/// Logs container selection panel
@MainActor
struct LogsPanelView: View {
    let containers: [DockerContainer]
    let onSelectContainer: (String) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Title and dismiss control stay grouped so the panel reads as a single transient surface.
            HStack {
                Text("View Logs")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .accessibilityHint("Closes the logs panel")
                .accessibilityIdentifier("logs-panel-close")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if containers.isEmpty {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("No containers")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                // The container list keeps running items discoverable and lets the user jump straight to logs.
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(sortedContainers) { container in
                            LogsContainerRowView(
                                container: container,
                                onSelect: {
                                    onSelectContainer(container.id)
                                }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 200)
            }
        }
        .background(Color.primary.opacity(0.03))
    }

    private var sortedContainers: [DockerContainer] {
        containers.sorted { lhs, rhs in
            // Running containers first, then by name
            if lhs.state == .running && rhs.state != .running { return true }
            if lhs.state != .running && rhs.state == .running { return false }
            return lhs.displayName < rhs.displayName
        }
    }
}

/// Container row for logs panel
@MainActor
struct LogsContainerRowView: View {
    let container: DockerContainer
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // The leading dot gives a quick visual state cue before the spoken label/value.
                Circle()
                    .fill(container.state == .running ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)

                Text(container.displayName)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Text(container.state == .running ? "Running" : "Stopped")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                // The chevron signals that selecting the row navigates into the log viewer flow.
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
                    .padding(.horizontal, 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(container.displayName)
        .accessibilityValue(container.status.isEmpty ? container.state.rawValue.capitalized : container.status)
        .accessibilityHint("Opens this container's logs")
        .accessibilityIdentifier("logs-panel-container-\(container.id)")
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
