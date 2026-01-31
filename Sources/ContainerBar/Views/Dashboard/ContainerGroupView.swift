import SwiftUI
import ContainerBarCore

/// A group of containers with collapsible header
struct ContainerGroup: Identifiable {
    let id: String
    let name: String
    let containers: [DockerContainer]

    var runningCount: Int {
        containers.filter { $0.state == .running }.count
    }

    var totalCount: Int {
        containers.count
    }
}

/// Collapsible container group view
struct ContainerGroupView: View {
    let group: ContainerGroup
    let stats: [String: ContainerStats]
    let onAction: (ContainerAction) -> Void
    var onAddContainer: (() -> Void)? = nil

    @State private var isExpanded = true
    @State private var isAddHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Group header
            HStack(spacing: 8) {
                // Collapse/expand button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 12)

                        Text(group.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)

                        // Count badge
                        Text("\(group.runningCount)/\(group.totalCount)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                // Add button
                Button {
                    onAddContainer?()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(
                            Circle()
                                .fill(isAddHovered ? Color.primary.opacity(0.1) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.1)) {
                        isAddHovered = hovering
                    }
                }
                .help("Add container to \(group.name)")
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)

            // Container cards
            if isExpanded {
                VStack(spacing: 6) {
                    ForEach(group.containers) { container in
                        ContainerCardView(
                            container: container,
                            stats: stats[container.id],
                            onAction: onAction
                        )
                    }
                }
                .padding(.leading, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

/// Container list section with grouping based on user-defined sections
struct ContainerListSection: View {
    @Environment(SettingsStore.self) private var settings

    let containers: [DockerContainer]
    let stats: [String: ContainerStats]
    let onAction: (ContainerAction) -> Void
    var onAddContainer: ((String) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if containers.isEmpty {
                emptyState
            } else {
                // Grouped containers
                VStack(spacing: 12) {
                    ForEach(containerGroups) { group in
                        ContainerGroupView(
                            group: group,
                            stats: stats,
                            onAction: onAction,
                            onAddContainer: {
                                onAddContainer?(group.name)
                            }
                        )
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
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
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Grouping Logic (using custom sections)

    private var containerGroups: [ContainerGroup] {
        groupContainersByCustomSections(containers)
    }

    private func groupContainersByCustomSections(_ containers: [DockerContainer]) -> [ContainerGroup] {
        let customSections = settings.sections.sorted { $0.sortOrder < $1.sortOrder }

        // If no sections configured, return empty (no groups shown)
        guard !customSections.isEmpty else { return [] }

        var groups: [ContainerGroup] = []
        var assignedContainerIds: Set<String> = []

        // Match containers to custom sections
        for section in customSections {
            var sectionContainers: [DockerContainer] = []

            for container in containers {
                // Skip if already assigned
                guard !assignedContainerIds.contains(container.id) else { continue }

                // Check if container matches this section
                if section.matches(
                    containerName: container.displayName,
                    image: container.image,
                    labels: container.labels
                ) {
                    sectionContainers.append(container)
                    assignedContainerIds.insert(container.id)
                }
            }

            // Only add group if it has containers
            if !sectionContainers.isEmpty {
                let sorted = sortContainers(sectionContainers)
                groups.append(ContainerGroup(id: section.id.uuidString, name: section.name, containers: sorted))
            }
        }

        return groups
    }

    private func sortContainers(_ containers: [DockerContainer]) -> [DockerContainer] {
        containers.sorted { lhs, rhs in
            // Running containers first, then by name
            if lhs.state == .running && rhs.state != .running { return true }
            if lhs.state != .running && rhs.state == .running { return false }
            return lhs.displayName < rhs.displayName
        }
    }
}

#if DEBUG
#Preview {
    let containers: [DockerContainer] = [
        .mock(name: "api-server", image: "myapp/api:latest", state: .running),
        .mock(name: "api-worker", image: "myapp/worker:latest", state: .running),
        .mock(name: "postgres", image: "postgres:15", state: .running),
        .mock(name: "redis", image: "redis:7", state: .running),
        .mock(name: "backup", image: "backup-tool:latest", state: .exited, status: "Exited (0) 2h ago"),
    ]

    return ContainerListSection(
        containers: containers,
        stats: [:],
        onAction: { _ in }
    )
    .padding(.vertical)
    .frame(width: 380)
    .background(Color(nsColor: .windowBackgroundColor))
}
#endif
