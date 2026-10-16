import SwiftUI
import ContainerBarCore

/// Connection settings pane for managing Docker hosts
struct ConnectionSettingsPane: View {
    @Environment(SettingsStore.self) private var settings
    /// Optional so the pane still renders where no settings window hosts it
    /// (previews, view tests); the controller always injects one (CB-078).
    @Environment(SettingsNavigation.self) private var navigation: SettingsNavigation?

    private let fetcherFactory: ContainerStore.FetcherFactory

    @State private var selectedHostId: UUID?
    @State private var isAddingHost = false
    /// True while the sheet was opened by a route that activates the saved
    /// host (the dashboard's Add Remote Host, CB-078); false for the + button.
    @State private var activateAddedHost = false
    @State private var connectionTests = ConnectionTestTracker()

    init(fetcherFactory: @escaping ContainerStore.FetcherFactory = ContainerStore.defaultFetcherFactory) {
        self.fetcherFactory = fetcherFactory
    }

    var body: some View {
        HSplitView {
            // Host list (left side)
            hostListView
                .frame(minWidth: 150, maxWidth: 200)

            // Host details (right side)
            hostDetailsView
                .frame(minWidth: 250)
        }
        .padding()
        .sheet(isPresented: $isAddingHost) {
            AddHostSheet(onSave: addHost)
        }
        // The dashboard's Add Remote Host routes here (CB-078): consume the
        // request when the pane appears, or when it arrives while showing.
        .onAppear(perform: presentRequestedAddHost)
        .onChange(of: navigation?.pendingAddHost) { _, pending in
            if pending != nil { presentRequestedAddHost() }
        }
    }

    private func presentRequestedAddHost() {
        if let request = navigation?.consumeAddHostRequest() {
            activateAddedHost = request.activateOnSave
            isAddingHost = true
        }
    }

    // MARK: - Host List

    private var hostListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(settings.hosts, selection: $selectedHostId) { host in
                HostRowView(
                    host: host,
                    isSelected: settings.selectedHostId == host.id
                )
                .tag(host.id)
            }
            .listStyle(.bordered)

            // Add/Remove buttons
            HStack(spacing: 4) {
                Button(action: {
                    activateAddedHost = false
                    isAddingHost = true
                }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Add Host")
                .accessibilityIdentifier("openAddHostSheet")

                Button(action: removeSelectedHost) {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(selectedHostId == nil || settings.hosts.count <= 1)
                .accessibilityLabel("Remove host")
                .accessibilityIdentifier("removeSelectedHost")

                Spacer()
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    // MARK: - Host Details

    @ViewBuilder
    private var hostDetailsView: some View {
        if let hostId = selectedHostId,
           let host = settings.hosts.first(where: { $0.id == hostId }) {
            HostDetailsView(
                host: host,
                isSelected: settings.selectedHostId == host.id,
                isTestingConnection: connectionTests.isTesting(host.id),
                testResult: connectionTests.result(for: host.id),
                onSetDefault: { setDefaultHost(host) },
                onTestConnection: { testConnection(host) },
                onUpdate: { updateHost($0) }
            )
        } else {
            VStack {
                Spacer()
                Text("Select a host to view details")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    // MARK: - Actions

    private func addHost(_ host: DockerHost) {
        Self.saveAddedHost(host, in: settings, activate: activateAddedHost)
        activateAddedHost = false
        selectedHostId = host.id
    }

    private func removeSelectedHost() {
        guard let hostId = selectedHostId else { return }
        settings.removeHost(id: hostId)
        connectionTests.invalidate(hostId: hostId)
        selectedHostId = settings.hosts.first?.id
    }

    private func setDefaultHost(_ host: DockerHost) {
        // The store observes `settings.selectedHostId` and reinitializes the
        // fetcher itself, so this only records the selection (CB-065).
        settings.selectedHostId = host.id
    }

    private func testConnection(_ host: DockerHost) {
        // The result is recorded against the host the test ran for, and only
        // if this run is still that host's current one (CB-080).
        let token = connectionTests.begin(hostId: host.id)

        Task { @MainActor in
            let result: ConnectionTestResult
            do {
                let fetcher = try fetcherFactory(host)
                try await fetcher.testConnection()
                result = .success
            } catch {
                // A Local Network denial gets the System Settings guidance
                // instead of ssh's "No route to host" line (CB-115).
                let denied = await LocalNetworkDiagnoser.live.isLocalNetworkDenied(error: error, host: host)
                result = .failure(denied ? LocalNetworkGuidance.message : error.localizedDescription)
            }
            connectionTests.finish(hostId: host.id, token: token, result: result)
        }
    }

    private func updateHost(_ host: DockerHost) {
        settings.updateHost(host)
        // An edited host's old result no longer describes it (CB-080).
        connectionTests.invalidate(hostId: host.id)
    }
}

// MARK: - Host Details View

struct HostDetailsView: View {
    let host: DockerHost
    let isSelected: Bool
    let isTestingConnection: Bool
    let testResult: ConnectionTestResult?
    let onSetDefault: () -> Void
    let onTestConnection: () -> Void
    let onUpdate: (DockerHost) -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent("Name") {
                    Text(host.name)
                        .accessibilityIdentifier(host.name.accessibilityIdentifier(prefix: "host", identity: host.id))
                }

                LabeledContent("Runtime") {
                    HStack(spacing: 4) {
                        Image(systemName: host.runtime.iconName)
                            .foregroundStyle(host.runtime == .docker ? .blue : .purple)
                        Text(host.runtime.displayName)
                    }
                }

                LabeledContent("Type") {
                    Text(host.connectionType.displayName)
                }

                if host.connectionType == .unixSocket {
                    LabeledContent("Socket Path") {
                        Text(host.socketPath ?? host.runtime.defaultSocketPath)
                            .font(.system(.body, design: .monospaced))
                    }
                }

                if host.connectionType == .ssh {
                    LabeledContent("Host") {
                        Text(host.host ?? "-")
                            .font(.system(.body, design: .monospaced))
                    }

                    LabeledContent("User") {
                        Text(host.sshUser ?? "-")
                    }

                    LabeledContent("Port") {
                        Text("\(host.sshPort ?? 22)")
                    }

                    LabeledContent("Remote Socket") {
                        Text(host.socketPath ?? host.runtime.defaultRemoteSocketPath)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            } header: {
                Text("Connection Details")
            }

            Section {
                HStack {
                    Button(action: onTestConnection) {
                        if isTestingConnection {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Test Connection")
                        }
                    }
                    .disabled(isTestingConnection)
                    .accessibilityLabel(isTestingConnection ? "Testing connection" : "Test connection")
                    .accessibilityIdentifier("testConnection")

                    if let result = testResult {
                        testResultView(result)
                    }
                }

                if !isSelected {
                    Button("Set as Active Host") {
                        onSetDefault()
                    }
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)
                        Text("Currently Active")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Actions")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func testResultView(_ result: ConnectionTestResult) -> some View {
        switch result {
        case .success:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Connected")
                    .foregroundStyle(.green)
            }
        case .failure(let message):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                    Text(message)
                        .foregroundStyle(.red)
                        .lineLimit(LocalNetworkGuidance.isGuidance(message) ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if LocalNetworkGuidance.isGuidance(message) {
                    OpenLocalNetworkSettingsButton()
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    ConnectionSettingsPane()
        .environment(SettingsStore())
        .frame(width: 500, height: 400)
}
#endif
