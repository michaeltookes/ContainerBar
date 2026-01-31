import SwiftUI
import ContainerBarCore

/// Main dashboard view for the menu bar popover
struct DashboardMenuView: View {
    @Environment(ContainerStore.self) private var store
    @Environment(SettingsStore.self) private var settings

    let onAction: (ContainerAction) -> Void
    let onSettings: () -> Void
    let onHosts: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            DashboardHeaderView(
                isRefreshing: store.isRefreshing,
                onRefresh: {
                    Task { await store.refresh(force: true) }
                },
                onSettings: onSettings
            )

            Divider()

            // Connection status bar
            ConnectionStatusBar(
                hostName: hostName,
                isConnected: store.isConnected,
                runningCount: runningCount,
                stoppedCount: stoppedCount
            )

            Divider()

            // Scrollable content
            ScrollView {
                VStack(spacing: 0) {
                    // General Stats Grid (only if connected with data)
                    if store.isConnected && !store.containers.isEmpty {
                        GeneralStatsGrid(
                            metrics: store.metricsSnapshot,
                            history: store.metricsHistory
                        )
                        .padding(.top, 12)
                        .padding(.bottom, 12)

                        Divider()
                            .padding(.horizontal, 16)
                    }

                    // Container List
                    ContainerListSection(
                        containers: displayedContainers,
                        stats: store.stats,
                        onAction: onAction
                    )
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                }
            }
            .frame(maxHeight: 400)

            Divider()

            // Quick action bar
            QuickActionBar(
                onRefresh: {
                    Task { await store.refresh(force: true) }
                },
                onHosts: onHosts,
                onSettings: onSettings
            )
        }
        .frame(width: 380)
        .background(.regularMaterial)
    }

    // MARK: - Computed Properties

    private var hostName: String {
        settings.selectedHost?.name ?? "Local Docker"
    }

    private var runningCount: Int {
        store.containers.filter { $0.state == .running }.count
    }

    private var stoppedCount: Int {
        store.containers.filter { $0.state == .exited || $0.state == .dead }.count
    }

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
}

#if DEBUG
#Preview {
    let store = ContainerStore(settings: SettingsStore())
    let settings = SettingsStore()

    return DashboardMenuView(
        onAction: { _ in },
        onSettings: {},
        onHosts: {}
    )
    .environment(store)
    .environment(settings)
}
#endif
