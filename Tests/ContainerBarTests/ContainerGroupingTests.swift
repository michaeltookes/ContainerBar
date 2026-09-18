import Foundation
import Testing
@testable import ContainerBar
@testable import ContainerBarCore

/// Covers the pure `ContainerGroup` counts and the extracted
/// `ContainerListSection.groupContainers(_:into:)` transform. The grouping
/// helper was lifted verbatim out of the view (see the refactor commit); these
/// tests pin the behavior it must preserve: section ordering by `sortOrder`,
/// first-match membership, omission of empty sections, and a sorted ungrouped
/// remainder (running first, then by display name).
@Suite("Container grouping")
@MainActor
struct ContainerGroupingTests {

    private func container(
        id: String,
        name: String,
        image: String = "nginx:latest",
        state: ContainerState = .running
    ) -> DockerContainer {
        .mock(id: id, name: name, image: image, state: state)
    }

    private func section(
        name: String,
        sortOrder: Int,
        nameContains: String
    ) -> ContainerSection {
        ContainerSection(
            name: name,
            sortOrder: sortOrder,
            matchRules: [.init(type: .containerNameContains, pattern: nameContains)]
        )
    }

    // MARK: - ContainerGroup counts

    @Test("runningCount and totalCount reflect a mix of states")
    func groupCountsWithMixedStates() {
        let group = ContainerGroup(
            id: "g",
            name: "Mix",
            containers: [
                container(id: "1", name: "a", state: .running),
                container(id: "2", name: "b", state: .running),
                container(id: "3", name: "c", state: .exited),
                container(id: "4", name: "d", state: .paused)
            ]
        )

        #expect(group.runningCount == 2)
        #expect(group.totalCount == 4)
    }

    @Test("An empty group reports zero counts")
    func emptyGroupCounts() {
        let group = ContainerGroup(id: "g", name: "Empty", containers: [])
        #expect(group.runningCount == 0)
        #expect(group.totalCount == 0)
    }

    // MARK: - Grouping transform

    @Test("Matching containers land in their section; the rest fall to ungrouped")
    func matchesGoToSectionOthersUngrouped() {
        let containers = [
            container(id: "1", name: "web-frontend"),
            container(id: "2", name: "db-postgres"),
            container(id: "3", name: "random-tool")
        ]
        let sections = [section(name: "Web", sortOrder: 0, nameContains: "web")]

        let (groups, ungrouped) = ContainerListSection.groupContainers(containers, into: sections)

        #expect(groups.count == 1)
        #expect(groups.first?.name == "Web")
        #expect(groups.first?.containers.map(\.id) == ["1"])
        #expect(Set(ungrouped.map(\.id)) == ["2", "3"])
    }

    @Test("Sections appear ordered by sortOrder regardless of input order")
    func sectionsOrderedBySortOrder() {
        let containers = [
            container(id: "1", name: "web-1"),
            container(id: "2", name: "api-1")
        ]
        // Passed in reverse of the intended display order.
        let sections = [
            section(name: "Api", sortOrder: 1, nameContains: "api"),
            section(name: "Web", sortOrder: 0, nameContains: "web")
        ]

        let (groups, _) = ContainerListSection.groupContainers(containers, into: sections)

        #expect(groups.map(\.name) == ["Web", "Api"])
    }

    @Test("Sections that match nothing are omitted from the result")
    func emptySectionsOmitted() {
        let containers = [container(id: "1", name: "web-1")]
        let sections = [
            section(name: "Web", sortOrder: 0, nameContains: "web"),
            section(name: "Databases", sortOrder: 1, nameContains: "db")
        ]

        let (groups, ungrouped) = ContainerListSection.groupContainers(containers, into: sections)

        #expect(groups.map(\.name) == ["Web"])
        #expect(ungrouped.isEmpty)
    }

    @Test("A container matching multiple sections joins the first by sortOrder only")
    func multiMatchResolvesToFirstSection() {
        // "web-api" matches both the "web" and "api" rules.
        let containers = [
            container(id: "1", name: "web-api"),
            container(id: "2", name: "api-worker")
        ]
        let sections = [
            section(name: "Web", sortOrder: 0, nameContains: "web"),
            section(name: "Api", sortOrder: 1, nameContains: "api")
        ]

        let (groups, ungrouped) = ContainerListSection.groupContainers(containers, into: sections)

        // web-api is claimed by Web (lower sortOrder) and not double-counted.
        let web = groups.first { $0.name == "Web" }
        let api = groups.first { $0.name == "Api" }
        #expect(web?.containers.map(\.id) == ["1"])
        #expect(api?.containers.map(\.id) == ["2"])
        #expect(ungrouped.isEmpty)
    }

    @Test("Within a group and the ungrouped list, running sorts before stopped, then by name")
    func membersSortedRunningFirstThenName() {
        let containers = [
            container(id: "1", name: "zeta", state: .running),
            container(id: "2", name: "alpha", state: .exited),
            container(id: "3", name: "beta", state: .running)
        ]
        // No sections -> everything is ungrouped and sorted by the same rule.
        let (groups, ungrouped) = ContainerListSection.groupContainers(containers, into: [])

        #expect(groups.isEmpty)
        // Running (beta, zeta by name) first, then exited (alpha).
        #expect(ungrouped.map(\.displayName) == ["beta", "zeta", "alpha"])
    }

    @Test("No sections yields no groups and every container ungrouped")
    func noSectionsMeansAllUngrouped() {
        let containers = [
            container(id: "1", name: "a"),
            container(id: "2", name: "b")
        ]

        let (groups, ungrouped) = ContainerListSection.groupContainers(containers, into: [])

        #expect(groups.isEmpty)
        #expect(ungrouped.count == 2)
    }
}
