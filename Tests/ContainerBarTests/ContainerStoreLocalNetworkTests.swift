import Foundation
import Testing
@testable import ContainerBar
@testable import ContainerBarCore

/// The dashboard refresh path shows the Local Network guidance for a probed
/// denial and recovers once access is granted, without relaunching (CB-115).
@Suite("ContainerStore Local Network Tests")
@MainActor
struct ContainerStoreLocalNetworkTests {

    private func makeStore(probe: LocalNetworkProbeResult) -> (ContainerStore, MockDockerAPIClient) {
        let settings = SettingsStore(userDefaults: UserDefaults(suiteName: "test.\(UUID())")!)
        let host = DockerHost(
            name: "QA Runtime",
            connectionType: .ssh,
            runtime: .podman,
            isDefault: true,
            host: "cbqa-tunnel",
            sshUser: "cbqa-fwd"
        )
        settings.addHost(host)
        settings.selectedHostId = host.id

        let mock = MockDockerAPIClient()
        mock.mockContainers = [DockerContainer.mock(id: "c1", name: "cbqa-target", state: .running)]
        mock.shouldFail = true
        mock.failureError = DockerAPIError.sshConnectionFailed(
            "ssh: connect to host 10.0.0.5 port 22: No route to host"
        )

        let store = ContainerStore(
            settings: settings,
            fetcherFactory: { host in ContainerFetcher(client: mock, host: host ?? .local) },
            startRefreshLoop: false,
            observeSettings: false
        )
        store.connectionDiagnoser = LocalNetworkDiagnoser(
            resolver: StubRouteResolver(route: LocalNetworkDiagnosisTests.lanRoute),
            probe: StubLocalNetworkProbe(result: probe)
        )
        return (store, mock)
    }

    @Test("Denied: refresh shows the guidance, never the raw ssh line or the address")
    func deniedShowsGuidance() async {
        let (store, _) = makeStore(probe: .denied)

        await store.refresh()

        #expect(store.connectionError == LocalNetworkGuidance.message)
        #expect(store.connectionError?.contains("No route to host") == false)
        #expect(store.connectionError?.contains("10.0.0.5") == false)
        #expect(store.isConnected == false)
        #expect(store.isRefreshing == false)
    }

    @Test("Granted afterwards: the next refresh connects and clears the guidance")
    func recoversAfterGrant() async {
        let (store, mock) = makeStore(probe: .denied)
        await store.refresh()
        #expect(store.connectionError == LocalNetworkGuidance.message)

        mock.shouldFail = false
        await store.refresh()

        #expect(store.isConnected)
        #expect(store.connectionError == nil)
    }

    @Test("Real routing failure keeps the normal SSH message")
    func routingFailureKeepsSSHMessage() async {
        let (store, _) = makeStore(probe: .inconclusive)

        await store.refresh()

        #expect(store.connectionError?.hasPrefix("Can't reach QA Runtime over SSH.") == true)
        #expect(store.connectionError != LocalNetworkGuidance.message)
    }
}
