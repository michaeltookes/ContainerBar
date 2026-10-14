import Foundation

/// Stable accessibility identifiers used by UI automation: the Prowl PR hunts and
/// the daily QA pass on the QA machine (CB-107). These strings are a contract with
/// the QA recipe, so they must not change once released.
///
/// Container-scoped identifiers share one slug so a card, its quick actions, and
/// its logs-panel row can be selected from the container name alone.
enum QAAccessibilityID {
    // MARK: Fixed identifiers

    static let statusItem = "containerBarStatusItem"
    static let connectionStatus = "connectionStatus"
    static let logsPanelText = "logsPanelText"
    static let checkForUpdatesGeneral = "checkForUpdates-general"
    static let checkForUpdatesAbout = "checkForUpdates-about"
    static let autoCheckUpdatesToggle = "autoCheckUpdatesToggle"
    static let showStoppedToggle = "showStoppedToggle"
    static let addSectionButton = "addSectionButton"

    // MARK: Container-scoped identifiers

    /// The container slug: the readable `accessibilitySlug` with `/` folded to `-`.
    /// Other characters (`_`, `.`) are kept as-is so existing `containerCard-` ids
    /// stay unchanged.
    static func containerSlug(_ name: String) -> String {
        name.accessibilitySlug.replacingOccurrences(of: "/", with: "-")
    }

    static func containerCard(_ name: String) -> String {
        "containerCard-" + containerSlug(name)
    }

    static func containerStop(_ name: String) -> String {
        "containerStop-" + containerSlug(name)
    }

    static func containerStart(_ name: String) -> String {
        "containerStart-" + containerSlug(name)
    }

    static func logsPanelRow(_ name: String) -> String {
        "logs-panel-container-" + containerSlug(name)
    }

    // MARK: Settings

    static func sectionRow(name: String, id: UUID) -> String {
        name.accessibilityIdentifier(prefix: "sectionRow", identity: id)
    }
}
