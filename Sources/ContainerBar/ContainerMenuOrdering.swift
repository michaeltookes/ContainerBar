import ContainerBarCore

/// Sort and filter the container list as it should appear in the menu's
/// "Container Actions" submenu:
///
/// 1. Running containers come before everything else.
/// 2. Within each tier, containers are sorted by display name,
///    case-insensitively and locale-aware.
/// 3. When two containers share a display name (possible across hosts),
///    they're tie-broken by `id` so the order is fully self-determined
///    rather than depending on input ordering or sort stability.
/// 4. When `showStopped` is `false`, containers in non-active states
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
            switch lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return lhs.id < rhs.id
            }
        }
        .filter { container in
            showStopped || container.state.isActive
        }
}
