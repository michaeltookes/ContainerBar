import Foundation
import Testing
@testable import ContainerBar
@testable import ContainerBarCore

/// The dashboard's Add Remote Host hands off to Settings through a
/// `SettingsRoute` and a one-shot `SettingsNavigation` request (CB-078).
@MainActor
@Suite("Settings routing")
struct SettingsRouteTests {

    @Test("The dashboard's Add Remote Host routes to Connections with the Add Host sheet and activates the saved host")
    func dashboardButtonRoute() {
        let route = SettingsRoute.dashboardAddRemoteHost
        #expect(route == .connections(addHost: true, activateOnSave: true))
        #expect(route.tab == .connections)
        #expect(route.presentsAddHost)
        #expect(route.addHostRequest == AddHostRequest(activateOnSave: true))
    }

    @Test("A plain tab route selects that tab and presents nothing", arguments: SettingsTab.allCases)
    func tabRoute(tab: SettingsTab) {
        let route = SettingsRoute.tab(tab)
        #expect(route.tab == tab)
        #expect(!route.presentsAddHost)
        #expect(route.addHostRequest == nil)
    }

    @Test("Connections without addHost opens the tab only")
    func connectionsWithoutSheet() {
        let route = SettingsRoute.connections(addHost: false)
        #expect(route.tab == .connections)
        #expect(!route.presentsAddHost)
        #expect(route.addHostRequest == nil)
    }

    @Test("Connections with addHost alone does not activate the saved host")
    func connectionsSheetWithoutActivation() {
        #expect(SettingsRoute.connections(addHost: true).addHostRequest == AddHostRequest(activateOnSave: false))
    }

    @Test("An add-host request is consumed exactly once, with its activation flag")
    func requestConsumedOnce() {
        let navigation = SettingsNavigation()
        #expect(navigation.pendingAddHost == nil)
        #expect(navigation.consumeAddHostRequest() == nil)

        navigation.requestAddHost(AddHostRequest(activateOnSave: true))
        #expect(navigation.pendingAddHost != nil)
        #expect(navigation.consumeAddHostRequest() == AddHostRequest(activateOnSave: true))
        #expect(navigation.pendingAddHost == nil)
        #expect(navigation.consumeAddHostRequest() == nil)
    }

    @Test("Repeated requests before the pane consumes them present the sheet once, latest wins")
    func repeatedRequestsCollapse() {
        let navigation = SettingsNavigation()
        navigation.requestAddHost(AddHostRequest(activateOnSave: false))
        navigation.requestAddHost(AddHostRequest(activateOnSave: true))
        #expect(navigation.consumeAddHostRequest() == AddHostRequest(activateOnSave: true))
        #expect(navigation.consumeAddHostRequest() == nil)
    }

    // MARK: - Saving

    private func remoteHost(_ name: String) -> DockerHost {
        DockerHost(name: name, connectionType: .ssh, host: "\(name).invalid", sshUser: "cbqa")
    }

    @Test("A host saved from the dashboard route becomes the active host")
    func saveFromDashboardActivates() {
        let settings = SettingsPaneViewTestSupport.isolatedSettingsStore()
        let previous = settings.selectedHostId
        let host = remoteHost("cbqa-remote")

        let request = SettingsRoute.dashboardAddRemoteHost.addHostRequest
        ConnectionSettingsPane.saveAddedHost(host, in: settings, activate: request?.activateOnSave ?? false)

        #expect(settings.hosts.contains { $0.id == host.id })
        #expect(settings.selectedHostId == host.id)
        #expect(settings.selectedHostId != previous)
    }

    @Test("A host saved from Settings opened normally leaves the active host alone")
    func saveFromSettingsKeepsSelection() {
        let settings = SettingsPaneViewTestSupport.isolatedSettingsStore()
        let previous = settings.selectedHostId
        let host = remoteHost("cbqa-other")

        ConnectionSettingsPane.saveAddedHost(host, in: settings, activate: false)

        #expect(settings.hosts.contains { $0.id == host.id })
        #expect(settings.selectedHostId == previous)
    }
}
