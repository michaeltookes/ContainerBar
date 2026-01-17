import SwiftUI
import DockerBarCore

/// Connection settings pane for managing Docker hosts
struct ConnectionSettingsPane: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ContainerStore.self) private var containerStore

    @State private var selectedHostId: UUID?
    @State private var isAddingHost = false
    @State private var isTestingConnection = false
    @State private var testResult: ConnectionTestResult?

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
                Button(action: { isAddingHost = true }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)

                Button(action: removeSelectedHost) {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(selectedHostId == nil || settings.hosts.count <= 1)

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
                isTestingConnection: isTestingConnection,
                testResult: testResult,
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
        settings.addHost(host)
        selectedHostId = host.id
    }

    private func removeSelectedHost() {
        guard let hostId = selectedHostId else { return }
        settings.removeHost(id: hostId)
        selectedHostId = settings.hosts.first?.id
    }

    private func setDefaultHost(_ host: DockerHost) {
        settings.selectedHostId = host.id
        containerStore.reinitializeFetcher()
        Task {
            await containerStore.refresh(force: true)
        }
    }

    private func testConnection(_ host: DockerHost) {
        isTestingConnection = true
        testResult = nil

        Task {
            do {
                let fetcher = try ContainerFetcher.forHost(host)
                try await fetcher.testConnection()
                await MainActor.run {
                    testResult = .success
                    isTestingConnection = false
                }
            } catch {
                await MainActor.run {
                    testResult = .failure(error.localizedDescription)
                    isTestingConnection = false
                }
            }
        }
    }

    private func updateHost(_ host: DockerHost) {
        settings.updateHost(host)
    }
}

// MARK: - Connection Test Result

enum ConnectionTestResult: Equatable {
    case success
    case failure(String)
}

// MARK: - Host Row View

struct HostRowView: View {
    let host: DockerHost
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(host.name)
                    .lineLimit(1)

                Text(host.connectionType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch host.connectionType {
        case .unixSocket: return "laptopcomputer"
        case .ssh: return "network"
        case .tcpTLS: return "lock.shield"
        }
    }

    private var iconColor: Color {
        switch host.connectionType {
        case .unixSocket: return .blue
        case .ssh: return .orange
        case .tcpTLS: return .green
        }
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
                }

                LabeledContent("Type") {
                    Text(host.connectionType.displayName)
                }

                if host.connectionType == .unixSocket {
                    LabeledContent("Socket Path") {
                        Text(host.socketPath ?? "/var/run/docker.sock")
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
                Text("Connected")
                    .foregroundStyle(.green)
            }
        case .failure(let message):
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }
}

// MARK: - Add Host Sheet

struct AddHostSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (DockerHost) -> Void

    @State private var name = ""
    @State private var connectionType: ConnectionType = .ssh
    @State private var host = ""
    @State private var sshUser = "root"
    @State private var sshPort = "22"

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $name, prompt: Text("My Server"))

                Picker("Connection Type", selection: $connectionType) {
                    Text("SSH Tunnel").tag(ConnectionType.ssh)
                    Text("Unix Socket (Local)").tag(ConnectionType.unixSocket)
                }

                if connectionType == .ssh {
                    TextField("Host", text: $host, prompt: Text("192.168.1.100"))
                    TextField("SSH User", text: $sshUser, prompt: Text("root"))
                    TextField("SSH Port", text: $sshPort, prompt: Text("22"))
                }
            }
            .formStyle(.grouped)
            .padding()

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    saveHost()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 350)
    }

    private var isValid: Bool {
        if name.isEmpty { return false }
        if connectionType == .ssh {
            return !host.isEmpty && !sshUser.isEmpty
        }
        return true
    }

    private func saveHost() {
        let newHost: DockerHost

        switch connectionType {
        case .unixSocket:
            newHost = DockerHost(
                name: name,
                connectionType: .unixSocket,
                isDefault: false
            )

        case .ssh:
            newHost = DockerHost(
                name: name,
                connectionType: .ssh,
                isDefault: false,
                host: host,
                sshUser: sshUser,
                sshPort: Int(sshPort) ?? 22
            )

        case .tcpTLS:
            // Not implemented yet
            return
        }

        onSave(newHost)
        dismiss()
    }
}

#if DEBUG
#Preview {
    ConnectionSettingsPane()
        .environment(SettingsStore())
        .environment(ContainerStore(settings: SettingsStore()))
        .frame(width: 500, height: 400)
}
#endif
