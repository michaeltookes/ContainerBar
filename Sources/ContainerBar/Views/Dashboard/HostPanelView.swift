import SwiftUI
import ContainerBarCore
import Logging

/// Host selection and management panel
@MainActor
struct HostPanelView: View {
    @Environment(SettingsStore.self) private var settings
    private let logger = Logger(label: "com.containerbar.ui.host-panel")

    let onSelectHost: (UUID) -> Void
    let onClose: () -> Void

    @State private var isAddingHost = false
    @State private var newHostName = ""
    @State private var newHostAddress = ""
    @State private var newHostUser = "root"
    @State private var newHostPort = ""
    @State private var validationError: String?

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
            ScrollView {
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
                }
            }
            .frame(maxHeight: 200)

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
        ScrollView {
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
                    .help("You can optionally include a port, for example host.example.com:2222.")
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
                        validationError = nil
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

            if let validationError {
                Text(validationError)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
        .padding(16)
        }
    }

    private var isNewHostValid: Bool {
        RemoteHostDraftBuilder.isValid(
            nameInput: newHostName,
            hostInput: newHostAddress,
            userInput: newHostUser,
            portInput: newHostPort
        )
    }

    private func saveNewHost() {
        do {
            let hostDraft = try RemoteHostDraftBuilder.build(
                nameInput: newHostName,
                hostInput: newHostAddress,
                userInput: newHostUser,
                portInput: newHostPort
            )

            let newHost = hostDraft.makeDockerHost()
            validationError = nil

            settings.addHost(newHost)

            withAnimation(.easeInOut(duration: 0.2)) {
                resetForm()
                isAddingHost = false
            }

            onSelectHost(newHost.id)
        } catch {
            logger.warning("Failed to save remote host from dashboard panel")
            validationError = error.localizedDescription
        }
    }

    private func resetForm() {
        newHostName = ""
        newHostAddress = ""
        newHostUser = "root"
        newHostPort = ""
        validationError = nil
    }
}

/// Individual host row in the list
@MainActor
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
