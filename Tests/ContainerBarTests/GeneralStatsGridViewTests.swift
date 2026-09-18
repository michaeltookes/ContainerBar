import Foundation
import Testing
import ViewInspector
@testable import ContainerBar
@testable import ContainerBarCore

/// View-body coverage for `GeneralStatsGrid` (CB-061).
///
/// The grid is parameter-injected (`metrics`, `history`) and reads no
/// `@Environment`, so its body is inspectable on this toolchain. These tests
/// assert the section header renders, the grid always emits its four
/// `MetricSparklineCard`s, the CPU/RAM tiles format their values from the
/// injected `ContainerMetricsSnapshot`, and the `nil`-metrics path falls back to
/// the zeroed placeholders the formatters produce. An empty
/// `AggregatedMetricsHistory` is injected so every card takes the no-data
/// placeholder branch rather than the Swift Charts subtree ViewInspector 0.10.3
/// does not model — the value labels these tests read are rendered regardless of
/// that branch.
@MainActor
@Suite("GeneralStatsGrid view body")
struct GeneralStatsGridViewTests {

    private func inspectedGrid(
        metrics: ContainerMetricsSnapshot?
    ) throws -> InspectableView<ViewType.View<GeneralStatsGrid>> {
        // Empty history -> hasData is false for every metric, so no Chart is built.
        try GeneralStatsGrid(metrics: metrics, history: AggregatedMetricsHistory(maxPoints: 30))
            .inspect()
            .find(GeneralStatsGrid.self)
    }

    @Test("Section header renders")
    func headerRenders() throws {
        let grid = try inspectedGrid(metrics: nil)
        #expect(throws: Never.self) { try grid.find(text: "GENERAL STATS") }
    }

    @Test("The grid always emits four metric cards")
    func fourCardsRender() throws {
        let grid = try inspectedGrid(metrics: .mock())
        #expect(grid.findAll(MetricSparklineCard.self).count == 4)
    }

    @Test("CPU and RAM tiles format their values from the injected snapshot")
    func tilesReflectSnapshot() throws {
        // .mock() -> totalCPUPercent 25.5, used 2 GB (2048 MB), limit 8 GB.
        let grid = try inspectedGrid(metrics: .mock())

        #expect(throws: Never.self) { try grid.find(text: "25.5%") }   // CPU
        #expect(throws: Never.self) { try grid.find(text: "2.0") }     // RAM value in GB
        #expect(throws: Never.self) { try grid.find(text: "GB / 8 GB") } // RAM subtitle
    }

    @Test("Nil metrics render the zeroed placeholder values")
    func nilMetricsRenderZeroes() throws {
        let grid = try inspectedGrid(metrics: nil)

        // formatPercent(0) -> "0.0%" for CPU; formatMemory(0) -> "0" for RAM.
        #expect(throws: Never.self) { try grid.find(text: "0.0%") }
        #expect(throws: Never.self) { try grid.find(text: "0") }
    }
}
