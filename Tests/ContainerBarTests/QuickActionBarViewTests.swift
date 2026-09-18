import Foundation
import Testing
import ViewInspector
@testable import ContainerBar

/// View-body coverage for `QuickActionBar` (CB-061).
///
/// `QuickActionBar` is closure-injected only (`onRefresh`/`onHosts`/`onLogs`/
/// `onSettings`) and reads no `@Environment`, so its body is inspectable on this
/// toolchain. Each of its four `ActionBarButton`s carries a stable CB-052
/// identifier (`actionBar-refresh/hosts/logs/settings`); these tests locate each
/// button by that identifier and assert `tap()` fires the matching closure.
///
/// The callbacks are asserted for real — ViewInspector's `Button.tap()` invokes
/// the stored action closure synchronously without a window server, so it runs
/// under `swift test` over SSH on the QA mini.
@MainActor
@Suite("QuickActionBar view body")
struct QuickActionBarViewTests {

    private func inspectedBar(
        onRefresh: @escaping () -> Void = {},
        onHosts: @escaping () -> Void = {},
        onLogs: @escaping () -> Void = {},
        onSettings: @escaping () -> Void = {}
    ) throws -> InspectableView<ViewType.View<QuickActionBar>> {
        try QuickActionBar(
            onRefresh: onRefresh,
            onHosts: onHosts,
            onLogs: onLogs,
            onSettings: onSettings
        )
        .inspect()
        .find(QuickActionBar.self)
    }

    @Test("All four action buttons render with their CB-052 identifiers")
    func allButtonsRender() throws {
        let bar = try inspectedBar()
        for identifier in ["actionBar-refresh", "actionBar-hosts", "actionBar-logs", "actionBar-settings"] {
            #expect(throws: Never.self) {
                try bar.find(viewWithAccessibilityIdentifier: identifier)
            }
        }
    }

    @Test("The visible button titles render")
    func titlesRender() throws {
        let bar = try inspectedBar()
        for title in ["Refresh", "Hosts", "Logs", "Settings"] {
            #expect(throws: Never.self) { try bar.find(text: title) }
        }
    }

    @Test("Tapping each button fires exactly its own closure")
    func tapsFireMatchingClosures() throws {
        var fired: [String] = []
        let bar = try inspectedBar(
            onRefresh: { fired.append("refresh") },
            onHosts: { fired.append("hosts") },
            onLogs: { fired.append("logs") },
            onSettings: { fired.append("settings") }
        )

        try bar.find(ViewType.Button.self, where: { try $0.accessibilityIdentifier() == "actionBar-refresh" }).tap()
        #expect(fired == ["refresh"])

        try bar.find(ViewType.Button.self, where: { try $0.accessibilityIdentifier() == "actionBar-hosts" }).tap()
        #expect(fired == ["refresh", "hosts"])

        try bar.find(ViewType.Button.self, where: { try $0.accessibilityIdentifier() == "actionBar-logs" }).tap()
        #expect(fired == ["refresh", "hosts", "logs"])

        try bar.find(ViewType.Button.self, where: { try $0.accessibilityIdentifier() == "actionBar-settings" }).tap()
        #expect(fired == ["refresh", "hosts", "logs", "settings"])
    }
}
