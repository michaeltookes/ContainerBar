import SwiftUI
import ContainerBarCore

/// Main dashboard view for the menu bar popover
struct DashboardMenuView: View {
    @Environment(ContainerStore.self) private var store
    @Environment(SettingsStore.self) private var settings

    let onAction: (ContainerAction) -> Void
    let onSettings: () -> Void
    var onQuit: (() -> Void)? = nil
    var onHostChanged: (() -> Void)? = nil
    /// Fires once SwiftUI has run the body and the view appears in the
    /// hierarchy. The host uses this to gate menu-open state mutations
    /// until after the initial render pass, replacing a fixed-delay sleep.
    var onFirstAppear: (() -> Void)? = nil

    @State private var isSearching = false
    @State private var searchText = ""
    @State private var isHostPanelOpen = false
    @State private var isLogsPanelOpen = false

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

            // Host picker (shown when multiple hosts configured)
            if settings.hosts.count > 1 {
                HostPickerView(
                    hosts: settings.hosts,
                    selectedHostId: settings.selectedHostId,
                    onSelectHost: { hostId in
                        settings.selectedHostId = hostId
                        onHostChanged?()
                    }
                )
            }

            Divider()

            // Connection status bar (hidden when searching)
            if !isSearching {
                ConnectionStatusBar(
                    presentation: connectionPresentation,
                    runningCount: runningCount,
                    stoppedCount: stoppedCount
                )
            }

            // Action error banner
            if let actionError = store.lastActionError {
                ActionErrorBanner(
                    message: actionError.message,
                    onDismiss: { store.dismissActionError() }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: actionError.id) {
                    do {
                        try await Task.sleep(for: .seconds(5))
                    } catch is CancellationError {
                        return
                    } catch {
                        return
                    }

                    guard !Task.isCancelled, store.lastActionError?.id == actionError.id else {
                        return
                    }

                    withAnimation(.easeOut(duration: 0.3)) {
                        store.dismissActionError()
                    }
                }
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
                isHostsActive: isHostPanelOpen,
                isLogsActive: isLogsPanelOpen,
                onRefresh: {
                    Task { await store.refresh(force: true) }
                },
                onHosts: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isLogsPanelOpen = false
                        isHostPanelOpen.toggle()
                    }
                },
                onLogs: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHostPanelOpen = false
                        isLogsPanelOpen.toggle()
                    }
                },
                onSettings: onSettings
            )

            // Host panel (slides out below action bar)
            if isHostPanelOpen {
                HostPanelView(
                    onSelectHost: { hostId in
                        settings.selectedHostId = hostId
                        onHostChanged?()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isHostPanelOpen = false
                        }
                    },
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isHostPanelOpen = false
                        }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Logs panel (slides out below action bar)
            if isLogsPanelOpen {
                LogsPanelView(
                    containers: store.containers,
                    onSelectContainer: { containerId in
                        onAction(.viewLogs(containerId))
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isLogsPanelOpen = false
                        }
                    },
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isLogsPanelOpen = false
                        }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: 400)
        .background(.regularMaterial)
        .onAppear { onFirstAppear?() }
    }

    // MARK: - Computed Properties

    private var hostName: String {
        settings.selectedHost?.name ?? "Local Docker"
    }

    private var connectionPresentation: ConnectionStatusPresentation {
        ConnectionStatusPresentation.make(
            hostName: hostName,
            isConnected: store.isConnected,
            isRefreshing: store.isRefreshing,
            connectionError: store.connectionError
        )
    }

    private var runningCount: Int {
        store.containers.filter { $0.state == .running }.count
    }

    private var stoppedCount: Int {
        store.containers.filter { $0.state == .exited || $0.state == .dead }.count
    }

    private var displayedContainers: [DockerContainer] {
        if isSearching && !searchText.isEmpty {
            // While searching, ignore the showStopped setting and only filter
            // by the query, then apply the menu's sort rule.
            let query = searchText.lowercased()
            let matches = store.containers.filter { container in
                container.displayName.lowercased().contains(query) ||
                container.image.lowercased().contains(query) ||
                container.id.lowercased().hasPrefix(query)
            }
            return sortedFilteredContainersForMenu(matches, showStopped: true)
        }

        return sortedFilteredContainersForMenu(
            store.containers,
            showStopped: settings.showStoppedContainers
        )
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
        onHostChanged: {}
    )
    .environment(store)
    .environment(settings)
}
#endif
