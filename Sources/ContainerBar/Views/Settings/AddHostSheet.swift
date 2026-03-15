import SwiftUI
import ContainerBarCore

@MainActor
struct AddHostSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (DockerHost) -> Void

    @State private var name = ""
    @State private var runtime: ContainerRuntime = .docker
    @State private var connectionType: ConnectionType = .ssh
    @State private var socketPath = ""
    @State private var host = ""
    @State private var sshUser = "root"
    @State private var sshPort = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $name, prompt: Text("My Server"))

                Picker("Runtime", selection: $runtime) {
                    ForEach(ContainerRuntime.allCases, id: \.self) { rt in
                        HStack {
                            Image(systemName: rt.iconName)
                            Text(rt.displayName)
                        }
                        .tag(rt)
                    }
                }
                .onChange(of: runtime) { _, newRuntime in
                    updateSocketPathForRuntime(newRuntime)
                }

                Picker("Connection Type", selection: $connectionType) {
                    Text("SSH Tunnel").tag(ConnectionType.ssh)
                    Text("Unix Socket (Local)").tag(ConnectionType.unixSocket)
                }
                .onChange(of: connectionType) { _, _ in
                    updateSocketPathForRuntime(runtime)
                }

                if connectionType == .unixSocket {
                    TextField("Socket Path", text: $socketPath, prompt: Text(runtime.defaultSocketPath))
                        .font(.system(.body, design: .monospaced))
                }

                if connectionType == .ssh {
                    TextField("Host", text: $host, prompt: Text("192.168.1.100"))
                        .help("You can optionally include a port, for example host.example.com:2222.")
                    TextField("SSH User", text: $sshUser, prompt: Text("root"))
                    TextField("SSH Port", text: $sshPort, prompt: Text("22"))

                    TextField("Remote Socket Path", text: $socketPath, prompt: Text(defaultRemoteSocketPath))
                        .font(.system(.body, design: .monospaced))
                        .help("Path to container socket on remote server. Leave empty for default.")
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
        .frame(width: 380)
    }

    private var isValid: Bool {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if connectionType == .ssh {
            return RemoteHostDraftBuilder.isValid(
                nameInput: name,
                hostInput: host,
                userInput: sshUser,
                portInput: sshPort,
                runtime: runtime,
                socketPath: socketPath
            )
        }
        return true
    }

    private var defaultRemoteSocketPath: String {
        runtime.defaultRemoteSocketPath
    }

    private func updateSocketPathForRuntime(_ newRuntime: ContainerRuntime) {
        let newDefaultPath: String
        if connectionType == .unixSocket {
            newDefaultPath = newRuntime.defaultSocketPath
        } else {
            newDefaultPath = newRuntime.defaultRemoteSocketPath
        }

        let knownDefaults = [
            ContainerRuntime.docker.defaultSocketPath,
            ContainerRuntime.docker.defaultRemoteSocketPath,
            ContainerRuntime.podman.defaultSocketPath,
            ContainerRuntime.podman.defaultRemoteSocketPath,
        ]

        if socketPath.isEmpty || knownDefaults.contains(socketPath) {
            socketPath = newDefaultPath
        }
    }

    private func saveHost() {
        let newHost: DockerHost

        switch connectionType {
        case .unixSocket:
            let trimmedSocketPath = socketPath.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalSocketPath = trimmedSocketPath.isEmpty ? runtime.defaultSocketPath : trimmedSocketPath
            newHost = DockerHost(
                name: name,
                connectionType: .unixSocket,
                runtime: runtime,
                isDefault: false,
                socketPath: finalSocketPath
            )

        case .ssh:
            guard let hostDraft = try? RemoteHostDraftBuilder.build(
                nameInput: name,
                hostInput: host,
                userInput: sshUser,
                portInput: sshPort,
                runtime: runtime,
                socketPath: socketPath
            ) else {
                return
            }
            newHost = hostDraft.makeDockerHost()

        case .tcpTLS:
            return
        }

        onSave(newHost)
        dismiss()
    }
}
