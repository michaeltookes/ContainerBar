import Foundation
import ContainerBarCore
import Logging

/// Settings/preferences state management
///
/// Persists user preferences to UserDefaults and provides reactive
/// state updates for the UI.
@MainActor
@Observable
public final class SettingsStore {
    // MARK: - User Defaults Keys

    private enum Keys {
        static let refreshInterval = "refreshInterval"
        static let showStoppedContainers = "showStoppedContainers"
        static let launchAtLogin = "launchAtLogin"
        static let iconStyle = "iconStyle"
        static let dockerHosts = "dockerHosts"
        static let selectedHostId = "selectedHostId"
    }

    // MARK: - Properties

    private let userDefaults: UserDefaults
    private let logger = Logger(label: "com.containerbar.store.settings")

    /// How often to auto-refresh container data
    public var refreshInterval: RefreshInterval {
        didSet {
            userDefaults.set(refreshInterval.rawValue, forKey: Keys.refreshInterval)
            logger.info("Refresh interval changed to \(refreshInterval.displayName)")
        }
    }

    /// Whether to show stopped containers in the list
    public var showStoppedContainers: Bool {
        didSet {
            userDefaults.set(showStoppedContainers, forKey: Keys.showStoppedContainers)
        }
    }

    /// Whether to launch the app at login
    public var launchAtLogin: Bool {
        didSet {
            userDefaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            LaunchAtLoginManager.shared.setEnabled(launchAtLogin)
        }
    }

    /// Menu bar icon display style
    public var iconStyle: IconStyle {
        didSet {
            userDefaults.set(iconStyle.rawValue, forKey: Keys.iconStyle)
        }
    }

    /// Configured Docker hosts
    public private(set) var hosts: [DockerHost] = []

    /// Currently selected host ID
    public var selectedHostId: UUID? {
        didSet {
            if let id = selectedHostId {
                userDefaults.set(id.uuidString, forKey: Keys.selectedHostId)
            } else {
                userDefaults.removeObject(forKey: Keys.selectedHostId)
            }
        }
    }

    /// The currently selected Docker host
    public var selectedHost: DockerHost? {
        guard let id = selectedHostId else {
            return hosts.first { $0.isDefault } ?? hosts.first
        }
        return hosts.first { $0.id == id }
    }

    // MARK: - Initialization

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        // Load saved settings
        self.refreshInterval = RefreshInterval(
            rawValue: userDefaults.string(forKey: Keys.refreshInterval) ?? ""
        ) ?? .seconds10

        self.showStoppedContainers = userDefaults.object(forKey: Keys.showStoppedContainers) as? Bool ?? true

        // Sync launch at login from actual system state (may have been changed in System Settings)
        self.launchAtLogin = LaunchAtLoginManager.shared.isEnabled

        self.iconStyle = IconStyle(
            rawValue: userDefaults.string(forKey: Keys.iconStyle) ?? ""
        ) ?? .containerCount

        if let idString = userDefaults.string(forKey: Keys.selectedHostId) {
            self.selectedHostId = UUID(uuidString: idString)
        }

        loadHosts()

        // Ensure we have at least the local host configured
        if hosts.isEmpty {
            addHost(.local)
        }

        logger.info("SettingsStore initialized with \(hosts.count) host(s)")
    }

    // MARK: - Host Management

    /// Add a new Docker host configuration
    public func addHost(_ host: DockerHost) {
        var newHost = host

        // If this is the first host or marked as default, make it default
        if hosts.isEmpty || host.isDefault {
            // Clear existing defaults
            hosts = hosts.map { h in
                var updated = h
                updated.isDefault = false
                return updated
            }
            newHost.isDefault = true
        }

        hosts.append(newHost)
        saveHosts()

        logger.info("Added host: \(host.name)")
    }

    /// Update an existing Docker host configuration
    public func updateHost(_ host: DockerHost) {
        guard let index = hosts.firstIndex(where: { $0.id == host.id }) else {
            logger.warning("Attempted to update non-existent host: \(host.id)")
            return
        }

        hosts[index] = host
        saveHosts()

        logger.info("Updated host: \(host.name)")
    }

    /// Remove a Docker host configuration
    public func removeHost(id: UUID) {
        let wasDefault = hosts.first { $0.id == id }?.isDefault ?? false
        hosts.removeAll { $0.id == id }

        // If we removed the default, make the first remaining host default
        if wasDefault, var first = hosts.first {
            first.isDefault = true
            hosts[0] = first
        }

        // Clear selection if we removed the selected host
        if selectedHostId == id {
            selectedHostId = nil
        }

        saveHosts()

        logger.info("Removed host: \(id)")
    }

    /// Set a host as the default
    public func setDefaultHost(id: UUID) {
        hosts = hosts.map { h in
            var updated = h
            updated.isDefault = (h.id == id)
            return updated
        }
        saveHosts()
    }

    // MARK: - Persistence

    private func loadHosts() {
        guard let data = userDefaults.data(forKey: Keys.dockerHosts),
              let decoded = try? JSONDecoder().decode([DockerHost].self, from: data) else {
            logger.info("No saved hosts found, will use defaults")
            return
        }
        hosts = decoded
    }

    private func saveHosts() {
        guard let data = try? JSONEncoder().encode(hosts) else {
            logger.error("Failed to encode hosts for persistence")
            return
        }
        userDefaults.set(data, forKey: Keys.dockerHosts)
    }
}

// MARK: - Enums

/// Refresh interval options
public enum RefreshInterval: String, CaseIterable, Sendable {
    case seconds5 = "5s"
    case seconds10 = "10s"
    case seconds30 = "30s"
    case minute1 = "1m"
    case minutes5 = "5m"
    case manual = "manual"

    public var seconds: TimeInterval? {
        switch self {
        case .seconds5: return 5
        case .seconds10: return 10
        case .seconds30: return 30
        case .minute1: return 60
        case .minutes5: return 300
        case .manual: return nil
        }
    }

    public var displayName: String {
        switch self {
        case .seconds5: return "5 seconds"
        case .seconds10: return "10 seconds"
        case .seconds30: return "30 seconds"
        case .minute1: return "1 minute"
        case .minutes5: return "5 minutes"
        case .manual: return "Manual only"
        }
    }
}

/// Menu bar icon display styles
public enum IconStyle: String, CaseIterable, Sendable {
    case containerCount
    case cpuMemoryBars
    case healthIndicator

    public var displayName: String {
        switch self {
        case .containerCount: return "Container Count"
        case .cpuMemoryBars: return "CPU + Memory Bars"
        case .healthIndicator: return "Health Indicator"
        }
    }
}
