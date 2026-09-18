import Foundation
import Testing
import ViewInspector
@testable import ContainerBar

/// View-body coverage for `AboutPane` (CB-060).
///
/// `AboutPane` takes no environment and holds no mutable state, so these tests
/// assert the structure the body promises: the version line carries its
/// accessibility identifier and is formatted from `Bundle.main` (under
/// `swift test` that is the test runner's bundle, so the view's fallback
/// values are what get exercised), both external links render, and the update
/// action is present. Kept `@MainActor` for
/// consistency with the rest of the settings-pane view suite.
@MainActor
@Suite("AboutPane view body")
struct AboutPaneViewTests {

    private func inspectedPane() throws -> InspectableView<ViewType.View<AboutPane>> {
        try AboutPane().inspect().find(AboutPane.self)
    }

    @Test("Version line carries the aboutVersion identifier and the real bundle version")
    func versionLineShowsBundleVersion() throws {
        let pane = try inspectedPane()

        let versionText = try pane.find(viewWithAccessibilityIdentifier: "aboutVersion").text().string()
        #expect(versionText.hasPrefix("Version "))

        // The label interpolates `Bundle.main`'s version and build number with the
        // same fallbacks the view uses; assert the format, not a hardcoded string.
        let expectedVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let expectedBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        #expect(versionText == "Version \(expectedVersion) (\(expectedBuild))")
    }

    @Test("App name and beta badge render")
    func nameAndBadgeRender() throws {
        let pane = try inspectedPane()

        #expect(throws: Never.self) { try pane.find(text: "ContainerBar") }
        #expect(throws: Never.self) { try pane.find(text: "Beta Preview") }
    }

    @Test("Both external reference links render")
    func referenceLinksRender() throws {
        let pane = try inspectedPane()

        #expect(throws: Never.self) {
            try pane.find(ViewType.Link.self, containing: "GitHub Repository")
        }
        #expect(throws: Never.self) {
            try pane.find(ViewType.Link.self, containing: "Docker API Documentation")
        }
        #expect(pane.findAll(ViewType.Link.self).count == 2)
    }

    @Test("Check for Updates button is present")
    func checkForUpdatesButtonPresent() throws {
        let pane = try inspectedPane()
        #expect(throws: Never.self) { try pane.find(button: "Check for Updates...") }
    }
}
