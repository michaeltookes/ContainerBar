import Foundation
import Testing
import ViewInspector
@testable import ContainerBar
@testable import ContainerBarCore

/// View-body coverage for `HostPickerView` (CB-061).
///
/// The picker is parameter-injected (`hosts`, `selectedHostId`, `onSelectHost`)
/// and reads no `@Environment`, so its body — including the private
/// `HostPillButton` rows, which ViewInspector descends into automatically during
/// `find`/`findAll` — is inspectable on this toolchain. These tests assert one
/// pill renders per host with its stable `hostPill-<slug>-<uuid>` identifier and
/// `Switch to host <name>` label, and that tapping a pill fires
/// `onSelectHost(host.id)` for that specific host (asserted with `Button.tap()`,
/// which needs no window server on the QA mini).
///
/// Not asserted: the *selected* pill's visual state — the `.isSelected`
/// accessibility trait, the semibold name weight, and the accent fill/border.
/// ViewInspector 0.10.3 exposes readers for accessibility label/value/hint/
/// identifier/hidden but none for added traits, and the weight is baked into a
/// `.font(.system(size:weight:))` rather than a separate `.fontWeight()`
/// modifier the inspector can read. Selection is therefore covered behaviorally
/// through the `onSelectHost` callback instead of by reading the styling.
@MainActor
@Suite("HostPickerView view body")
struct HostPickerViewTests {

    private func hosts() -> [DockerHost] {
        [
            DockerHost(id: UUID(), name: "Beelink Docker", connectionType: .ssh, runtime: .docker),
            DockerHost(id: UUID(), name: "Beelink Podman", connectionType: .ssh, runtime: .podman)
        ]
    }

    private func inspectedPicker(
        hosts: [DockerHost],
        selectedHostId: UUID? = nil,
        onSelectHost: @escaping (UUID) -> Void = { _ in }
    ) throws -> InspectableView<ViewType.View<HostPickerView>> {
        try HostPickerView(
            hosts: hosts,
            selectedHostId: selectedHostId,
            onSelectHost: onSelectHost
        )
        .inspect()
        .find(HostPickerView.self)
    }

    @Test("One pill renders per host, each with its hostPill identifier")
    func onePillPerHost() throws {
        let hosts = hosts()
        let picker = try inspectedPicker(hosts: hosts)

        #expect(picker.findAll(ViewType.Button.self).count == hosts.count)
        for host in hosts {
            let identifier = host.name.accessibilityIdentifier(prefix: "hostPill", identity: host.id)
            #expect(throws: Never.self) {
                try picker.find(viewWithAccessibilityIdentifier: identifier)
            }
        }
    }

    @Test("Each pill carries a Switch to host <name> accessibility label")
    func pillLabels() throws {
        let hosts = hosts()
        let picker = try inspectedPicker(hosts: hosts)

        for host in hosts {
            let identifier = host.name.accessibilityIdentifier(prefix: "hostPill", identity: host.id)
            let pill = try picker.find(viewWithAccessibilityIdentifier: identifier)
            #expect(try pill.accessibilityLabel().string() == "Switch to host \(host.name)")
        }
    }

    @Test("Tapping a pill fires onSelectHost with that host's id")
    func tapSelectsHost() throws {
        let hosts = hosts()
        var selected: UUID?
        let picker = try inspectedPicker(hosts: hosts) { selected = $0 }

        let second = hosts[1]
        let identifier = second.name.accessibilityIdentifier(prefix: "hostPill", identity: second.id)
        try picker.find(
            ViewType.Button.self,
            where: { try $0.accessibilityIdentifier() == identifier }
        ).tap()

        #expect(selected == second.id)
    }
}
