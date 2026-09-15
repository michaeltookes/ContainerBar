import Foundation
import Testing
@testable import ContainerBar
@testable import ContainerBarCore

/// Host- and section-management coverage plus persistence round-trips for
/// `SettingsStore`. Kept separate from `SettingsStoreTests` (defaults/enums)
/// so each file stays focused. Every test uses an isolated UserDefaults suite
/// wiped up front so runs never bleed into `.standard` or each other.
@Suite("SettingsStore host & section management")
struct SettingsStoreHostSectionTests {

    /// A store bound to a throwaway UserDefaults suite, carrying the suite name
    /// so persistence tests can reload from and tear down the same backing.
    private struct Fixture {
        let store: SettingsStore
        let defaults: UserDefaults
        let suiteName: String
    }

    @MainActor
    private func freshStore(_ suite: String = #function) -> Fixture {
        let name = "SettingsStoreHostSection.\(suite).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return Fixture(store: SettingsStore(userDefaults: defaults), defaults: defaults, suiteName: name)
    }

    // MARK: - Host management

    @Test("Adding a host marked default demotes the existing default")
    @MainActor
    func addDefaultHostDemotesExisting() {
        let store = freshStore().store
        // Store seeds one default local host.
        let originalDefaultId = store.hosts.first { $0.isDefault }?.id

        store.addHost(DockerHost(name: "Remote", connectionType: .ssh, isDefault: true))

        #expect(store.hosts.count == 2)
        let defaults = store.hosts.filter { $0.isDefault }
        #expect(defaults.count == 1)
        #expect(defaults.first?.name == "Remote")
        #expect(store.hosts.first { $0.id == originalDefaultId }?.isDefault == false)
    }

    @Test("Adding a non-default host leaves the existing default intact")
    @MainActor
    func addNonDefaultHostKeepsDefault() {
        let store = freshStore().store
        let originalDefaultId = store.hosts.first { $0.isDefault }?.id

        store.addHost(DockerHost(name: "Secondary", connectionType: .ssh, isDefault: false))

        #expect(store.hosts.count == 2)
        #expect(store.hosts.filter { $0.isDefault }.count == 1)
        #expect(store.hosts.first { $0.isDefault }?.id == originalDefaultId)
        #expect(store.hosts.first { $0.name == "Secondary" }?.isDefault == false)
    }

    @Test("Updating an existing host mutates it; updating an unknown host is a no-op")
    @MainActor
    func updateHostBehavior() {
        let store = freshStore().store
        var host = store.hosts[0]
        host.name = "Renamed"
        store.updateHost(host)
        #expect(store.hosts[0].name == "Renamed")

        let ghost = DockerHost(name: "Ghost", connectionType: .ssh)
        let before = store.hosts
        store.updateHost(ghost)
        #expect(store.hosts == before)
    }

    @Test("Removing the default host promotes the first remaining host to default")
    @MainActor
    func removeDefaultPromotesFirstRemaining() {
        let store = freshStore().store
        store.addHost(DockerHost(name: "Second", connectionType: .ssh, isDefault: false))
        let defaultId = store.hosts.first { $0.isDefault }!.id

        store.removeHost(id: defaultId)

        #expect(store.hosts.count == 1)
        #expect(store.hosts.first?.isDefault == true)
        #expect(store.hosts.first?.name == "Second")
    }

    @Test("Removing the selected host clears the selection")
    @MainActor
    func removeSelectedClearsSelection() {
        let store = freshStore().store
        store.addHost(DockerHost(name: "Second", connectionType: .ssh))
        let secondId = store.hosts.first { $0.name == "Second" }!.id
        store.selectedHostId = secondId
        #expect(store.selectedHostId == secondId)

        store.removeHost(id: secondId)

        #expect(store.selectedHostId == nil)
    }

    @Test("Removing a non-default, non-selected host leaves default and selection untouched")
    @MainActor
    func removeOtherHostKeepsState() {
        let store = freshStore().store
        store.addHost(DockerHost(name: "Second", connectionType: .ssh))
        let defaultId = store.hosts.first { $0.isDefault }!.id
        let secondId = store.hosts.first { $0.name == "Second" }!.id
        store.selectedHostId = defaultId

        store.removeHost(id: secondId)

        #expect(store.hosts.count == 1)
        #expect(store.selectedHostId == defaultId)
        #expect(store.hosts.first?.isDefault == true)
    }

    @Test("setDefaultHost makes exactly the named host default")
    @MainActor
    func setDefaultHostIsExclusive() {
        let store = freshStore().store
        store.addHost(DockerHost(name: "Second", connectionType: .ssh))
        let secondId = store.hosts.first { $0.name == "Second" }!.id

        store.setDefaultHost(id: secondId)

        #expect(store.hosts.filter { $0.isDefault }.count == 1)
        #expect(store.hosts.first { $0.id == secondId }?.isDefault == true)
    }

    // MARK: - Section management

    @Test("addSection assigns a monotonically increasing sortOrder")
    @MainActor
    func addSectionAssignsSortOrder() {
        let store = freshStore().store
        store.addSection(ContainerSection(name: "A", sortOrder: 99))
        store.addSection(ContainerSection(name: "B", sortOrder: 99))
        store.addSection(ContainerSection(name: "C", sortOrder: 99))

        #expect(store.sections.map(\.name) == ["A", "B", "C"])
        #expect(store.sections.map(\.sortOrder) == [0, 1, 2])
    }

    @Test("updateSection mutates an existing section; unknown id is a no-op")
    @MainActor
    func updateSectionBehavior() {
        let store = freshStore().store
        store.addSection(ContainerSection(name: "Original"))
        var section = store.sections[0]
        section.name = "Edited"
        store.updateSection(section)
        #expect(store.sections[0].name == "Edited")

        let before = store.sections
        store.updateSection(ContainerSection(name: "Ghost"))
        #expect(store.sections == before)
    }

    @Test("removeSection deletes the section and resequences sortOrder")
    @MainActor
    func removeSectionResequences() {
        let store = freshStore().store
        store.addSection(ContainerSection(name: "A"))
        store.addSection(ContainerSection(name: "B"))
        store.addSection(ContainerSection(name: "C"))
        let middle = store.sections[1].id

        store.removeSection(id: middle)

        #expect(store.sections.map(\.name) == ["A", "C"])
        #expect(store.sections.map(\.sortOrder) == [0, 1])
    }

    @Test("moveSection reorders and resequences sortOrder")
    @MainActor
    func moveSectionReorders() {
        let store = freshStore().store
        store.addSection(ContainerSection(name: "A"))
        store.addSection(ContainerSection(name: "B"))
        store.addSection(ContainerSection(name: "C"))

        // Move the first item (A) to the end.
        store.moveSection(from: IndexSet(integer: 0), to: 3)

        #expect(store.sections.map(\.name) == ["B", "C", "A"])
        #expect(store.sections.map(\.sortOrder) == [0, 1, 2])
    }

    // MARK: - Persistence round-trips

    @Test("Scalar preferences survive a reload from the same defaults")
    @MainActor
    func scalarPreferencesPersist() {
        let fx = freshStore(); let store = fx.store; let defaults = fx.defaults; let name = fx.suiteName
        store.refreshInterval = .minutes5
        store.showStoppedContainers = false
        store.iconStyle = .healthIndicator

        let reloaded = SettingsStore(userDefaults: defaults)

        #expect(reloaded.refreshInterval == .minutes5)
        #expect(reloaded.showStoppedContainers == false)
        #expect(reloaded.iconStyle == .healthIndicator)
        defaults.removePersistentDomain(forName: name)
    }

    @Test("Hosts persist as JSON and reload with fields intact")
    @MainActor
    func hostsPersist() {
        let fx = freshStore(); let store = fx.store; let defaults = fx.defaults; let name = fx.suiteName
        store.addHost(DockerHost(
            name: "Beelink",
            connectionType: .ssh,
            isDefault: true,
            host: "192.168.86.28",
            sshUser: "luciusfox"
        ))

        let reloaded = SettingsStore(userDefaults: defaults)
        let beelink = reloaded.hosts.first { $0.name == "Beelink" }

        #expect(reloaded.hosts.count == 2)
        #expect(beelink?.connectionType == .ssh)
        #expect(beelink?.host == "192.168.86.28")
        #expect(beelink?.sshUser == "luciusfox")
        #expect(beelink?.isDefault == true)
        defaults.removePersistentDomain(forName: name)
    }

    @Test("Sections persist and reload sorted by sortOrder")
    @MainActor
    func sectionsPersistSorted() {
        let fx = freshStore(); let store = fx.store; let defaults = fx.defaults; let name = fx.suiteName
        store.addSection(ContainerSection(name: "First"))
        store.addSection(ContainerSection(name: "Second", matchRules: [
            .init(type: .imageContains, pattern: "nginx")
        ]))
        // Persisted out of natural order to prove the load path sorts.
        store.moveSection(from: IndexSet(integer: 0), to: 2)

        let reloaded = SettingsStore(userDefaults: defaults)

        #expect(reloaded.sections.map(\.name) == ["Second", "First"])
        #expect(reloaded.sections.map(\.sortOrder) == [0, 1])
        #expect(reloaded.sections.first?.matchRules.first?.pattern == "nginx")
        defaults.removePersistentDomain(forName: name)
    }

    @Test("selectedHostId persists, and setting it to nil removes the key")
    @MainActor
    func selectedHostIdPersistence() {
        let fx = freshStore(); let store = fx.store; let defaults = fx.defaults; let name = fx.suiteName
        store.addHost(DockerHost(name: "Second", connectionType: .ssh))
        let secondId = store.hosts.first { $0.name == "Second" }!.id
        store.selectedHostId = secondId

        let reloaded = SettingsStore(userDefaults: defaults)
        #expect(reloaded.selectedHostId == secondId)

        reloaded.selectedHostId = nil
        #expect(defaults.string(forKey: "selectedHostId") == nil)
        defaults.removePersistentDomain(forName: name)
    }

    @Test("Corrupt persisted host data falls back to the seeded local host")
    @MainActor
    func corruptHostDataFallsBack() {
        let name = "SettingsStoreHostSection.corrupt.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(Data("not-json".utf8), forKey: "dockerHosts")

        let store = SettingsStore(userDefaults: defaults)

        // Decode fails silently; the store still guarantees a usable local host.
        #expect(store.hosts.count == 1)
        #expect(store.hosts.first?.connectionType == .unixSocket)
        #expect(store.hosts.first?.isDefault == true)
        defaults.removePersistentDomain(forName: name)
    }
}
