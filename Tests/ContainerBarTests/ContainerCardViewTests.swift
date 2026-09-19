import Foundation
import Testing
import ViewInspector
@testable import ContainerBar
@testable import ContainerBarCore

/// View-body coverage for `ContainerCardView` (CB-061).
///
/// `ContainerCardView` is fully parameter-injected (`container`, `stats`,
/// `onAction`) and reads no `@Environment`, so ViewInspector 0.10.3 can inspect
/// its body directly on this toolchain — no `ViewHosting` and none of the
/// Observation-`@Environment` limitation that blocks the Settings panes and the
/// env-reading Dashboard views (CB-060). These tests assert what the body
/// promises: the injected container's name and state chip render, the CPU/MEM
/// labels reflect the injected `ContainerStats` only while running, the no-stats
/// path drops those labels, the card carries its stable identifier, and the
/// quick-action button forwards the correct `ContainerAction` to `onAction`.
///
/// The action callback is asserted for real: `Button.tap()` invokes the stored
/// action closure synchronously without a window server (it reads
/// `action|closure` via reflection), so it runs under `swift test` over SSH on
/// the QA mini. The quick-action button sits behind `.opacity(0)` until hover,
/// but opacity is not `.hidden()`, so ViewInspector still treats it as
/// responsive and `tap()` fires.
@MainActor
@Suite("ContainerCardView view body")
struct ContainerCardViewTests {

    private func inspectedCard(
        container: DockerContainer,
        stats: ContainerStats?,
        onAction: @escaping (ContainerAction) -> Void = { _ in }
    ) throws -> InspectableView<ViewType.View<ContainerCardView>> {
        try ContainerCardView(container: container, stats: stats, onAction: onAction)
            .inspect()
            .find(ContainerCardView.self)
    }

    @Test("Container name and uppercased state chip render from the injected container")
    func nameAndStateRender() throws {
        let container = DockerContainer.mock(name: "nginx-proxy", state: .running)
        let card = try inspectedCard(container: container, stats: .mock())

        #expect(throws: Never.self) { try card.find(text: "nginx-proxy") }
        // The status chip renders `state.rawValue.uppercased()`.
        #expect(throws: Never.self) { try card.find(text: "RUNNING") }
    }

    @Test("The service icon receives the injected container")
    func serviceIconReceivesContainer() throws {
        let container = DockerContainer.mock(name: "grafana", state: .running)
        let card = try inspectedCard(container: container, stats: .mock())

        let icon = try card.find(ServiceIcon.self).actualView()
        #expect(icon.container.id == container.id)
    }

    @Test("Running card renders CPU/MEM labels derived from the injected stats")
    func cpuAndMemoryReflectStats() throws {
        let container = DockerContainer.mock(name: "api", state: .running)
        // 134_217_728 bytes == 128 MB; cpuPercent 2.3 -> "2.3%"; formatMemory -> "128 MB".
        let stats = ContainerStats.mock(cpuPercent: 2.3, memoryUsageBytes: 134_217_728)
        let card = try inspectedCard(container: container, stats: stats)

        #expect(throws: Never.self) { try card.find(text: "CPU") }
        #expect(throws: Never.self) { try card.find(text: "MEM") }
        #expect(throws: Never.self) { try card.find(text: "2.3%") }
        #expect(throws: Never.self) { try card.find(text: "128 MB") }
    }

    @Test("Memory formats to GB above 1024 MB")
    func memoryFormatsToGigabytes() throws {
        let container = DockerContainer.mock(name: "db", state: .running)
        // 1_610_612_736 bytes == 1536 MB == 1.5 GB -> "1.5 GB".
        let stats = ContainerStats.mock(cpuPercent: 12.0, memoryUsageBytes: 1_610_612_736)
        let card = try inspectedCard(container: container, stats: stats)

        #expect(throws: Never.self) { try card.find(text: "1.5 GB") }
    }

    @Test("Stopped card with no stats omits the CPU/MEM labels and shows its status text")
    func noStatsOmitsMetrics() throws {
        let container = DockerContainer.mock(
            name: "plex",
            state: .exited,
            status: "Exited (0) 2 hours ago"
        )
        let card = try inspectedCard(container: container, stats: nil)

        // The metrics row is gated on `.running` + non-nil stats, so it is absent.
        #expect(throws: (any Error).self) { try card.find(text: "CPU") }
        #expect(throws: (any Error).self) { try card.find(text: "MEM") }
        // A non-running container shows its raw status string.
        #expect(throws: Never.self) { try card.find(text: "Exited (0) 2 hours ago") }
        #expect(throws: Never.self) { try card.find(text: "EXITED") }
    }

    @Test("Card carries its containerCard-<slug> accessibility identifier")
    func cardCarriesIdentifier() throws {
        let container = DockerContainer.mock(name: "My Service", state: .running)
        let card = try inspectedCard(container: container, stats: .mock())

        let expected = "containerCard-" + container.displayName.accessibilitySlug
            .replacingOccurrences(of: "/", with: "-")
        #expect(throws: Never.self) {
            try card.find(viewWithAccessibilityIdentifier: expected)
        }
    }

    @Test("Tapping the quick action on a running container fires onAction(.stop)")
    func runningQuickActionStops() throws {
        let container = DockerContainer.mock(id: "run-1", name: "web", state: .running)
        var received: ContainerAction?
        let card = try inspectedCard(container: container, stats: .mock()) { received = $0 }

        try card.find(ViewType.Button.self).tap()

        guard case .stop(let id) = received else {
            Issue.record("Expected .stop, got \(String(describing: received))")
            return
        }
        #expect(id == container.id)
    }

    @Test("Tapping the quick action on an exited container fires onAction(.start)")
    func exitedQuickActionStarts() throws {
        let container = DockerContainer.mock(id: "exit-1", name: "worker", state: .exited)
        var received: ContainerAction?
        let card = try inspectedCard(container: container, stats: nil) { received = $0 }

        try card.find(ViewType.Button.self).tap()

        guard case .start(let id) = received else {
            Issue.record("Expected .start, got \(String(describing: received))")
            return
        }
        #expect(id == container.id)
    }
}
