import Foundation

extension String {
    /// Lowercased, hyphenated form of a user-facing name, used to build stable
    /// accessibility identifiers such as `hostRow-<slug>-<id>` for UI automation.
    var accessibilitySlug: String {
        lowercased().replacingOccurrences(of: " ", with: "-")
    }

    func accessibilityIdentifier(prefix: String, identity: UUID) -> String {
        accessibilityIdentifier(prefix: prefix, identity: identity.uuidString)
    }

    func accessibilityIdentifier(prefix: String, identity: String) -> String {
        "\(prefix)-\(accessibilitySlug)-\(identity.lowercased())"
    }
}
