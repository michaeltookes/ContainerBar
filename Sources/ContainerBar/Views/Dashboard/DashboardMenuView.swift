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

/// Host selection and management panel
struct HostPanelView: View {
    @Environment(SettingsStore.self) private var settings

    let onSelectHost: (UUID) -> Void
    let onClose: () -> Void

    @State private var isAddingHost = false
    @State private var newHostName = ""
    @State private var newHostAddress = ""
    @State private var newHostUser = "root"
    @State private var newHostPort = "22"

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select Host")
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if isAddingHost {
                // Add host form
                addHostForm
            } else {
                // Host list
                hostList
            }
        }
        .background(Color.primary.opacity(0.03))
    }

    private var hostList: some View {
        VStack(spacing: 0) {
            ForEach(settings.hosts) { host in
                HostListRowView(
                    host: host,
                    isSelected: settings.selectedHostId == host.id,
                    onSelect: {
                        onSelectHost(host.id)
                    }
                )
            }

            Divider()
                .padding(.vertical, 4)

            // Add host button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isAddingHost = true
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accentColor)

                    Text("Add Remote Host")
                        .font(.system(size: 12, weight: .medium))

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private var addHostForm: some View {
        VStack(spacing: 12) {
            // Name field
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("My Server", text: $newHostName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }

            // Host/IP field
            VStack(alignment: .leading, spacing: 4) {
                Text("Host (IP or hostname)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("192.168.1.100", text: $newHostAddress)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }

            // SSH User and Port
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SSH User")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("root", text: $newHostUser)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Port")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("22", text: $newHostPort)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .frame(width: 60)
                }
            }

            // Action buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        resetForm()
                        isAddingHost = false
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Save") {
                    saveNewHost()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!isNewHostValid)
            }
            .padding(.top, 4)
        }
        .padding(16)
    }

    private var isNewHostValid: Bool {
        let trimmedHost = newHostAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPort = newHostPort.trimmingCharacters(in: .whitespacesAndNewlines)

        // Host must be non-empty
        guard !trimmedHost.isEmpty else { return false }

        // Port must be valid if provided
        if !trimmedPort.isEmpty {
            guard let port = Int(trimmedPort), (1...65535).contains(port) else { return false }
        }

        return true
    }

    private func saveNewHost() {
        let trimmedName = newHostName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = newHostAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = newHostUser.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPort = newHostPort.trimmingCharacters(in: .whitespacesAndNewlines)

        let name = trimmedName.isEmpty ? "Remote Host" : trimmedName
        let port = trimmedPort.isEmpty ? 22 : (Int(trimmedPort) ?? 22)
        let user = trimmedUser.isEmpty ? "root" : trimmedUser

        let newHost = DockerHost(
            name: name,
            connectionType: .ssh,
            isDefault: false,
            host: trimmedHost,
            sshUser: user,
            sshPort: port
        )

        settings.addHost(newHost)

        withAnimation(.easeInOut(duration: 0.2)) {
            resetForm()
            isAddingHost = false
        }

        // Select the new host
        onSelectHost(newHost.id)
    }

    private func resetForm() {
        newHostName = ""
        newHostAddress = ""
        newHostUser = "root"
        newHostPort = "22"
    }
}

/// Individual host row in the list
struct HostListRowView: View {
    let host: DockerHost
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // Connection type icon
                Image(systemName: iconName)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(host.name)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)

                    Text(hostDescription)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
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
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var iconName: String {
        switch host.connectionType {
        case .unixSocket: return "laptopcomputer"
        case .tcpTLS: return "lock.shield"
        case .ssh: return "network"
        }
    }

    private var hostDescription: String {
        switch host.connectionType {
        case .unixSocket:
            return "Local Docker"
        case .tcpTLS:
            return "\(host.host ?? ""):\(host.port ?? 2376)"
        case .ssh:
            return "\(host.sshUser ?? "root")@\(host.host ?? ""):\(host.sshPort ?? 22)"
        }
    }
}

/// Logs container selection panel
struct LogsPanelView: View {
    let containers: [DockerContainer]
    let onSelectContainer: (String) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
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
                // Container list
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
struct LogsContainerRowView: View {
    let container: DockerContainer
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // Status indicator
                Circle()
                    .fill(container.state == .running ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)

                // Container name
                Text(container.displayName)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                // Status text
                Text(container.state == .running ? "Running" : "Stopped")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                // Arrow
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
        .onHover { hovering in
            isHovered = hovering
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
        onHostChanged: {}
    )
    .environment(store)
    .environment(settings)
}
#endif
