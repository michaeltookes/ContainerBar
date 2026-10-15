import Testing
@testable import ContainerBar

/// The dashboard's Add Remote Host hands off to Settings through a
/// `SettingsRoute` and a one-shot `SettingsNavigation` request (CB-078).
@MainActor
@Suite("Settings routing")
struct SettingsRouteTests {

    @Test("The dashboard's Add Remote Host routes to Connections with the Add Host sheet")
    func dashboardButtonRoute() {
        let route = SettingsRoute.dashboardAddRemoteHost
        #expect(route == .connections(addHost: true))
        #expect(route.tab == .connections)
        #expect(route.presentsAddHost)
    }

    @Test("A plain tab route selects that tab and presents nothing", arguments: SettingsTab.allCases)
    func tabRoute(tab: SettingsTab) {
        let route = SettingsRoute.tab(tab)
        #expect(route.tab == tab)
        #expect(!route.presentsAddHost)
    }

    @Test("Connections without addHost opens the tab only")
    func connectionsWithoutSheet() {
        let route = SettingsRoute.connections(addHost: false)
        #expect(route.tab == .connections)
        #expect(!route.presentsAddHost)
    }

    @Test("An add-host request is consumed exactly once")
    func requestConsumedOnce() {
        let navigation = SettingsNavigation()
        #expect(!navigation.pendingAddHost)
        #expect(!navigation.consumeAddHostRequest())

        navigation.requestAddHost()
        #expect(navigation.pendingAddHost)
        #expect(navigation.consumeAddHostRequest())
        #expect(!navigation.pendingAddHost)
        #expect(!navigation.consumeAddHostRequest())
    }

    @Test("Repeated requests before the pane consumes them present the sheet once")
    func repeatedRequestsCollapse() {
        let navigation = SettingsNavigation()
        navigation.requestAddHost()
        navigation.requestAddHost()
        #expect(navigation.consumeAddHostRequest())
        #expect(!navigation.consumeAddHostRequest())
    }
}
