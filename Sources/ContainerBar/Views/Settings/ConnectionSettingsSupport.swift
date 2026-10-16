import SwiftUI
import ContainerBarCore

enum ConnectionTestResult: Equatable {
    case success
    case failure(String)
}

@MainActor
struct HostRowView: View {
    let host: DockerHost
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(host.name)
                        .accessibilityIdentifier(host.name.accessibilityIdentifier(prefix: "hostRow", identity: host.id))
                        .lineLimit(1)

                    Text(host.runtime.displayName)
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(runtimeColor.opacity(0.15))
                        .foregroundStyle(runtimeColor)
                        .clipShape(Capsule())
                }

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

    private var runtimeColor: Color {
        switch host.runtime {
        case .docker: return .blue
        case .podman: return .purple
        }
    }
}

// MARK: - Saving an added host

extension ConnectionSettingsPane {
    /// Persists a host from the Add Host sheet. With `activate`, it also
    /// becomes the active host, so a host added through the dashboard's Add
    /// Remote Host is the one the dashboard shows next (CB-078); the store
    /// observes `selectedHostId` and reinitializes the fetcher (CB-065).
    static func saveAddedHost(_ host: DockerHost, in settings: SettingsStore, activate: Bool) {
        settings.addHost(host)
        if activate {
            settings.selectedHostId = host.id
        }
    }
}
