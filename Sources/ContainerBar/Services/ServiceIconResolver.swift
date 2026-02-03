import Foundation
import AppKit
import ContainerBarCore

/// Resolves container images to their corresponding service icons
struct ServiceIconResolver {

    // MARK: - Singleton

    static let shared = ServiceIconResolver()

    // MARK: - Properties

    private let serviceMappings: [String: String]
    private let prefixMappings: [String: String]

    // MARK: - Initialization

    private init() {
        // Load mappings from bundled JSON
        if let url = Bundle.main.url(forResource: "service-icons", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            self.serviceMappings = json["services"] as? [String: String] ?? [:]
            self.prefixMappings = json["prefixMappings"] as? [String: String] ?? [:]
        } else {
            self.serviceMappings = Self.defaultMappings
            self.prefixMappings = Self.defaultPrefixMappings
        }
    }

    // MARK: - Public API

    /// Returns the icon name for a container, or nil if no match found
    func iconName(for container: DockerContainer) -> String? {
        return iconName(forImage: container.image)
    }

    /// Returns the icon name for an image string, or nil if no match found
    func iconName(forImage image: String) -> String? {
        let normalizedImage = normalizeImage(image)

        // Try exact match first
        if let icon = serviceMappings[normalizedImage] {
            return icon
        }

        // Try matching individual segments
        let segments = extractSegments(from: normalizedImage)
        for segment in segments {
            if let icon = serviceMappings[segment] {
                return icon
            }
        }

        return nil
    }

    /// Extracts the service name from a container image
    func extractServiceName(from image: String) -> String? {
        let normalizedImage = normalizeImage(image)
        let segments = extractSegments(from: normalizedImage)

        // Return the most likely service name (usually the last non-tag segment)
        return segments.first { serviceMappings[$0] != nil } ?? segments.last
    }

    /// Check if a service icon exists in the bundle
    func hasIcon(named name: String) -> Bool {
        // Check if we have this icon in our assets
        return Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "ServiceIcons") != nil
            || NSImage(named: name) != nil
    }

    // MARK: - Private Helpers

    /// Normalizes an image name by removing registry prefixes and tags
    private func normalizeImage(_ image: String) -> String {
        var normalized = image.lowercased()

        // Remove known prefixes
        for (prefix, _) in prefixMappings {
            if normalized.hasPrefix(prefix) {
                normalized = String(normalized.dropFirst(prefix.count))
                break
            }
        }

        // Remove tag (everything after :)
        if let colonIndex = normalized.firstIndex(of: ":") {
            normalized = String(normalized[..<colonIndex])
        }

        // Remove digest (everything after @)
        if let atIndex = normalized.firstIndex(of: "@") {
            normalized = String(normalized[..<atIndex])
        }

        return normalized
    }

    /// Extracts meaningful segments from an image name
    private func extractSegments(from image: String) -> [String] {
        // Split by / and return all segments
        let parts = image.split(separator: "/").map(String.init)

        // For "grafana/grafana", return ["grafana", "grafana"]
        // For "linuxserver/plex", return ["linuxserver", "plex"]
        var segments: [String] = []

        for part in parts {
            // Also split by - for names like "nginx-proxy-manager"
            let subParts = part.split(separator: "-").map(String.init)
            segments.append(contentsOf: subParts)
            segments.append(part) // Also include the full part
        }

        // Remove duplicates while preserving order
        var seen = Set<String>()
        return segments.filter { seen.insert($0).inserted }
    }

    // MARK: - Default Mappings (Fallback)

    private static let defaultMappings: [String: String] = [
        "nginx": "nginx",
        "redis": "redis",
        "postgres": "postgresql",
        "mysql": "mysql",
        "mongo": "mongodb",
        "grafana": "grafana",
        "prometheus": "prometheus",
        "plex": "plex",
        "jellyfin": "jellyfin",
        "portainer": "portainer",
        "traefik": "traefik",
        "pihole": "pihole",
        "homeassistant": "homeassistant",
        "nextcloud": "nextcloud",
    ]

    private static let defaultPrefixMappings: [String: String] = [
        "linuxserver/": "",
        "lscr.io/linuxserver/": "",
        "ghcr.io/": "",
        "docker.io/": "",
        "library/": "",
    ]
}

// MARK: - DockerContainer Extension

extension DockerContainer {
    /// The service icon name for this container, if available
    var serviceIconName: String? {
        ServiceIconResolver.shared.iconName(for: self)
    }

    /// Whether this container has a known service icon
    var hasServiceIcon: Bool {
        serviceIconName != nil
    }
}
