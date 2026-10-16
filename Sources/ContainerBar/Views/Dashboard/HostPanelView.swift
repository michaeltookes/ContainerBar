import SwiftUI
import ContainerBarCore

/// Host selection panel in the dashboard.
///
/// The panel lists hosts and switches between them; it has no host-entry
/// form of its own. **Add Remote Host** hands off to Settings > Connections,
/// whose `AddHostSheet` is the single place a host is entered, so the runtime
/// picker, remote socket path and SSH target validation cannot drift between
/// two forms, and closing the panel cannot discard a half-typed host (CB-078).
@MainActor
struct HostPanelView: View {
    @Environment(SettingsStore.self) private var settings

    let onSelectHost: (UUID) -> Void
    let onAddHost: () -> Void
    let onClose: () -> Void

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
                .accessibilityLabel("Close host panel")
                .accessibilityIdentifier("closeHostPanel")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            hostList
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

            // Opens Settings > Connections with the Add Host sheet (CB-078).
            Button(action: onAddHost) {
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
            .accessibilityLabel("Add remote host")
            .accessibilityHint("Opens Settings to add a host")
            .accessibilityIdentifier("addRemoteHost")
        }
        .padding(.vertical, 4)
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
                    .accessibilityHidden(true)

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
                        .accessibilityHidden(true)
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
        .accessibilityLabel("Select host \(host.name)")
        .accessibilityValue(hostDescription)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(host.name.accessibilityIdentifier(prefix: "hostPanelRow", identity: host.id))
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
