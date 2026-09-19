import Foundation
import Testing
import ViewInspector
@testable import ContainerBar
@testable import ContainerBarCore

/// View-body coverage for `ContainerGroupView` (CB-061).
///
/// `ContainerGroupView` is parameter-injected (`group`, `stats`, `onAction`) and
/// reads no `@Environment`, so its body is inspectable on this toolchain. It is
/// the *inner* view of the grouping hierarchy: `ContainerListSection` (same
/// file) is the one that reads `@Environment(SettingsStore.self)` and is blocked
/// by the CB-060 Observation-`@Environment` limitation, but that view is never
/// evaluated here — a `ContainerGroupView` only contains `ContainerCardView`s
/// (also env-free), so inspecting it transitively evaluates nothing that traps.
/// `ContainerListSection`'s grouping logic is already covered by
/// `ContainerGroupingTests`.
///
/// These tests assert the header's derived state: the group name renders, the
/// running/total count badge is computed from the injected group (asserted for a
/// mixed running/stopped group), the collapsible header carries its
/// accessibility identifier and a count-aware VoiceOver label, and — with the
/// header expanded by default — one `ContainerCardView` is emitted per member.
@MainActor
@Suite("ContainerGroupView view body")
struct ContainerGroupViewTests {

    private func mixedGroup() -> ContainerGroup {
        ContainerGroup(
            id: "web-stack",
            name: "Web Stack",
            containers: [
                .mock(id: "c1", name: "nginx", state: .running),
                .mock(id: "c2", name: "api", state: .running),
                .mock(id: "c3", name: "backup", state: .exited)
            ]
        )
    }

    private func inspectedGroup(
        _ group: ContainerGroup
    ) throws -> InspectableView<ViewType.View<ContainerGroupView>> {
        try ContainerGroupView(group: group, stats: [:], onAction: { _ in })
            .inspect()
            .find(ContainerGroupView.self)
    }

    @Test("Header renders the group name")
    func headerRendersName() throws {
        let view = try inspectedGroup(mixedGroup())
        #expect(throws: Never.self) { try view.find(text: "Web Stack") }
    }

    @Test("Count badge shows runningCount/totalCount for a mixed group")
    func countBadgeReflectsGroup() throws {
        let group = mixedGroup()
        #expect(group.runningCount == 2)
        #expect(group.totalCount == 3)

        let view = try inspectedGroup(group)
        // Badge text is "\(runningCount)/\(totalCount)".
        #expect(throws: Never.self) { try view.find(text: "2/3") }
    }

    @Test("Header button carries its identifier and a count-aware VoiceOver label")
    func headerCarriesIdentifierAndLabel() throws {
        let group = mixedGroup()
        let view = try inspectedGroup(group)

        let identifier = group.name.accessibilityIdentifier(
            prefix: "containerGroup",
            identity: group.id
        )
        let header = try view.find(viewWithAccessibilityIdentifier: identifier)
        // Default state is expanded, so the label offers to collapse and states
        // the running/total count in words.
        #expect(try header.accessibilityLabel().string()
            == "Collapse Web Stack group, 2 of 3 containers running")
    }

    @Test("Expanded group emits one ContainerCardView per member")
    func oneCardPerContainer() throws {
        let group = mixedGroup()
        let view = try inspectedGroup(group)

        // isExpanded defaults to true, so every member card is present.
        #expect(view.findAll(ContainerCardView.self).count == group.totalCount)
    }

    @Test("Single-container group uses the singular container noun in its label")
    func singularCountLabel() throws {
        let group = ContainerGroup(
            id: "solo",
            name: "Solo",
            containers: [.mock(id: "only", name: "only", state: .running)]
        )
        let view = try inspectedGroup(group)

        let identifier = group.name.accessibilityIdentifier(
            prefix: "containerGroup",
            identity: group.id
        )
        let header = try view.find(viewWithAccessibilityIdentifier: identifier)
        #expect(try header.accessibilityLabel().string()
            == "Collapse Solo group, 1 of 1 container running")
    }
}
