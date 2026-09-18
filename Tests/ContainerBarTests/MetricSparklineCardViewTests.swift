import Foundation
import SwiftUI
import Testing
import ViewInspector
@testable import ContainerBar
@testable import ContainerBarCore

/// View-body coverage for `MetricSparklineCard` (CB-061).
///
/// The card is fully parameter-injected (`title`, `value`, `subtitle`,
/// `history`, `tint`, `icon`) and reads no `@Environment`, so its body is
/// inspectable on this toolchain. These tests assert the title/value render from
/// the injected strings, the optional subtitle renders only when supplied, and
/// the no-data branch of the injected `MetricsHistory` renders the "..."
/// placeholder (`history.hasData` is `count >= 2`, so a history with fewer than
/// two points takes that branch).
///
/// **Limitation (documented, `.disabled` intent test below):** the *populated*
/// branch builds a Swift `Charts.Chart`, and inspecting a card that contains one
/// traps the swift-testing process with SIGTRAP (signal 5) on this toolchain —
/// ViewInspector 0.10.3 does not model the Swift Charts view tree, and any
/// `find`/`findAll` that traverses into the `Chart` subtree crashes rather than
/// throwing a catchable error. So every executable test here injects a
/// sub-threshold history (0–1 points) to keep the card on the placeholder
/// branch, and the chart-branch assertion is captured as a `.disabled` intent
/// test to enable once ViewInspector gains Swift Charts support. Do NOT remove
/// `.disabled` without confirming that support — the body crashes the test
/// runner when run today. The `hasData` threshold itself is model logic covered
/// in `ContainerBarCore`.
@MainActor
@Suite("MetricSparklineCard view body")
struct MetricSparklineCardViewTests {

    private static let chartBlocked: Comment =
        "Blocked: ViewInspector 0.10.3 traps (SIGTRAP) traversing a Swift Charts subtree; see file header (CB-061)."

    private func history(pointCount: Int) -> MetricsHistory {
        var history = MetricsHistory(maxPoints: 30)
        for index in 0..<pointCount {
            history.append(Double(index * 10 + 5))
        }
        return history
    }

    private func inspectedCard(
        title: String = "CPU",
        value: String = "23.4%",
        subtitle: String? = nil,
        history: MetricsHistory
    ) throws -> InspectableView<ViewType.View<MetricSparklineCard>> {
        try MetricSparklineCard(
            title: title,
            value: value,
            subtitle: subtitle,
            history: history,
            tint: .blue,
            icon: "cpu"
        )
        .inspect()
        .find(MetricSparklineCard.self)
    }

    @Test("Title and value render from the injected strings")
    func titleAndValueRender() throws {
        let card = try inspectedCard(title: "RAM", value: "2.4 GB", history: history(pointCount: 0))
        #expect(throws: Never.self) { try card.find(text: "RAM") }
        #expect(throws: Never.self) { try card.find(text: "2.4 GB") }
    }

    @Test("Subtitle renders when supplied")
    func subtitleRendersWhenSupplied() throws {
        let card = try inspectedCard(value: "367", subtitle: "KB/s", history: history(pointCount: 0))
        #expect(throws: Never.self) { try card.find(text: "KB/s") }
    }

    @Test("Subtitle is absent when nil")
    func subtitleAbsentWhenNil() throws {
        let card = try inspectedCard(value: "367", subtitle: nil, history: history(pointCount: 0))
        #expect(throws: (any Error).self) { try card.find(text: "KB/s") }
    }

    @Test("An empty history (fewer than 2 points) renders the placeholder, not a chart")
    func emptyHistoryShowsPlaceholder() throws {
        // One point is below the hasData threshold of 2, so the no-data branch runs.
        let card = try inspectedCard(history: history(pointCount: 1))
        #expect(throws: Never.self) { try card.find(text: "...") }
    }

    @Test("A populated history takes the chart branch, so the placeholder is absent",
          .disabled(chartBlocked))
    func populatedHistoryShowsChart() throws {
        let card = try inspectedCard(history: history(pointCount: 5))
        // The value still renders on the chart branch...
        #expect(throws: Never.self) { try card.find(text: "23.4%") }
        // ...and the no-data placeholder is gone, proving history.hasData was consumed.
        // (Blocked: traversing the Chart subtree to confirm the placeholder's
        // absence crashes the runner on this toolchain — see file header.)
        #expect(throws: (any Error).self) { try card.find(text: "...") }
    }
}
