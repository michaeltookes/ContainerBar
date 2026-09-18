import Foundation
import Testing
import ViewInspector
@testable import ContainerBar
@testable import ContainerBarCore

// MARK: - Known limitation (CB-060)
//
// `ConnectionSettingsPane` reads `@Environment(SettingsStore.self)` and
// `@Environment(ContainerStore.self)`. As documented in
// `GeneralSettingsPaneViewTests`, ViewInspector 0.10.3 on this toolchain
// (Swift 6.3.3 / macOS 26) cannot inspect the body of a view that reads an
// Observation-framework `@Environment(Type.self)` — it injects only classic
// `ObservableObject`s, and both stores are `@Observable`, so body evaluation
// traps ("No Observable object of type SettingsStore found"). `ViewHosting`
// does not change this, and the source-hook workaround is disallowed on this
// branch.
//
// The pane also takes a `fetcherFactory`; the intent tests below inject one
// backed by `MockDockerAPIClient` (via `SettingsPaneViewTestSupport`) so that,
// once inspection is possible, no test can reach a real socket or SSH host.
// Host-management logic is covered today by `SettingsStoreHostSectionTests`.
// The intended view-body assertions are captured below and marked `.disabled`
// until ViewInspector gains Observation `@Environment` support. Do NOT remove
// `.disabled` without confirming that support — the bodies trap when run today.
@MainActor
@Suite("ConnectionSettingsPane view body")
struct ConnectionSettingsPaneViewTests {

    private static let blocked: Comment =
        "Blocked: ViewInspector 0.10.3 cannot inject Observation @Environment stores; see file header (CB-060)."

    private func makePane(
        settings: SettingsStore
    ) throws -> InspectableView<ViewType.View<ConnectionSettingsPane>> {
        let containerStore = SettingsPaneViewTestSupport.mockContainerStore(settings: settings)
        return try ConnectionSettingsPane(fetcherFactory: SettingsPaneViewTestSupport.mockFetcherFactory())
            .environment(settings)
            .environment(containerStore)
            .inspect()
            .find(ConnectionSettingsPane.self)
    }

    @Test("Host list renders exactly one row per configured host", .disabled(blocked))
    func rendersOneRowPerHost() throws {
        let settings = SettingsPaneViewTestSupport.isolatedSettingsStore()
        settings.addHost(DockerHost(
            name: "Beelink",
            connectionType: .ssh,
            host: "example.test",
            sshUser: "admin"
        ))
        #expect(settings.hosts.count == 2)

        let pane = try makePane(settings: settings)

        for host in settings.hosts {
            let identifier = host.name.accessibilityIdentifier(prefix: "hostRow", identity: host.id)
            #expect(throws: Never.self) {
                try pane.find(viewWithAccessibilityIdentifier: identifier)
            }
        }
    }

    @Test("Remove Host button is disabled when no host is selected", .disabled(blocked))
    func removeButtonDisabledWithoutSelection() throws {
        let settings = SettingsPaneViewTestSupport.isolatedSettingsStore()
        settings.addHost(DockerHost(name: "Beelink", connectionType: .ssh, host: "example.test"))

        let pane = try makePane(settings: settings)

        // `selectedHostId` starts nil, so Remove must be disabled even with >1 host.
        let removeButton = try pane.find(viewWithAccessibilityIdentifier: "removeSelectedHost")
        #expect(try removeButton.isDisabled())
    }

    @Test("Detail pane shows the empty-selection placeholder when no host is selected",
          .disabled(blocked))
    func detailPlaceholderWhenNoSelection() throws {
        let settings = SettingsPaneViewTestSupport.isolatedSettingsStore()
        let pane = try makePane(settings: settings)

        #expect(throws: Never.self) {
            try pane.find(text: "Select a host to view details")
        }
    }
}
