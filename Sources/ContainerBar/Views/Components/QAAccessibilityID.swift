import Foundation

/// Stable accessibility identifiers used by UI automation: the Prowl PR hunts and
/// the daily QA pass on the QA machine (CB-107). These strings are a contract with
/// the QA recipe, so they must not change once released.
///
/// Container-scoped identifiers share one name slug, so a card, its quick actions,
/// and its logs-panel row can be found from the container name. The quick actions
/// and the logs-panel row also end in the container's short id, because two valid
/// container names can share a slug (`Web` and `web`): QA selects them by the
/// prefix `<kind>-<slug>-` and the id keeps every identifier unique.
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

    static func containerStop(name: String, id: String) -> String {
        containerScoped("containerStop", name: name, id: id)
    }

    static func containerStart(name: String, id: String) -> String {
        containerScoped("containerStart", name: name, id: id)
    }

    static func logsPanelRow(name: String, id: String) -> String {
        containerScoped("logs-panel-container", name: name, id: id)
    }

    /// Docker's short id: the first 12 characters of the container id, lowercased.
    static func shortContainerID(_ id: String) -> String {
        String(id.prefix(12)).lowercased()
    }

    /// `<prefix>-<slug>-<short id>`: readable from the name, unique by the id.
    private static func containerScoped(_ prefix: String, name: String, id: String) -> String {
        "\(prefix)-\(containerSlug(name))-\(shortContainerID(id))"
    }

    // MARK: Settings

    static func sectionRow(name: String, id: UUID) -> String {
        name.accessibilityIdentifier(prefix: "sectionRow", identity: id)
    }
}
