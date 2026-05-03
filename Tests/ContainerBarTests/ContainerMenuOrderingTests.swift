import Testing
@testable import ContainerBar
@testable import ContainerBarCore

@Suite("Container Menu Ordering")
struct ContainerMenuOrderingTests {

    @Test("Empty input produces empty output")
    func emptyInputIsEmpty() {
        let result = sortedFilteredContainersForMenu([], showStopped: true)
        #expect(result.isEmpty)
    }

    @Test("Running containers come before non-running ones")
    func runningBeforeStopped() {
        let containers: [DockerContainer] = [
            .mock(id: "a", name: "alpha", state: .exited),
            .mock(id: "b", name: "bravo", state: .running),
            .mock(id: "c", name: "charlie", state: .exited)
        ]

        let result = sortedFilteredContainersForMenu(containers, showStopped: true)

        #expect(result.map(\.id) == ["b", "a", "c"])
    }

    @Test("Within a tier, names are sorted case-insensitively")
    func caseInsensitiveSortWithinTier() {
        let containers: [DockerContainer] = [
            .mock(id: "1", name: "Bravo", state: .running),
            .mock(id: "2", name: "alpha", state: .running),
            .mock(id: "3", name: "Charlie", state: .running)
        ]

        let result = sortedFilteredContainersForMenu(containers, showStopped: true)

        // Case-insensitive: alpha < Bravo < Charlie
        #expect(result.map(\.id) == ["2", "1", "3"])
    }

    @Test("Stopped containers sort alphabetically among themselves")
    func stoppedTierIsAlphabetical() {
        let containers: [DockerContainer] = [
            .mock(id: "1", name: "zebra", state: .exited),
            .mock(id: "2", name: "apple", state: .exited),
            .mock(id: "3", name: "mango", state: .exited)
        ]

        let result = sortedFilteredContainersForMenu(containers, showStopped: true)

        #expect(result.map(\.id) == ["2", "3", "1"])
    }

    @Test("showStopped=false filters exited containers")
    func showStoppedFalseFiltersExited() {
        let containers: [DockerContainer] = [
            .mock(id: "r", name: "running-svc", state: .running),
            .mock(id: "e", name: "exited-svc", state: .exited)
        ]

        let result = sortedFilteredContainersForMenu(containers, showStopped: false)

        #expect(result.map(\.id) == ["r"])
    }

    @Test("showStopped=true keeps exited containers")
    func showStoppedTrueKeepsExited() {
        let containers: [DockerContainer] = [
            .mock(id: "r", name: "running-svc", state: .running),
            .mock(id: "e", name: "exited-svc", state: .exited)
        ]

        let result = sortedFilteredContainersForMenu(containers, showStopped: true)

        #expect(result.map(\.id) == ["r", "e"])
    }

    @Test("Paused and restarting containers are kept even when showStopped=false")
    func activeNonRunningStatesAreNeverFiltered() {
        let containers: [DockerContainer] = [
            .mock(id: "p", name: "paused-svc", state: .paused),
            .mock(id: "r", name: "restarting-svc", state: .restarting),
            .mock(id: "e", name: "exited-svc", state: .exited)
        ]

        let result = sortedFilteredContainersForMenu(containers, showStopped: false)

        // Both paused and restarting are .isActive == true; exited is filtered.
        // Neither is .running, so they sort to the bottom tier alphabetically.
        #expect(Set(result.map(\.id)) == ["p", "r"])
        #expect(result.map(\.id) == ["p", "r"])  // paused-svc < restarting-svc
    }

    @Test("All non-active terminal states are filtered when showStopped=false")
    func everyNonActiveTerminalStateFilters() {
        let containers: [DockerContainer] = [
            .mock(id: "ex", name: "ex", state: .exited),
            .mock(id: "de", name: "de", state: .dead),
            .mock(id: "cr", name: "cr", state: .created),
            .mock(id: "rm", name: "rm", state: .removing),
            .mock(id: "ru", name: "ru", state: .running)
        ]

        let result = sortedFilteredContainersForMenu(containers, showStopped: false)

        #expect(result.map(\.id) == ["ru"])
    }

    @Test("Running tier always wins regardless of name ordering")
    func runningWinsOverEarlierAlphabeticalNames() {
        let containers: [DockerContainer] = [
            .mock(id: "a", name: "aardvark", state: .exited),
            .mock(id: "z", name: "zebra", state: .running)
        ]

        let result = sortedFilteredContainersForMenu(containers, showStopped: true)

        // Even though "aardvark" sorts before "zebra", running wins.
        #expect(result.map(\.id) == ["z", "a"])
    }

    @Test("Mixed full set produces stable, predictable order")
    func mixedRealisticSet() {
        let containers: [DockerContainer] = [
            .mock(id: "1", name: "postgres", state: .running),
            .mock(id: "2", name: "Redis", state: .running),
            .mock(id: "3", name: "old-job", state: .exited),
            .mock(id: "4", name: "Adminer", state: .running),
            .mock(id: "5", name: "broken-worker", state: .dead)
        ]

        let result = sortedFilteredContainersForMenu(containers, showStopped: true)

        // Tier 1 (running, case-insensitive): Adminer, postgres, Redis
        // Tier 2 (non-running): broken-worker, old-job
        #expect(result.map(\.id) == ["4", "1", "2", "5", "3"])
    }
}
