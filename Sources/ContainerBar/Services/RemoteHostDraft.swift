import Foundation
import ContainerBarCore

struct RemoteHostDraft: Sendable {
    let name: String
    let runtime: ContainerRuntime
    let socketPath: String?
    let host: String
    let sshUser: String
    let sshPort: Int

    func makeDockerHost() -> DockerHost {
        DockerHost(
            name: name,
            connectionType: .ssh,
            runtime: runtime,
            isDefault: false,
            socketPath: socketPath,
            host: host,
            sshUser: sshUser,
            sshPort: sshPort
        )
    }
}

enum RemoteHostDraftBuilder {
    enum ValidationError: LocalizedError {
        case emptyHost
        case invalidPort

        var errorDescription: String? {
            switch self {
            case .emptyHost:
                return "Host is required."
            case .invalidPort:
                return "SSH port must be between 1 and 65535."
            }
        }
    }

    static func isValid(
        nameInput: String,
        hostInput: String,
        userInput: String,
        portInput: String? = nil,
        runtime: ContainerRuntime = .docker,
        socketPath: String? = nil
    ) -> Bool {
        (try? build(
            nameInput: nameInput,
            hostInput: hostInput,
            userInput: userInput,
            portInput: portInput,
            runtime: runtime,
            socketPath: socketPath
        )) != nil
    }

    static func build(
        nameInput: String,
        hostInput: String,
        userInput: String,
        portInput: String? = nil,
        runtime: ContainerRuntime = .docker,
        socketPath: String? = nil
    ) throws -> RemoteHostDraft {
        let trimmedName = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSocketPath = socketPath?.trimmingCharacters(in: .whitespacesAndNewlines)

        let (parsedHost, inlinePort) = try parseHostAndInlinePort(from: hostInput)
        let port = try resolvePort(portInput, inlinePort: inlinePort)

        return RemoteHostDraft(
            name: trimmedName.isEmpty ? "Remote Host" : trimmedName,
            runtime: runtime,
            socketPath: trimmedSocketPath?.isEmpty == true ? nil : trimmedSocketPath,
            host: parsedHost,
            sshUser: trimmedUser.isEmpty ? "root" : trimmedUser,
            sshPort: port
        )
    }

    private static func resolvePort(_ portInput: String?, inlinePort: Int?) throws -> Int {
        let trimmedPort = portInput?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !trimmedPort.isEmpty {
            return try parsePort(trimmedPort)
        }

        if let inlinePort {
            return inlinePort
        }

        return 22
    }

    private static func parseHostAndInlinePort(from hostInput: String) throws -> (String, Int?) {
        let trimmedHost = hostInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            throw ValidationError.emptyHost
        }

        if trimmedHost.hasPrefix("["),
           let closingBracket = trimmedHost.firstIndex(of: "]") {
            let hostStart = trimmedHost.index(after: trimmedHost.startIndex)
            let host = String(trimmedHost[hostStart..<closingBracket]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !host.isEmpty else {
                throw ValidationError.emptyHost
            }

            let remainder = trimmedHost[trimmedHost.index(after: closingBracket)...]
            if remainder.isEmpty {
                return (host, nil)
            }

            if remainder.first == ":" {
                let portString = String(remainder.dropFirst())
                return (host, try parsePort(portString))
            }
        }

        let colonCount = trimmedHost.reduce(into: 0) { count, character in
            if character == ":" {
                count += 1
            }
        }

        if colonCount == 1,
           let separator = trimmedHost.lastIndex(of: ":") {
            let parsedHost = String(trimmedHost[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let parsedPort = String(trimmedHost[trimmedHost.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)

            if !parsedHost.isEmpty, !parsedPort.isEmpty, parsedPort.allSatisfy(\.isNumber) {
                return (parsedHost, try parsePort(parsedPort))
            }
        }

        return (trimmedHost, nil)
    }

    private static func parsePort(_ portInput: String) throws -> Int {
        guard let port = Int(portInput), (1...65535).contains(port) else {
            throw ValidationError.invalidPort
        }
        return port
    }
}
