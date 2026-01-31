import Foundation

/// A user-defined section for organizing containers
public struct ContainerSection: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var sortOrder: Int
    public var matchRules: [MatchRule]

    public init(id: UUID = UUID(), name: String, sortOrder: Int = 0, matchRules: [MatchRule] = []) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.matchRules = matchRules
    }

    /// Rule for matching containers to this section
    public struct MatchRule: Codable, Equatable, Identifiable {
        public var id: UUID
        public var type: MatchType
        public var pattern: String

        public init(id: UUID = UUID(), type: MatchType, pattern: String) {
            self.id = id
            self.type = type
            self.pattern = pattern
        }
    }

    /// Types of matching rules
    public enum MatchType: String, Codable, CaseIterable {
        case containerNameContains = "Container name contains"
        case containerNameEquals = "Container name equals"
        case imageContains = "Image contains"
        case imageStartsWith = "Image starts with"
        case labelEquals = "Label equals"
        case composeProject = "Compose project"

        public var description: String { rawValue }
    }

    /// Check if a container matches any of this section's rules
    public func matches(containerName: String, image: String, labels: [String: String]) -> Bool {
        guard !matchRules.isEmpty else { return false }

        return matchRules.contains { rule in
            let pattern = rule.pattern.lowercased()
            switch rule.type {
            case .containerNameContains:
                return containerName.lowercased().contains(pattern)
            case .containerNameEquals:
                return containerName.lowercased() == pattern
            case .imageContains:
                return image.lowercased().contains(pattern)
            case .imageStartsWith:
                return image.lowercased().hasPrefix(pattern)
            case .labelEquals:
                // Format: "key=value"
                let parts = rule.pattern.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    let key = String(parts[0])
                    let value = String(parts[1]).lowercased()
                    return labels[key]?.lowercased() == value
                }
                return false
            case .composeProject:
                return labels["com.docker.compose.project"]?.lowercased() == pattern
            }
        }
    }
}
