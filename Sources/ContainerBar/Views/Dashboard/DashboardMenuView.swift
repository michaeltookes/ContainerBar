import SwiftUI
import ContainerBarCore

/// Main dashboard view for the menu bar popover
struct DashboardMenuView: View {
    @Environment(ContainerStore.self) private var store
    @Environment(SettingsStore.self) private var settings

    let onAction: (ContainerAction) -> Void
    let onSettings: () -> Void
    let onQuit: () -> Void

    @State private var searchText = ""

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

            // Search bar
            SearchBarView(text: $searchText)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            Divider()

            // Scrollable container list
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(filteredContainers) { container in
                        ContainerCardView(
                            container: container,
                            stats: store.stats[container.id],
                            onAction: onAction
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .frame(maxHeight: 350)

            Divider()

            // Quit button
            Button(action: onQuit) {
                Text("Quit ContainerBar")
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
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

    private var filteredContainers: [DockerContainer] {
        let sorted = store.containers.sorted { lhs, rhs in
            // Running containers first, then by name
            if lhs.state == .running && rhs.state != .running { return true }
            if lhs.state != .running && rhs.state == .running { return false }
            return lhs.displayName < rhs.displayName
        }

        // Filter based on settings
        let displayed = settings.showStoppedContainers
            ? sorted
            : sorted.filter { $0.state.isActive }

        // Filter by search text
        if searchText.isEmpty {
            return displayed
        }
        return displayed.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.image.localizedCaseInsensitiveContains(searchText)
        }
    }
}

/// Search bar with magnifying glass icon
struct SearchBarView: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextField("Search containers...", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#if DEBUG
#Preview {
    let store = ContainerStore(settings: SettingsStore())
    let settings = SettingsStore()

    return DashboardMenuView(
        onAction: { _ in },
        onSettings: {},
        onQuit: {}
    )
    .environment(store)
    .environment(settings)
}
#endif
