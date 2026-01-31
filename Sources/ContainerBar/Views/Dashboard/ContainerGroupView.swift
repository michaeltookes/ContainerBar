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

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Group header
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

                    Spacer()

                    // Count badge
                    Text("\(group.runningCount)/\(group.totalCount)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Container cards
            if isExpanded {
                VStack(spacing: 4) {
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

/// Container list section with grouping
struct ContainerListSection: View {
    let containers: [DockerContainer]
    let stats: [String: ContainerStats]
    let onAction: (ContainerAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text("CONTAINERS")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)

                Spacer()

                Text("\(containers.count) total")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)

            if containers.isEmpty {
                emptyState
            } else {
                // Grouped containers
                VStack(spacing: 8) {
                    ForEach(containerGroups) { group in
                        ContainerGroupView(
                            group: group,
                            stats: stats,
                            onAction: onAction
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

    // MARK: - Grouping Logic

    private var containerGroups: [ContainerGroup] {
        groupContainers(containers)
    }

    private func groupContainers(_ containers: [DockerContainer]) -> [ContainerGroup] {
        var groups: [String: [DockerContainer]] = [:]

        for container in containers {
            // Priority 1: Docker Compose project label
            if let project = container.labels["com.docker.compose.project"] {
                groups[project, default: []].append(container)
                continue
            }

            // Priority 2: Group by image prefix (before first /)
            let imagePrefix = extractImagePrefix(container.image)
            groups[imagePrefix, default: []].append(container)
        }

        // Sort containers within each group (running first, then by name)
        return groups.map { key, containers in
            let sorted = containers.sorted { lhs, rhs in
                if lhs.state == .running && rhs.state != .running { return true }
                if lhs.state != .running && rhs.state == .running { return false }
                return lhs.displayName < rhs.displayName
            }
            return ContainerGroup(id: key, name: formatGroupName(key), containers: sorted)
        }
        .sorted { $0.runningCount > $1.runningCount } // Groups with more running containers first
    }

    private func extractImagePrefix(_ image: String) -> String {
        // Remove tag (after :)
        let imageName = image.split(separator: ":").first.map(String.init) ?? image

        // If contains /, use the first part as group
        if let slashIndex = imageName.firstIndex(of: "/") {
            return String(imageName[..<slashIndex])
        }

        // Otherwise use "Other"
        return "Other"
    }

    private func formatGroupName(_ name: String) -> String {
        // Capitalize first letter
        name.prefix(1).uppercased() + name.dropFirst()
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
