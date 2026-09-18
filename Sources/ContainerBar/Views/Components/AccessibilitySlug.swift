import Foundation

extension String {
    /// Lowercased, hyphenated form of a user-facing name, used to build stable
    /// accessibility identifiers such as `hostRow-<slug>` for UI automation.
    var accessibilitySlug: String {
        lowercased().replacingOccurrences(of: " ", with: "-")
    }
}
