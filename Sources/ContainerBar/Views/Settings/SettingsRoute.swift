import Observation

/// Where the Settings window opens, and whether it presents the Add Host
/// sheet once it is there (CB-078).
///
/// The dashboard's **Add Remote Host** button no longer has a form of its
/// own: it routes here so that the one `AddHostSheet` (runtime picker,
/// remote socket path, SSH target validation) is the only place a host is
/// entered. The route is a value handed to `SettingsWindowController`, not a
/// notification, so the caller and the window agree on exactly one request.
enum SettingsRoute: Equatable, Sendable {
    /// Open on a tab with nothing presented.
    case tab(SettingsTab)
    /// Open on Connections; `addHost: true` also presents the Add Host sheet.
    case connections(addHost: Bool)

    /// The route the dashboard host panel's Add Remote Host button takes.
    static let dashboardAddRemoteHost = SettingsRoute.connections(addHost: true)

    /// The tab the window shows for this route.
    var tab: SettingsTab {
        switch self {
        case .tab(let tab): return tab
        case .connections: return .connections
        }
    }

    /// Whether the Connections pane presents the Add Host sheet on arrival.
    var presentsAddHost: Bool {
        switch self {
        case .tab: return false
        case .connections(let addHost): return addHost
        }
    }
}

/// One-shot requests from the settings window controller to the panes it
/// hosts. The controller sets a request before it swaps in (or keeps) the
/// pane; the pane consumes it on appear or on change, so a request is acted
/// on exactly once whether or not the pane was already showing.
@MainActor
@Observable
final class SettingsNavigation {
    /// Set when the Connections pane should present the Add Host sheet.
    private(set) var pendingAddHost = false

    func requestAddHost() {
        pendingAddHost = true
    }

    /// Returns `true` once per request and clears it.
    func consumeAddHostRequest() -> Bool {
        guard pendingAddHost else { return false }
        pendingAddHost = false
        return true
    }
}
