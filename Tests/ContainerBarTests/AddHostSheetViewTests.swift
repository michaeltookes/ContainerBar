import Foundation
import Testing
import ViewInspector
@testable import ContainerBar
@testable import ContainerBarCore

/// View-body coverage for `AddHostSheet` (CB-060).
///
/// `AddHostSheet` drives its whole form off private `@State` (name, host,
/// connection type, …) with no external injection point. ViewInspector can read
/// and assert the *initial* rendered state without hosting, but mutating that
/// `@State` from a test — typing into a field, switching the connection-type
/// picker — requires `ViewHosting`, which needs a live AppKit window server and
/// is therefore not available on the headless CI/QA runners this project builds
/// on. Adding an inspection hook to the view was disallowed for this branch
/// (only accessibility-identifier additions were permitted), so:
///
///   - The *disabled* direction of "Save is disabled until the form is valid" is
///     asserted here from the empty initial state (the SSH default requires a
///     host, so Add starts disabled).
///   - The *enabled* direction and the unix-socket field-swap are validation
///     logic that lives in `RemoteHostDraftBuilder`; that logic is covered
///     structurally by `RemoteHostDraftTests` and behaviorally by
///     `SettingsStoreHostSectionTests`. They are intentionally not re-driven
///     through this view.
@MainActor
@Suite("AddHostSheet view body")
struct AddHostSheetViewTests {

    private func inspectedSheet() throws -> InspectableView<ViewType.View<AddHostSheet>> {
        try AddHostSheet(onSave: { _ in }).inspect().find(AddHostSheet.self)
    }

    @Test("Add button is disabled for the empty initial form (SSH default needs a host)")
    func addButtonDisabledWhenFormEmpty() throws {
        let sheet = try inspectedSheet()
        let addButton = try sheet.find(viewWithAccessibilityIdentifier: "confirmAddHost")
        #expect(try addButton.isDisabled())
    }

    @Test("Cancel button renders and is always enabled")
    func cancelButtonEnabled() throws {
        let sheet = try inspectedSheet()
        let cancel = try sheet.find(viewWithAccessibilityIdentifier: "cancelAddHost")
        #expect(try cancel.isDisabled() == false)
    }

    @Test("SSH is the default connection type, so SSH fields render and the unix socket field does not")
    func sshFieldsRenderByDefault() throws {
        let sheet = try inspectedSheet()

        // SSH-only fields are present.
        #expect(throws: Never.self) { try sheet.find(ViewType.TextField.self, containing: "Host") }
        #expect(throws: Never.self) { try sheet.find(ViewType.TextField.self, containing: "SSH User") }
        #expect(throws: Never.self) { try sheet.find(ViewType.TextField.self, containing: "SSH Port") }
        #expect(throws: Never.self) { try sheet.find(ViewType.TextField.self, containing: "Remote Socket Path") }

        // The unix-socket-only field is absent while the SSH branch is active.
        #expect(sheet.findAll(ViewType.TextField.self).filter {
            (try? $0.labelView().text().string()) == "Socket Path"
        }.isEmpty)
    }

    @Test("SSH User field defaults to root")
    func sshUserDefaultsToRoot() throws {
        let sheet = try inspectedSheet()
        let userField = try sheet.find(ViewType.TextField.self, containing: "SSH User")
        #expect(try userField.input() == "root")
    }

    @Test("Runtime and Connection Type pickers render")
    func pickersRender() throws {
        let sheet = try inspectedSheet()
        #expect(throws: Never.self) { try sheet.find(ViewType.Picker.self, containing: "Runtime") }
        #expect(throws: Never.self) { try sheet.find(ViewType.Picker.self, containing: "Connection Type") }
    }
}
