import Foundation
import Testing
import ViewInspector
@testable import ContainerBar

/// View-body coverage for `DashboardHeaderView` (CB-061).
///
/// The header is parameter/closure-injected (`isRefreshing`, `isSearching`,
/// `onRefresh`/`onSearch`/`onQuit`/`onSettings`) and reads no `@Environment`, so
/// its body is inspectable on this toolchain. These tests assert the title
/// renders, each of the four `HeaderButton`s carries its CB-052 identifier and
/// fires its closure, and the `isRefreshing` branch is real: the refresh button
/// is `.disabled(isRefreshing)`, so it reports disabled while refreshing and
/// enabled otherwise. Callbacks are asserted with `Button.tap()`, which runs
/// without a window server on the QA mini.
@MainActor
@Suite("DashboardHeaderView view body")
struct DashboardHeaderViewTests {

    private func inspectedHeader(
        isRefreshing: Bool = false,
        isSearching: Bool = false,
        onRefresh: @escaping () -> Void = {},
        onSearch: @escaping () -> Void = {},
        onQuit: @escaping () -> Void = {},
        onSettings: @escaping () -> Void = {}
    ) throws -> InspectableView<ViewType.View<DashboardHeaderView>> {
        try DashboardHeaderView(
            isRefreshing: isRefreshing,
            isSearching: isSearching,
            onRefresh: onRefresh,
            onSearch: onSearch,
            onQuit: onQuit,
            onSettings: onSettings
        )
        .inspect()
        .find(DashboardHeaderView.self)
    }

    @Test("App title renders")
    func titleRenders() throws {
        let header = try inspectedHeader()
        #expect(throws: Never.self) { try header.find(text: "ContainerBar") }
    }

    @Test("All four header buttons render with their CB-052 identifiers")
    func headerButtonsRender() throws {
        let header = try inspectedHeader()
        for identifier in ["refreshContainers", "toggleSearch", "quitApp", "openSettings"] {
            #expect(throws: Never.self) {
                try header.find(viewWithAccessibilityIdentifier: identifier)
            }
        }
    }

    @Test("Search, quit, and settings buttons fire their closures")
    func closuresFire() throws {
        var fired: [String] = []
        let header = try inspectedHeader(
            onSearch: { fired.append("search") },
            onQuit: { fired.append("quit") },
            onSettings: { fired.append("settings") }
        )

        try header.find(ViewType.Button.self, where: { try $0.accessibilityIdentifier() == "toggleSearch" }).tap()
        try header.find(ViewType.Button.self, where: { try $0.accessibilityIdentifier() == "quitApp" }).tap()
        try header.find(ViewType.Button.self, where: { try $0.accessibilityIdentifier() == "openSettings" }).tap()

        #expect(fired == ["search", "quit", "settings"])
    }

    @Test("Refresh button is enabled and fires when not refreshing")
    func refreshEnabledWhenIdle() throws {
        var refreshed = false
        let header = try inspectedHeader(isRefreshing: false, onRefresh: { refreshed = true })

        let refresh = try header.find(
            ViewType.Button.self,
            where: { try $0.accessibilityIdentifier() == "refreshContainers" }
        )
        #expect(refresh.isDisabled() == false)
        try refresh.tap()
        #expect(refreshed)
    }

    @Test("Refresh button is disabled while refreshing")
    func refreshDisabledWhileRefreshing() throws {
        let header = try inspectedHeader(isRefreshing: true)
        let refresh = try header.find(
            ViewType.Button.self,
            where: { try $0.accessibilityIdentifier() == "refreshContainers" }
        )
        #expect(refresh.isDisabled())
    }
}
