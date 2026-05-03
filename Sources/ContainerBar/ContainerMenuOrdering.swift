import ContainerBarCore

/// Sort and filter the container list as it should appear in the menu's
/// "Container Actions" submenu:
///
/// 1. Running containers come before everything else.
/// 2. Within each tier, containers are sorted by display name,
///    case-insensitively and locale-aware.
/// 3. When `showStopped` is `false`, containers in non-active states
///    (`exited`, `dead`, `created`, `removing`) are filtered out;
///    `paused` and `restarting` always remain because they're "active".
func sortedFilteredContainersForMenu(
    _ containers: [DockerContainer],
    showStopped: Bool
) -> [DockerContainer] {
    containers
        .sorted { lhs, rhs in
            if lhs.state == .running && rhs.state != .running { return true }
            if lhs.state != .running && rhs.state == .running { return false }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        .filter { container in
            showStopped || container.state.isActive
        }
}
