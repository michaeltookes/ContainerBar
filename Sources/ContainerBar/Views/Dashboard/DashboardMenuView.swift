import SwiftUI
import ContainerBarCore

/// Main dashboard view for the menu bar popover
struct DashboardMenuView: View {
    @Environment(ContainerStore.self) private var store
    @Environment(SettingsStore.self) private var settings

    let onAction: (ContainerAction) -> Void
    let onSettings: () -> Void
    var onQuit: (() -> Void)? = nil
    var onHosts: (() -> Void)? = nil
    var onLogs: (() -> Void)? = nil

    @State private var isSearching = false
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            DashboardHeaderView(
                isRefreshing: store.isRefreshing,
                isSearching: isSearching,
                onRefresh: {
                    Task { await store.refresh(force: true) }
                },
                onSearch: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSearching.toggle()
                        if !isSearching {
                            searchText = ""
                        }
                    }
                },
                onQuit: {
                    onQuit?()
                },
                onSettings: onSettings
            )

            // Search bar (shown when searching)
            if isSearching {
                SearchBarView(searchText: $searchText)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Divider()

            // Connection status bar (hidden when searching)
            if !isSearching {
                ConnectionStatusBar(
                    hostName: hostName,
                    isConnected: store.isConnected,
                    runningCount: runningCount,
                    stoppedCount: stoppedCount
                )
            }

            // Scrollable content
            ScrollView {
                VStack(spacing: 0) {
                    // General Stats Grid (only if connected with data and not searching)
                    if store.isConnected && !store.containers.isEmpty && !isSearching {
                        GeneralStatsGrid(
                            metrics: store.metricsSnapshot,
                            history: store.metricsHistory
                        )
                        .padding(.top, 12)
                        .padding(.bottom, 12)
                    }

                    // Container List
                    ContainerListSection(
                        containers: displayedContainers,
                        stats: store.stats,
                        onAction: onAction
                    )
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                }
            }
            .frame(maxHeight: 520)

            Divider()

            // Quick action bar
            QuickActionBar(
                onRefresh: {
                    Task { await store.refresh(force: true) }
                },
                onHosts: {
                    onHosts?()
                },
                onLogs: {
                    onLogs?()
                },
                onSettings: onSettings
            )
        }
        .frame(width: 400)
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
        var containers = store.containers

        // When searching, search ALL containers (active and inactive)
        if isSearching && !searchText.isEmpty {
            let query = searchText.lowercased()
            containers = containers.filter { container in
                container.displayName.lowercased().contains(query) ||
                container.image.lowercased().contains(query) ||
                container.id.lowercased().hasPrefix(query)
            }
        } else if !isSearching {
            // When not searching, filter based on settings
            if !settings.showStoppedContainers {
                containers = containers.filter { $0.state.isActive }
            }
        }

        // Sort: running containers first, then by name
        return containers.sorted { lhs, rhs in
            if lhs.state == .running && rhs.state != .running { return true }
            if lhs.state != .running && rhs.state == .running { return false }
            return lhs.displayName < rhs.displayName
        }
    }
}

/// Search bar view for filtering containers
struct SearchBarView: View {
    @Binding var searchText: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextField("Search containers...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05))
        .onAppear {
            isFocused = true
        }
    }
}

#if DEBUG
#Preview {
    let store = ContainerStore(settings: SettingsStore())
    let settings = SettingsStore()

    return DashboardMenuView(
        onAction: { _ in },
        onSettings: {},
        onQuit: {},
        onHosts: {},
        onLogs: {}
    )
    .environment(store)
    .environment(settings)
}
#endif
