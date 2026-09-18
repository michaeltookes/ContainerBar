import Foundation
import Testing
import ViewInspector
@testable import ContainerBar
@testable import ContainerBarCore

// MARK: - Known limitation (CB-060)
//
// `SectionsSettingsPane` reads `@Environment(SettingsStore.self)`. As documented
// in `GeneralSettingsPaneViewTests`, ViewInspector 0.10.3 on this toolchain
// (Swift 6.3.3 / macOS 26) cannot inspect the body of a view that reads an
// Observation-framework `@Environment(Type.self)` — it injects only classic
// `ObservableObject`s, and `SettingsStore` is `@Observable`, so body evaluation
// traps ("No Observable object of type SettingsStore found"). `ViewHosting`
// does not change this, and the source-hook workaround is disallowed on this
// branch.
//
// Section add/update/remove/reorder logic is covered today by
// `SettingsStoreHostSectionTests`. The intended view-body assertions are
// captured below and marked `.disabled` until ViewInspector gains Observation
// `@Environment` support. Do NOT remove `.disabled` without confirming that
// support — the bodies trap when run today.
@MainActor
@Suite("SectionsSettingsPane view body")
struct SectionsSettingsPaneViewTests {

    private static let blocked: Comment =
        "Blocked: ViewInspector 0.10.3 cannot inject Observation @Environment(SettingsStore.self); see file header (CB-060)."

    private func makePane(
        settings: SettingsStore
    ) throws -> InspectableView<ViewType.View<SectionsSettingsPane>> {
        try SectionsSettingsPane()
            .environment(settings)
            .inspect()
            .find(SectionsSettingsPane.self)
    }

    @Test("Empty store renders the empty state and the intro header", .disabled(blocked))
    func emptyStateRenders() throws {
        let settings = SettingsPaneViewTestSupport.isolatedSettingsStore()
        #expect(settings.sections.isEmpty)

        let pane = try makePane(settings: settings)

        #expect(throws: Never.self) {
            try pane.find(viewWithAccessibilityIdentifier: "sectionsIntro")
        }
        #expect(throws: Never.self) { try pane.find(text: "No sections defined") }
    }

    @Test("Each configured section renders a row with its edit and delete identifiers",
          .disabled(blocked))
    func rendersOneRowPerSection() throws {
        let settings = SettingsPaneViewTestSupport.isolatedSettingsStore()
        settings.addSection(ContainerSection(name: "Web"))
        settings.addSection(ContainerSection(name: "Databases"))
        #expect(settings.sections.count == 2)

        let pane = try makePane(settings: settings)

        for section in settings.sections {
            let editID = section.name.accessibilityIdentifier(prefix: "editSection", identity: section.id)
            let deleteID = section.name.accessibilityIdentifier(prefix: "deleteSection", identity: section.id)
            #expect(throws: Never.self) { try pane.find(viewWithAccessibilityIdentifier: editID) }
            #expect(throws: Never.self) { try pane.find(viewWithAccessibilityIdentifier: deleteID) }
            #expect(throws: Never.self) { try pane.find(text: section.name) }
        }
    }

    @Test("Populated store shows the live section count", .disabled(blocked))
    func showsSectionCount() throws {
        let settings = SettingsPaneViewTestSupport.isolatedSettingsStore()
        settings.addSection(ContainerSection(name: "Web"))
        settings.addSection(ContainerSection(name: "Databases"))
        settings.addSection(ContainerSection(name: "Media"))

        let pane = try makePane(settings: settings)

        #expect(throws: Never.self) { try pane.find(text: "3 section(s)") }
    }
}
