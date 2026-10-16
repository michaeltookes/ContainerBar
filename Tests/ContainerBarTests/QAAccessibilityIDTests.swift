import Foundation
import Testing
@testable import ContainerBar
@testable import ContainerBarCore

/// Pure-helper coverage for the QA-hooks identifiers (CB-107, CB-056 pattern):
/// every helper-built identifier has one test, and container-scoped identifiers
/// share the card's slug for any name, including characters outside the slug
/// alphabet, and the id-suffixed ones stay unique when two names share a slug. No view hosting.
@MainActor
@Suite("QA accessibility identifiers")
struct QAAccessibilityIDTests {

    /// A Docker-style 64-hex container id (upper case to prove lowercasing).
    private let fixtureID = "3F9A1C2B4D5E" + String(repeating: "0", count: 52)

    @Test("Fixed identifiers match the QA recipe contract")
    func fixedIdentifiers() {
        #expect(QAAccessibilityID.statusItem == "containerBarStatusItem")
        #expect(QAAccessibilityID.connectionStatus == "connectionStatus")
        #expect(QAAccessibilityID.logsPanelText == "logsPanelText")
        #expect(QAAccessibilityID.checkForUpdatesGeneral == "checkForUpdates-general")
        #expect(QAAccessibilityID.checkForUpdatesAbout == "checkForUpdates-about")
        #expect(QAAccessibilityID.autoCheckUpdatesToggle == "autoCheckUpdatesToggle")
        #expect(QAAccessibilityID.showStoppedToggle == "showStoppedToggle")
        #expect(QAAccessibilityID.addSectionButton == "addSectionButton")
    }

    @Test("Card identifier keeps the existing containerCard-<slug> form")
    func cardIdentifier() {
        #expect(QAAccessibilityID.containerCard("cbqa-target") == "containerCard-cbqa-target")
        #expect(QAAccessibilityID.containerCard("My Service") == "containerCard-my-service")
        #expect(QAAccessibilityID.containerCard("team/api") == "containerCard-team-api")
    }

    @Test("Stop identifier is containerStop-<slug>-<short id>")
    func stopIdentifier() {
        #expect(
            QAAccessibilityID.containerStop(name: "cbqa-target", id: fixtureID) ==
                "containerStop-cbqa-target-3f9a1c2b4d5e"
        )
    }

    @Test("Start identifier is containerStart-<slug>-<short id>")
    func startIdentifier() {
        #expect(
            QAAccessibilityID.containerStart(name: "cbqa-stopped", id: fixtureID) ==
                "containerStart-cbqa-stopped-3f9a1c2b4d5e"
        )
    }

    @Test("Logs-panel row identifier is logs-panel-container-<slug>-<short id>")
    func logsPanelRowIdentifier() {
        #expect(
            QAAccessibilityID.logsPanelRow(name: "cbqa-logs", id: fixtureID) ==
                "logs-panel-container-cbqa-logs-3f9a1c2b4d5e"
        )
    }

    @Test("Short id is the first 12 characters, lowercased; shorter ids are kept whole")
    func shortContainerID() {
        #expect(QAAccessibilityID.shortContainerID(fixtureID) == "3f9a1c2b4d5e")
        #expect(QAAccessibilityID.shortContainerID("ABC") == "abc")
    }

    @Test("Containers whose names share a slug get distinct container-scoped identifiers")
    func sameSlugNamesStayDistinct() {
        let web = (name: "Web", id: "aaaaaaaaaaaa1111")
        let other = (name: "web", id: "bbbbbbbbbbbb2222")
        #expect(QAAccessibilityID.containerSlug(web.name) == QAAccessibilityID.containerSlug(other.name))

        #expect(
            QAAccessibilityID.logsPanelRow(name: web.name, id: web.id) !=
                QAAccessibilityID.logsPanelRow(name: other.name, id: other.id)
        )
        #expect(
            QAAccessibilityID.containerStop(name: web.name, id: web.id) !=
                QAAccessibilityID.containerStop(name: other.name, id: other.id)
        )
        #expect(
            QAAccessibilityID.containerStart(name: web.name, id: web.id) !=
                QAAccessibilityID.containerStart(name: other.name, id: other.id)
        )
    }

    @Test("Section row identifier is sectionRow-<slug>-<uuid>")
    func sectionRowIdentifier() throws {
        let id = try #require(UUID(uuidString: "F1A7E000-0000-4000-8000-000000000002"))
        #expect(
            QAAccessibilityID.sectionRow(name: "QA Fixtures", id: id) ==
                "sectionRow-qa-fixtures-f1a7e000-0000-4000-8000-000000000002"
        )
    }

    @Test(
        "Card, quick actions, and logs row share one slug for any name",
        arguments: ["cbqa_Odd.Name", "cbqa-target", "Web Server", "org/app:v2", "ÄPI Gateway"]
    )
    func slugIsSharedAcrossContainerIdentifiers(name: String) {
        let slug = QAAccessibilityID.containerSlug(name)
        #expect(!slug.isEmpty)
        #expect(QAAccessibilityID.containerCard(name) == "containerCard-\(slug)")
        #expect(QAAccessibilityID.containerStop(name: name, id: fixtureID) == "containerStop-\(slug)-3f9a1c2b4d5e")
        #expect(QAAccessibilityID.containerStart(name: name, id: fixtureID) == "containerStart-\(slug)-3f9a1c2b4d5e")
        #expect(
            QAAccessibilityID.logsPanelRow(name: name, id: fixtureID) == "logs-panel-container-\(slug)-3f9a1c2b4d5e"
        )
    }

    @Test("Odd-character names produce the documented slug")
    func oddNameSlug() {
        #expect(QAAccessibilityID.containerSlug("cbqa_Odd.Name") == "cbqa_odd.name")
    }

    @Test("connectionStatus label names the host when connected")
    func connectionStatusConnectedLabel() {
        let presentation = ConnectionStatusPresentation.make(
            hostName: "QA Runtime",
            isConnected: true,
            isRefreshing: false,
            connectionError: nil
        )
        #expect(presentation.accessibilityLabel == "Connected to QA Runtime")
    }

    @Test("connectionStatus label carries the error text when the runtime is unreachable")
    func connectionStatusErrorLabel() {
        let presentation = ConnectionStatusPresentation.make(
            hostName: "QA Runtime",
            isConnected: false,
            isRefreshing: false,
            connectionError: "  Connection refused  "
        )
        #expect(presentation.accessibilityLabel == "Connection failed for QA Runtime. Connection refused")
    }
}
