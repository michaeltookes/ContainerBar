import SwiftUI
import ContainerBarCore

/// Segmented picker for switching between configured hosts
struct HostPickerView: View {
    let hosts: [DockerHost]
    let selectedHostId: UUID?
    let onSelectHost: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(hosts) { host in
                    HostPillButton(
                        host: host,
                        isSelected: host.id == selectedHostId,
                        onTap: { onSelectHost(host.id) }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
}

// MARK: - Host Pill Button

private struct HostPillButton: View {
    let host: DockerHost
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                // Runtime icon
                Image(systemName: host.runtime.badgeIconName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(runtimeColor)

                // Host name
                Text(host.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.5) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
    }

    private var runtimeColor: Color {
        switch host.runtime {
        case .docker: return .blue
        case .podman: return .purple
        @unknown default: return .secondary
        }
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 20) {
        // Multiple hosts
        HostPickerView(
            hosts: [
                DockerHost(name: "Beelink Docker", connectionType: .ssh, runtime: .docker),
                DockerHost(name: "Beelink Podman", connectionType: .ssh, runtime: .podman),
            ],
            selectedHostId: nil,
            onSelectHost: { _ in }
        )

        // Single host (should be hidden in real use)
        HostPickerView(
            hosts: [
                DockerHost(name: "Local Docker", connectionType: .unixSocket, runtime: .docker),
            ],
            selectedHostId: nil,
            onSelectHost: { _ in }
        )
    }
    .frame(width: 400)
    .background(.regularMaterial)
}
#endif
