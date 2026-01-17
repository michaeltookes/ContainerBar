import Foundation

/// Represents a Docker container from the Docker API
public struct DockerContainer: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let names: [String]
    public let image: String
    public let imageID: String
    public let command: String
    public let created: Date
    public let state: ContainerState
    public let status: String
    public let ports: [PortMapping]
    public let labels: [String: String]
    public let networkMode: String?

    /// Primary container name (without leading slash)
    public var displayName: String {
        names.first?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? String(id.prefix(12))
    }

    public init(
        id: String,
        names: [String],
        image: String,
        imageID: String,
        command: String,
        created: Date,
        state: ContainerState,
        status: String,
        ports: [PortMapping],
        labels: [String: String],
        networkMode: String?
    ) {
        self.id = id
        self.names = names
        self.image = image
        self.imageID = imageID
        self.command = command
        self.created = created
        self.state = state
        self.status = status
        self.ports = ports
        self.labels = labels
        self.networkMode = networkMode
    }

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case names = "Names"
        case image = "Image"
        case imageID = "ImageID"
        case command = "Command"
        case created = "Created"
        case state = "State"
        case status = "Status"
        case ports = "Ports"
        case labels = "Labels"
        case networkMode = "HostConfig"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        names = try container.decode([String].self, forKey: .names)
        image = try container.decode(String.self, forKey: .image)
        imageID = try container.decode(String.self, forKey: .imageID)
        command = try container.decode(String.self, forKey: .command)

        let timestamp = try container.decode(Int.self, forKey: .created)
        created = Date(timeIntervalSince1970: TimeInterval(timestamp))

        let stateString = try container.decode(String.self, forKey: .state)
        state = ContainerState(rawValue: stateString.lowercased()) ?? .created

        status = try container.decode(String.self, forKey: .status)
        ports = try container.decodeIfPresent([PortMapping].self, forKey: .ports) ?? []
        labels = try container.decodeIfPresent([String: String].self, forKey: .labels) ?? [:]

        // NetworkMode is nested in HostConfig
        if let hostConfig = try? container.nestedContainer(keyedBy: HostConfigKeys.self, forKey: .networkMode) {
            networkMode = try hostConfig.decodeIfPresent(String.self, forKey: .networkMode)
        } else {
            networkMode = nil
        }
    }

    private enum HostConfigKeys: String, CodingKey {
        case networkMode = "NetworkMode"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(names, forKey: .names)
        try container.encode(image, forKey: .image)
        try container.encode(imageID, forKey: .imageID)
        try container.encode(command, forKey: .command)
        try container.encode(Int(created.timeIntervalSince1970), forKey: .created)
        try container.encode(state.rawValue, forKey: .state)
        try container.encode(status, forKey: .status)
        try container.encode(ports, forKey: .ports)
        try container.encode(labels, forKey: .labels)
    }
}

/// Container state enumeration
public enum ContainerState: String, Codable, Sendable, Equatable {
    case running
    case paused
    case restarting
    case exited
    case created
    case dead
    case removing

    public var isActive: Bool {
        self == .running || self == .paused || self == .restarting
    }

    public var displayColor: String {
        switch self {
        case .running: return "green"
        case .paused: return "yellow"
        case .restarting: return "orange"
        case .exited, .dead: return "red"
        case .created, .removing: return "gray"
        }
    }
}

/// Port mapping configuration
public struct PortMapping: Codable, Sendable, Equatable {
    public let privatePort: Int
    public let publicPort: Int?
    public let type: String
    public let ip: String?

    public init(privatePort: Int, publicPort: Int?, type: String, ip: String?) {
        self.privatePort = privatePort
        self.publicPort = publicPort
        self.type = type
        self.ip = ip
    }

    private enum CodingKeys: String, CodingKey {
        case privatePort = "PrivatePort"
        case publicPort = "PublicPort"
        case type = "Type"
        case ip = "IP"
    }
}

#if DEBUG
extension DockerContainer {
    /// Creates a mock container for testing and previews
    public static func mock(
        id: String = "abc123def456",
        name: String = "test-container",
        image: String = "nginx:latest",
        state: ContainerState = .running,
        status: String = "Up 2 hours"
    ) -> DockerContainer {
        DockerContainer(
            id: id,
            names: ["/\(name)"],
            image: image,
            imageID: "sha256:abc123",
            command: "nginx -g 'daemon off;'",
            created: Date().addingTimeInterval(-7200),
            state: state,
            status: status,
            ports: [PortMapping(privatePort: 80, publicPort: 8080, type: "tcp", ip: "0.0.0.0")],
            labels: [:],
            networkMode: "bridge"
        )
    }
}
#endif
