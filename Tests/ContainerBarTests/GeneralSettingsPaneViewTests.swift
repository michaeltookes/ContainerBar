import Foundation
import Testing
import ViewInspector
@testable import ContainerBar
@testable import ContainerBarCore

// MARK: - Known limitation (CB-060)
//
// `GeneralSettingsPane` reads `@Environment(SettingsStore.self)`. On this
// toolchain (Swift 6.3.3 / macOS 26) ViewInspector 0.10.3 cannot inspect the
// body of a view that reads an Observation-framework `@Environment(Type.self)`:
//
//   Fatal error: No Observable object of type SettingsStore found.
//
// ViewInspector evaluates `body` via reflection and only injects environment
// objects that conform to the *classic* `ObservableObject` protocol (see
// ViewInspector's `EnvironmentInjection` and `CustomViewModifier`; the
// `object is any ObservableObject` gate). `SettingsStore` is `@Observable`, so
// nothing is injected and the first line of the body traps. `ViewHosting` does
// not help — `.inspect()`/`.find()` re-evaluate `body` through reflection with
// ViewInspector's own (un-injected) medium, so hosting still traps. The only
// documented workaround is a source-level inspection hook (`didAppear` /
// `onReceive`) added to the view, which this branch disallows (the sole
// permitted view change was adding accessibility identifiers).
//
// The pane's underlying state/persistence logic is covered by
// `SettingsStoreTests` and `SettingsStoreHostSectionTests`. The intended
// view-body assertions are captured below but marked `.disabled` until
// ViewInspector gains Observation `@Environment` support (or the team opts to
// add inspection hooks). Do NOT remove `.disabled` without confirming the
// upstream/toolchain support first — the bodies trap when run today.
@MainActor
@Suite("GeneralSettingsPane view body")
struct GeneralSettingsPaneViewTests {

    private static let blocked: Comment =
        "Blocked: ViewInspector 0.10.3 cannot inject Observation @Environment(SettingsStore.self); see file header (CB-060)."

    @Test("Show Stopped Containers toggle reflects the store and flips it when tapped",
          .disabled(blocked))
    func showStoppedToggleIsBoundToStore() throws {
        let store = SettingsPaneViewTestSupport.isolatedSettingsStore()
        store.showStoppedContainers = true

        let pane = try GeneralSettingsPane()
            .environment(store)
            .inspect()
            .find(GeneralSettingsPane.self)

        let toggle = try pane.find(ViewType.Toggle.self, containing: "Show Stopped Containers")
        #expect(try toggle.isOn() == true)

        try toggle.tap()
        #expect(store.showStoppedContainers == false)
    }

    @Test("Refresh Interval picker is bound to the store and updates it on selection",
          .disabled(blocked))
    func refreshIntervalPickerUpdatesStore() throws {
        let store = SettingsPaneViewTestSupport.isolatedSettingsStore()
        store.refreshInterval = .seconds10

        let pane = try GeneralSettingsPane()
            .environment(store)
            .inspect()
            .find(GeneralSettingsPane.self)

        let picker = try pane.find(ViewType.Picker.self, containing: "Refresh Interval")
        try picker.select(value: RefreshInterval.minutes5)
        #expect(store.refreshInterval == .minutes5)
    }
}
